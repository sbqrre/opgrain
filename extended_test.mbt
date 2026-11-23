///|
test "text0 typed operations and explicit coordinate conversion" {
  let source = "看😀e\u0301\r\n板"
  let index = @opgrain.TextIndex::new(source)
  assert_eq(index.lengths().utf16, 8)
  assert_eq(index.lengths().code_points, 7)
  let operation = index.splice_code_points(1, 1, "任务")
  assert_eq(operation.apply(source), "看任务e\u0301\r\n板")
  assert_eq(operation.invert().apply(operation.apply(source)), source)
}

///|
test "limits reject intermediate growth and preserve snapshots" {
  let engine = @opgrain.Engine::new()
  let snapshot = @opgrain.Snapshot::new(Some([]))
  let operation = @opgrain.Operation::parse(
    "[{\"p\":[0],\"li\":[1,2,3]},{\"p\":[0],\"ld\":[1,2,3]}]",
  )
  let limits = {
    ..@opgrain.OperationLimits::default(),
    max_document_values: 3L,
  }
  assert_true(
    (Some(engine.apply_limited(snapshot, operation, limits~)) catch {
      _ => None
    })
    is None,
  )
  assert_eq(snapshot.to_json(), Some([]))
  assert_eq(engine.apply_limited(snapshot, operation).to_json(), Some([]))
}

///|
test "conditions distinguish missing and null and check postconditions" {
  let engine = @opgrain.Engine::new()
  let snapshot = @opgrain.Snapshot::new(Some({ "n": 3, "task": Json::null() }))
  let path = @opgrain.Path::new([Key("task")])
  assert_true(snapshot.test_condition(PathPresent(path)))
  assert_true(!snapshot.test_condition(PathAbsent(path)))
  assert_true(snapshot.test_condition(EqualValue(path, Json::null())))
  let number = @opgrain.Path::new([Key("n")])
  let operation = @opgrain.Operation::parse("[{\"p\":[\"n\"],\"na\":2}]")
  let result = engine.apply_when(
    snapshot,
    operation,
    [NumberRange(number, Some(3), Some(3))],
    after=[NumberRange(number, Some(5), Some(5))],
  )
  assert_eq(result.read([Key("n")]), 5)
  assert_true(
    (Some(
      engine.apply_when(snapshot, operation, [], after=[
        NumberRange(number, None, Some(4)),
      ]),
    ) catch {
      _ => None
    })
    is None,
  )
  assert_eq(snapshot.read([Key("n")]), 3)
}
