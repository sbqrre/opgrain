///|
test "tracking follows nested card paths through moves and reports the first deletion" {
  let engine = @opgrain.Engine::new()
  let source =
    #|{"cards":[{"title":"A"},{"title":"B"},{"title":"C"}]}
  let base = @opgrain.parse_json(source)
  let path : Array[@opgrain.PathSegment] = [
    Key("cards"),
    Index(0),
    Key("title"),
  ]
  let move_card = @opgrain.Operation::parse("[{\"p\":[\"cards\",0],\"lm\":2}]")
  let edit =
    #|[{"p":["cards",0],"ld":{"title":"B"}},{"p":["cards",1,"title",1],"si":"!"}]
  let batches = [move_card, @opgrain.Operation::parse(edit)]
  let result = engine.apply_tracked_batches(Some(base), batches, [
    Node(path),
    Node([Key("cards"), Index(1)]),
    Node([Key("cards"), Index(2)]),
    Node([Key("cards")]),
    Cursor(path, { offset: 1, affinity: AfterInsertion, }),
  ])
  path[0] = Key("discard")
  assert_eq(result.locations(), [
    Some(Node([Key("cards"), Index(1), Key("title")])),
    None,
    Some(Node([Key("cards"), Index(0)])),
    Some(Node([Key("cards")])),
    Some(
      Cursor([Key("cards"), Index(1), Key("title")], {
        offset: 2,
        affinity: AfterInsertion,
      }),
    ),
  ])
  assert_eq(result.losses(), [
    None,
    Some({ batch: 1, component: 0, reason: ListItemRemoved, }),
    None,
    None,
    None,
  ])
  let expected =
    #|{"cards":[{"title":"C"},{"title":"A!"}]}
  assert_eq(result.snapshot(), Some(@opgrain.parse_json(expected)))
  guard result.locations()[0] is Some(Node(returned)) else {
    fail("anchor was lost")
  }
  returned[0] = Key("discard")
  assert_eq(
    result.locations()[0],
    Some(Node([Key("cards"), Index(1), Key("title")])),
  )
}

///|
test "tracking applies before and after insertion affinity inside UTF-16 ranges" {
  let engine = @opgrain.Engine::new()
  let base = Some(Json::string("待😀办"))
  let draft = engine.draft(base)
  draft.splice_text([], 1, 2, "稿😀")
  let left : @opgrain.TextPosition = { offset: 2, affinity: BeforeInsertion, }
  let right : @opgrain.TextPosition = { offset: 2, affinity: AfterInsertion, }
  let range_end : @opgrain.TextPosition = { ..right, offset: 3, }
  for encoding in [@opgrain.TextEncoding::Text0, Legacy] {
    let operation = engine.reencode_text(draft.operation(), encoding)
    let result = engine.apply_tracked(base, operation, [
      Node([]),
      Cursor([], left),
      Cursor([], right),
      TextRange([], left, range_end),
      TextRange([], right, { ..left, offset: 3, }),
    ])
    assert_eq(result.snapshot(), Some(Json::string("待稿😀办")))
    assert_eq(result.locations(), [
      Some(Node([])),
      Some(Cursor([], { ..left, offset: 1, })),
      Some(Cursor([], { ..right, offset: 4, })),
      Some(TextRange([], { ..left, offset: 1, }, { ..right, offset: 4, })),
      Some(TextRange([], { ..right, offset: 4, }, { ..left, offset: 4, })),
    ])
  }
}

///|
test "tracking distinguishes overwritten values and opaque custom subtype effects" {
  let engine = @opgrain.Engine::new()
  engine.register_subtype("board", {
    apply: (_, value) => value,
    compose: (_, next) => next,
    invert: value => value,
    transform: (value, _, _) => value,
  })
  let source =
    #|{"a":{"round":1},"b":null,"c":["A","B"]}
  let wire =
    #|[{"p":["b"],"oi":false,"od":null},{"p":["a"],"t":"board","o":{"round":2}},{"p":["c",1],"lm":0}]
  let base = Some(@opgrain.parse_json(source))
  let operation = @opgrain.Operation::parse(wire)
  let result = engine.apply_tracked(base, operation, [
    Node([Key("a"), Key("round")]),
    Node([Key("b")]),
    Node([Key("c"), Index(0)]),
    Node([Key("c"), Index(1)]),
  ])
  assert_eq(result.locations(), [
    None,
    None,
    Some(Node([Key("c"), Index(1)])),
    Some(Node([Key("c"), Index(0)])),
  ])
  assert_eq(result.losses(), [
    Some({ batch: 0, component: 1, reason: OpaqueSubtype, }),
    Some({ batch: 0, component: 0, reason: NodeOverwritten, }),
    None,
    None,
  ])
}

///|
test "tracking identifies invalid starting positions and the failing batch" {
  let engine = @opgrain.Engine::new()
  let base = Some(Json::string("😀"))
  try
    engine.apply_tracked_batches(base, [], [
      Node([]),
      Cursor([], { offset: 3, affinity: BeforeInsertion, }),
    ])
  catch {
    @opgrain.InvalidLocation(1, [], @opgrain.InvalidPath(_, _)) => ()
    error => raise error
  } noraise {
    _ => fail("invalid cursor was accepted")
  }
  let first = @opgrain.Operation::parse("[{\"p\":[2],\"si\":\"!\"}]")
  let stale = @opgrain.Operation::parse("[{\"p\":[2],\"sd\":\"?\"}]")
  try engine.apply_tracked_batches(base, [first, stale], []) catch {
    @opgrain.TrackingApplyFailed(
      1,
      @opgrain.ComponentFailed(0, [Index(2)], @opgrain.TextMismatch(2))
    ) => ()
    error => raise error
  } noraise {
    _ => fail("incorrect deletion was accepted")
  }
}
