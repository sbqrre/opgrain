///|
fn Engine::invert_component(
  self : Engine,
  component : Component,
) -> Component raise OpError {
  let { path, action, } = component
  let inverse = match action {
    Add(amount) => Add(-amount)
    ListEdit(insert, delete) => ListEdit(delete, insert)
    ObjectEdit(insert, delete) => ObjectEdit(delete, insert)
    LegacyText(insert, text) => LegacyText(!insert, text)
    Move(to) => {
      guard path.last() is Some(Index(from)) else {
        raise InvalidPath(path.copy(), "move must end at an index")
      }
      let reverse_path = path.copy()
      reverse_path[reverse_path.length() - 1] = Index(to)
      return { path: reverse_path, action: Move(from), }
    }
    SubtypeEdit(kind, payload) => {
      let inverse = match self.subtypes.get(kind) {
        Some(subtype) => copy_json((subtype.invert)(copy_json(payload)))
        None if kind == "text0" => {
          let edits = decode_text0(payload)
          edits.rev_in_place()
          encode_text0(edits.map(edit => { ..edit, insert: !edit.insert, }))
        }
        None => raise UnknownSubtype(kind)
      }
      SubtypeEdit(kind, inverse)
    }
  }
  { path, action: inverse, }
}

///|
pub fn Engine::invert(self : Engine, op : Operation) -> Operation raise OpError {
  let components = []
  for i in 0..<op.components.length() {
    components.push(
      self.invert_component(op.components[op.components.length() - 1 - i]),
    )
  }
  { components, }
}

///|
pub fn invert(op : Operation) -> Operation raise OpError {
  Engine::new().invert(op)
}
