///|
/// Syntactic access categories; these do not replace JSON0 conflict resolution.
#derive(Eq, @debug.Debug)
pub(all) enum AccessKind {
  NumericUpdate
  InsertValue
  DeleteValue
  ReplaceValue
  InsertItem
  DeleteItem
  ReplaceItem
  MoveItemAccess(Int32)
  InsertString(Int32, Int32)
  DeleteString(Int32, Int32)
  SubtypeAccess(String)
}

///|
pub extend AccessKind with Eq::{equal, not_equal}

///|
pub extend AccessKind with @debug.Debug::{to_repr}

///|
pub struct Access {
  priv component : Int32
  priv path : Path
  priv kind : AccessKind
}

///|
pub fn Access::component(self : Access) -> Int32 {
  self.component
}

///|
pub fn Access::path(self : Access) -> Path {
  self.path
}

///|
pub fn Access::kind(self : Access) -> AccessKind {
  self.kind
}

///|
fn access_for(component : Component, index : Int32) -> Access {
  let mut path = component.path
  let kind = match component.action {
    Add(_) => NumericUpdate
    ObjectEdit(Some(_), Some(_)) => ReplaceValue
    ObjectEdit(Some(_), None) => InsertValue
    ObjectEdit(None, _) => DeleteValue
    ListEdit(Some(_), Some(_)) => ReplaceItem
    ListEdit(Some(_), None) => InsertItem
    ListEdit(None, _) => DeleteItem
    Move(destination) => MoveItemAccess(destination)
    LegacyText(insert, text) => {
      let offset = match path.last() {
        Some(Index(offset)) => offset
        _ => 0
      }
      path = path[:path.length() - 1].to_owned()
      if insert {
        InsertString(offset, text.length())
      } else {
        DeleteString(offset, text.length())
      }
    }
    SubtypeEdit(kind, _) => SubtypeAccess(kind)
  }
  { component: index, path: { segments: path.copy(), }, kind, }
}

///|
/// Paths are in each component's sequential coordinate system.
pub fn Operation::accesses(self : Operation) -> Array[Access] {
  self.components.mapi((index, component) => access_for(component, index))
}

///|
#derive(Eq, @debug.Debug)
pub(all) enum InteractionKind {
  SameValue
  AncestorWrite
  ListCoordinates
  TextCoordinates
  CommutativeAddition
  OpaqueSubtypeAccess
}

///|
pub extend InteractionKind with Eq::{equal, not_equal}

///|
pub extend InteractionKind with @debug.Debug::{to_repr}

///|
pub(all) struct Interaction {
  left_component : Int32
  right_component : Int32
  kind : InteractionKind
}

///|
fn AccessKind::writes_subtree(self : AccessKind) -> Bool {
  match self {
    InsertValue | DeleteValue | ReplaceValue | DeleteItem | ReplaceItem => true
    _ => false
  }
}

///|
fn AccessKind::shifts_list(self : AccessKind) -> Bool {
  match self {
    InsertItem | DeleteItem | MoveItemAccess(_) => true
    _ => false
  }
}

///|
fn AccessKind::text_access(self : AccessKind) -> Bool {
  match self {
    InsertString(_, _) | DeleteString(_, _) | SubtypeAccess("text0") => true
    _ => false
  }
}

///|
fn Access::may_shift(self : Access, other : Access) -> Bool {
  guard self.kind.shifts_list() else { return false }
  guard self.path.parent() is Some(parent) else { return false }
  guard other.path.starts_with(parent) && other.path.length() > parent.length() else {
    return false
  }
  guard self.path.last() is Some(Index(at)) &&
    other.path.segments[parent.length()] is Index(current) else {
    return false
  }
  match self.kind {
    InsertItem | DeleteItem => current >= at
    MoveItemAccess(destination) =>
      current >= at.min(destination) && current <= at.max(destination)
    _ => false
  }
}

///|
fn interaction_kind(left : Access, right : Access) -> InteractionKind? {
  if left.path.equal(right.path) {
    if left.kind == NumericUpdate && right.kind == NumericUpdate {
      return Some(CommutativeAddition)
    }
    if left.kind.text_access() && right.kind.text_access() {
      return Some(TextCoordinates)
    }
    if left.kind is SubtypeAccess(_) || right.kind is SubtypeAccess(_) {
      return Some(OpaqueSubtypeAccess)
    }
    return Some(SameValue)
  }
  if (left.kind.writes_subtree() && right.path.starts_with(left.path)) ||
    (right.kind.writes_subtree() && left.path.starts_with(right.path)) {
    return Some(AncestorWrite)
  }
  if left.may_shift(right) || right.may_shift(left) {
    return Some(ListCoordinates)
  }
  None
}

///|
/// Conservative syntactic candidates. Later components may use shifted paths.
/// The actual transformed operations remain the authority for conflict outcomes.
pub fn Operation::interactions(
  self : Operation,
  other : Operation,
) -> Array[Interaction] {
  let output = []
  for left in self.accesses() {
    for right in other.accesses() {
      if interaction_kind(left, right) is Some(kind) {
        output.push({
          left_component: left.component,
          right_component: right.component,
          kind,
        })
      }
    }
  }
  output
}

///|
pub fn Operation::write_roots(self : Operation) -> Array[Path] {
  let roots : Array[Path] = []
  for access in self.accesses() {
    let path = if access.kind.shifts_list() {
      access.path.parent().unwrap()
    } else {
      access.path
    }
    if roots.any(root => path.starts_with(root)) {
      continue
    }
    let retained = roots.filter(root => !root.starts_with(path))
    roots.clear()
    roots.append(retained)
    roots.push(path)
  }
  roots
}

///|
pub fn Operation::may_affect(self : Operation, path : Path) -> Bool {
  self
  .write_roots()
  .any(root => path.starts_with(root) || root.starts_with(path))
}

///|
pub fn Operation::subtypes(self : Operation) -> Array[String] {
  let names : Array[String] = []
  for component in self.components {
    if component.action is SubtypeEdit(name, _) && !names.contains(name) {
      names.push(name)
    }
  }
  names
}
