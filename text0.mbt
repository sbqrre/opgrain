///|
priv struct TextEdit {
  position : Int32
  insert : Bool
  text : String
}

///|
fn code_slice(text : String, start : Int32, end : Int32) -> String {
  let units = Array::makei(end - start, i => {
    text.code_unit_at(start + i).to_int().unsafe_to_char()
  })
  String::from_array(units)
}

///|
fn inject(text : String, position : Int32, inserted : String) -> String {
  code_slice(text, 0, position) +
  inserted +
  code_slice(text, position, text.length())
}

///|
fn decode_text0(value : Json) -> Array[TextEdit] raise OpError {
  guard value is Array(items) else {
    raise InvalidComponent(0, "text0 expects an operation array")
  }
  let edits = []
  for index, item in items {
    guard item is Object(fields) && fields.get("p") is Some(offset) else {
      raise InvalidComponent(index, "text0 component requires p")
    }
    let position = nonnegative_index(offset, index)
    match (fields.get("i"), fields.get("d")) {
      (Some(String(text)), None) =>
        edits.push({ position, insert: true, text, })
      (None, Some(String(text))) =>
        edits.push({ position, insert: false, text, })
      _ => raise InvalidComponent(index, "text0 expects either i or d")
    }
  }
  edits
}

///|
fn edit_string(
  text : String,
  edit : TextEdit,
  path : Array[PathSegment],
) -> String raise OpError {
  let position = edit.position
  guard position <= text.length() else {
    raise InvalidPath(path.copy(), "text offset out of bounds")
  }
  if edit.insert {
    return inject(text, position, edit.text)
  }
  guard edit.text.length() <= text.length() - position else {
    raise InvalidPath(path.copy(), "text deletion out of bounds")
  }
  let end = position + edit.text.length()
  guard code_slice(text, position, end) == edit.text else {
    raise TextMismatch(position)
  }
  code_slice(text, 0, position) + code_slice(text, end, text.length())
}
