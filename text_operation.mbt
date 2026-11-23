///|
#derive(Eq, @debug.Debug)
pub(all) enum TextInstruction {
  InsertText(Int32, String)
  DeleteText(Int32, String)
}

///|
pub extend TextInstruction with Eq::{equal, not_equal}

///|
pub extend TextInstruction with @debug.Debug::{to_repr}

///|
/// A validated text0 operation using UTF-16 positions.
pub struct TextOperation {
  priv edits : Array[TextEdit]
}

///|
fn checked_text_edit(
  edit : TextInstruction,
  index : Int32,
) -> TextEdit raise OpError {
  let (position, insert, text) = match edit {
    InsertText(position, text) => (position, true, text)
    DeleteText(position, text) => (position, false, text)
  }
  guard position >= 0 else {
    raise InvalidComponent(index, "negative text position")
  }
  if !insert {
    ignore(shift_text_position(position, text.length()))
  }
  { position, insert, text, }
}

///|
pub fn TextOperation::new(
  instructions : Array[TextInstruction],
) -> TextOperation raise OpError {
  {
    edits: instructions.mapi((index, instruction) => {
      checked_text_edit(instruction, index)
    }),
  }
}

///|
pub fn TextOperation::from_json(value : Json) -> TextOperation raise OpError {
  { edits: decode_text0(copy_checked_json(value)), }
}

///|
pub fn TextOperation::parse(source : String) -> TextOperation raise OpError {
  TextOperation::from_json(parse_json(source))
}

///|
pub fn TextOperation::empty() -> TextOperation {
  { edits: [], }
}

///|
pub fn TextOperation::to_json(self : TextOperation) -> Json {
  encode_text0(self.edits)
}

///|
pub fn TextOperation::instructions(
  self : TextOperation,
) -> Array[TextInstruction] {
  self.edits.map(edit => {
    if edit.insert {
      InsertText(edit.position, edit.text)
    } else {
      DeleteText(edit.position, edit.text)
    }
  })
}

///|
pub fn TextOperation::length(self : TextOperation) -> Int32 {
  self.edits.length()
}

///|
pub fn TextOperation::apply(
  self : TextOperation,
  source : String,
) -> String raise OpError {
  let mut text = source
  for edit in self.edits {
    text = edit_string(text, edit, [])
  }
  text
}

///|
pub fn TextOperation::normalize(self : TextOperation) -> TextOperation {
  let output = []
  for edit in self.edits {
    append_text0(output, edit)
  }
  { edits: output, }
}

///|
pub fn TextOperation::compose(
  self : TextOperation,
  next : TextOperation,
) -> TextOperation {
  { edits: compose_text0(self.edits, next.edits), }
}

///|
pub fn TextOperation::invert(self : TextOperation) -> TextOperation {
  {
    edits: Array::makei(self.edits.length(), index => {
      let edit = self.edits[self.edits.length() - index - 1]
      { ..edit, insert: !edit.insert, }
    }),
  }
}

///|
pub fn TextOperation::transform_pair(
  self : TextOperation,
  other : TextOperation,
) -> (TextOperation, TextOperation) raise OpError {
  let (left, right) = transform_pair(
    self.edits,
    other.edits,
    (dest, edit, concurrent, side) => {
      transform_text0(dest, edit, concurrent, side)
    },
    (dest, edit) => append_text0(dest, edit),
  )
  ({ edits: left, }, { edits: right, })
}

///|
pub fn TextOperation::transform(
  self : TextOperation,
  other : TextOperation,
  side : Side,
) -> TextOperation raise OpError {
  let (left, right) = match side {
    Left => self.transform_pair(other)
    Right => other.transform_pair(self)
  }
  match side {
    Left => left
    Right => right
  }
}

///|
pub fn TextOperation::transform_position(
  self : TextOperation,
  position : Int32,
  side~ : Side = Left,
) -> Int32 raise OpError {
  guard position >= 0 else {
    raise InvalidComponent(0, "negative text position")
  }
  let mut position = position
  for edit in self.edits {
    position = transform_position(position, edit, side)
  }
  position
}

///|
pub fn TextOperation::as_json0(
  self : TextOperation,
  path : Path,
  encoding~ : TextEncoding = Text0,
) -> Operation {
  { components: text_components(path.segments, self.edits, encoding), }
}

///|
pub fn TextOperation::splice(
  source : String,
  start : Int32,
  delete_count : Int32,
  inserted : String,
) -> TextOperation raise OpError {
  { edits: splice_edits(source, start, delete_count, inserted, []), }
}

///|
pub fn TextOperation::net_length(self : TextOperation) -> Int64 {
  let mut delta = 0L
  for edit in self.edits {
    let count = edit.text.length().to_int64()
    delta += if edit.insert { count } else { -count }
  }
  delta
}
