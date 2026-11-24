// JSON0/text0 semantics adapted from ottypes/json0, ot-json0@1.1.0.
// Copyright 2011 ottypes library contributors.
// MoonBit implementation and adaptations copyright (c) 2026 sbqrre.
// See THIRD_PARTY_NOTICES.md and LICENSES/ot-json0-1.1.0.txt.

///|
fn shift_text_position(position : Int32, length : Int32) -> Int32 raise OpError {
  guard position <= 2147483647 - length else {
    raise InvalidComponent(0, "transformed text offset exceeds Int32")
  }
  position + length
}

///|
pub fn text0_transform_cursor(
  position : Int32,
  op : Json,
  side~ : Side = Left,
) -> Int32 raise OpError {
  guard position >= 0 else {
    raise InvalidComponent(0, "negative cursor position")
  }
  let mut position = position
  for edit in decode_text0(op) {
    position = transform_position(position, edit, side)
  }
  position
}

///|
fn transform_position(
  position : Int32,
  other : TextEdit,
  side : Side,
) -> Int32 raise OpError {
  if other.insert {
    if other.position < position ||
      (other.position == position && side == Right) {
      return shift_text_position(position, other.text.length())
    }
    return position
  }
  if position <= other.position {
    return position
  }
  if position - other.position <= other.text.length() {
    return other.position
  }
  position - other.text.length()
}

///|
fn transform_text0(
  dest : Array[TextEdit],
  edit : TextEdit,
  other : TextEdit,
  side : Side,
) -> Unit raise OpError {
  if edit.insert {
    append_text0(dest, {
      ..edit,
      position: transform_position(edit.position, other, side),
    })
    return
  }
  if other.insert {
    let split = (other.position - edit.position).max(0).min(edit.text.length())
    if split > 0 {
      append_text0(dest, { ..edit, text: code_slice(edit.text, 0, split), })
    }
    if split < edit.text.length() {
      append_text0(dest, {
        ..edit,
        position: shift_text_position(edit.position, other.text.length()),
        text: code_slice(edit.text, split, edit.text.length()),
      })
    }
    return
  }
  let edit_end = shift_text_position(edit.position, edit.text.length())
  let other_end = shift_text_position(other.position, other.text.length())
  if edit.position >= other_end {
    append_text0(dest, {
      ..edit,
      position: edit.position - other.text.length(),
    })
    return
  }
  if edit_end <= other.position {
    append_text0(dest, edit)
    return
  }
  let start = edit.position.max(other.position)
  let end = edit_end.min(other_end)
  let overlap = code_slice(
    edit.text,
    start - edit.position,
    end - edit.position,
  )
  guard overlap ==
    code_slice(other.text, start - other.position, end - other.position) else {
    raise TextMismatch(start)
  }
  let prefix = code_slice(edit.text, 0, start - edit.position)
  let suffix = code_slice(edit.text, end - edit.position, edit.text.length())
  append_text0(dest, {
    ..edit,
    position: transform_position(edit.position, other, Left),
    text: prefix + suffix,
  })
}
