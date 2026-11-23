///|
#derive(@debug.Debug)
pub(all) suberror PointerError {
  InvalidPointer(Int32, String)
  PointerPath(Int32, OpError)
}

///|
pub extend PointerError with @debug.Debug::{to_repr}

///|
fn pointer_tokens(source : String) -> Array[String] raise PointerError {
  if source == "" {
    return []
  }
  guard source[0] == '/' else {
    raise InvalidPointer(0, "pointer must start with slash")
  }
  let tokens = []
  let mut token = StringBuilder()
  let mut index = 1
  while index < source.length() {
    let unit = source[index].to_int()
    if unit == 47 {
      tokens.push(token.to_string())
      token = StringBuilder()
      index += 1
    } else if unit == 126 {
      guard index + 1 < source.length() else {
        raise InvalidPointer(index, "unfinished pointer escape")
      }
      match source[index + 1].to_int() {
        48 => token.write_char('~')
        49 => token.write_char('/')
        _ => raise InvalidPointer(index, "pointer escape must be ~0 or ~1")
      }
      index += 2
    } else {
      token.write_char(unit.unsafe_to_char())
      index += 1
    }
  }
  tokens.push(token.to_string())
  tokens
}

///|
fn pointer_index(token : String, offset : Int32) -> Int32 raise PointerError {
  guard token != "" && (token.length() == 1 || token[0] != '0') else {
    raise InvalidPointer(offset, "noncanonical list index")
  }
  let mut value = 0
  for unit in token {
    let digit = unit.to_int() - 48
    guard digit >= 0 && digit <= 9 && value <= (2147483647 - digit) / 10 else {
      raise InvalidPointer(offset, "invalid or overflowing list index")
    }
    value = value * 10 + digit
  }
  value
}

///|
/// Resolve pointer tokens using actual container types, preserving the JSON0
/// distinction between an object key "0" and a list index 0.
pub fn Snapshot::resolve_pointer(
  self : Snapshot,
  source : String,
  allow_missing_leaf~ : Bool = false,
) -> Path raise PointerError {
  let tokens = pointer_tokens(source)
  let path = []
  let mut value = self.value
  for index, token in tokens {
    let last = index == tokens.length() - 1
    match value {
      Some(Object(fields)) => {
        path.push(Key(token))
        value = fields.get(token)
        guard value is Some(_) || (last && allow_missing_leaf) else {
          raise InvalidPointer(index, "object member does not exist")
        }
      }
      Some(Array(items)) => {
        let position = if token == "-" && last && allow_missing_leaf {
          items.length()
        } else {
          pointer_index(token, index)
        }
        guard position < items.length() ||
          (last && allow_missing_leaf && position == items.length()) else {
          raise InvalidPointer(index, "list index out of bounds")
        }
        path.push(Index(position))
        value = items.get(position)
      }
      _ => raise InvalidPointer(index, "parent is missing or not a container")
    }
  }
  { segments: path, }
}

///|
fn write_pointer_token(out : StringBuilder, token : String) -> Unit {
  for unit in token {
    match unit.to_int() {
      47 => out.write_string("~1")
      126 => out.write_string("~0")
      value => out.write_char(value.unsafe_to_char())
    }
  }
}

///|
/// Pointer text alone does not retain object/list segment types; resolve it
/// against the document when converting back into a JSON0 path.
pub fn Path::to_pointer(self : Path) -> String {
  let out = StringBuilder()
  for segment in self.segments {
    out.write_char('/')
    match segment {
      Key(key) => write_pointer_token(out, key)
      Index(index) => out.write_string(index.to_string())
    }
  }
  out.to_string()
}

///|
pub fn Snapshot::read_pointer(
  self : Snapshot,
  source : String,
) -> Json raise PointerError {
  let path = self.resolve_pointer(source)
  self.at(path) catch {
    error => raise PointerPath(path.length(), error)
  }
}

///|
pub fn Snapshot::contains_pointer(
  self : Snapshot,
  source : String,
) -> Bool raise PointerError {
  ignore(pointer_tokens(source))
  self.contains_path(self.resolve_pointer(source)) catch {
    InvalidPointer(_, _) => false
    error => raise error
  }
}
