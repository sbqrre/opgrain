///|
#derive(@debug.Debug)
pub(all) suberror ArchiveError {
  InvalidArchive(String)
  ArchiveDecode(DecodeError)
  ArchiveValue(OpError)
  ArchiveReplay(Int32, VerificationError)
  ArchiveLimit(LimitError)
  ArchiveOperation(Int32, OpError)
  ArchiveBatch(Int32, LimitError)
  ArchiveCheckpointMismatch
}

///|
pub extend ArchiveError with @debug.Debug::{to_repr}

///|
/// A local replay format containing standard JSON0 operation arrays.
/// This envelope is separate from the JSON0 operation wire format.
pub struct JournalArchive {
  priv base : Snapshot
  priv base_revision : Int32
  priv operations : Array[Operation]
  priv head : Snapshot
}

///|
pub fn JournalArchive::base(self : JournalArchive) -> Snapshot {
  self.base
}

///|
pub fn JournalArchive::base_revision(self : JournalArchive) -> Int32 {
  self.base_revision
}

///|
pub fn JournalArchive::head(self : JournalArchive) -> Snapshot {
  self.head
}

///|
pub fn JournalArchive::operations(self : JournalArchive) -> Array[Operation] {
  self.operations.copy()
}

///|
pub fn JournalArchive::head_revision(self : JournalArchive) -> Int32 {
  self.base_revision + self.operations.length()
}

///|
pub fn Journal::archive(self : Journal) -> JournalArchive {
  {
    base: self.base,
    base_revision: self.base_revision,
    operations: self.operations_in(self.base_revision, self.head()),
    head: self.checkpoint(self.head()),
  }
}

///|
pub fn JournalArchive::to_json(self : JournalArchive) -> Json {
  let fields : Map[String, Json] = {
    "format": Json::string("opgrain.journal"),
    "version": Json::number(1),
    "base_revision": Json::number(self.base_revision.to_double()),
    "base_present": Json::boolean(self.base.value is Some(_)),
    "head_present": Json::boolean(self.head.value is Some(_)),
    "operations": Json::array(
      self.operations.map(operation => operation.to_json()),
    ),
  }
  if self.base.value is Some(value) {
    fields["base"] = copy_json(value)
  }
  if self.head.value is Some(value) {
    fields["head"] = copy_json(value)
  }
  Json::object(fields)
}

///|
fn archive_fields(value : Json) -> Map[String, Json] raise ArchiveError {
  guard value is Object(fields) else {
    raise InvalidArchive("expected an archive object")
  }
  let allowed = [
    "format", "version", "base_revision", "base_present", "base", "head_present",
    "head", "operations",
  ]
  for key, _ in fields {
    guard allowed.contains(key) else {
      raise InvalidArchive("unknown archive field: " + key)
    }
  }
  guard fields.get("format") == Some(Json::string("opgrain.journal")) &&
    fields.get("version") == Some(Json::number(1)) else {
    raise InvalidArchive("unsupported archive format or version")
  }
  fields
}

///|
fn archive_snapshot(
  fields : Map[String, Json],
  prefix : String,
) -> Snapshot raise ArchiveError {
  guard fields.get(prefix + "_present") is Some(True) ||
    fields.get(prefix + "_present") is Some(False) else {
    raise InvalidArchive("missing presence flag: " + prefix)
  }
  let present = fields.get(prefix + "_present") == Some(Json::boolean(true))
  let value = fields.get(prefix)
  guard present == (value is Some(_)) else {
    raise InvalidArchive("presence flag disagrees with value: " + prefix)
  }
  let value = value.map(copy_checked_json) catch {
    error => raise ArchiveValue(error)
  }
  { value, }
}

///|
fn archive_revision(fields : Map[String, Json]) -> Int32 raise ArchiveError {
  guard fields.get("base_revision") is Some(Number(value, ..)) &&
    value >= 0 &&
    value <= 2147483647 &&
    value.to_int().to_double() == value else {
    raise InvalidArchive("base_revision must be a nonnegative Int32")
  }
  value.to_int()
}

///|
pub fn Engine::read_archive(
  self : Engine,
  value : Json,
  limits~ : OperationLimits = OperationLimits::default(),
) -> JournalArchive raise ArchiveError {
  validate_json_value(value, []) catch {
    error => raise ArchiveValue(error)
  }
  let fields = archive_fields(value)
  let base = archive_snapshot(fields, "base")
  let expected = archive_snapshot(fields, "head")
  let base_revision = archive_revision(fields)
  guard fields.get("operations") is Some(Array(raw)) else {
    raise InvalidArchive("operations must be an array")
  }
  guard raw.length() <= 2147483647 - base_revision else {
    raise InvalidArchive("revision overflow")
  }
  limits.validate() catch {
    error => raise ArchiveLimit(error)
  }
  limits.check_document(base) catch {
    error => raise ArchiveLimit(error)
  }
  let operations = []
  let mut snapshot = base
  for index, value in raw {
    let operation = Operation::from_json(value) catch {
      error => raise ArchiveOperation(index, error)
    }
    ignore(
      self.check_operation_limits(operation, limits~) catch {
        error => raise ArchiveBatch(index, error)
      },
    )
    snapshot = self.apply_limited(snapshot, operation, limits~) catch {
      error => raise ArchiveBatch(index, error)
    }
    operations.push(operation)
  }
  guard snapshot.equivalent(expected) else { raise ArchiveCheckpointMismatch }
  { base, base_revision, operations, head: snapshot, }
}

///|
pub fn Engine::decode_archive(
  self : Engine,
  source : String,
  decode_options~ : DecodeOptions = DecodeOptions::default(),
  limits~ : OperationLimits = OperationLimits::default(),
) -> JournalArchive raise ArchiveError {
  let value = decode_json(source, options=decode_options) catch {
    error => raise ArchiveDecode(error)
  }
  self.read_archive(value, limits~)
}

///|
pub fn JournalArchive::restore(
  self : JournalArchive,
  engine : Engine,
) -> Journal raise ArchiveError {
  let entries = []
  let mut snapshot = self.base
  for index, operation in self.operations {
    snapshot = engine.apply_snapshot_verified(snapshot, operation) catch {
      error => raise ArchiveReplay(index, error)
    }
    entries.push(Revision::{ operation, snapshot, })
  }
  guard snapshot.equivalent(self.head) else { raise ArchiveCheckpointMismatch }
  {
    engine: engine.fork(),
    base: self.base,
    base_revision: self.base_revision,
    entries,
    busy: false,
  }
}

///|
pub fn JournalArchive::encode(
  self : JournalArchive,
  options~ : EncodeOptions = EncodeOptions::default(),
) -> String raise EncodeError {
  encode_json(self.to_json(), options~)
}

///|
/// Select a retained interval and replay it as an independent archive.
pub fn Journal::archive_range(
  self : Journal,
  start : Int32,
  end : Int32,
) -> JournalArchive raise HistoryError {
  self.check_range(start, end)
  {
    base: self.checkpoint(start),
    base_revision: start,
    operations: self.operations_in(start, end),
    head: self.checkpoint(end),
  }
}

///|
/// Split without composing batches, retaining exact absolute revision boundaries.
pub fn JournalArchive::split(
  self : JournalArchive,
  engine : Engine,
  revision : Int32,
) -> (JournalArchive, JournalArchive) raise ArchiveError {
  guard revision >= self.base_revision && revision <= self.head_revision() else {
    raise InvalidArchive("split revision outside archive")
  }
  let count = revision - self.base_revision
  let mut middle = self.base
  for index in 0..<count {
    middle = engine.apply_snapshot_verified(middle, self.operations[index]) catch {
      error => raise ArchiveReplay(index, error)
    }
  }
  (
    {
      base: self.base,
      base_revision: self.base_revision,
      operations: self.operations[:count].to_owned(),
      head: middle,
    },
    {
      base: middle,
      base_revision: revision,
      operations: self.operations[count:].to_owned(),
      head: self.head,
    },
  )
}

///|
/// Join only adjacent archives whose checkpoint values agree exactly.
pub fn JournalArchive::join(
  self : JournalArchive,
  other : JournalArchive,
) -> JournalArchive raise ArchiveError {
  guard self.head_revision() == other.base_revision &&
    self.head.equivalent(other.base) else {
    raise InvalidArchive("archives do not share an adjacent checkpoint")
  }
  let operations = self.operations.copy()
  operations.append(other.operations)
  {
    base: self.base,
    base_revision: self.base_revision,
    operations,
    head: other.head,
  }
}
