///|
fn same_container(a : Json, b : Json) -> Bool {
  match (a, b) {
    (Array(a), Array(b)) => physical_equal(a, b)
    (Object(a), Object(b)) => physical_equal(a, b)
    _ => false
  }
}

///|
priv enum JsonVisit {
  Enter(Json)
  Leave
}

///|
fn validate_json_iterative(
  value : Json,
  ancestors : Array[Json],
) -> Unit raise OpError {
  let visits : Array[JsonVisit] = [Enter(value)]
  while visits.pop() is Some(visit) {
    match visit {
      Leave => ignore(ancestors.pop())
      Enter(value) =>
        match value {
          Array(items) => {
            guard !ancestors.any(parent => same_container(parent, value)) else {
              raise InvalidJson("cyclic JSON array")
            }
            ancestors.push(value)
            visits.push(Leave)
            for i = items.length() - 1; i >= 0; i = i - 1 {
              visits.push(Enter(items[i]))
            }
          }
          Object(fields) => {
            guard !ancestors.any(parent => same_container(parent, value)) else {
              raise InvalidJson("cyclic JSON object")
            }
            ancestors.push(value)
            visits.push(Leave)
            for _, child in fields {
              visits.push(Enter(child))
            }
          }
          Number(number, ..) => ignore(checked_number(number))
          _ => ()
        }
    }
  }
}

///|
fn empty_copy(value : Json) -> Json {
  match value {
    Object(_) => Json::object(Map([]))
    Array(_) => Json::array([])
    _ => value
  }
}

///|
fn copy_checked_depth(
  value : Json,
  ancestors : Array[Json],
) -> Json raise OpError {
  if ancestors.length() == 64 {
    validate_json_value(value, ancestors.copy())
    return copy_json_iterative(value)
  }
  match value {
    Object(fields) => {
      guard !ancestors.any(parent => same_container(parent, value)) else {
        raise InvalidJson("cyclic JSON object")
      }
      ancestors.push(value)
      defer ignore(ancestors.pop())
      let output = Map([])
      for key, child in fields {
        output[key] = copy_checked_depth(child, ancestors)
      }
      Json::object(output)
    }
    Array(items) => {
      guard !ancestors.any(parent => same_container(parent, value)) else {
        raise InvalidJson("cyclic JSON array")
      }
      ancestors.push(value)
      defer ignore(ancestors.pop())
      Json::array(items.map(child => copy_checked_depth(child, ancestors)))
    }
    Number(number, ..) => {
      ignore(checked_number(number))
      value
    }
    _ => value
  }
}

///|
fn copy_checked_json(value : Json) -> Json raise OpError {
  copy_checked_depth(value, [])
}

///|
fn require_list(
  value : Json,
  path : Array[PathSegment],
) -> Array[Json] raise OpError {
  guard value is Array(items) else {
    raise InvalidPath(path.copy(), "expected a list")
  }
  items
}

///|
fn require_object(
  value : Json,
  path : Array[PathSegment],
) -> Map[String, Json] raise OpError {
  guard value is Object(fields) else {
    raise InvalidPath(path.copy(), "expected an object")
  }
  fields
}

///|
/// Check the operand for a JSON0 list instruction.
pub fn check_list(value : Json) -> Unit raise OpError {
  ignore(require_list(value, []))
}

///|
/// Check the operand for a JSON0 object instruction.
pub fn check_obj(value : Json) -> Unit raise OpError {
  ignore(require_object(value, []))
}

///|
fn validate_json_value(
  value : Json,
  ancestors : Array[Json],
) -> Unit raise OpError {
  if ancestors.length() >= 64 {
    validate_json_iterative(value, ancestors.copy())
    return
  }
  match value {
    Object(fields) => {
      guard !ancestors.any(parent => same_container(parent, value)) else {
        raise InvalidJson("cyclic JSON object")
      }
      ancestors.push(value)
      defer ignore(ancestors.pop())
      for _, child in fields {
        validate_json_value(child, ancestors)
      }
    }
    Array(items) => {
      guard !ancestors.any(parent => same_container(parent, value)) else {
        raise InvalidJson("cyclic JSON array")
      }
      ancestors.push(value)
      defer ignore(ancestors.pop())
      for child in items {
        validate_json_value(child, ancestors)
      }
    }
    Number(number, ..) => ignore(checked_number(number))
    _ => ()
  }
}
