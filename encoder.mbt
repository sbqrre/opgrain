///|
pub(all) struct EncodeOptions {
  escape_non_ascii : Bool
  sort_keys : Bool
  indent : Int32
  chunk_units : Int32
  max_output_units : Int32
}

///|
pub fn EncodeOptions::default() -> EncodeOptions {
  {
    escape_non_ascii: true,
    sort_keys: false,
    indent: 0,
    chunk_units: 4096,
    max_output_units: 67108864,
  }
}

///|
#derive(@debug.Debug)
pub(all) suberror EncodeError {
  InvalidEncodeOptions(String)
  InvalidEncodedValue(OpError)
  EncodedOutputLimit(Int32, Int32)
}

///|
pub extend EncodeError with @debug.Debug::{to_repr}

///|
priv struct JsonEmitter {
  options : EncodeOptions
  sink : (String) -> Unit
  pieces : Array[String]
  mut buffered : Int32
  mut written : Int32
}

///|
fn JsonEmitter::flush(self : JsonEmitter) -> Unit {
  if self.buffered == 0 {
    return
  }
  let out = StringBuilder()
  for piece in self.pieces {
    out.write_string(piece)
  }
  self.pieces.clear()
  self.buffered = 0
  (self.sink)(out.to_string())
}

///|
fn JsonEmitter::write(
  self : JsonEmitter,
  text : String,
) -> Unit raise EncodeError {
  guard text.length() <= self.options.max_output_units - self.written else {
    raise EncodedOutputLimit(self.options.max_output_units, self.written)
  }
  self.written += text.length()
  let mut start = 0
  while start < text.length() {
    let count = (self.options.chunk_units - self.buffered).min(
      text.length() - start,
    )
    self.pieces.push(code_slice(text, start, start + count))
    self.buffered += count
    start += count
    if self.buffered == self.options.chunk_units {
      self.flush()
    }
  }
}

///|
fn JsonEmitter::newline(
  self : JsonEmitter,
  depth : Int32,
) -> Unit raise EncodeError {
  if self.options.indent == 0 {
    return
  }
  self.write("\n")
  for _ in 0..<depth {
    for _ in 0..<self.options.indent {
      self.write(" ")
    }
  }
}

///|
fn escaped_unit(unit : Int32) -> String {
  let text = StringBuilder()
  text.write_string("\\u")
  write_hex_unit(text, unit)
  text.to_string()
}

///|
fn high_surrogate(unit : Int32) -> Bool {
  unit >= 0xD800 && unit <= 0xDBFF
}

///|
fn low_surrogate(unit : Int32) -> Bool {
  unit >= 0xDC00 && unit <= 0xDFFF
}

///|
fn JsonEmitter::string(
  self : JsonEmitter,
  text : String,
) -> Unit raise EncodeError {
  self.write("\"")
  let mut index = 0
  let mut start = 0
  while index < text.length() {
    let unit = text.code_unit_at(index).to_int()
    let paired = high_surrogate(unit) &&
      index + 1 < text.length() &&
      low_surrogate(text.code_unit_at(index + 1).to_int())
    let escaped = unit < 0x20 ||
      unit == 0x22 ||
      unit == 0x5C ||
      (self.options.escape_non_ascii && unit > 0x7E) ||
      (is_surrogate(unit) && !paired)
    if escaped {
      if start < index {
        self.write(code_slice(text, start, index))
      }
      self.write(escaped_unit(unit))
      index += 1
      start = index
    } else {
      index += if paired { 2 } else { 1 }
    }
  }
  if start < text.length() {
    self.write(code_slice(text, start, text.length()))
  }
  self.write("\"")
}

///|
priv enum EmitTask {
  EmitValue(Json, Int32)
  EmitArray(Array[Json], Int32, Int32)
  EmitObject(Array[(String, Json)], Int32, Int32)
}

///|
fn ordered_members(
  fields : Map[String, Json],
  sorted : Bool,
) -> Array[(String, Json)] {
  let keys = []
  for key, _ in fields {
    keys.push(key)
  }
  if sorted {
    keys.sort()
  }
  keys.map(key => (key, fields[key]))
}

///|
fn JsonEmitter::value(
  self : JsonEmitter,
  value : Json,
) -> Unit raise EncodeError {
  let tasks = [EmitValue(value, 0)]
  while tasks.pop() is Some(task) {
    match task {
      EmitValue(value, depth) =>
        match value {
          String(text) => self.string(text)
          Array(items) => {
            self.write("[")
            tasks.push(EmitArray(items, 0, depth))
          }
          Object(fields) => {
            self.write("{")
            tasks.push(
              EmitObject(
                ordered_members(fields, self.options.sort_keys),
                0,
                depth,
              ),
            )
          }
          Number(number, ..) => self.write(Json::number(number).stringify())
          _ => self.write(value.stringify())
        }
      EmitArray(items, index, depth) =>
        if index == items.length() {
          if index != 0 {
            self.newline(depth)
          }
          self.write("]")
        } else {
          if index != 0 {
            self.write(",")
          }
          self.newline(depth + 1)
          tasks.push(EmitArray(items, index + 1, depth))
          tasks.push(EmitValue(items[index], depth + 1))
        }
      EmitObject(members, index, depth) =>
        if index == members.length() {
          if index != 0 {
            self.newline(depth)
          }
          self.write("}")
        } else {
          if index != 0 {
            self.write(",")
          }
          self.newline(depth + 1)
          let (key, child) = members[index]
          self.string(key)
          self.write(if self.options.indent == 0 { ":" } else { ": " })
          tasks.push(EmitObject(members, index + 1, depth))
          tasks.push(EmitValue(child, depth + 1))
        }
    }
  }
}

///|
/// Emit bounded UTF-16 chunks. A sink may observe a prefix if a later budget fails.
pub fn encode_json_to(
  value : Json,
  sink : (String) -> Unit,
  options~ : EncodeOptions = EncodeOptions::default(),
) -> Int32 raise EncodeError {
  guard options.indent >= 0 &&
    options.indent <= 16 &&
    options.chunk_units > 0 &&
    options.max_output_units >= 0 else {
    raise InvalidEncodeOptions(
      "invalid indentation, chunk size or output budget",
    )
  }
  let value = copy_checked_json(value) catch {
    error => raise InvalidEncodedValue(error)
  }
  let emitter = JsonEmitter::{
    options,
    sink,
    pieces: [],
    buffered: 0,
    written: 0,
  }
  emitter.value(value)
  emitter.flush()
  emitter.written
}

///|
pub fn encode_json(
  value : Json,
  options~ : EncodeOptions = EncodeOptions::default(),
) -> String raise EncodeError {
  let out = StringBuilder()
  ignore(encode_json_to(value, text => out.write_string(text), options~))
  out.to_string()
}

///|
pub fn Operation::decode(
  source : String,
  options~ : DecodeOptions = DecodeOptions::default(),
) -> Operation raise {
  Operation::from_json(decode_json(source, options~))
}

///|
pub fn Operation::encode(
  self : Operation,
  options~ : EncodeOptions = EncodeOptions::default(),
) -> String raise EncodeError {
  encode_json(self.to_json(), options~)
}
