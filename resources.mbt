///|
pub(all) struct ValueMetrics {
  values : Int64
  containers : Int64
  strings : Int64
  string_units : Int64
  numbers : Int64
  max_depth : Int32
}

///|
pub(all) struct OperationMetrics {
  components : Int32
  path_segments : Int64
  max_path : Int32
  payload_values : Int64
  payload_string_units : Int64
  max_payload_depth : Int32
  text_units : Int64
  moves : Int32
}

///|
fn value_metrics(value : Json?) -> ValueMetrics {
  let pending = []
  if value is Some(value) {
    pending.push((value, 0))
  }
  let mut values = 0L
  let mut containers = 0L
  let mut strings = 0L
  let mut string_units = 0L
  let mut numbers = 0L
  let mut max_depth = 0
  while pending.pop() is Some((value, depth)) {
    values += 1
    max_depth = max_depth.max(depth)
    match value {
      Object(fields) => {
        containers += 1
        for key, child in fields {
          string_units += key.length().to_int64()
          pending.push((child, depth + 1))
        }
      }
      Array(items) => {
        containers += 1
        for child in items {
          pending.push((child, depth + 1))
        }
      }
      String(text) => {
        strings += 1
        string_units += text.length().to_int64()
      }
      Number(_) => numbers += 1
      _ => ()
    }
  }
  { values, containers, strings, string_units, numbers, max_depth, }
}

///|
pub fn Snapshot::metrics(self : Snapshot) -> ValueMetrics {
  value_metrics(self.value)
}

///|
fn component_payloads(component : Component) -> Array[Json] {
  let values = []
  match component.action {
    ObjectEdit(insert, delete) | ListEdit(insert, delete) => {
      if insert is Some(value) {
        values.push(value)
      }
      if delete is Some(value) {
        values.push(value)
      }
    }
    SubtypeEdit(_, payload) => values.push(payload)
    _ => ()
  }
  values
}

///|
pub fn Operation::metrics(self : Operation) -> OperationMetrics {
  let mut path_segments = 0L
  let mut max_path = 0
  let mut payload_values = 0L
  let mut payload_string_units = 0L
  let mut max_payload_depth = 0
  let mut text_units = 0L
  let mut moves = 0
  for component in self.components {
    path_segments += component.path.length().to_int64()
    max_path = max_path.max(component.path.length())
    for segment in component.path {
      if segment is Key(key) {
        payload_string_units += key.length().to_int64()
      }
    }
    for payload in component_payloads(component) {
      let metrics = value_metrics(Some(payload))
      payload_values += metrics.values
      payload_string_units += metrics.string_units
      max_payload_depth = max_payload_depth.max(metrics.max_depth)
    }
    match component.action {
      LegacyText(_, text) => text_units += text.length().to_int64()
      Move(_) => moves += 1
      _ => ()
    }
  }
  {
    components: self.length(),
    path_segments,
    max_path,
    payload_values,
    payload_string_units,
    max_payload_depth,
    text_units,
    moves,
  }
}

///|
pub(all) struct OperationLimits {
  max_components : Int32
  max_path : Int32
  max_payload_values : Int64
  max_payload_depth : Int32
  max_string_units : Int64
  max_document_values : Int64
  max_document_depth : Int32
  allowed_subtypes : Array[String]?
  allow_root_edits : Bool
  allow_legacy_text : Bool
}

///|
pub fn OperationLimits::default() -> OperationLimits {
  {
    max_components: 10000,
    max_path: 1024,
    max_payload_values: 1000000L,
    max_payload_depth: 1024,
    max_string_units: 67108864L,
    max_document_values: 1000000L,
    max_document_depth: 1024,
    allowed_subtypes: None,
    allow_root_edits: true,
    allow_legacy_text: true,
  }
}

///|
#derive(@debug.Debug)
pub(all) suberror LimitError {
  InvalidLimits(String)
  OperationLimit(String, Int64, Int64)
  ComponentPolicy(Int32, String)
  LimitedApply(Int32, VerificationError)
}

///|
pub extend LimitError with @debug.Debug::{to_repr}

///|
fn check_limit(
  name : String,
  actual : Int64,
  maximum : Int64,
) -> Unit raise LimitError {
  if actual > maximum {
    raise OperationLimit(name, actual, maximum)
  }
}

///|
fn OperationLimits::validate(self : OperationLimits) -> Unit raise LimitError {
  guard self.max_components >= 0 &&
    self.max_path >= 0 &&
    self.max_payload_values >= 0L &&
    self.max_payload_depth >= 0 &&
    self.max_string_units >= 0L &&
    self.max_document_values >= 0L &&
    self.max_document_depth >= 0 else {
    raise InvalidLimits("negative resource limit")
  }
}

///|
fn OperationLimits::check_document(
  self : OperationLimits,
  snapshot : Snapshot,
) -> Unit raise LimitError {
  let metrics = snapshot.metrics()
  check_limit("document values", metrics.values, self.max_document_values)
  check_limit(
    "document depth",
    metrics.max_depth.to_int64(),
    self.max_document_depth.to_int64(),
  )
  check_limit("document strings", metrics.string_units, self.max_string_units)
}

///|
pub fn Engine::check_operation_limits(
  self : Engine,
  operation : Operation,
  limits~ : OperationLimits = OperationLimits::default(),
) -> OperationMetrics raise LimitError {
  limits.validate()
  let metrics = operation.metrics()
  check_limit(
    "components",
    metrics.components.to_int64(),
    limits.max_components.to_int64(),
  )
  check_limit("path", metrics.max_path.to_int64(), limits.max_path.to_int64())
  check_limit(
    "payload values",
    metrics.payload_values,
    limits.max_payload_values,
  )
  check_limit(
    "payload depth",
    metrics.max_payload_depth.to_int64(),
    limits.max_payload_depth.to_int64(),
  )
  check_limit(
    "payload strings",
    metrics.payload_string_units + metrics.text_units,
    limits.max_string_units,
  )
  for index, component in operation.components {
    if !limits.allow_root_edits && component.path.is_empty() {
      raise ComponentPolicy(index, "root edits are disabled")
    }
    match component.action {
      LegacyText(_, _) if !limits.allow_legacy_text =>
        raise ComponentPolicy(index, "legacy text is disabled")
      SubtypeEdit(kind, _) => {
        if limits.allowed_subtypes is Some(allowed) && !allowed.contains(kind) {
          raise ComponentPolicy(index, "subtype is not allowed")
        }
        self.ensure_registered(component) catch {
          _ => raise ComponentPolicy(index, "subtype is unavailable or invalid")
        }
      }
      _ => ()
    }
  }
  metrics
}

///|
/// Check every intermediate document before returning an atomic result.
pub fn Engine::apply_limited(
  self : Engine,
  snapshot : Snapshot,
  operation : Operation,
  limits~ : OperationLimits = OperationLimits::default(),
) -> Snapshot raise LimitError {
  ignore(self.check_operation_limits(operation, limits~))
  limits.check_document(snapshot)
  let mut result = snapshot
  for index, component in operation.components {
    let value = self.verify_component(
      result.value,
      component,
      index,
      persistent=true,
    ) catch {
      error => raise LimitedApply(index, error)
    }
    result = { value, }
    limits.check_document(result)
  }
  result
}
