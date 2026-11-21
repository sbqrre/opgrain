///|
fn scenario_board(size : Int32) -> Json {
  Json::object(
    Map([
      (
        "tasks",
        Json::array(
          Array::makei(size, index => {
            Json::object(
              Map([
                ("id", Json::string("task-\{index}")),
                ("title", Json::string("复核😀é")),
                ("points", Json::number(index.to_double())),
              ]),
            )
          }),
        ),
      ),
      ("release", Json::boolean(false)),
    ]),
  )
}

///|
fn scenario_batch(
  engine : @opgrain.Engine,
  snapshot : @opgrain.Snapshot,
  seed : UInt32,
) -> @opgrain.Operation raise @opgrain.OpError {
  let draft = engine.draft_snapshot(snapshot)
  let from = (seed % 5U).reinterpret_as_int()
  let to = ((seed >> 4) % 5U).reinterpret_as_int()
  draft.move_item([Key("tasks"), Index(from)], to)
  let target = ((seed >> 8) % 5U).reinterpret_as_int()
  draft.add_number(
    [Key("tasks"), Index(target), Key("points")],
    ((seed >> 12) % 7U).to_double() / 4.0,
  )
  guard draft.read([Key("tasks"), Index(target), Key("title")]) is String(title) else {
    raise @opgrain.InvalidJson("expected a task title")
  }
  let position = ((seed >> 16) % (title.length() + 1).reinterpret_as_uint()).reinterpret_as_int()
  draft.splice_text(
    [Key("tasks"), Index(target), Key("title")],
    position,
    0,
    "!",
  )
  draft.operation()
}

///|
test "fixed-seed sequential branches agree with compose inverse and snapshot merging" {
  let engine = @opgrain.Engine::new()
  let base = @opgrain.Snapshot::new(Some(scenario_board(5)))
  let mut state = 20261122U
  for index in 0..<128 {
    state = state * 1664525U + 1013904223U
    let left = scenario_batch(engine, base, state)
    state = state * 1664525U + 1013904223U
    let right = scenario_batch(engine, base, state)
    let after_left = engine.apply_snapshot_verified(base, left)
    let after_right = engine.apply_snapshot_verified(base, right)
    state = state * 1664525U + 1013904223U
    let later_left = scenario_batch(engine, after_left, state)
    state = state * 1664525U + 1013904223U
    let later_right = scenario_batch(engine, after_right, state)
    let merged = engine.merge_snapshot_histories(base, [left, later_left], [
      right, later_right,
    ])
    let sequence = engine.apply_snapshot_batches(base, [left, later_left])
    let composed = engine.compose(left, later_left)
    assert_true(
      engine.apply_snapshot_verified(base, composed).to_json() ==
      sequence.to_json(),
      msg="compose seed 20261122 case \{index}",
    )
    let inverse = engine.invert(composed)
    assert_true(
      engine.apply_snapshot_verified(sequence, inverse).to_json() ==
      base.to_json(),
      msg="inverse seed 20261122 case \{index}",
    )
    let journal = engine.journal_snapshot(base)
    ignore(journal.append_all([left, later_left]))
    ignore(journal.integrate(0, [right, later_right]))
    assert_true(
      journal.snapshot() == merged.snapshot(),
      msg="merge seed 20261122 case \{index}",
    )
  }
}
