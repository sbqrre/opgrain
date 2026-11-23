///|
#derive(@debug.Debug)
pub(all) suberror TextProjectionError {
  TextProjectionPath(OpError)
  TextProjectionApply(Int32, VerificationError)
  TextAnchorLost(Int32, LossReason)
  UnsupportedTextProjection(Int32)
  TextProjectionMismatch
}

///|
pub extend TextProjectionError with @debug.Debug::{to_repr}

///|
/// Text edits extracted from a JSON0 history, following the text node through
/// list moves. This is an observation of the history, not a replacement for it.
pub struct TextProjection {
  priv initial_path : Path
  priv final_path : Path
  priv before : String
  priv after : String
  priv operation : TextOperation
  priv snapshot : Snapshot
  priv components : Array[Int32]
}

///|
pub fn TextProjection::initial_path(self : TextProjection) -> Path {
  self.initial_path
}

///|
pub fn TextProjection::final_path(self : TextProjection) -> Path {
  self.final_path
}

///|
pub fn TextProjection::before(self : TextProjection) -> String {
  self.before
}

///|
pub fn TextProjection::after(self : TextProjection) -> String {
  self.after
}

///|
pub fn TextProjection::operation(self : TextProjection) -> TextOperation {
  self.operation
}

///|
pub fn TextProjection::snapshot(self : TextProjection) -> Snapshot {
  self.snapshot
}

///|
pub fn TextProjection::components(self : TextProjection) -> Array[Int32] {
  self.components.copy()
}

///|
fn project_component_text(
  engine : Engine,
  component : Component,
  path : Array[PathSegment],
  index : Int32,
) -> Array[TextEdit] raise TextProjectionError {
  match component.action {
    LegacyText(_, _) if parent_path(component.path) == path => {
      guard !engine.subtypes.contains("text0") else {
        raise UnsupportedTextProjection(index)
      }
      let (_, edit) = legacy_edit(component) catch {
        error => raise TextProjectionPath(error)
      }
      [edit]
    }
    SubtypeEdit("text0", payload) if component.path == path => {
      guard !engine.subtypes.contains("text0") else {
        raise UnsupportedTextProjection(index)
      }
      decode_text0(payload) catch {
        error => raise TextProjectionPath(error)
      }
    }
    SubtypeEdit(_, _) if component.path == path =>
      raise UnsupportedTextProjection(index)
    _ => []
  }
}

///|
/// Reject node replacement, deletion and opaque subtype edits explicitly.
/// Other branches can change freely, and list-coordinate changes follow the node.
pub fn Engine::project_text(
  self : Engine,
  snapshot : Snapshot,
  operation : Operation,
  path : Path,
) -> TextProjection raise TextProjectionError {
  let before = lookup_value(snapshot.value, path.segments, path.length()) catch {
    error => raise TextProjectionPath(error)
  }
  guard before is String(before) else {
    raise TextProjectionPath(
      InvalidPath(path.segments(), "text projection requires a string"),
    )
  }
  let mut location = Node(path.segments())
  let mut updated = snapshot
  let edits = []
  let components = []
  for index, component in operation.components {
    let captured = project_component_text(
      self,
      component,
      location.path(),
      index,
    )
    let value = self.verify_component(
      updated.value,
      component,
      index,
      persistent=true,
    ) catch {
      error => raise TextProjectionApply(index, error)
    }
    updated = { value, }
    if !captured.is_empty() {
      edits.append(captured)
      components.push(index)
    }
    let change = self.location_change(component) catch {
      error => raise TextProjectionPath(error)
    }
    guard location.after_change(change) is Some(next) else {
      raise TextAnchorLost(
        index,
        change.loss_reason().unwrap_or(NodeOverwritten),
      )
    }
    location = next
  }
  let final_path = Path::{ segments: location.path().copy(), }
  let after = lookup_value(
    updated.value,
    final_path.segments,
    final_path.length(),
  ) catch {
    error => raise TextProjectionPath(error)
  }
  guard after is String(after) else { raise TextProjectionMismatch }
  let extracted = TextOperation::{ edits, }
  let actual = extracted.apply(before) catch {
    error => raise TextProjectionPath(error)
  }
  guard actual == after else { raise TextProjectionMismatch }
  {
    initial_path: path,
    final_path,
    before,
    after,
    operation: extracted,
    snapshot: updated,
    components,
  }
}

///|
/// Extract from sequential batches without changing their JSON0 components.
pub fn Engine::project_text_batches(
  self : Engine,
  snapshot : Snapshot,
  operations : Array[Operation],
  path : Path,
) -> TextProjection raise TextProjectionError {
  let components = []
  for operation in operations {
    components.append(operation.components)
  }
  self.project_text(snapshot, { components, }, path)
}

///|
pub fn TextProjection::trace(
  self : TextProjection,
  context_units~ : Int32 = 20,
) -> TextTrace raise OpError {
  self.operation.trace(self.before, context_units~)
}
