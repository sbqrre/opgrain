///|
pub(all) struct PackingLimits {
  max_components : Int32
  max_wire_units : Int32
  max_payload_values : Int64
}

///|
pub fn PackingLimits::default() -> PackingLimits {
  {
    max_components: 1000,
    max_wire_units: 1048576,
    max_payload_values: 1000000L,
  }
}

///|
#derive(@debug.Debug)
pub(all) suberror PackingError {
  InvalidPackingLimits
  ComponentTooLarge(Int32, String, Int64, Int64)
  PackingEncoding(Int32, OpError)
  PackingReplay(Int32, VerificationError)
}

///|
pub extend PackingError with @debug.Debug::{to_repr}

///|
pub(all) struct PackedBatchMetrics {
  components : Int32
  wire_units : Int32
  payload_values : Int64
}

///|
pub struct PackedOperations {
  priv operations : Array[Operation]
  priv metrics : Array[PackedBatchMetrics]
}

///|
pub fn PackedOperations::operations(
  self : PackedOperations,
) -> Array[Operation] {
  self.operations.copy()
}

///|
pub fn PackedOperations::metrics(
  self : PackedOperations,
) -> Array[PackedBatchMetrics] {
  self.metrics.copy()
}

///|
/// Split a sequential operation without composing, reordering or dropping components.
/// Wire units count UTF-16 units of stringify_json, including brackets and commas.
pub fn Operation::pack(
  self : Operation,
  limits~ : PackingLimits = PackingLimits::default(),
) -> PackedOperations raise PackingError {
  guard limits.max_components > 0 &&
    limits.max_wire_units >= 2 &&
    limits.max_payload_values >= 0L else {
    raise InvalidPackingLimits
  }
  let operations = []
  let metrics = []
  let mut pending : Array[Component] = []
  let mut units = 2
  let mut values = 0L
  for index, component in self.components {
    let encoded = stringify_json(component.to_json()) catch {
      error => raise PackingEncoding(index, error)
    }
    let component_units = encoded.length()
    let component_values = Operation::single(component).metrics().payload_values
    guard component_units <= limits.max_wire_units - 2 else {
      raise ComponentTooLarge(
        index,
        "wire units",
        component_units.to_int64() + 2L,
        limits.max_wire_units.to_int64(),
      )
    }
    guard component_values <= limits.max_payload_values else {
      raise ComponentTooLarge(
        index,
        "payload values",
        component_values,
        limits.max_payload_values,
      )
    }
    let separator = if pending.is_empty() { 0 } else { 1 }
    let overflow = pending.length() == limits.max_components ||
      component_units > limits.max_wire_units - units - separator ||
      component_values > limits.max_payload_values - values
    if overflow {
      metrics.push({
        components: pending.length(),
        wire_units: units,
        payload_values: values,
      })
      operations.push(Operation::{ components: pending, })
      pending = []
      units = 2
      values = 0L
    }
    if !pending.is_empty() {
      units += 1
    }
    pending.push(component)
    units += component_units
    values += component_values
  }
  if !pending.is_empty() {
    metrics.push({
      components: pending.length(),
      wire_units: units,
      payload_values: values,
    })
    operations.push({ components: pending, })
  }
  { operations, metrics, }
}

///|
pub fn PackedOperations::flatten(self : PackedOperations) -> Operation {
  let components = []
  for operation in self.operations {
    components.append(operation.components)
  }
  { components, }
}

///|
pub fn PackedOperations::wire(self : PackedOperations) -> Array[Json] {
  self.operations.map(operation => operation.to_json())
}

///|
/// Retain batch boundaries when validating and replaying a packed operation.
pub fn Engine::replay_packed(
  self : Engine,
  snapshot : Snapshot,
  packed : PackedOperations,
) -> Array[Snapshot] raise PackingError {
  let checkpoints = [snapshot]
  let mut result = snapshot
  for index, operation in packed.operations {
    result = self.apply_snapshot_verified(result, operation) catch {
      error => raise PackingReplay(index, error)
    }
    checkpoints.push(result)
  }
  checkpoints
}
