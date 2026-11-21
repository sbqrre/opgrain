///|
test "persistent snapshots retain their ancestors and expose detached data" {
  let engine = @opgrain.Engine::new()
  let raw =
    #|{"tasks":[{"title":"A","points":1},{"title":"B","points":2}]}
  let input = @opgrain.parse_json(raw)
  let original = @opgrain.Snapshot::new(Some(input))
  let op = @opgrain.Operation::parse(
    "[{\"p\":[\"tasks\",0],\"lm\":1},{\"p\":[\"tasks\",1,\"points\"],\"na\":0.5}]",
  )
  let updated = engine.apply_snapshot_verified(original, op)
  let expected =
    #|{"tasks":[{"title":"B","points":2},{"title":"A","points":1.5}]}
  assert_eq(updated.to_json(), Some(@opgrain.parse_json(expected)))
  assert_eq(original.to_json(), Some(input))
  assert_eq(
    engine.apply_snapshot(updated, engine.invert(op)).to_json(),
    Some(input),
  )
  let subtree = updated.subtree([Key("tasks"), Index(1)])
  guard subtree.to_json() is Some(Object(fields)) else { fail("object") }
  fields["title"] = Json::null()
  assert_eq(
    updated.read([Key("tasks"), Index(1), Key("title")]),
    Json::string("A"),
  )
  guard input is Object(fields) else { fail("object") }
  fields["tasks"] = Json::null()
  assert_eq(original.to_json(), Some(@opgrain.parse_json(raw)))
}

///|
test "persistent batches leave earlier snapshots intact after a late failure" {
  let engine = @opgrain.Engine::new()
  let original = @opgrain.Snapshot::new(Some(Json::array([Json::string("A")])))
  let first = @opgrain.Operation::parse("[{\"p\":[0],\"li\":\"B\"}]")
  let stale = @opgrain.Operation::parse("[{\"p\":[1],\"ld\":\"B\"}]")
  try engine.apply_snapshot_batches(original, [first, stale]) catch {
    @opgrain.HistoryApplyFailed(
      Original,
      Left,
      1,
      @opgrain.StalePreimage(0, _, _, _),
    ) => ()
    error => raise error
  } noraise {
    _ => fail("stale preimage passed")
  }
  assert_eq(original.to_json(), Some(Json::array([Json::string("A")])))
  assert_eq(
    engine.apply_snapshot_batches(original, []).to_json(),
    original.to_json(),
  )
}

///|
test "custom subtype callbacks cannot mutate a persistent ancestor on failure" {
  let engine = @opgrain.Engine::new()
  engine.register_subtype("mutating", {
    apply: (value, _) => {
      guard value is Object(fields) else {
        raise @opgrain.SubtypeError("mutating", "object")
      }
      fields["title"] = Json::string("changed")
      raise @opgrain.SubtypeError("mutating", "failed")
    },
    compose: (a, _) => a,
    invert: a => a,
    transform: (a, _, _) => a,
  })
  let raw =
    #|{"task":{"title":"A"}}
  let original = @opgrain.Snapshot::new(Some(@opgrain.parse_json(raw)))
  let op = @opgrain.Operation::parse(
    "[{\"p\":[\"task\"],\"t\":\"mutating\",\"o\":null}]",
  )
  try engine.apply_snapshot(original, op) catch {
    @opgrain.SubtypeError("mutating", "failed") => ()
    error => raise error
  } noraise {
    _ => fail("callback should fail")
  }
  assert_eq(original.read([Key("task"), Key("title")]), Json::string("A"))
}

///|
test "missing root and null remain distinct across persistent updates" {
  let engine = @opgrain.Engine::new()
  let root = @opgrain.Snapshot::new(None)
  let create = @opgrain.Operation::parse("[{\"p\":[],\"oi\":null}]")
  let next = engine.apply_snapshot_verified(root, create)
  assert_eq(next.to_json(), Some(Json::null()))
  assert_eq(root.to_json(), None)
  assert_eq(
    engine.apply_snapshot_verified(next, engine.invert(create)).to_json(),
    None,
  )
}

///|
test "clone and path rebuilding handle four thousand nested containers" {
  let mut nested = Json::number(1)
  let path : Array[@opgrain.PathSegment] = []
  for _ in 0..<4000 {
    nested = Json::array([nested])
    path.push(Index(0))
  }
  let original = @opgrain.Snapshot::new(Some(nested))
  let draft = @opgrain.Engine::new().draft(Some(nested))
  draft.add_number(path, 0.5)
  let updated = @opgrain.Engine::new().apply_snapshot_verified(
    original,
    draft.operation(),
  )
  assert_eq(original.read(path), Json::number(1))
  assert_eq(updated.read(path), Json::number(1.5))
}
