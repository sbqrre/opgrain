///|
#derive(@debug.Debug)
pub(all) suberror CoordinateError {
  CoordinateOutOfBounds(String, Int32)
  SplitCodePoint(Int32)
  IsolatedSurrogate(Int32)
}

///|
pub extend CoordinateError with @debug.Debug::{to_repr}

///|
pub(all) struct TextCoordinates {
  utf16 : Int32
  code_points : Int32
  utf8_bytes : Int32
}

///|
pub struct TextIndex {
  priv text : String
  priv units : Array[Int32]
  priv bytes : Array[Int32]
  priv lines : Array[Int32]
}

///|
fn scalar_width(unit : Int32) -> Int32 {
  if unit <= 0x7F {
    1
  } else if unit <= 0x7FF {
    2
  } else {
    3
  }
}

///|
/// Build strict scalar boundaries. Isolated UTF-16 surrogates return their offset.
pub fn TextIndex::new(text : String) -> TextIndex raise CoordinateError {
  let units = [0]
  let bytes = [0]
  let lines = [0]
  let mut offset = 0
  let mut byte_count = 0
  let mut previous_cr = false
  while offset < text.length() {
    let unit = text.code_unit_at(offset).to_int()
    let width = if high_surrogate(unit) {
      guard offset + 1 < text.length() &&
        low_surrogate(text.code_unit_at(offset + 1).to_int()) else {
        raise IsolatedSurrogate(offset)
      }
      2
    } else {
      guard !low_surrogate(unit) else { raise IsolatedSurrogate(offset) }
      1
    }
    let count = if width == 2 { 4 } else { scalar_width(unit) }
    guard byte_count <= 2147483647 - count else {
      raise CoordinateOutOfBounds("UTF-8 length", byte_count)
    }
    byte_count += count
    offset += width
    units.push(offset)
    bytes.push(byte_count)
    if unit == 0x0D {
      lines.push(offset)
      previous_cr = true
    } else if unit == 0x0A {
      if previous_cr {
        lines[lines.length() - 1] = offset
      } else {
        lines.push(offset)
      }
      previous_cr = false
    } else {
      previous_cr = false
    }
  }
  { text, units, bytes, lines, }
}

///|
pub fn TextIndex::lengths(self : TextIndex) -> TextCoordinates {
  {
    utf16: self.text.length(),
    code_points: self.units.length() - 1,
    utf8_bytes: self.bytes[self.bytes.length() - 1],
  }
}

///|
fn boundary_search(boundaries : Array[Int32], value : Int32) -> Int32? {
  let mut low = 0
  let mut high = boundaries.length()
  while low < high {
    let middle = low + (high - low) / 2
    if boundaries[middle] < value {
      low = middle + 1
    } else {
      high = middle
    }
  }
  if low < boundaries.length() && boundaries[low] == value {
    Some(low)
  } else {
    None
  }
}

///|
pub fn TextIndex::at_utf16(
  self : TextIndex,
  offset : Int32,
) -> TextCoordinates raise CoordinateError {
  guard offset >= 0 && offset <= self.text.length() else {
    raise CoordinateOutOfBounds("UTF-16", offset)
  }
  guard boundary_search(self.units, offset) is Some(index) else {
    raise SplitCodePoint(offset)
  }
  { utf16: offset, code_points: index, utf8_bytes: self.bytes[index], }
}

///|
pub fn TextIndex::at_code_point(
  self : TextIndex,
  offset : Int32,
) -> TextCoordinates raise CoordinateError {
  guard offset >= 0 && offset < self.units.length() else {
    raise CoordinateOutOfBounds("code points", offset)
  }
  {
    utf16: self.units[offset],
    code_points: offset,
    utf8_bytes: self.bytes[offset],
  }
}

///|
pub fn TextIndex::at_utf8(
  self : TextIndex,
  offset : Int32,
) -> TextCoordinates raise CoordinateError {
  guard offset >= 0 && offset <= self.bytes[self.bytes.length() - 1] else {
    raise CoordinateOutOfBounds("UTF-8", offset)
  }
  guard boundary_search(self.bytes, offset) is Some(index) else {
    raise CoordinateOutOfBounds("inside UTF-8 sequence", offset)
  }
  { utf16: self.units[index], code_points: index, utf8_bytes: offset, }
}

///|
pub fn TextIndex::line_count(self : TextIndex) -> Int32 {
  self.lines.length()
}

///|
/// Line and column are zero-based, and column is a UTF-16 offset.
pub fn TextIndex::line_position(
  self : TextIndex,
  offset : Int32,
) -> (Int32, Int32) raise CoordinateError {
  guard offset >= 0 && offset <= self.text.length() else {
    raise CoordinateOutOfBounds("UTF-16", offset)
  }
  let mut low = 0
  let mut high = self.lines.length()
  while low < high {
    let middle = low + (high - low) / 2
    if self.lines[middle] <= offset {
      low = middle + 1
    } else {
      high = middle
    }
  }
  let line = low - 1
  (line, offset - self.lines[line])
}

///|
pub fn TextIndex::line_offset(
  self : TextIndex,
  line : Int32,
  column : Int32,
) -> Int32 raise CoordinateError {
  guard line >= 0 && line < self.lines.length() && column >= 0 else {
    raise CoordinateOutOfBounds("line", line)
  }
  let start = self.lines[line]
  let end = if line + 1 < self.lines.length() {
    self.lines[line + 1]
  } else {
    self.text.length()
  }
  guard column <= end - start &&
    (line + 1 == self.lines.length() || column < end - start) else {
    raise CoordinateOutOfBounds("column", column)
  }
  start + column
}

///|
pub fn TextIndex::slice_code_points(
  self : TextIndex,
  start : Int32,
  end : Int32,
) -> String raise CoordinateError {
  guard start >= 0 && end >= start && end < self.units.length() else {
    raise CoordinateOutOfBounds("code point slice", end)
  }
  code_slice(self.text, self.units[start], self.units[end])
}

///|
pub fn TextIndex::splice_code_points(
  self : TextIndex,
  start : Int32,
  count : Int32,
  inserted : String,
) -> TextOperation raise {
  guard count >= 0 &&
    start >= 0 &&
    start < self.units.length() &&
    count <= self.units.length() - 1 - start else {
    raise CoordinateOutOfBounds("code point splice", start)
  }
  TextOperation::splice(
    self.text,
    self.units[start],
    self.units[start + count] - self.units[start],
    inserted,
  )
}

///|
pub fn TextIndex::nearest_boundary(
  self : TextIndex,
  offset : Int32,
  affinity : InsertionAffinity,
) -> Int32 raise CoordinateError {
  guard offset >= 0 && offset <= self.text.length() else {
    raise CoordinateOutOfBounds("UTF-16", offset)
  }
  if boundary_search(self.units, offset) is Some(_) {
    return offset
  }
  match affinity {
    BeforeInsertion => offset - 1
    AfterInsertion => offset + 1
  }
}
