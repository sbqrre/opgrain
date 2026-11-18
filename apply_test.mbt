///|
test "apply board edits without aliases" {
  let start = @opgrain.parse_json(
    "{\"tasks\":[{\"title\":\"A\",\"estimate\":1.25},{\"title\":\"B\"}]}",
  )
  let operation = @opgrain.Operation::parse(
    (
      #|[{"p":["tasks",0],"lm":1},{"p":["tasks",1,"estimate"],"na":0.5},{"p":["tasks",1,"title",1],"si":"!"},{"p":["done"],"oi":false}]
    ),
  )
  let result = @opgrain.apply(start, operation)
  assert_eq(
    result,
    @opgrain.parse_json(
      "{\"tasks\":[{\"title\":\"B\"},{\"title\":\"A!\",\"estimate\":1.75}],\"done\":false}",
    ),
  )
  assert_eq(
    start,
    @opgrain.parse_json(
      "{\"tasks\":[{\"title\":\"A\",\"estimate\":1.25},{\"title\":\"B\"}]}",
    ),
  )
}

///|
test "UTF-16 half survives JSON0 interchange" {
  let snapshot = @opgrain.parse_json(
    (
      #|"\u4e2d\ud83d\ude00e\u0301"
    ),
  )
  let operation = @opgrain.Operation::parse(
    (
      #|[{"p":[1],"sd":"\ud83d"}]
    ),
  )
  assert_eq(
    @opgrain.stringify_json(@opgrain.apply(snapshot, operation)),
    (
      #|"\u4e2d\ude00e\u0301"
    ),
  )
}

///|
test "null and absent roots are distinct" {
  let registry = @opgrain.Engine::new()
  let drop = @opgrain.Operation::parse(
    (
      #|[{"p":[],"od":null}]
    ),
  )
  assert_eq(registry.apply_optional(Some(Json::null()), drop), None)
  let restore = @opgrain.Operation::parse(
    (
      #|[{"p":[],"oi":null}]
    ),
  )
  assert_eq(registry.apply_optional(None, restore), Some(Json::null()))
}

///|
test "failed batch leaves caller data intact" {
  let initial =
    #|{"tasks":[1]}
  let edits =
    #|[{"p":["tasks",0],"na":1},{"p":["tasks",2],"ld":1}]
  let start = @opgrain.parse_json(initial)
  let operation = @opgrain.Operation::parse(edits)
  try @opgrain.apply(start, operation) catch {
    @opgrain.InvalidPath(_, _) => ()
    _ => fail("unexpected error variant")
  } noraise {
    _ => fail("expected out-of-bounds path")
  }
  assert_eq(start, @opgrain.parse_json(initial))
}
