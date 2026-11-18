///|
fn same_container(a : Json, b : Json) -> Bool {
  match (a, b) {
    (Array(a), Array(b)) => physical_equal(a, b)
    (Object(a), Object(b)) => physical_equal(a, b)
    _ => false
  }
}

///|
fn validate_json_value(
  value : Json,
  ancestors : Array[Json],
) -> Unit raise OpError {
  match value {
    Array(items) => {
      guard !ancestors.any(parent => same_container(parent, value)) else {
        raise InvalidJson("cyclic JSON array")
      }
      ancestors.push(value)
      for child in items {
        validate_json_value(child, ancestors)
      }
      ignore(ancestors.pop())
    }
    Object(fields) => {
      guard !ancestors.any(parent => same_container(parent, value)) else {
        raise InvalidJson("cyclic JSON object")
      }
      ancestors.push(value)
      for _, child in fields {
        validate_json_value(child, ancestors)
      }
      ignore(ancestors.pop())
    }
    Number(number, ..) => ignore(checked_number(number))
    _ => ()
  }
}

///|
fn copy_checked_json(value : Json) -> Json raise OpError {
  validate_json_value(value, [])
  copy_json(value)
}
