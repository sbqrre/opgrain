///|
fn card(id : String, value : Int32) -> Json {
  { "id": id, "points": value, "title": "Review" }
}

///|
test "indexed list diff rotation uses one move and preserves edited task identity" {
  let engine = @opgrain.Engine::new()
  let before = [card("a", 1), card("b", 2), card("c", 3), card("d", 4)]
  let after = [card("b", 2), card("c", 30), card("d", 4), card("a", 1)]
  let plan = engine.diff_keyed_list(before, after, "id")
  assert_eq(plan.metrics().moved, 1)
  assert_eq(plan.metrics().retained, 3)
  assert_eq(plan.metrics().changed_items, 1)
  assert_eq(
    engine.apply(Json::array(before), plan.operation()),
    Json::array(after),
  )
}

///|
test "indexed list fixed seed randomized additions deletions and reorders" {
  let engine = @opgrain.Engine::new()
  let mut random = 20261123U
  for trial in 0..<512 {
    let before = Array::makei(24, index => card(index.to_string(), index))
    let after = before.filter(_ => {
      random = random * 1664525U + 1013904223U
      random % 4U != 0U
    })
    for index in 0..<8 {
      after.push(card("new" + index.to_string(), trial))
    }
    for index in 0..<after.length() {
      random = random * 1664525U + 1013904223U
      let other = (random % after.length().reinterpret_as_uint()).reinterpret_as_int()
      let saved = after[index]
      after[index] = after[other]
      after[other] = saved
    }
    let plan = engine.diff_keyed_list(before, after, "id")
    let snapshot = @opgrain.Snapshot::new(Some(Json::array(before)))
    assert_eq(
      engine.apply_snapshot_verified(snapshot, plan.operation()).to_json(),
      Some(Json::array(after)),
    )
    let prepared = engine.prepare_edit(snapshot, plan.operation())
    assert_eq(
      engine
      .apply_snapshot_verified(prepared.snapshot(), prepared.inverse())
      .to_json(),
      snapshot.to_json(),
    )
  }
}

///|
test "text alignments preserve arbitrary UTF16 and every fixed-seed generated target" {
  let alphabet = ["看", "😀", "e\u0301", "\r\n", "\n", "a", "b", "c", ""]
  let mut random = 17123U
  for _ in 0..<256 {
    let left = StringBuilder()
    let right = StringBuilder()
    for _ in 0..<12 {
      random = random * 1664525U + 1013904223U
      left.write_string(alphabet[(random % 9U).reinterpret_as_int()])
      random = random * 1664525U + 1013904223U
      right.write_string(alphabet[(random % 9U).reinterpret_as_int()])
    }
    let before = left.to_string()
    let after = right.to_string()
    for budget in [0L, 100000L] {
      let diff = @opgrain.diff_text(before, after, options={
        max_cells: budget,
        max_units: 1000,
      })
      assert_eq(diff.operation().apply(before), after)
      assert_eq(diff.operation().invert().apply(after), before)
    }
    let lines = @opgrain.diff_text_lines(before, after)
    assert_eq(lines.operation().apply(before), after)
    assert_eq(lines.operation().trace(before).after(), after)
  }
}

///|
test "undo history groups user actions and rebases inverse chains" {
  let engine = @opgrain.Engine::new()
  let history = engine.undo_history(
    @opgrain.Snapshot::new(Some({ "points": 0 })),
  )
  let add1 = @opgrain.Operation::parse("[{\"p\":[\"points\"],\"na\":1}]")
  let add2 = @opgrain.Operation::parse("[{\"p\":[\"points\"],\"na\":2}]")
  ignore(history.record(add1, label="estimate"))
  ignore(history.record(add2, join_previous=true))
  assert_eq(history.undo_count(), 1)
  ignore(history.apply_external(add2))
  assert_eq(history.undo().read([Key("points")]), 2)
  assert_eq(history.redo().read([Key("points")]), 5)
  ignore(history.undo())
  ignore(history.record(add1))
  assert_eq(history.redo_count(), 0)
}

///|
test "journal archives preserve absent roots absolute revisions and split replay" {
  let engine = @opgrain.Engine::new()
  let journal = engine.journal(None)
  ignore(
    journal.append(
      @opgrain.Operation::parse("[{\"p\":[],\"oi\":{\"points\":1}}]"),
    ),
  )
  ignore(
    journal.append(@opgrain.Operation::parse("[{\"p\":[\"points\"],\"na\":2}]")),
  )
  let archive = journal.archive()
  let decoded = engine.decode_archive(archive.encode())
  assert_eq(decoded.restore(engine).snapshot(), journal.snapshot())
  let (prefix, suffix) = decoded.split(engine, 1)
  assert_eq(prefix.head().to_json(), suffix.base().to_json())
  assert_eq(suffix.restore(engine).oldest_revision(), 1)
  let raw = archive.to_json()
  guard raw is Object(fields) else { fail("object") }
  fields["head"] = { "points": 999 }
  try engine.read_archive(raw) catch {
    @opgrain.ArchiveCheckpointMismatch => ()
    error => raise error
  } noraise {
    _ => fail("forged checkpoint accepted")
  }
  fields["operations"] = [[], [{ "p": [], "od": 1 }]]
  try engine.read_archive(raw) catch {
    @opgrain.ArchiveBatch(1, _) => ()
    error => raise error
  } noraise {
    _ => fail("invalid archive batch accepted")
  }
}

///|
test "branch previews and rebases reject stale acceptance" {
  let engine = @opgrain.Engine::new()
  let base = @opgrain.Snapshot::new(Some({ "tasks": [] }))
  let left = @opgrain.Operation::parse(
    "[{\"p\":[\"tasks\",0],\"li\":\"Review\"}]",
  )
  let right = @opgrain.Operation::parse(
    "[{\"p\":[\"tasks\",0],\"li\":\"Publish\"}]",
  )
  let pair = engine.branch_pair(base)
  ignore(pair.append(Left, left))
  ignore(pair.append(Right, right))
  let preview = pair.preview()
  let expected = preview.result().to_json()
  assert_eq(pair.accept(preview).to_json(), expected)
  try pair.accept(preview) catch {
    @opgrain.StaleBranchPreview => ()
    error => raise error
  } noraise {
    _ => fail("stale preview accepted")
  }
  let pending = engine.rebase_buffer(base)
  ignore(pending.append(left))
  let rebased = pending.preview([right])
  assert_eq(pending.accept(rebased).to_json(), expected)
  let visible = pending.snapshot().to_json()
  assert_eq(pending.confirm_prefix(1).to_json(), visible)
  assert_eq(pending.length(), 0)
}

///|
test "packing traces and projections retain meaningful component boundaries" {
  let engine = @opgrain.Engine::new()
  let base = @opgrain.Snapshot::new(
    Some({ "tasks": [card("a", 1), card("b", 2)] }),
  )
  let operation = @opgrain.Operation::parse(
    "[{\"p\":[\"tasks\",0,\"points\"],\"na\":2},{\"p\":[\"tasks\",0],\"lm\":1}]",
  )
  let packed = operation.pack(limits={
    ..@opgrain.PackingLimits::default(),
    max_components: 1,
  })
  assert_eq(packed.operations().length(), 2)
  assert_eq(packed.flatten().to_json(), operation.to_json())
  let trace = engine.trace_apply(base, operation)
  assert_eq(trace.records()[1].previous_value(), Some(card("a", 3)))
  assert_eq(trace.records()[1].next_value(), Some(card("a", 3)))
  let projection = base.project([
    ExactKey("tasks"),
    AnyIndex,
    ExactKey("points"),
  ])
  let update = engine.update_projection(projection, operation)
  assert_eq(update.changes().length(), 2)
  let selected = base.select([ExactKey("tasks"), AnyIndex, ExactKey("points")])
  let edit = engine.edit_selection(selected, (_, value) => {
    match value {
      Number(number, ..) => Json::number(number + 10)
      _ => raise @opgrain.InvalidJson("number")
    }
  })
  assert_eq(edit.snapshot().read([Key("tasks"), Index(1), Key("points")]), 12)
}

///|
test "verified composition preserves actual binary64 results" {
  let engine = @opgrain.Engine::new()
  let base = @opgrain.Snapshot::new(Some(Json::number(1)))
  let add = @opgrain.Operation::parse("[{\"p\":[],\"na\":10000000000000000}]")
  let subtract = @opgrain.Operation::parse(
    "[{\"p\":[],\"na\":-10000000000000000}]",
  )
  let composed = engine.compose_verified(base, [add, subtract])
  assert_eq(composed.snapshot().to_json(), Some(Json::number(0)))
  assert_eq(composed.decision(), SequentialFallback)
  assert_eq(
    engine.apply_snapshot(base, composed.operation()).to_json(),
    composed.snapshot().to_json(),
  )
}

///|
test "pointers resolve typed paths and ordered multiway merge uses JSON0 priority" {
  let engine = @opgrain.Engine::new()
  let base = @opgrain.Snapshot::new(Some({ "0": { "a/b~": [1] }, "tasks": [] }))
  let path = base.resolve_pointer("/0/a~1b~0/0")
  assert_eq(path.segments(), [Key("0"), Key("a/b~"), Index(0)])
  assert_eq(base.read_pointer(path.to_pointer()), 1)
  let branches = ["Review", "Publish", "Verify"].map(title => {
    [
      @opgrain.Operation::single(
        @opgrain.Component::new(
          [Key("tasks"), Index(0)],
          ListInsert(Json::string(title)),
        ),
      ),
    ]
  })
  let merged = engine.merge_many(base, branches)
  assert_eq(merged.result().read([Key("tasks")]), [
    "Review", "Publish", "Verify",
  ])
  assert_eq(
    engine.apply_snapshot_batches(base, merged.operations()).to_json(),
    merged.result().to_json(),
  )
}
