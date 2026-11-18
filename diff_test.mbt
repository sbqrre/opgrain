///|
test "diff moves identified cards then edits the moved title" {
  let engine = @opgrain.Engine::new()
  let old_wire =
    #|{"cards":[{"id":"a","title":"Review"},{"id":"b","title":"审😀稿"},{"id":"d","title":"Older"}],"score":2}
  let new_wire =
    #|{"cards":[{"id":"b","title":"审😃稿"},{"id":"a","title":"Review"},{"id":"c","title":"Document"}],"score":2.5}
  let before = @opgrain.parse_json(old_wire)
  let after = @opgrain.parse_json(new_wire)
  let options = {
    ..@opgrain.DiffOptions::default(),
    list_identity_key: Some("id"),
    prefer_number_add: true,
  }
  let operation = engine.diff(Some(before), Some(after), options~)
  let expected =
    #|[{"p":["cards",2],"ld":{"id":"d","title":"Older"}},{"p":["cards",1],"lm":0},{"p":["cards",0,"title"],"t":"text0","o":[{"p":2,"d":"\ude00"},{"p":2,"i":"\ude03"}]},{"p":["cards",2],"li":{"id":"c","title":"Document"}},{"p":["score"],"na":0.5}]
  assert_eq(operation.to_json(), @opgrain.parse_json(expected))
  let operation = @opgrain.Operation::parse(operation.stringify())
  assert_eq(engine.apply_verified(Some(before), operation), Some(after))
  assert_eq(
    engine.apply_verified(Some(after), engine.invert(operation)),
    Some(before),
  )
}

///|
test "diff keeps unchanged middle spans when alignment is available" {
  let engine = @opgrain.Engine::new()
  let before = Json::string("aXYZb")
  let after = Json::string("cXYZd")
  let options = { ..@opgrain.DiffOptions::default(), text_encoding: Legacy, }
  let expected =
    #|[{"p":[0],"sd":"a"},{"p":[0],"si":"c"},{"p":[4],"sd":"b"},{"p":[4],"si":"d"}]
  let operation = engine.diff(Some(before), Some(after), options~)
  assert_eq(operation.to_json(), @opgrain.parse_json(expected))
  let coarse = { ..options, alignment_cells: 0, }
  let compact = engine.diff(Some(before), Some(after), options=coarse)
  assert_eq(compact.length(), 2)
  assert_eq(engine.apply(before, compact), after)
  assert_eq(engine.apply(after, engine.invert(compact)), before)
}

///|
test "diff falls back for duplicate list identities and irreversible number addition" {
  let engine = @opgrain.Engine::new()
  let old_source =
    #|{"n":1e-20,"tasks":[{"id":"a","name":"A"},{"id":"a","name":"B"}]}
  let new_source =
    #|{"tasks":[{"id":"a","name":"B"},{"id":"a","name":"A"}],"n":1}
  let before = @opgrain.parse_json(old_source)
  let after = @opgrain.parse_json(new_source)
  let options = {
    ..@opgrain.DiffOptions::default(),
    list_identity_key: Some("id"),
    prefer_number_add: true,
  }
  let operation = engine.diff(Some(before), Some(after), options~)
  let first_wire =
    #|{"p":["n"],"oi":1,"od":1e-20}
  assert_eq(
    operation.get_components()[0].to_json(),
    @opgrain.parse_json(first_wire),
  )
  assert_eq(engine.apply_verified(Some(before), operation), Some(after))
  assert_eq(
    engine.apply_verified(Some(after), engine.invert(operation)),
    Some(before),
  )
}

///|
test "diff handles missing roots and unbounded JSON values are rejected" {
  let engine = @opgrain.Engine::new()
  let null = Some(Json::null())
  let create = engine.diff(None, null)
  assert_eq(engine.apply_verified(None, create), null)
  assert_eq(engine.apply_verified(null, engine.diff(null, None)), None)
  assert_eq(engine.diff(null, null).length(), 0)
  let items : Array[Json] = []
  let cycle = Json::array(items)
  items.push(cycle)
  try engine.diff(None, Some(cycle)) catch {
    @opgrain.InvalidJson(_) => ()
    error => raise error
  } noraise {
    _ => fail("cyclic snapshot was accepted")
  }
}

///|
fn board_values(seed : UInt32, size : Int32) -> Json {
  let mut value = seed
  let items = Array::makei(size, i => {
    value = value * 1664525U + 1013904223U
    let category = (value >> 27).reinterpret_as_int() % 6
    match category {
      0 => Json::null()
      1 => Json::string("待😀办")
      2 => Json::number(i.to_double())
      3 => Json::string("已完成")
      4 => Json::array([Json::boolean(i % 2 == 0), Json::string("复核")])
      _ =>
        Json::object(Map([("status", Json::number((value >> 30).to_double()))]))
    }
  })
  Json::object(Map([("tasks", Json::array(items))]))
}

///|
test "seeded board snapshots diff and invert at different alignment budgets" {
  let engine = @opgrain.Engine::new()
  for seed in 0..<150 {
    let before = board_values(seed.reinterpret_as_uint(), seed % 13)
    let after = board_values((2411 + seed).reinterpret_as_uint(), seed * 3 % 17)
    let options = {
      ..@opgrain.DiffOptions::default(),
      alignment_cells: if seed % 2 == 0 {
        0
      } else {
        16384
      },
    }
    let operation = engine.diff(Some(before), Some(after), options~)
    let updated = engine.apply_verified(Some(before), operation)
    assert_true(updated == Some(after), msg="forward seed \{seed}")
    assert_true(
      engine.apply_verified(updated, engine.invert(operation)) == Some(before),
      msg="inverse seed \{seed}",
    )
  }
}
