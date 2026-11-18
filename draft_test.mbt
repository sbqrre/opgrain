///|
test "draft captures preimages as the board changes" {
  let base = @opgrain.parse_json(
    "{\"tasks\":[null,{\"title\":\"审😀稿\"}],\"score\":2}",
  )
  let engine = @opgrain.Engine::new()
  let draft = engine.draft(Some(base))
  draft.remove_item([Key("tasks"), Index(0)])
  draft.splice_text(
    [Key("tasks"), Index(0), Key("title")],
    1,
    2,
    "完",
    encoding=Legacy,
  )
  draft.set([Key("owner")], Json::null())
  draft.add_number([Key("score")], 0.5)
  let operation = draft.operation()
  assert_eq(engine.apply_verified(Some(base), operation), draft.snapshot())
  assert_eq(
    engine.apply_verified(draft.snapshot(), engine.invert(operation)),
    Some(base),
  )
  assert_eq(
    operation.to_json(),
    @opgrain.parse_json(
      (
        #|[{"p":["tasks",0],"ld":null},{"p":["tasks",0,"title",1],"sd":"😀"},{"p":["tasks",0,"title",1],"si":"完"},{"p":["owner"],"oi":null},{"p":["score"],"na":0.5}]
      ),
    ),
  )
}

///|
test "failed append leaves the draft and its operation unchanged" {
  let engine = @opgrain.Engine::new()
  let base = @opgrain.parse_json("{\"tasks\":[null]}")
  let draft = engine.draft(Some(base))
  let raw =
    #|[{"p":["tasks",1],"li":"B"},{"p":["tasks",0],"ld":"stale"}]
  let operation = @opgrain.Operation::parse(raw)
  try draft.append(operation) catch {
    @opgrain.StalePreimage(index, path, expected, actual) => {
      assert_eq(index, 1)
      assert_eq(path, [Key("tasks"), Index(0)])
      assert_eq(expected, Some(Json::string("stale")))
      assert_eq(actual, Some(Json::null()))
    }
    error => raise error
  } noraise {
    _ => fail("stale operation was accepted")
  }
  assert_eq(draft.snapshot(), Some(base))
  assert_eq(draft.operation().length(), 0)
}

///|
test "verified apply distinguishes an absent root from null and indexes path errors" {
  let engine = @opgrain.Engine::new()
  let create = @opgrain.Operation::parse("[{\"p\":[],\"oi\":null}]")
  assert_eq(engine.apply_verified(None, create), Some(Json::null()))
  try engine.apply_verified(Some(Json::null()), create) catch {
    @opgrain.StalePreimage(0, [], None, Some(Null)) => ()
    error => raise error
  } noraise {
    _ => fail("root creation overwrote null")
  }
  let bad = @opgrain.Operation::parse("[{\"p\":[\"absent\",0],\"li\":null}]")
  try engine.apply_verified(Some(Json::object(Map([]))), bad) catch {
    @opgrain.ComponentFailed(
      0,
      [Key("absent"), Index(0)],
      @opgrain.InvalidPath(_, _)
    ) => ()
    error => raise error
  } noraise {
    _ => fail("missing parent was accepted")
  }
}

///|
test "draft paths, input values, reads, and saved operations are detached" {
  let input = @opgrain.parse_json("{\"tasks\":[]}")
  let value = @opgrain.parse_json("{\"caption\":\"First\"}")
  let draft = @opgrain.Engine::new().draft(Some(input))
  let path : Array[@opgrain.PathSegment] = [Key("tasks"), Index(0)]
  draft.insert_item(path, value)
  path[1] = Index(1)
  let saved = draft.operation()
  guard value is Object(fields) else { fail("expected object") }
  fields["caption"] = Json::string("Modified")
  guard draft.read([Key("tasks"), Index(0)]) is Object(read) else {
    fail("expected object")
  }
  read["caption"] = Json::null()
  draft.move_item([Key("tasks"), Index(0)], 0)
  draft.insert_item(path, Json::null())
  assert_eq(saved.length(), 1)
  assert_eq(saved.get_components()[0].get_path(), [Key("tasks"), Index(0)])
  assert_eq(
    draft.read([Key("tasks"), Index(0), Key("caption")]),
    Json::string("First"),
  )
  assert_eq(input, @opgrain.parse_json("{\"tasks\":[]}"))
}

///|
test "a split surrogate can be spliced and inverted on the wire" {
  let engine = @opgrain.Engine::new()
  let draft = engine.draft(Some(Json::string("😀")))
  draft.splice_text([], 1, 1, "!")
  guard draft.snapshot() is Some(updated) else { fail("missing root") }
  assert_eq(@opgrain.stringify_json(updated), "\"\\ud83d!\"")
  let roundtrip = @opgrain.Operation::parse(draft.operation().stringify())
  assert_eq(
    engine.apply_verified(Some(updated), engine.invert(roundtrip)),
    Some(Json::string("😀")),
  )
}
