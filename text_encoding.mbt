///|
fn legacy_edit(
  component : Component,
) -> (Array[PathSegment], TextEdit) raise OpError {
  guard component.action is LegacyText(insert, text) &&
    component.path.last() is Some(Index(position)) else {
    raise InvalidPath(
      component.path.copy(),
      "legacy text requires a UTF-16 index",
    )
  }
  let path = component.path.copy()
  ignore(path.pop())
  (path, { position, insert, text, })
}

///|
fn flush_text_run(
  output : Array[Component],
  path : Array[PathSegment],
  edits : Array[TextEdit],
) -> Unit {
  if !edits.is_empty() {
    output.push({ path, action: SubtypeEdit("text0", encode_text0(edits)), })
    edits.clear()
  }
}

///|
fn to_explicit_text(operation : Operation) -> Operation raise OpError {
  let output = []
  let edits = []
  let mut pending_path = []
  for component in operation.components {
    match component.action {
      LegacyText(_, _) => {
        let (path, edit) = legacy_edit(component)
        if pending_path != path {
          flush_text_run(output, pending_path, edits)
          pending_path = path
        }
        edits.push(edit)
      }
      _ => {
        flush_text_run(output, pending_path, edits)
        output.push(component)
      }
    }
  }
  flush_text_run(output, pending_path, edits)
  { components: output, }
}

///|
fn to_legacy_text(operation : Operation) -> Operation raise OpError {
  let output = []
  for component in operation.components {
    match component.action {
      SubtypeEdit("text0", payload) =>
        for
          legacy in text_components(
            component.path,
            decode_text0(payload),
            Legacy,
          ) {
          output.push(legacy)
        }
      _ => output.push(component)
    }
  }
  { components: output, }
}

///|
/// Convert built-in text operations while preserving their sequential coordinates.
pub fn Engine::reencode_text(
  self : Engine,
  operation : Operation,
  encoding : TextEncoding,
) -> Operation raise OpError {
  if self.subtypes.contains("text0") {
    for component in operation.components {
      match (encoding, component.action) {
        (Text0, LegacyText(_, _)) | (Legacy, SubtypeEdit("text0", _)) =>
          raise SubtypeError(
            "text0", "text encoding conversion requires the built-in text0",
          )
        _ => ()
      }
    }
    return operation
  }
  match encoding {
    Legacy => to_legacy_text(operation)
    Text0 => to_explicit_text(operation)
  }
}
