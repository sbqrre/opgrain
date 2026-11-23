///|
/// Typed JSON0 instruction payloads. All deleted values are retained for undo.
#derive(@debug.Debug)
pub(all) enum Instruction {
  NumberAdd(Double)
  ObjectInsert(Json)
  ObjectDelete(Json)
  ObjectReplace(Json, Json)
  ListInsert(Json)
  ListDelete(Json)
  ListReplace(Json, Json)
  ListMove(Int32)
  StringInsert(String)
  StringDelete(String)
  SubtypeOperation(String, Json)
}

///|
pub extend Instruction with @debug.Debug::{to_repr}

///|
fn checked_path(path : Array[PathSegment]) -> Array[PathSegment] raise OpError {
  for part in path {
    if part is Index(index) && index < 0 {
      raise InvalidPath(path.copy(), "negative path index")
    }
  }
  path.copy()
}

///|
/// Construct using the same validation as the JSON0 wire reader.
pub fn Component::new(
  path : Array[PathSegment],
  instruction : Instruction,
) -> Component raise OpError {
  let action = match instruction {
    NumberAdd(amount) => Add(amount)
    ObjectInsert(value) => ObjectEdit(Some(value), None)
    ObjectDelete(value) => ObjectEdit(None, Some(value))
    ObjectReplace(before, after) => ObjectEdit(Some(after), Some(before))
    ListInsert(value) => ListEdit(Some(value), None)
    ListDelete(value) => ListEdit(None, Some(value))
    ListReplace(before, after) => ListEdit(Some(after), Some(before))
    ListMove(destination) => Move(destination)
    StringInsert(text) => LegacyText(true, text)
    StringDelete(text) => LegacyText(false, text)
    SubtypeOperation(name, payload) => SubtypeEdit(name, payload)
  }
  // Validate before encoding, which assumes finite acyclic payloads.
  match action {
    Add(amount) => ignore(checked_number(amount))
    ListEdit(insert, delete) | ObjectEdit(insert, delete) => {
      ignore(insert.map(copy_checked_json))
      ignore(delete.map(copy_checked_json))
    }
    SubtypeEdit(_, payload) => ignore(copy_checked_json(payload))
    _ => ()
  }
  let component = Component::{ path: checked_path(path), action, }
  Component::from_json(component.to_json())
}

///|
pub fn Component::instruction(self : Component) -> Instruction {
  match self.action {
    Add(amount) => NumberAdd(amount)
    ObjectEdit(Some(after), Some(before)) =>
      ObjectReplace(copy_json(before), copy_json(after))
    ObjectEdit(Some(value), None) => ObjectInsert(copy_json(value))
    ObjectEdit(None, Some(value)) => ObjectDelete(copy_json(value))
    ListEdit(Some(after), Some(before)) =>
      ListReplace(copy_json(before), copy_json(after))
    ListEdit(Some(value), None) => ListInsert(copy_json(value))
    ListEdit(None, Some(value)) => ListDelete(copy_json(value))
    Move(destination) => ListMove(destination)
    LegacyText(true, text) => StringInsert(text)
    LegacyText(false, text) => StringDelete(text)
    SubtypeEdit(name, payload) => SubtypeOperation(name, copy_json(payload))
    _ => abort("validated component contains an empty edit")
  }
}

///|
pub fn Operation::empty() -> Operation {
  { components: [], }
}

///|
pub fn Operation::single(component : Component) -> Operation {
  { components: [component], }
}

///|
/// Concatenate sequential components without changing their normalization.
pub fn Operation::concat(self : Operation, next : Operation) -> Operation {
  let components = self.components.copy()
  for component in next.components {
    components.push(component)
  }
  { components, }
}

///|
pub fn Operation::slice(
  self : Operation,
  start : Int32,
  end : Int32,
) -> Operation raise OpError {
  guard start >= 0 && end >= start && end <= self.components.length() else {
    raise InvalidComponent(start, "operation slice out of bounds")
  }
  {
    components: Array::makei(end - start, index => {
      self.components[start + index]
    }),
  }
}

///|
/// Embed a subtree operation in an enclosing document.
pub fn Operation::with_prefix(
  self : Operation,
  prefix : Array[PathSegment],
) -> Operation raise OpError {
  let prefix = checked_path(prefix)
  let components = self.components.map(component => {
    let path = prefix.copy()
    for segment in component.path {
      path.push(segment)
    }
    Component::from_json(
      Component::{ path, action: component.action, }.to_json(),
    )
  })
  { components, }
}

///|
/// Extract a subtree operation only when every component lies in that subtree.
pub fn Operation::without_prefix(
  self : Operation,
  prefix : Array[PathSegment],
) -> Operation? {
  let components = []
  for component in self.components {
    if !has_prefix(component.path, prefix) {
      return None
    }
    let path = Array::makei(component.path.length() - prefix.length(), i => {
      component.path[prefix.length() + i]
    })
    let candidate = Component::{ path, action: component.action, }
    let candidate = Component::from_json(candidate.to_json()) catch {
      _ => return None
    }
    components.push(candidate)
  }
  Some({ components, })
}

///|
pub fn Engine::compose_all(
  self : Engine,
  operations : Array[Operation],
) -> Operation raise OpError {
  let mut result = Operation::empty()
  for operation in operations {
    result = self.compose(result, operation)
  }
  result
}

///|
pub fn Engine::invert_all(
  self : Engine,
  operations : Array[Operation],
) -> Array[Operation] raise OpError {
  Array::makei(operations.length(), i => {
    self.invert(operations[operations.length() - i - 1])
  })
}
