///|
test "typed instructions roundtrip through JSON0 and retain detached payloads" {
  let payload = Json::array([Json::string("Review")])
  let insert = @opgrain.Component::new([Key("tasks")], ObjectInsert(payload))
  guard payload is Array(items) else { fail("array") }
  items.push(Json::null())
  assert_eq(
    insert.to_json(),
    @opgrain.parse_json("{\"p\":[\"tasks\"],\"oi\":[\"Review\"]}"),
  )
  let operation = @opgrain.Operation::single(insert)
  let prefixed = operation.with_prefix([Key("board")])
  assert_eq(
    prefixed.without_prefix([Key("board")]).unwrap().to_json(),
    operation.to_json(),
  )
  assert_true(prefixed.without_prefix([Key("other")]) is None)
}

///|
test "bounded queries distinguish object keys from indices and avoid duplicate descendant matches" {
  let snapshot = @opgrain.Snapshot::new(
    Some(
      @opgrain.parse_json(
        "{\"tasks\":[{\"title\":\"Review\"},{\"title\":\"Publish\"}],\"0\":{\"title\":\"Key\"}}",
      ),
    ),
  )
  let selected = snapshot.select([Descendants, Descendants, ExactKey("title")])
  assert_eq(selected.values(), [
    Json::string("Key"),
    Json::string("Review"),
    Json::string("Publish"),
  ])
  assert_eq(selected.length(), 3)
  assert_true(snapshot.contains_path(@opgrain.Path::parse("[\"0\",\"title\"]")))
  assert_false(snapshot.contains_path(@opgrain.Path::parse("[0]")))
  let limits = { ..@opgrain.QueryLimits::default(), max_matches: 1, }
  try snapshot.select([Descendants], limits~) catch {
    @opgrain.QueryBudget("matches", 1) => ()
    error => raise error
  } noraise {
    _ => fail("query budget ignored")
  }
}

///|
test "bounded JSON decoder preserves surrogates, duplicate policy and error offsets" {
  let source = "{\"title\":\"\\ud800!\",\"value\":1,\"value\":2}"
  assert_eq(@opgrain.decode_json(source), @opgrain.parse_json(source))
  let options = {
    ..@opgrain.DecodeOptions::default(),
    reject_duplicate_keys: true,
  }
  try @opgrain.decode_json(source, options~) catch {
    @opgrain.DuplicateMember(_, "value") => ()
    error => raise error
  } noraise {
    _ => fail("duplicate key accepted")
  }
  for bad in ["[1,]", "{\"a\":1,}", "[01]", "{\"a\" 1}", "true false"] {
    try @opgrain.decode_json(bad) catch {
      @opgrain.JsonSyntax(_, _) => ()
      error => raise error
    } noraise {
      _ => fail("invalid JSON accepted")
    }
  }
  let input = @opgrain.JsonInput::new()
  input.push("{\"title\":\"\\ud")
  input.push("800\"}")
  assert_eq(input.finish(), @opgrain.parse_json("{\"title\":\"\\ud800\"}"))
}

///|
test "configurable JSON encoding produces bounded chunks and readable pairs" {
  let value = @opgrain.parse_json("{\"z\":\"😀\\ud800\",\"a\":[1,true]}")
  let options = {
    ..@opgrain.EncodeOptions::default(),
    sort_keys: true,
    escape_non_ascii: false,
    indent: 2,
    chunk_units: 3,
  }
  let chunks = []
  let units = @opgrain.encode_json_to(
    value,
    text => chunks.push(text),
    options~,
  )
  assert_true(chunks.all(chunk => chunk.length() <= 3))
  let encoded = @opgrain.encode_json(value, options~)
  assert_eq(units, encoded.length())
  assert_eq(@opgrain.decode_json(encoded), value)
}

///|
test "iterative JSON decoder can accept deeper documents with an explicit limit" {
  let source = "[".repeat(2000) + "null" + "]".repeat(2000)
  let options = { ..@opgrain.DecodeOptions::default(), max_depth: 2000, }
  let value = @opgrain.decode_json(source, options~)
  assert_eq(@opgrain.stringify_json(value), source)
  try @opgrain.decode_json(source) catch {
    @opgrain.JsonLimit(_, "depth", 1024) => ()
    error => raise error
  } noraise {
    _ => fail("depth limit ignored")
  }
}
