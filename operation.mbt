///|
#derive(Eq, Debug)
pub(all) enum PathSegment {
  Key(String)
  Index(Int32)
}

///|
pub extend PathSegment with Eq::{not_equal, equal}

///|
pub extend PathSegment with @debug.Debug::{to_repr}

///|
#derive(Eq, Debug)
pub(all) enum Side {
  Left
  Right
}

///|
pub extend Side with Eq::{not_equal, equal}

///|
pub extend Side with @debug.Debug::{to_repr}

///|
#derive(Debug)
pub(all) suberror OpError {
  InvalidJson(String)
  InvalidComponent(Int32, String)
  InvalidPath(Array[PathSegment], String)
  UnknownSubtype(String)
  SubtypeError(String, String)
  TextMismatch(Int32)
  NonFiniteNumber
  MissingRoot
}

///|
pub extend OpError with @debug.Debug::{to_repr}

///|
priv enum Action {
  Add(Double)
  ListEdit(Json?, Json?)
  Move(Int32)
  ObjectEdit(Json?, Json?)
  LegacyText(Bool, String)
  SubtypeEdit(String, Json)
}

///|
pub struct Component {
  priv path : Array[PathSegment]
  priv action : Action
}

///|
/// A validated JSON0 operation. Components are applied in array order.
pub struct Operation {
  priv components : Array[Component]
}

///|
pub let name : String = "json0"

///|
pub let uri : String = "http://sharejs.org/types/JSONv0"

///|
fn copy_json(value : Json) -> Json {
  match value {
    Object(fields) => {
      let result = Map([])
      for key, item in fields {
        result[key] = copy_json(item)
      }
      Json::object(result)
    }
    Array(items) => Json::array(items.map(copy_json))
    _ => value
  }
}

///|
fn checked_number(value : Double) -> Double raise OpError {
  guard !value.is_nan() && !value.is_inf() else { raise NonFiniteNumber }
  value
}

///|
fn nonnegative_index(value : Json, index : Int32) -> Int32 raise OpError {
  guard value is Number(n, ..) &&
    n >= 0.0 &&
    n <= 2147483647.0 &&
    n == n.to_int().to_double() else {
    raise InvalidComponent(index, "expected a nonnegative integer index")
  }
  n.to_int()
}

///|
fn decode_path(value : Json, index : Int32) -> Array[PathSegment] raise OpError {
  guard value is Array(items) else {
    raise InvalidComponent(index, "p must be an array")
  }
  items.map(part => {
    match part {
      String(key) => Key(key)
      _ => Index(nonnegative_index(part, index))
    }
  })
}

///|
fn encode_path(path : Array[PathSegment]) -> Json {
  Json::array(
    path.map(part => {
      match part {
        Key(key) => Json::string(key)
        Index(index) => Json::number(index.to_double())
      }
    }),
  )
}

///|
fn decode_component(
  value : Json,
  index : Int32,
  default_path~ : Bool,
) -> Component raise OpError {
  guard value is Object(fields) else {
    raise InvalidComponent(index, "component must be an object")
  }
  let path = match fields.get("p") {
    None if default_path => []
    Some(Null) if default_path => []
    Some(value) => decode_path(value, index)
    _ => raise InvalidComponent(index, "missing p")
  }
  let li = fields.get("li")
  let ld = fields.get("ld")
  let oi = fields.get("oi")
  let od = fields.get("od")
  let na = fields.get("na")
  let lm = fields.get("lm")
  let si = fields.get("si")
  let sd = fields.get("sd")
  let kind = fields.get("t")
  let payload = fields.get("o")
  let mut groups = 0
  for
    present in [
      li is Some(_) || ld is Some(_),
      oi is Some(_) || od is Some(_),
      na is Some(_),
      lm is Some(_),
      si is Some(_),
      sd is Some(_),
      kind is Some(_) || payload is Some(_),
    ] {
    if present {
      groups += 1
    }
  }
  guard groups == 1 else {
    raise InvalidComponent(index, "expected one instruction")
  }
  let action = match (li, ld, oi, od, na, lm, si, sd, kind, payload) {
    (Some(_), _, _, _, _, _, _, _, _, _)
    | (_, Some(_), _, _, _, _, _, _, _, _) => {
      guard path.last() is Some(Index(_)) else {
        raise InvalidComponent(index, "list path must end in an index")
      }
      ListEdit(li.map(copy_json), ld.map(copy_json))
    }
    (_, _, Some(_), _, _, _, _, _, _, _)
    | (_, _, _, Some(_), _, _, _, _, _, _) => {
      guard path.is_empty() || path.last() is Some(Key(_)) else {
        raise InvalidComponent(index, "object path must end in a key")
      }
      ObjectEdit(oi.map(copy_json), od.map(copy_json))
    }
    (_, _, _, _, Some(Number(amount, ..)), _, _, _, _, _) =>
      Add(checked_number(amount))
    (_, _, _, _, _, Some(destination), _, _, _, _) => {
      guard path.last() is Some(Index(_)) else {
        raise InvalidComponent(index, "move path must end in an index")
      }
      Move(nonnegative_index(destination, index))
    }
    (_, _, _, _, _, _, Some(String(text)), _, _, _)
    | (_, _, _, _, _, _, _, Some(String(text)), _, _) => {
      guard path.last() is Some(Index(_)) else {
        raise InvalidComponent(index, "legacy text path must end in an offset")
      }
      LegacyText(si is Some(_), text)
    }
    (_, _, _, _, _, _, _, _, Some(String(kind)), Some(payload)) if !kind.is_empty() =>
      SubtypeEdit(kind, copy_json(payload))
    _ => raise InvalidComponent(index, "invalid instruction payload")
  }
  { path, action, }
}

///|
fn put_if_some(fields : Map[String, Json], key : String, value : Json?) -> Unit {
  if value is Some(value) {
    fields[key] = copy_json(value)
  }
}

///|
fn encode_component(component : Component) -> Json {
  let fields = Map([])
  fields["p"] = encode_path(component.path)
  match component.action {
    Add(amount) => fields["na"] = Json::number(amount)
    Move(index) => fields["lm"] = Json::number(index.to_double())
    ListEdit(insert, delete) => {
      put_if_some(fields, "li", insert)
      put_if_some(fields, "ld", delete)
    }
    ObjectEdit(insert, delete) => {
      put_if_some(fields, "oi", insert)
      put_if_some(fields, "od", delete)
    }
    LegacyText(insert, text) =>
      fields[if insert { "si" } else { "sd" }] = Json::string(text)
    SubtypeEdit(kind, payload) => {
      fields["t"] = Json::string(kind)
      fields["o"] = copy_json(payload)
    }
  }
  Json::object(fields)
}

///|
pub fn Component::from_json(value : Json) -> Component raise OpError {
  decode_component(value, 0, default_path=false)
}

///|
pub fn Component::to_json(self : Component) -> Json {
  encode_component(self)
}

///|
pub fn Component::get_path(self : Component) -> Array[PathSegment] {
  self.path.copy()
}

///|
pub fn Operation::from_components(components : Array[Component]) -> Operation {
  { components: components.copy(), }
}

///|
pub fn Operation::get_components(self : Operation) -> Array[Component] {
  self.components.copy()
}

///|
pub fn Operation::from_json(value : Json) -> Operation raise OpError {
  guard value is Array(items) else {
    raise InvalidComponent(0, "expected an operation array")
  }
  let components = []
  for i, item in items {
    components.push(decode_component(item, i, default_path=false))
  }
  { components, }
}

///|
pub fn Operation::parse(source : String) -> Operation raise OpError {
  Operation::from_json(parse_json(source))
}

///|
pub fn Operation::to_json(self : Operation) -> Json {
  Json::array(self.components.map(encode_component))
}

///|
pub fn Operation::stringify(self : Operation) -> String raise OpError {
  stringify_json(self.to_json())
}

///|
pub fn Operation::length(self : Operation) -> Int32 {
  self.components.length()
}

///|
pub fn Operation::shatter(self : Operation) -> Array[Operation] {
  self.components.map(component => { components: [component], })
}

///|
pub fn check_valid_op(value : Json) -> Unit raise OpError {
  ignore(Operation::from_json(value))
}

///|
pub fn create(data~ : Json = Json::null()) -> Json {
  copy_json(data)
}
