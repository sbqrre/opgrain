///|
fn history_op(wire : String) -> @opgrain.Operation raise @opgrain.OpError {
  @opgrain.Operation::parse(wire)
}

///|
test "history crosses several batches with list moves and retains no-op boundaries" {
  let engine = @opgrain.Engine::new()
  let base = Some(
    @opgrain.parse_json("{\"todo\":[\"A\",\"B\",\"C\"],\"points\":1}"),
  )
  let left = [
    history_op("[{\"p\":[\"todo\",0],\"lm\":2}]"),
    history_op("[]"),
    history_op("[{\"p\":[\"todo\",0,1],\"si\":\" updated\"}]"),
  ]
  let right = [
    history_op("[{\"p\":[\"todo\",1],\"li\":\"D\"}]"),
    history_op("[{\"p\":[\"points\"],\"na\":2}]"),
    history_op("[{\"p\":[\"todo\",0],\"ld\":\"A\"}]"),
  ]
  let merged = engine.merge_histories(base, left, right)
  let histories = merged.histories()
  assert_eq(histories.left_after_right().length(), 3)
  assert_eq(histories.left_after_right()[1].length(), 0)
  assert_eq(histories.right_after_left().length(), 3)
  let expected = Some(
    @opgrain.parse_json("{\"todo\":[\"D\",\"B updated\",\"C\"],\"points\":3}"),
  )
  assert_eq(merged.snapshot(), expected)
  let journal = engine.journal(base)
  assert_eq(journal.append_all(left), 3)
  assert_eq(journal.integrate(0, right), 6)
  assert_eq(journal.snapshot(), expected)
  assert_eq(
    journal.operations(3, 6).map(op => op.to_json()),
    histories.right_after_left().map(op => op.to_json()),
  )
}

///|
test "history can choose a single text encoding for both branches" {
  let engine = @opgrain.Engine::new()
  let base = Some(Json::string("待😀办"))
  let legacy = history_op("[{\"p\":[3],\"si\":\"左\"}]")
  let explicit = history_op(
    "[{\"p\":[],\"t\":\"text0\",\"o\":[{\"p\":3,\"i\":\"右\"}]}]",
  )
  for encoding in [@opgrain.TextEncoding::Legacy, Text0] {
    let result = engine.merge_histories(
      base,
      [legacy],
      [explicit],
      text_encoding=Some(encoding),
    )
    assert_eq(result.snapshot(), Some(Json::string("待😀左右办")))
    let result = engine.merge_histories(
      base,
      [explicit],
      [legacy],
      text_encoding=Some(encoding),
    )
    assert_eq(result.snapshot(), Some(Json::string("待😀右左办")))
  }
}

///|
test "text encoding conversion preserves runs, order, wire offsets and all other edits" {
  let engine = @opgrain.Engine::new()
  let source =
    #|[{"p":["a",1],"sd":"\ude00"},{"p":["a",1],"si":"?"},{"p":["n"],"na":2},{"p":["a",0],"si":"x"},{"p":["b",1],"si":"!"}]
  let expect =
    #|[{"p":["a"],"t":"text0","o":[{"p":1,"d":"\ude00"},{"p":1,"i":"?"}]},{"p":["n"],"na":2},{"p":["a"],"t":"text0","o":[{"p":0,"i":"x"}]},{"p":["b"],"t":"text0","o":[{"p":1,"i":"!"}]}]
  let before =
    #|{"a":"😀","b":"待办","n":0}
  let base = @opgrain.parse_json(before)
  let legacy = history_op(source)
  let explicit = engine.reencode_text(legacy, Text0)
  assert_eq(explicit.to_json(), @opgrain.parse_json(expect))
  assert_eq(engine.reencode_text(explicit, Legacy).to_json(), legacy.to_json())
  assert_eq(engine.apply(base, legacy), engine.apply(base, explicit))
}

///|
test "history exposes branch, batch, and component for stale input" {
  let engine = @opgrain.Engine::new()
  let bad = history_op("[{\"p\":[0],\"ld\":\"stale\"}]")
  let ok = history_op("[{\"p\":[0],\"li\":\"A\"}]")
  let base = Some(Json::array([]))
  try engine.merge_histories(base, [], [ok, bad]) catch {
    @opgrain.HistoryApplyFailed(
      Original,
      Right,
      1,
      @opgrain.StalePreimage(0, [Index(0)], _, _),
    ) => ()
    error => raise error
  } noraise {
    _ => fail("stale branch passed validation")
  }
  let journal = engine.journal(base)
  try journal.append_all([ok, bad]) catch {
    @opgrain.HistoryApplyFailed(
      Original,
      Left,
      1,
      @opgrain.StalePreimage(0, [Index(0)], _, _),
    ) => ()
    error => raise error
  } noraise {
    _ => fail("stale batch was saved")
  }
  assert_eq(journal.head(), 0)
  assert_eq(journal.snapshot(), base)
}

///|
test "a journal reverts a past deletion without losing later card edits" {
  let engine = @opgrain.Engine::new()
  let input =
    #|{"todo":["A", "B"],"note":"Check"}
  let base = Some(@opgrain.parse_json(input))
  let journal = engine.journal(base)
  assert_eq(
    journal.append(history_op("[{\"p\":[\"todo\",0],\"ld\":\"A\"}]")),
    1,
  )
  let later =
    #|[{"p":["todo",0,1],"si":" revised"},{"p":["note",5],"si":"!"}]
  assert_eq(journal.append(history_op(later)), 2)
  assert_eq(journal.revert(0, 1), 3)
  let expected =
    #|{"todo":["A","B revised"],"note":"Check!"}
  assert_eq(journal.snapshot(), Some(@opgrain.parse_json(expected)))
  assert_eq(journal.snapshot_at(0), base)
  assert_eq(journal.operations(0, 3).length(), 3)
  assert_eq(journal.revert(2, 2), 3)
  assert_eq(journal.undo_operation(3, 3).length(), 0)
  try journal.snapshot_at(4) catch {
    @opgrain.InvalidRevisionRange(4, 4, 3) => ()
    error => raise error
  } noraise {
    _ => fail("future revision can be read")
  }
}

///|
test "history reports floating-point divergence and a non-recovering inverse" {
  let engine = @opgrain.Engine::new()
  let base = Some(Json::number(1.0e16))
  let cancel = history_op("[{\"p\":[],\"na\":-1e16}]")
  let increment = history_op("[{\"p\":[],\"na\":1}]")
  try engine.merge_histories(base, [cancel], [increment]) catch {
    @opgrain.DivergentHistory(left, right) => {
      assert_eq(left, Some(Json::number(1.0)))
      assert_eq(right, Some(Json::number(0.0)))
    }
    error => raise error
  } noraise {
    _ => fail("rounding divergence was discarded")
  }
  let journal = engine.journal(Some(Json::number(1.0e-20)))
  ignore(journal.append(increment))
  try journal.revert(0, 1) catch {
    @opgrain.HistoryUndoMismatch(before, actual) => {
      assert_eq(before, Some(Json::number(1.0e-20)))
      assert_eq(actual, Some(Json::number(0.0)))
    }
    error => raise error
  } noraise {
    _ => fail("rounding loss was discarded")
  }
  assert_eq(journal.head(), 1)
}
