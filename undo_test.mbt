///|
test "document-aware undo restores rounding loss at roots, objects and list items" {
  let engine = @opgrain.Engine::new()
  for
    wire in [
      "[{\"p\":[],\"na\":1}]", "[{\"p\":[\"points\"],\"na\":1}]", "[{\"p\":[0],\"na\":1}]",
    ] {
    let operation = @opgrain.Operation::parse(wire)
    let path = operation.get_components()[0].get_path()
    let old = Json::number(1.0e-20)
    let value = match path.last() {
      Some(Key(_)) => Json::object(Map([("points", old)]))
      Some(Index(_)) => Json::array([old])
      None => old
    }
    let base = @opgrain.Snapshot::new(Some(value))
    let edit = engine.prepare_edit(base, operation)
    assert_eq(edit.operation().to_json(), operation.to_json())
    assert_eq(
      engine.apply_snapshot_verified(edit.snapshot(), edit.inverse()).to_json(),
      Some(value),
    )
    assert_true(edit.inverse().to_json() != engine.invert(operation).to_json())
    assert_eq(base.read(path), old)
  }
}

///|
test "prepared undo keeps standard numeric inverse when it is exact" {
  let engine = @opgrain.Engine::new()
  let operation = @opgrain.Operation::parse(
    "[{\"p\":[],\"na\":0.5},{\"p\":[],\"na\":2}]",
  )
  let base = @opgrain.Snapshot::new(Some(Json::number(2)))
  let edit = engine.prepare_edit(base, operation)
  assert_eq(edit.inverse().to_json(), engine.invert(operation).to_json())
  assert_eq(edit.snapshot().to_json(), Some(Json::number(4.5)))
}

///|
test "prepared undo reports subtype inverses that do not recover their document" {
  let engine = @opgrain.Engine::new()
  engine.register_subtype("bad-inverse", {
    apply: (_, value) => value,
    compose: (_, b) => b,
    invert: _ => Json::null(),
    transform: (a, _, _) => a,
  })
  let base = @opgrain.Snapshot::new(Some(Json::number(1)))
  let operation = @opgrain.Operation::parse(
    "[{\"p\":[],\"t\":\"bad-inverse\",\"o\":2}]",
  )
  try engine.prepare_edit(base, operation) catch {
    @opgrain.UndoDidNotRestore(before, after) => {
      assert_eq(before, Some(Json::number(1)))
      assert_eq(after, Some(Json::null()))
    }
    error => raise error
  } noraise {
    _ => fail("incorrect subtype inverse accepted")
  }
  assert_eq(base.to_json(), Some(Json::number(1)))
}

///|
test "prepared undo does not expose partial forward state after a later rejection" {
  let engine = @opgrain.Engine::new()
  let base = @opgrain.Snapshot::new(Some(Json::array([Json::string("A")])))
  let operation = @opgrain.Operation::parse(
    "[{\"p\":[0],\"li\":\"B\"},{\"p\":[1],\"ld\":\"stale\"}]",
  )
  try engine.prepare_edit(base, operation) catch {
    @opgrain.ForwardRejected(@opgrain.StalePreimage(1, _, _, _)) => ()
    error => raise error
  } noraise {
    _ => fail("stale component accepted")
  }
  assert_eq(base.to_json(), Some(Json::array([Json::string("A")])))
}
