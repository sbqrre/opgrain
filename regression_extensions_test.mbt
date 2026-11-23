///|
test "prefix manipulation preserves component validity for list and legacy text paths" {
  let list = @opgrain.Operation::parse("[{\"p\":[\"tasks\",0],\"li\":1}]")
  assert_true(list.without_prefix([Key("tasks"), Index(0)]) is None)
  let root = @opgrain.Operation::parse("[{\"p\":[],\"oi\":1}]")
  try root.with_prefix([Index(0)]) catch {
    @opgrain.InvalidComponent(_, _) => ()
    error => raise error
  } noraise {
    _ => fail("invalid root object edit embedded into list")
  }
  let text = @opgrain.Operation::parse("[{\"p\":[\"title\",0],\"si\":\"x\"}]")
  assert_true(text.without_prefix([Key("title"), Index(0)]) is None)
}

///|
test "undo grouping checks exact floating point result and external action boundaries" {
  let engine = @opgrain.Engine::new()
  let history = engine.undo_history(
    @opgrain.Snapshot::new(Some(Json::number(1))),
  )
  let add = @opgrain.Operation::parse("[{\"p\":[],\"na\":10000000000000000}]")
  let subtract = @opgrain.Operation::parse(
    "[{\"p\":[],\"na\":-10000000000000000}]",
  )
  ignore(history.record(add))
  ignore(history.record(subtract, join_previous=true))
  assert_eq(history.undo_count(), 1)
  assert_eq(history.undo().to_json(), Some(Json::number(1)))
  assert_eq(history.redo().to_json(), Some(Json::number(0)))
  ignore(
    history.apply_external(@opgrain.Operation::parse("[{\"p\":[],\"na\":1}]")),
  )
  ignore(history.record(subtract, join_previous=true))
  assert_eq(history.undo_count(), 2)
}

///|
test "verified deep replacement compares iterative preimages" {
  let mut value = Json::number(1)
  for _ in 0..<4000 {
    value = Json::array([value])
  }
  let engine = @opgrain.Engine::new()
  let snapshot = @opgrain.Snapshot::new(Some(value))
  let replacement = @opgrain.Operation::single(
    @opgrain.Component::new([], ObjectReplace(value, Json::null())),
  )
  assert_eq(
    engine.apply_snapshot_verified(snapshot, replacement).to_json(),
    Some(Json::null()),
  )
}

///|
test "resource and comparison budgets never report incomplete success" {
  let snapshot = @opgrain.Snapshot::new(Some({ "tasks": [1, 2, 3] }))
  let other = @opgrain.Snapshot::new(Some({ "tasks": [1, 2, 4] }))
  try
    snapshot.compare(other, limits={
      ..@opgrain.ComparisonLimits::default(),
      max_visits: 1,
    })
  catch {
    @opgrain.ComparisonBudget(_, _) => ()
    error => raise error
  } noraise {
    _ => fail("partial comparison reported success")
  }
  let engine = @opgrain.Engine::new()
  let operation = @opgrain.Operation::parse("[{\"p\":[\"tasks\",0],\"li\":1}]")
  try
    engine.check_operation_limits(operation, limits={
      ..@opgrain.OperationLimits::default(),
      max_components: 0,
    })
  catch {
    @opgrain.OperationLimit("components", 1L, 0L) => ()
    error => raise error
  } noraise {
    _ => fail("operation resource limit ignored")
  }
}
