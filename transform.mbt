///|
// Cross each component in sequence. A split right edit crosses the unprocessed tail.
fn[A] transform_pair(
  left : Array[A],
  right : Array[A],
  transform_one : (Array[A], A, A, Side) -> Unit raise OpError,
  append : (Array[A], A) -> Unit raise OpError,
) -> (Array[A], Array[A]) raise OpError {
  let mut current_left = left
  let output_right = []
  for r in right {
    let mut pending = Some(r)
    let output_left = []
    for i in 0..<current_left.length() {
      guard pending is Some(r) else { break }
      let l = current_left[i]
      let next_right = []
      transform_one(output_left, l, r, Left)
      transform_one(next_right, r, l, Right)
      if next_right.length() == 1 {
        pending = Some(next_right[0])
        continue
      }
      let tail = Array::makei(current_left.length() - i - 1, offset => {
        current_left[i + offset + 1]
      })
      let (rest_left, rest_right) = if next_right.is_empty() {
        (tail, [])
      } else {
        transform_pair(tail, next_right, transform_one, append)
      }
      for c in rest_left {
        append(output_left, c)
      }
      for c in rest_right {
        append(output_right, c)
      }
      pending = None
      break
    }
    if pending is Some(r) {
      append(output_right, r)
    }
    current_left = output_left
  }
  (current_left, output_right)
}

///|
fn[A] transform_side(
  op : Array[A],
  other : Array[A],
  side : Side,
  transform_one : (Array[A], A, A, Side) -> Unit raise OpError,
  append : (Array[A], A) -> Unit raise OpError,
) -> Array[A] raise OpError {
  if other.is_empty() {
    return op
  }
  if op.length() == 1 && other.length() == 1 {
    let output = []
    transform_one(output, op[0], other[0], side)
    return output
  }
  match side {
    Left => transform_pair(op, other, transform_one, append).0
    Right => transform_pair(other, op, transform_one, append).1
  }
}

///|
fn operand_length(component : Component) -> Int32 {
  component.path.length() +
  (match component.action {
    Add(_) | SubtypeEdit(_, _) => 1
    _ => 0
  })
}

///|
fn common_length(
  a : Array[PathSegment],
  a_length : Int32,
  b : Array[PathSegment],
  b_length : Int32,
) -> Int32? {
  if a_length == 0 {
    return Some(-1)
  }
  if b_length == 0 {
    return None
  }
  for i in 0..<(a_length - 1) {
    if i >= b_length - 1 || a[i] != b[i] {
      return None
    }
  }
  Some(a_length - 1)
}

///|
fn segment(path : Array[PathSegment], index : Int32) -> PathSegment? {
  if index >= 0 && index < path.length() {
    Some(path[index])
  } else {
    None
  }
}

///|
pub fn common_length_for_ops(a : Component, b : Component) -> Int32? {
  common_length(a.path, operand_length(a), b.path, operand_length(b))
}

///|
pub fn Engine::transform_component(
  self : Engine,
  c : Component,
  other : Component,
  side : Side,
) -> Operation raise OpError {
  self.ensure_registered(c)
  self.ensure_registered(other)
  let components = []
  self.transform_one(components, c, other, side)
  { components, }
}

///|
pub fn can_op_affect_path(op : Operation, path : Array[PathSegment]) -> Bool {
  op.components.any(c => {
    common_length(path, path.length(), c.path, operand_length(c)) is Some(_)
  })
}

///|
fn changed_index(c : Component, at : Int32, next : Int32) -> Component {
  let path = c.path.copy()
  path[at] = Index(next)
  { ..c, path, }
}

///|
fn shifted_index(
  c : Component,
  at : Int32,
  index : Int32,
  delta : Int32,
) -> Component raise OpError {
  let next = index.to_int64() + delta.to_int64()
  guard next >= 0L && next <= 2147483647L else {
    raise InvalidPath(c.path.copy(), "transformed index is outside Int32")
  }
  changed_index(c, at, next.to_int())
}

///|
fn shifted_destination(
  c : Component,
  destination : Int32,
  delta : Int32,
) -> Component raise OpError {
  let next = destination.to_int64() + delta.to_int64()
  guard next >= 0L && next <= 2147483647L else {
    raise InvalidPath(
      c.path.copy(),
      "transformed move destination is outside Int32",
    )
  }
  { ..c, action: Move(next.to_int()), }
}

///|
fn is_insert(c : Component) -> Bool {
  c.action is ListEdit(Some(_), None)
}

///|
fn move_against_move(
  c : Component,
  at : Int32,
  source : Int32,
  destination : Int32,
  other_source : Int32,
  other_destination : Int32,
  side : Side,
) -> Component? raise OpError {
  if other_source == other_destination {
    return Some(c)
  }
  if source == other_source {
    if side == Right {
      return None
    }
    let moved = changed_index(c, at, other_destination)
    return Some(
      if source == destination {
        { ..moved, action: Move(other_destination), }
      } else {
        moved
      },
    )
  }
  // Follow the moved source through the removal and insertion.
  let source_delta = (if source > other_source { -1 } else { 0 }) +
    (if source > other_destination ||
      (source == other_destination && other_source > other_destination) {
      1
    } else {
      0
    })
  let mut destination_delta = if source == destination &&
    source == other_destination &&
    other_source > other_destination {
    1
  } else {
    0
  }
  if destination > other_source ||
    (destination == other_source && destination > source) {
    destination_delta -= 1
  }
  if destination > other_destination {
    destination_delta += 1
  } else if destination == other_destination {
    let same_direction = (
        other_destination > other_source && destination > source
      ) ||
      (other_destination < other_source && destination < source)
    if same_direction {
      if side == Right {
        destination_delta += 1
      }
    } else if destination > source {
      destination_delta += 1
    } else if destination == other_source {
      destination_delta -= 1
    }
  }
  Some(
    shifted_destination(
      shifted_index(c, at, source, source_delta),
      destination,
      destination_delta,
    ),
  )
}

///|
fn transform_list(
  c : Component,
  other : Component,
  at : Int32,
  same_operand : Bool,
  side : Side,
) -> Component? raise OpError {
  guard segment(c.path, at) is Some(Index(index)) &&
    segment(other.path, at) is Some(Index(other_index)) else {
    return Some(c)
  }
  match other.action {
    ListEdit(Some(inserted), Some(_)) => {
      if index != other_index {
        return Some(c)
      }
      if !same_operand {
        return None
      }
      match c.action {
        ListEdit(Some(next), Some(_)) if side == Left =>
          Some({ ..c, action: ListEdit(Some(next), Some(inserted)), })
        ListEdit(_, Some(_)) => None
        _ => Some(c)
      }
    }
    ListEdit(Some(_), None) => {
      let current = if same_operand && is_insert(c) && index == other_index {
        if side == Right {
          shifted_index(c, at, index, 1)
        } else {
          c
        }
      } else if other_index <= index {
        shifted_index(c, at, index, 1)
      } else {
        c
      }
      if same_operand &&
        c.action is Move(destination) &&
        other_index <= destination {
        return Some(shifted_destination(current, destination, 1))
      }
      Some(current)
    }
    ListEdit(None, Some(_)) => {
      let mut current = c
      if same_operand && c.action is Move(destination) {
        if other_index == index {
          return None
        }
        if other_index < destination ||
          (other_index == destination && index < destination) {
          current = shifted_destination(c, destination, -1)
        }
      }
      if other_index < index {
        return Some(shifted_index(current, at, index, -1))
      }
      if other_index != index {
        return Some(current)
      }
      if !same_operand {
        return None
      }
      match c.action {
        ListEdit(Some(item), Some(_)) =>
          Some({ ..c, action: ListEdit(Some(item), None), })
        ListEdit(None, Some(_)) => None
        _ => Some(current)
      }
    }
    Move(destination) => {
      if same_operand && c.action is Move(to) {
        return move_against_move(
          c, at, index, to, other_index, destination, side,
        )
      }
      if same_operand && is_insert(c) {
        let delta = (if index > other_index { -1 } else { 0 }) +
          (if index > destination { 1 } else { 0 })
        return Some(shifted_index(c, at, index, delta))
      }
      if index == other_index {
        return Some(changed_index(c, at, destination))
      }
      let delta = (if index > other_index { -1 } else { 0 }) +
        (if index > destination ||
          (index == destination && other_index > destination) {
          1
        } else {
          0
        })
      Some(shifted_index(c, at, index, delta))
    }
    _ => Some(c)
  }
}

///|
fn Engine::preserve_deleted_value(
  self : Engine,
  c : Component,
  other : Component,
) -> Component raise OpError {
  let length = operand_length(c)
  let other_length = operand_length(other)
  guard other_length > length &&
    common_length(c.path, length, other.path, other_length) is Some(at) &&
    segment(c.path, at) == segment(other.path, at) else {
    return c
  }
  let original = match c.action {
    ObjectEdit(_, Some(old)) | ListEdit(_, Some(old)) => old
    _ => return c
  }
  let nested = Array::makei(other.path.length() - length, i => {
    other.path[i + length]
  })
  let payload = self.apply_component(Some(copy_json(original)), {
    ..other,
    path: nested,
  })
  guard payload is Some(payload) else { raise MissingRoot }
  let action = match c.action {
    ObjectEdit(insert, _) => ObjectEdit(insert, Some(payload))
    ListEdit(insert, _) => ListEdit(insert, Some(payload))
    _ => c.action
  }
  { ..c, action, }
}

///|
fn Engine::transform_subtype(
  self : Engine,
  kind : String,
  a : Json,
  b : Json,
  side : Side,
) -> Json raise OpError {
  match self.subtypes.get(kind) {
    Some(subtype) =>
      copy_json((subtype.transform)(copy_json(a), copy_json(b), side))
    None if kind == "text0" =>
      encode_text0(
        transform_side(
          decode_text0(a),
          decode_text0(b),
          side,
          transform_text0,
          (dest, edit) => append_text0(dest, edit),
        ),
      )
    None => raise UnknownSubtype(kind)
  }
}

///|
fn Engine::transform_one(
  self : Engine,
  dest : Array[Component],
  component : Component,
  other : Component,
  side : Side,
) -> Unit raise OpError {
  let c = self.preserve_deleted_value(component, other)
  let length = operand_length(c)
  let other_length = operand_length(other)
  guard common_length(other.path, other_length, c.path, length) is Some(at) else {
    self.append_component(dest, c)
    return
  }
  let same_operand = length == other_length
  if legacy_parts(c) is Some((parent, first)) &&
    legacy_parts(other) is Some((_, second)) {
    let edits = self.transform_subtype(
      "text0",
      encode_text0([first]),
      encode_text0([second]),
      side,
    )
    for edit in decode_text0(edits) {
      self.append_component(dest, legacy_component(parent, edit))
    }
    return
  }
  let same_segment = segment(c.path, at) == segment(other.path, at)
  let result = match other.action {
    SubtypeEdit(kind, b) =>
      if c.action is SubtypeEdit(current_kind, a) && current_kind == kind {
        let payload = self.transform_subtype(kind, a, b, side)
        if payload is Array(items) && items.is_empty() {
          return
        }
        Some({ ..c, action: SubtypeEdit(kind, payload), })
      } else {
        Some(c)
      }
    ListEdit(_, _) | Move(_) => transform_list(c, other, at, same_operand, side)
    ObjectEdit(Some(inserted), Some(_)) if same_segment =>
      match c.action {
        ObjectEdit(Some(next), _) if same_operand && side == Left =>
          Some({ ..c, action: ObjectEdit(Some(next), Some(inserted)), })
        _ => None
      }
    ObjectEdit(Some(inserted), None) if same_segment &&
      c.action is ObjectEdit(Some(_), _) => {
      if side == Right {
        return
      }
      self.append_component(dest, {
        path: c.path,
        action: ObjectEdit(None, Some(inserted)),
      })
      Some(c)
    }
    ObjectEdit(None, Some(_)) if same_segment => {
      if !same_operand {
        return
      }
      match c.action {
        ObjectEdit(Some(next), _) =>
          Some({ ..c, action: ObjectEdit(Some(next), None), })
        _ => None
      }
    }
    _ => Some(c)
  }
  if result is Some(result) {
    self.append_component(dest, result)
  }
}

///|
/// Returns the left operation after the right, and the right operation after the left.
pub fn Engine::transform_x(
  self : Engine,
  left : Operation,
  right : Operation,
) -> (Operation, Operation) raise OpError {
  for c in left.components {
    self.ensure_registered(c)
  }
  for c in right.components {
    self.ensure_registered(c)
  }
  let (left, right) = transform_pair(
    left.components,
    right.components,
    (dest, c, other, side) => self.transform_one(dest, c, other, side),
    (dest, c) => self.append_component(dest, c),
  )
  ({ components: left, }, { components: right, })
}

///|
pub fn Engine::transform(
  self : Engine,
  op : Operation,
  other : Operation,
  side : Side,
) -> Operation raise OpError {
  for c in op.components {
    self.ensure_registered(c)
  }
  for c in other.components {
    self.ensure_registered(c)
  }
  let components = transform_side(
    op.components,
    other.components,
    side,
    (dest, c, other, side) => self.transform_one(dest, c, other, side),
    (dest, c) => self.append_component(dest, c),
  )
  { components, }
}

///|
pub fn transform_x(
  left : Operation,
  right : Operation,
) -> (Operation, Operation) raise OpError {
  Engine::new().transform_x(left, right)
}

///|
pub fn transform(
  op : Operation,
  other : Operation,
  side : Side,
) -> Operation raise OpError {
  Engine::new().transform(op, other, side)
}
