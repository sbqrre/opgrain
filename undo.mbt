///|
#derive(@debug.Debug)
pub(all) suberror UndoError {
  ForwardRejected(VerificationError)
  InverseRejected(Int32, OpError)
  UndoRejected(VerificationError)
  UndoDidNotRestore(Json?, Json?)
}

///|
pub extend UndoError with @debug.Debug::{to_repr}

///|
/// A forward operation, a verified undo operation and its resulting snapshot.
pub struct UndoableEdit {
  priv operation : Operation
  priv inverse : Operation
  priv snapshot : Snapshot
}

///|
pub fn UndoableEdit::operation(self : UndoableEdit) -> Operation {
  self.operation
}

///|
pub fn UndoableEdit::inverse(self : UndoableEdit) -> Operation {
  self.inverse
}

///|
pub fn UndoableEdit::snapshot(self : UndoableEdit) -> Snapshot {
  self.snapshot
}

///|
fn Engine::inverse_with_snapshot(
  self : Engine,
  before : Snapshot,
  after : Snapshot,
  component : Component,
) -> Component raise OpError {
  if component.action is Add(amount) {
    let path = component.path
    let previous = lookup_value(before.value, path, path.length())
    let next = lookup_value(after.value, path, path.length())
    guard previous is Number(old, ..) && next is Number(value, ..) else {
      raise InvalidPath(path.copy(), "numeric undo requires numbers")
    }
    if value - amount != old {
      let action = if path.last() is Some(Index(_)) {
        ListEdit(Some(previous), Some(next))
      } else {
        ObjectEdit(Some(previous), Some(next))
      }
      return { path: path.copy(), action, }
    }
  }
  self.invert_component(component)
}

///|
/// Construct undo from the actual preimages and verify that it restores the input.
/// When numeric negation loses precision, undo uses a JSON0 value replacement.
pub fn Engine::prepare_edit(
  self : Engine,
  snapshot : Snapshot,
  operation : Operation,
) -> UndoableEdit raise UndoError {
  let mut updated = snapshot
  let inverses = []
  for index, component in operation.components {
    let before = updated
    let value = self.verify_component(
      before.value,
      component,
      index,
      persistent=true,
    ) catch {
      error => raise ForwardRejected(error)
    }
    updated = { value, }
    let inverse = self.inverse_with_snapshot(before, updated, component) catch {
      error => raise InverseRejected(index, error)
    }
    inverses.push(inverse)
  }
  inverses.rev_in_place()
  let inverse = Operation::{ components: inverses, }
  let restored = self.apply_snapshot_verified(updated, inverse) catch {
    error => raise UndoRejected(error)
  }
  guard restored.value == snapshot.value else {
    raise UndoDidNotRestore(snapshot.to_json(), restored.to_json())
  }
  { operation, inverse, snapshot: updated, }
}
