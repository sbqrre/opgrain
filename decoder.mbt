///|
pub(all) struct DecodeOptions {
  max_depth : Int32
  max_values : Int32
  max_string_units : Int32
  max_input_units : Int32
  reject_duplicate_keys : Bool
}

///|
pub fn DecodeOptions::default() -> DecodeOptions {
  {
    max_depth: 1024,
    max_values: 1000000,
    max_string_units: 16777216,
    max_input_units: 67108864,
    reject_duplicate_keys: false,
  }
}

///|
#derive(@debug.Debug)
pub(all) suberror DecodeError {
  JsonSyntax(Int32, String)
  JsonLimit(Int32, String, Int32)
  DuplicateMember(Int32, String)
  InvalidDecodeOptions(String)
  JsonNumberOverflow(Int32)
}

///|
pub extend DecodeError with @debug.Debug::{to_repr}

///|
priv struct JsonDecoder {
  reader : WireReader
  options : DecodeOptions
  mut values : Int32
}

///|
priv struct DecodeFrame {
  container : Json
  mut state : Int32
  mut key : String
}

///|
fn check_decode_options(options : DecodeOptions) -> Unit raise DecodeError {
  guard options.max_depth >= 0 &&
    options.max_values >= 0 &&
    options.max_string_units >= 0 &&
    options.max_input_units >= 0 else {
    raise InvalidDecodeOptions("limits must be nonnegative")
  }
}

///|
fn JsonDecoder::peek(self : JsonDecoder) -> Int32? {
  if self.reader.offset < self.reader.input.length() {
    Some(self.reader.input.code_unit_at(self.reader.offset).to_int())
  } else {
    None
  }
}

///|
fn JsonDecoder::space(self : JsonDecoder) -> Unit {
  while self.peek() is Some(unit) &&
        (unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D) {
    self.reader.offset += 1
  }
}

///|
fn JsonDecoder::take(self : JsonDecoder) -> Int32 raise DecodeError {
  guard self.peek() is Some(unit) else {
    raise JsonSyntax(self.reader.offset, "unexpected end of input")
  }
  self.reader.offset += 1
  unit
}

///|
fn JsonDecoder::expect(
  self : JsonDecoder,
  expected : Int32,
) -> Unit raise DecodeError {
  let offset = self.reader.offset
  guard self.take() == expected else {
    raise JsonSyntax(offset, "unexpected JSON punctuation")
  }
}

///|
fn JsonDecoder::literal(
  self : JsonDecoder,
  expected : String,
) -> Unit raise DecodeError {
  for index in 0..<expected.length() {
    self.expect(expected.code_unit_at(index).to_int())
  }
}

///|
fn JsonDecoder::string(self : JsonDecoder) -> String raise DecodeError {
  self.expect(0x22)
  let units = []
  while true {
    let offset = self.reader.offset
    let unit = self.take()
    if unit == 0x22 {
      break
    }
    guard unit >= 0x20 else {
      raise JsonSyntax(offset, "unescaped control in string")
    }
    let decoded = if unit == 0x5C {
      self.reader.escape() catch {
        _ => raise JsonSyntax(self.reader.offset, "invalid string escape")
      }
    } else {
      unit
    }
    guard units.length() < self.options.max_string_units else {
      raise JsonLimit(offset, "string units", self.options.max_string_units)
    }
    units.push(decoded.unsafe_to_char())
  }
  String::from_array(units)
}

///|
fn decimal_digit(unit : Int32?) -> Bool {
  unit is Some(unit) && unit >= 0x30 && unit <= 0x39
}

///|
fn JsonDecoder::digits(self : JsonDecoder) -> Unit raise DecodeError {
  guard decimal_digit(self.peek()) else {
    raise JsonSyntax(self.reader.offset, "expected decimal digit")
  }
  while decimal_digit(self.peek()) {
    self.reader.offset += 1
  }
}

///|
fn JsonDecoder::number(self : JsonDecoder) -> Json raise DecodeError {
  let start = self.reader.offset
  if self.peek() == Some(0x2D) {
    self.reader.offset += 1
  }
  if self.peek() == Some(0x30) {
    self.reader.offset += 1
    if decimal_digit(self.peek()) {
      raise JsonSyntax(self.reader.offset, "leading zero in number")
    }
  } else {
    guard self.peek() is Some(first) && first >= 0x31 && first <= 0x39 else {
      raise JsonSyntax(self.reader.offset, "invalid number")
    }
    self.digits()
  }
  if self.peek() == Some(0x2E) {
    self.reader.offset += 1
    self.digits()
  }
  if self.peek() == Some(0x65) || self.peek() == Some(0x45) {
    self.reader.offset += 1
    if self.peek() == Some(0x2B) || self.peek() == Some(0x2D) {
      self.reader.offset += 1
    }
    self.digits()
  }
  let source = code_slice(self.reader.input, start, self.reader.offset)
  let value = @json.parse(source) catch {
    _ => raise JsonSyntax(start, "invalid JSON number")
  }
  guard value is Number(number, ..) else {
    raise JsonSyntax(start, "expected a number")
  }
  guard !number.is_nan() && !number.is_inf() else {
    raise JsonNumberOverflow(start)
  }
  value
}

///|
fn JsonDecoder::value(
  self : JsonDecoder,
  frames : Array[DecodeFrame],
) -> Json raise DecodeError {
  self.space()
  guard self.values < self.options.max_values else {
    raise JsonLimit(self.reader.offset, "values", self.options.max_values)
  }
  self.values += 1
  match self.peek() {
    Some(0x22) => Json::string(self.string())
    Some(0x74) => {
      self.literal("true")
      Json::boolean(true)
    }
    Some(0x66) => {
      self.literal("false")
      Json::boolean(false)
    }
    Some(0x6E) => {
      self.literal("null")
      Json::null()
    }
    Some(0x5B) | Some(0x7B) => {
      guard frames.length() < self.options.max_depth else {
        raise JsonLimit(self.reader.offset, "depth", self.options.max_depth)
      }
      let container = if self.take() == 0x5B {
        Json::array([])
      } else {
        Json::object(Map([]))
      }
      frames.push({ container, state: 0, key: "", })
      container
    }
    Some(unit) if unit == 0x2D || (unit >= 0x30 && unit <= 0x39) =>
      self.number()
    _ => raise JsonSyntax(self.reader.offset, "expected JSON value")
  }
}

///|
fn JsonDecoder::array_step(
  self : JsonDecoder,
  frame : DecodeFrame,
  items : Array[Json],
  frames : Array[DecodeFrame],
) -> Unit raise DecodeError {
  match frame.state {
    0 if self.peek() == Some(0x5D) => {
      self.reader.offset += 1
      ignore(frames.pop())
    }
    0 | 1 => {
      frame.state = 2
      let value = self.value(frames)
      items.push(value)
    }
    2 =>
      match self.take() {
        0x2C => frame.state = 1
        0x5D => ignore(frames.pop())
        _ =>
          raise JsonSyntax(
            self.reader.offset - 1,
            "expected list separator or closing bracket",
          )
      }
    _ => abort("invalid array parser state")
  }
}

///|
fn JsonDecoder::object_step(
  self : JsonDecoder,
  frame : DecodeFrame,
  fields : Map[String, Json],
  frames : Array[DecodeFrame],
) -> Unit raise DecodeError {
  match frame.state {
    0 if self.peek() == Some(0x7D) => {
      self.reader.offset += 1
      ignore(frames.pop())
    }
    0 | 1 => {
      let offset = self.reader.offset
      frame.key = self.string()
      if self.options.reject_duplicate_keys && fields.contains(frame.key) {
        raise DuplicateMember(offset, frame.key)
      }
      frame.state = 3
    }
    3 => {
      self.expect(0x3A)
      frame.state = 4
    }
    4 => {
      frame.state = 5
      let value = self.value(frames)
      fields[frame.key] = value
    }
    5 =>
      match self.take() {
        0x2C => frame.state = 1
        0x7D => ignore(frames.pop())
        _ =>
          raise JsonSyntax(
            self.reader.offset - 1,
            "expected member separator or closing brace",
          )
      }
    _ => abort("invalid object parser state")
  }
}

///|
/// Parse JSON with UTF-16 offsets, finite binary64 numbers and configurable budgets.
pub fn decode_json(
  source : String,
  options~ : DecodeOptions = DecodeOptions::default(),
) -> Json raise DecodeError {
  check_decode_options(options)
  guard source.length() <= options.max_input_units else {
    raise JsonLimit(0, "input units", options.max_input_units)
  }
  let decoder = JsonDecoder::{
    reader: { input: source, offset: 0, },
    options,
    values: 0,
  }
  let frames = []
  let root = decoder.value(frames)
  while frames.last() is Some(frame) {
    decoder.space()
    match frame.container {
      Array(items) => decoder.array_step(frame, items, frames)
      Object(fields) => decoder.object_step(frame, fields, frames)
      _ => abort("invalid container parser frame")
    }
  }
  decoder.space()
  guard decoder.peek() is None else {
    raise JsonSyntax(decoder.reader.offset, "trailing input")
  }
  root
}

///|
/// A bounded input accumulator for callers receiving chunks of JSON text.
pub struct JsonInput {
  priv options : DecodeOptions
  priv chunks : Array[String]
  priv mut units : Int32
}

///|
pub fn JsonInput::new(
  options~ : DecodeOptions = DecodeOptions::default(),
) -> JsonInput raise DecodeError {
  check_decode_options(options)
  { options, chunks: [], units: 0, }
}

///|
pub fn JsonInput::push(
  self : JsonInput,
  chunk : String,
) -> Unit raise DecodeError {
  guard chunk.length() <= self.options.max_input_units - self.units else {
    raise JsonLimit(self.units, "input units", self.options.max_input_units)
  }
  self.chunks.push(chunk)
  self.units += chunk.length()
}

///|
pub fn JsonInput::length(self : JsonInput) -> Int32 {
  self.units
}

///|
pub fn JsonInput::finish(self : JsonInput) -> Json raise DecodeError {
  let out = StringBuilder()
  for chunk in self.chunks {
    out.write_string(chunk)
  }
  decode_json(out.to_string(), options=self.options)
}

///|
pub fn JsonInput::reset(self : JsonInput) -> Unit {
  self.chunks.clear()
  self.units = 0
}

///|
pub(all) struct SourcePosition {
  offset : Int32
  line : Int32
  column : Int32
}

///|
pub fn source_position(
  source : String,
  offset : Int32,
) -> SourcePosition raise OpError {
  guard offset >= 0 && offset <= source.length() else {
    raise InvalidJson("source position outside input")
  }
  let mut line = 1
  let mut column = 1
  let mut last_cr = false
  for index in 0..<offset {
    let unit = source.code_unit_at(index).to_int()
    if unit == 0x0D {
      line += 1
      column = 1
      last_cr = true
    } else if unit == 0x0A {
      if !last_cr {
        line += 1
      }
      column = 1
      last_cr = false
    } else {
      column += 1
      last_cr = false
    }
  }
  { offset, line, column, }
}
