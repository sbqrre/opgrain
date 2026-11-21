///|
priv struct WireReader {
  input : String
  mut offset : Int32
}

///|
fn WireReader::take(self : WireReader) -> Int32 raise OpError {
  guard self.offset < self.input.length() else {
    raise InvalidJson("unexpected end of string")
  }
  let unit = self.input.code_unit_at(self.offset).to_int()
  self.offset += 1
  unit
}

///|
fn hex_digit(unit : Int32) -> Int32 raise OpError {
  if unit >= 0x30 && unit <= 0x39 {
    unit - 0x30
  } else if unit >= 0x41 && unit <= 0x46 {
    unit - 0x41 + 10
  } else if unit >= 0x61 && unit <= 0x66 {
    unit - 0x61 + 10
  } else {
    raise InvalidJson("invalid Unicode escape")
  }
}

///|
fn write_hex_unit(out : StringBuilder, unit : Int32) -> Unit {
  let digits = "0123456789abcdef"
  for shift in [12, 8, 4, 0] {
    out.write_char(
      digits.code_unit_at((unit >> shift) & 15).to_int().unsafe_to_char(),
    )
  }
}

///|
fn WireReader::escape(self : WireReader) -> Int32 raise OpError {
  match self.take() {
    0x22 => 0x22
    0x5C => 0x5C
    0x2F => 0x2F
    0x62 => 8
    0x66 => 12
    0x6E => 10
    0x72 => 13
    0x74 => 9
    0x75 => {
      let mut unit = 0
      for _ in 0..<4 {
        unit = unit * 16 + hex_digit(self.take())
      }
      unit
    }
    _ => raise InvalidJson("invalid string escape")
  }
}

///|
fn is_surrogate(unit : Int32) -> Bool {
  unit >= 0xD800 && unit <= 0xDFFF
}

///|
const WIRE_MARKER : Int32 = 0xE000

///|
fn write_shielded_unit(out : StringBuilder, unit : Int32) -> Unit {
  if is_surrogate(unit) || unit == WIRE_MARKER {
    out.write_string("\\ue000")
    write_hex_unit(out, unit)
  } else if unit < 0x20 || unit == 0x22 || unit == 0x5C {
    out.write_string("\\u")
    write_hex_unit(out, unit)
  } else {
    out.write_char(unit.unsafe_to_char())
  }
}

///|
fn unpack_units(encoded : String) -> String raise OpError {
  if !encoded.contains_code_unit(0xE000) {
    return encoded
  }
  let units = []
  let reader = WireReader::{ input: encoded, offset: 0, }
  while reader.offset < encoded.length() {
    let unit = reader.take()
    if unit == WIRE_MARKER {
      let mut literal = 0
      for _ in 0..<4 {
        literal = literal * 16 + hex_digit(reader.take())
      }
      units.push(literal.unsafe_to_char())
    } else {
      units.push(unit.unsafe_to_char())
    }
  }
  String::from_array(units)
}

///|
fn restore_wire_atom(value : Json) -> Json raise OpError {
  match value {
    String(text) => Json::string(unpack_units(text))
    Array(_) => Json::array([])
    Object(_) => Json::object(Map([]))
    Number(n, ..) => {
      ignore(checked_number(n))
      value
    }
    _ => value
  }
}

///|
fn restore_wire_strings(value : Json) -> Json raise OpError {
  let root = restore_wire_atom(value)
  let pending = [(value, root)]
  while pending.pop() is Some((source, target)) {
    match (source, target) {
      (Array(items), Array(output)) =>
        for child in items {
          let restored = restore_wire_atom(child)
          output.push(restored)
          match child {
            Array(_) | Object(_) => pending.push((child, restored))
            _ => ()
          }
        }
      (Object(fields), Object(output)) =>
        for key, child in fields {
          let restored = restore_wire_atom(child)
          output[unpack_units(key)] = restored
          match child {
            Array(_) | Object(_) => pending.push((child, restored))
            _ => ()
          }
        }
      _ => ()
    }
  }
  root
}

///|
/// Parse JSON while retaining isolated UTF-16 surrogate code units.
pub fn parse_json(source : String) -> Json raise OpError {
  let reader = WireReader::{ input: source, offset: 0, }
  let out = StringBuilder()
  while reader.offset < source.length() {
    let unit = reader.take()
    if unit == 0x22 {
      // Reserve the marker in each string before passing its grammar to core/json.
      out.write_char('"')
      while true {
        let next = reader.take()
        if next == 0x22 {
          break
        }
        guard next >= 0x20 else {
          raise InvalidJson("unescaped control in string")
        }
        let decoded = if next == 0x5C { reader.escape() } else { next }
        write_shielded_unit(out, decoded)
      }
      out.write_char('"')
    } else {
      guard unit <= 0x7F else { raise InvalidJson("invalid JSON token") }
      out.write_char(unit.unsafe_to_char())
    }
  }
  let value = @json.parse(out.to_string()) catch {
    error => raise InvalidJson(error.to_string())
  }
  restore_wire_strings(value)
}

///|
fn write_wire_string(out : StringBuilder, value : String) -> Unit {
  out.write_char('"')
  for i in 0..<value.length() {
    let unit = value.code_unit_at(i).to_int()
    if unit >= 0x20 && unit <= 0x7E && unit != 0x22 && unit != 0x5C {
      out.write_char(unit.unsafe_to_char())
    } else {
      out.write_string("\\u")
      write_hex_unit(out, unit)
    }
  }
  out.write_char('"')
}

///|
priv enum WireTask {
  Value(Json)
  Punctuation(Char)
  Key(String)
}

///|
fn write_wire(out : StringBuilder, value : Json) -> Unit raise OpError {
  let tasks = [WireTask::Value(value)]
  while tasks.pop() is Some(task) {
    match task {
      Punctuation(character) => out.write_char(character)
      Key(key) => write_wire_string(out, key)
      Value(value) =>
        match value {
          String(text) => write_wire_string(out, text)
          Array(items) => {
            out.write_char('[')
            tasks.push(Punctuation(']'))
            for i = items.length() - 1; i >= 0; i = i - 1 {
              tasks.push(Value(items[i]))
              if i != 0 {
                tasks.push(Punctuation(','))
              }
            }
          }
          Object(fields) => {
            out.write_char('{')
            tasks.push(Punctuation('}'))
            let members = []
            for key, child in fields {
              members.push((key, child))
            }
            for i = members.length() - 1; i >= 0; i = i - 1 {
              let (key, child) = members[i]
              tasks.push(Value(child))
              tasks.push(Punctuation(':'))
              tasks.push(Key(key))
              if i != 0 {
                tasks.push(Punctuation(','))
              }
            }
          }
          Number(n, ..) => {
            ignore(checked_number(n))
            out.write_string(Json::number(n).stringify())
          }
          _ => out.write_string(value.stringify())
        }
    }
  }
}

///|
/// Write JSON with a reversible escape for every non-ASCII code unit.
pub fn stringify_json(value : Json) -> String raise OpError {
  validate_json_value(value, [])
  let out = StringBuilder()
  write_wire(out, value)
  out.to_string()
}
