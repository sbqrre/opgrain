///|
test "transactions can read their changes and retain old snapshot handles" {
  let engine = @opgrain.Engine::new()
  let original = @opgrain.parse_json(
    "{\"tasks\":[\"Review\",\"Publish\"],\"points\":2}",
  )
  let draft = engine.draft(Some(original))
  let handle = draft.snapshot_handle()
  let delta = draft.transaction(candidate => {
    candidate.move_item([Key("tasks"), Index(1)], 0)
    candidate.add_number([Key("points")], 0.5)
    if candidate.read([Key("tasks"), Index(0)]) != Json::string("Publish") {
      raise @opgrain.InvalidJson("transaction did not expose the moved card")
    }
  })
  assert_eq(delta.to_json(), draft.operation().to_json())
  assert_eq(handle.to_json(), Some(original))
  assert_eq(
    engine.apply_snapshot_verified(handle, delta).to_json(),
    draft.snapshot(),
  )
  let previous = draft.snapshot()
  try
    draft.transaction(candidate => {
      candidate.remove_item([Key("tasks"), Index(0)])
      candidate.remove([Key("missing")])
    })
  catch {
    @opgrain.InvalidPath(_, _) => ()
    error => raise error
  } noraise {
    _ => fail("missing key was accepted")
  }
  assert_eq(draft.snapshot(), previous)
  assert_eq(draft.operation().to_json(), delta.to_json())
}

///|
test "transactions reject captured draft writes and unlock after failure" {
  let draft = @opgrain.Engine::new().draft(Some(Json::number(1)))
  try
    draft.transaction(candidate => {
      candidate.add_number([], 2)
      draft.add_number([], 10)
    })
  catch {
    @opgrain.DraftBusy => ()
    error => raise error
  } noraise {
    _ => fail("reentrant write was accepted")
  }
  assert_eq(draft.snapshot(), Some(Json::number(1)))
  draft.add_number([], 0.5)
  assert_eq(draft.snapshot(), Some(Json::number(1.5)))
}

///|
test "list splice is atomic over invalid values and carries all deletion preimages" {
  let engine = @opgrain.Engine::new()
  let base = Json::array([Json::string("A"), Json::null(), Json::string("C")])
  let draft = engine.draft(Some(base))
  draft.splice_items([], 1, 2, [
    Json::string("B"),
    Json::string("D"),
    Json::number(2),
  ])
  assert_eq(
    draft.snapshot(),
    Some(
      Json::array([
        Json::string("A"),
        Json::string("B"),
        Json::string("D"),
        Json::number(2),
      ]),
    ),
  )
  assert_eq(
    engine.apply_verified(draft.snapshot(), engine.invert(draft.operation())),
    Some(base),
  )
  let previous = draft.snapshot()
  try
    draft.splice_items([], 0, 1, [Json::null(), Json::number(1.0 / 0.0)])
  catch {
    @opgrain.NonFiniteNumber => ()
    error => raise error
  } noraise {
    _ => fail("infinity was accepted")
  }
  assert_eq(draft.snapshot(), previous)
}

///|
test "compaction preserves absolute revisions and retained handles" {
  let engine = @opgrain.Engine::new()
  let journal = engine.journal(Some(Json::number(0)))
  let plus = @opgrain.Operation::parse("[{\"p\":[],\"na\":1}]")
  ignore(journal.append_all([plus, plus, plus]))
  let oldest = journal.snapshot_handle_at(0)
  let middle = journal.snapshot_handle_at(2)
  journal.compact(2)
  assert_eq(journal.oldest_revision(), 2)
  assert_eq(journal.head(), 3)
  assert_eq(journal.snapshot_at(2), Some(Json::number(2)))
  assert_eq(journal.operations(2, 3).length(), 1)
  assert_eq(oldest.to_json(), Some(Json::number(0)))
  assert_eq(middle.to_json(), Some(Json::number(2)))
  assert_eq(journal.integrate(2, [plus]), 4)
  assert_eq(journal.snapshot(), Some(Json::number(4)))
  assert_eq(journal.revert(2, 3), 5)
  assert_eq(journal.snapshot(), Some(Json::number(3)))
  try journal.snapshot_at(1) catch {
    @opgrain.InvalidRevisionRange(1, 1, 5) => ()
    error => raise error
  } noraise {
    _ => fail("compacted revision was accepted")
  }
  try journal.compact(1) catch {
    @opgrain.InvalidRevisionRange(_, _, _) => ()
    error => raise error
  } noraise {
    _ => fail("backward compaction was accepted")
  }
  journal.compact(journal.head())
  assert_eq(journal.operations(5, 5).length(), 0)
  assert_eq(journal.append(plus), 6)
}

///|
test "journal rejects mutation reentered through a subtype callback" {
  let engine = @opgrain.Engine::new()
  let journal = engine.journal(Some(Json::number(1)))
  let plus = @opgrain.Operation::parse("[{\"p\":[],\"na\":1}]")
  let mut prevented = false
  engine.register_subtype("reentrant", {
    apply: (value, _) => {
      try journal.append(plus) catch {
        @opgrain.HistoryBusy => prevented = true
        _ =>
          raise @opgrain.SubtypeError("reentrant", "unexpected history error")
      } noraise {
        _ => raise @opgrain.SubtypeError("reentrant", "write was accepted")
      }
      value
    },
    compose: (a, _) => a,
    invert: a => a,
    transform: (a, _, _) => a,
  })
  let custom = @opgrain.Operation::parse(
    "[{\"p\":[],\"t\":\"reentrant\",\"o\":null}]",
  )
  assert_eq(journal.append(custom), 1)
  assert_true(prevented)
  assert_eq(journal.snapshot(), Some(Json::number(1)))
  assert_eq(journal.append(plus), 2)
}

///|
test "forked registries isolate registration without altering the original engine" {
  let original = @opgrain.Engine::new()
  let forked = original.fork()
  forked.register_subtype("identity", {
    apply: (value, _) => value,
    compose: (a, _) => a,
    invert: a => a,
    transform: (a, _, _) => a,
  })
  let draft = forked.draft(Some(Json::number(1)))
  draft.edit_subtype([], "identity", Json::null())
  assert_eq(draft.snapshot(), Some(Json::number(1)))
  try original.apply(Json::number(1), draft.operation()) catch {
    @opgrain.UnknownSubtype("identity") => ()
    error => raise error
  } noraise {
    _ => fail("registry was shared")
  }
}
