///|
#derive(@debug.Debug)
pub(all) suberror CursorError {
  InvalidCursorStep(Int32)
  CursorLimits(LimitError)
  CursorComponent(Int32, VerificationError)
  CursorOffset(Int32, Int32)
}

///|
pub extend CursorError with @debug.Debug::{to_repr}

///|
/// An immutable, bounded application checkpoint. Advancing returns a new cursor;
/// a failure cannot publish a partial snapshot or move the original offset.
pub struct ApplyCursor {
  priv engine : Engine
  priv operation : Operation
  priv initial : Snapshot
  priv snapshot : Snapshot
  priv offset : Int32
  priv limits : OperationLimits
}

///|
pub fn Engine::apply_cursor(
  self : Engine,
  snapshot : Snapshot,
  operation : Operation,
  limits~ : OperationLimits = OperationLimits::default(),
) -> ApplyCursor raise CursorError {
  // Detach the one mutable field of this public options record.
  let limits = {
    ..limits,
    allowed_subtypes: limits.allowed_subtypes.map(names => names.copy()),
  }
  ignore(
    self.check_operation_limits(operation, limits~) catch {
      error => raise CursorLimits(error)
    },
  )
  limits.check_document(snapshot) catch {
    error => raise CursorLimits(error)
  }
  {
    engine: self.fork(),
    operation,
    initial: snapshot,
    snapshot,
    offset: 0,
    limits,
  }
}

///|
pub fn ApplyCursor::offset(self : ApplyCursor) -> Int32 {
  self.offset
}

///|
pub fn ApplyCursor::remaining(self : ApplyCursor) -> Int32 {
  self.operation.length() - self.offset
}

///|
pub fn ApplyCursor::done(self : ApplyCursor) -> Bool {
  self.offset == self.operation.length()
}

///|
pub fn ApplyCursor::snapshot(self : ApplyCursor) -> Snapshot {
  self.snapshot
}

///|
pub fn ApplyCursor::initial(self : ApplyCursor) -> Snapshot {
  self.initial
}

///|
pub fn ApplyCursor::advance(
  self : ApplyCursor,
  count : Int32,
) -> ApplyCursor raise CursorError {
  guard count > 0 else { raise InvalidCursorStep(count) }
  let size = count.min(self.remaining())
  let end = self.offset + size
  let mut snapshot = self.snapshot
  for index in self.offset..<end {
    let value = self.engine.verify_component(
      snapshot.value,
      self.operation.components[index],
      index,
      persistent=true,
    ) catch {
      error => raise CursorComponent(index, error)
    }
    snapshot = { value, }
    self.limits.check_document(snapshot) catch {
      error => raise CursorLimits(error)
    }
  }
  { ..self, snapshot, offset: end, }
}

///|
/// Return exactly the already applied components without normalizing them.
pub fn ApplyCursor::applied(self : ApplyCursor) -> Operation {
  { components: self.operation.components[:self.offset].to_owned(), }
}

///|
pub fn ApplyCursor::pending(self : ApplyCursor) -> Operation {
  { components: self.operation.components[self.offset:].to_owned(), }
}

///|
/// Replay from the original checkpoint to an absolute component offset.
pub fn ApplyCursor::seek(
  self : ApplyCursor,
  offset : Int32,
) -> ApplyCursor raise CursorError {
  guard offset >= 0 && offset <= self.operation.length() else {
    raise CursorOffset(offset, self.operation.length())
  }
  if offset == self.offset {
    return self
  }
  if offset > self.offset {
    return self.advance(offset - self.offset)
  }
  let initial = ApplyCursor::{ ..self, snapshot: self.initial, offset: 0, }
  if offset == 0 {
    initial
  } else {
    initial.advance(offset)
  }
}

///|
pub fn ApplyCursor::finish(self : ApplyCursor) -> Snapshot raise CursorError {
  if self.done() {
    self.snapshot
  } else {
    self.advance(self.remaining()).snapshot
  }
}

///|
/// Checkpoints are opaque snapshots, so retaining every bounded step shares
/// unedited document branches rather than cloning the full document each time.
pub fn ApplyCursor::checkpoints(
  self : ApplyCursor,
  components_per_step : Int32,
) -> Array[ApplyCursor] raise CursorError {
  guard components_per_step > 0 else {
    raise InvalidCursorStep(components_per_step)
  }
  let checkpoints = [self]
  let mut cursor = self
  while !cursor.done() {
    cursor = cursor.advance(components_per_step)
    checkpoints.push(cursor)
  }
  checkpoints
}
