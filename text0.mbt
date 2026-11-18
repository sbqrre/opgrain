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
fn encode_text0(edits : Array[TextEdit]) -> Json {
  Json::array(
    edits.map(edit => {
      let fields = Map([])
      fields["p"] = Json::number(edit.position.to_double())
      fields[if edit.insert { "i" } else { "d" }] = Json::string(edit.text)
      Json::object(fields)
    }),
  )
}

///|
fn append_text0(dest : Array[TextEdit], next : TextEdit) -> Unit {
  if next.text.is_empty() {
    return
  }
  if dest.last() is Some(last) {
    let end = dest.length() - 1
    let delta = next.position - last.position
    if last.insert && next.insert && delta >= 0 && delta <= last.text.length() {
      dest[end] = { ..last, text: inject(last.text, delta, next.text), }
      return
    }
    if !last.insert &&
      !next.insert &&
      delta <= 0 &&
      -delta <= next.text.length() {
      dest[end] = { ..next, text: inject(next.text, -delta, last.text), }
      return
    }
  }
  dest.push(next)
}

///|
fn compose_text0(
  first : Array[TextEdit],
  second : Array[TextEdit],
) -> Array[TextEdit] {
  let output = first.copy()
  for edit in second {
    append_text0(output, edit)
  }
  output
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

///|
pub fn text0_normalize(value : Json) -> Json raise OpError {
  let inputs = match value {
    Array(items) => items
    Object(fields) if fields.get("i") is Some(_) || fields.get("p") is Some(_) =>
      [value]
    Object(_) => []
    _ => raise InvalidComponent(0, "text0 expects an operation")
  }
  let output = []
  for item in inputs {
    guard copy_json(item) is Object(fields) else {
      raise InvalidComponent(0, "text0 component must be an object")
    }
    if fields.get("p") is None || fields.get("p") is Some(Null) {
      fields["p"] = Json::number(0.0)
    }
    let edits = decode_text0(Json::array([Json::object(fields)]))
    append_text0(output, edits[0])
  }
  encode_text0(output)
}
