///|
pub struct ChangeRecord {
  priv batch : Int32
  priv component_index : Int32
  priv component : Component
  priv before : Snapshot
  priv after : Snapshot
  priv source : Path?
  priv destination : Path?
}

///|
pub fn ChangeRecord::batch(self : ChangeRecord) -> Int32 {
  self.batch
}

///|
pub fn ChangeRecord::index(self : ChangeRecord) -> Int32 {
  self.component_index
}

///|
pub fn ChangeRecord::operation(self : ChangeRecord) -> Operation {
  Operation::single(self.component)
}

///|
pub fn ChangeRecord::before(self : ChangeRecord) -> Snapshot {
  self.before
}

///|
pub fn ChangeRecord::after(self : ChangeRecord) -> Snapshot {
  self.after
}

///|
pub fn ChangeRecord::source(self : ChangeRecord) -> Path? {
  self.source
}

///|
pub fn ChangeRecord::destination(self : ChangeRecord) -> Path? {
  self.destination
}

///|
pub fn ChangeRecord::previous_value(self : ChangeRecord) -> Json? {
  match self.source {
    Some(path) => guard_value(self.before, path).map(copy_json)
    None => None
  }
}

///|
pub fn ChangeRecord::next_value(self : ChangeRecord) -> Json? {
  match self.destination {
    Some(path) => guard_value(self.after, path).map(copy_json)
    None => None
  }
}

///|
pub fn ChangeRecord::matches(
  self : ChangeRecord,
  pattern : Array[PathPattern],
) -> Bool {
  (self.source is Some(path) && path.matches(pattern)) ||
  (self.destination is Some(path) && path.matches(pattern))
}

///|
pub struct ApplyTrace {
  priv initial : Snapshot
  priv result : Snapshot
  priv records : Array[ChangeRecord]
}

///|
pub fn ApplyTrace::initial(self : ApplyTrace) -> Snapshot {
  self.initial
}

///|
pub fn ApplyTrace::result(self : ApplyTrace) -> Snapshot {
  self.result
}

///|
pub fn ApplyTrace::records(self : ApplyTrace) -> Array[ChangeRecord] {
  self.records.copy()
}

///|
pub fn ApplyTrace::select(
  self : ApplyTrace,
  pattern : Array[PathPattern],
) -> Array[ChangeRecord] {
  self.records.filter(record => record.matches(pattern))
}

///|
pub fn ApplyTrace::operations(self : ApplyTrace) -> Operation {
  { components: self.records.map(record => record.component), }
}

///|
pub fn ApplyTrace::checkpoint(
  self : ApplyTrace,
  through : Int32,
) -> Snapshot raise OpError {
  guard through >= 0 && through <= self.records.length() else {
    raise InvalidJson("trace checkpoint out of range")
  }
  if through == 0 {
    self.initial
  } else {
    self.records[through - 1].after
  }
}

///|
fn component_endpoints(component : Component) -> (Path?, Path?) {
  let path = Path::{ segments: component.path.copy(), }
  match component.action {
    ObjectEdit(Some(_), None) | ListEdit(Some(_), None) => (None, Some(path))
    ObjectEdit(None, _) | ListEdit(None, _) => (Some(path), None)
    Move(destination) => {
      let target = path.segments.copy()
      target[target.length() - 1] = Index(destination)
      (Some(path), Some({ segments: target, }))
    }
    LegacyText(_, _) => {
      let target = path.parent().unwrap()
      (Some(target), Some(target))
    }
    _ => (Some(path), Some(path))
  }
}

///|
/// Retain persistent checkpoints and component preimages without copying whole documents.
pub fn Engine::trace_batches(
  self : Engine,
  snapshot : Snapshot,
  operations : Array[Operation],
) -> ApplyTrace raise HistoryError {
  let records = []
  let mut result = snapshot
  for batch, operation in operations {
    for index, component in operation.components {
      let before = result
      let value = self.verify_component(
        before.value,
        component,
        index,
        persistent=true,
      ) catch {
        error => raise HistoryApplyFailed(Original, Left, batch, error)
      }
      result = { value, }
      let (source, destination) = component_endpoints(component)
      records.push({
        batch,
        component_index: index,
        component,
        before,
        after: result,
        source,
        destination,
      })
    }
  }
  { initial: snapshot, result, records, }
}

///|
pub fn Engine::trace_apply(
  self : Engine,
  snapshot : Snapshot,
  operation : Operation,
) -> ApplyTrace raise HistoryError {
  self.trace_batches(snapshot, [operation])
}

///|
pub struct MergePreview {
  priv left : ApplyTrace
  priv right : ApplyTrace
  priv right_after_left : ApplyTrace
  priv left_after_right : ApplyTrace
  priv interactions : Array[Interaction]
}

///|
pub fn MergePreview::left(self : MergePreview) -> ApplyTrace {
  self.left
}

///|
pub fn MergePreview::right(self : MergePreview) -> ApplyTrace {
  self.right
}

///|
pub fn MergePreview::right_after_left(self : MergePreview) -> ApplyTrace {
  self.right_after_left
}

///|
pub fn MergePreview::left_after_right(self : MergePreview) -> ApplyTrace {
  self.left_after_right
}

///|
pub fn MergePreview::interactions(self : MergePreview) -> Array[Interaction] {
  self.interactions.copy()
}

///|
pub fn MergePreview::result(self : MergePreview) -> Snapshot {
  self.right_after_left.result
}

///|
/// Execute both convergence paths. A preview fails if either path is invalid or divergent.
pub fn Engine::preview_merge(
  self : Engine,
  snapshot : Snapshot,
  left : Operation,
  right : Operation,
  text_encoding~ : TextEncoding? = None,
) -> MergePreview raise HistoryError {
  let left = self.prepare_history([left], Left, text_encoding)[0]
  let right = self.prepare_history([right], Right, text_encoding)[0]
  let left_trace = self.trace_apply(snapshot, left)
  let right_trace = self.trace_apply(snapshot, right)
  let transformed = self.transform_histories([left], [right])
  let right_after_left = self.trace_batches(
    left_trace.result,
    transformed.right_after_left,
  )
  let left_after_right = self.trace_batches(
    right_trace.result,
    transformed.left_after_right,
  )
  guard right_after_left.result.value == left_after_right.result.value else {
    raise DivergentHistory(
      right_after_left.result.to_json(),
      left_after_right.result.to_json(),
    )
  }
  {
    left: left_trace,
    right: right_trace,
    right_after_left,
    left_after_right,
    interactions: left.interactions(right),
  }
}
