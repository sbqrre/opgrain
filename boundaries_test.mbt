///|
test "all UTF16 units roundtrip through bounded decoder and both encoder modes" {
  let text = String::from_array(
    Array::makei(65536, index => index.unsafe_to_char()),
  )
  let value = Json::string(text)
  for escape_non_ascii in [true, false] {
    let encoded = @opgrain.encode_json(value, options={
      ..@opgrain.EncodeOptions::default(),
      escape_non_ascii,
      chunk_units: 7,
    })
    assert_eq(@opgrain.decode_json(encoded), value)
  }
}

///|
test "coordinate conversions reject split pairs and malformed scalar strings" {
  let index = @opgrain.TextIndex::new("😀a\r\n中")
  assert_eq(index.lengths().utf8_bytes, 10)
  assert_eq(index.at_code_point(1).utf16, 2)
  assert_eq(index.at_utf8(4).code_points, 1)
  try index.at_utf16(1) catch {
    @opgrain.SplitCodePoint(1) => ()
    error => raise error
  } noraise {
    _ => fail("surrogate split accepted")
  }
  try index.at_utf8(2) catch {
    @opgrain.CoordinateOutOfBounds("inside UTF-8 sequence", 2) => ()
    error => raise error
  } noraise {
    _ => fail("UTF8 split accepted")
  }
  let isolated = String::from_array([(0xd800).unsafe_to_char()])
  try @opgrain.TextIndex::new(isolated) catch {
    @opgrain.IsolatedSurrogate(0) => ()
    error => raise error
  } noraise {
    _ => fail("isolated surrogate indexed as a scalar")
  }
  for offset in 0..<(index.lengths().utf16 + 1) {
    let (line, column) = index.line_position(offset)
    assert_eq(index.line_offset(line, column), offset)
  }
}

///|
test "bounded decoder rejects malformed JSON and enforces every resource dimension" {
  for
    source in [
      "", "-", "00", "1.", "1e", "1e+", "+1", ".1", "[", "{", "{\"x\":}", "[true false]",
      "\"\\x\"", "\"\\u00x0\"", "1e309",
    ] {
    try @opgrain.decode_json(source) catch {
      _ => ()
    } noraise {
      _ => fail("accepted " + source)
    }
  }
  let base = @opgrain.DecodeOptions::default()
  for
    (source, options) in [
      ("[]", { ..base, max_depth: 0, }),
      ("[1]", { ..base, max_values: 1, }),
      ("\"abc\"", { ..base, max_string_units: 2, }),
      ("null", { ..base, max_input_units: 3, }),
    ] {
    try @opgrain.decode_json(source, options~) catch {
      @opgrain.JsonLimit(_, _, _) => ()
      error => raise error
    } noraise {
      _ => fail("decoder budget ignored")
    }
  }
  let input = @opgrain.JsonInput::new(options={ ..base, max_input_units: 4, })
  input.push("null")
  try input.push(" ") catch {
    @opgrain.JsonLimit(_, _, _) => ()
    error => raise error
  } noraise {
    _ => fail("input overflow accepted")
  }
  assert_eq(input.finish(), Json::null())
  input.reset()
  input.push("true")
  assert_eq(input.finish(), Json::boolean(true))
}

///|
test "bounded application cursor is persistent resumable and atomic on stale preimages" {
  let engine = @opgrain.Engine::new()
  let base = @opgrain.Snapshot::new(Some({ "points": 1 }))
  let operation = @opgrain.Operation::parse(
    "[{\"p\":[\"points\"],\"na\":2},{\"p\":[\"title\"],\"oi\":\"Review\"}]",
  )
  let initial = engine.apply_cursor(base, operation)
  let first = initial.advance(1)
  assert_eq(initial.offset(), 0)
  assert_eq(first.snapshot().read([Key("points")]), 3)
  assert_eq(first.seek(0).snapshot().to_json(), base.to_json())
  assert_eq(first.finish().read([Key("title")]), "Review")
  assert_eq(initial.checkpoints(1).length(), 3)
  let stale = @opgrain.Operation::parse(
    "[{\"p\":[\"points\"],\"na\":1},{\"p\":[\"points\"],\"od\":99}]",
  )
  let cursor = engine.apply_cursor(base, stale)
  try cursor.advance(2) catch {
    @opgrain.CursorComponent(1, _) => ()
    error => raise error
  } noraise {
    _ => fail("stale inverse ignored")
  }
  assert_eq(cursor.snapshot().read([Key("points")]), 1)
}

///|
test "tracked snapshots and text projections follow task identity across moves" {
  let engine = @opgrain.Engine::new()
  let snapshot = @opgrain.Snapshot::new(
    Some({ "tasks": [{ "title": "看😀板" }, { "title": "Publish" }] }),
  )
  let operation = @opgrain.Operation::parse(
    "[{\"p\":[\"tasks\",0],\"lm\":1},{\"p\":[\"tasks\",1,\"title\",3],\"si\":\"!\"}]",
  )
  let path = @opgrain.Path::new([Key("tasks"), Index(0), Key("title")])
  let projected = engine.project_text(snapshot, operation, path)
  assert_eq(projected.after(), "看😀!板")
  assert_eq(projected.final_path().segments(), [
    Key("tasks"),
    Index(1),
    Key("title"),
  ])
  let tracked = engine.apply_tracked_snapshot(snapshot, operation, [
    Node(path.segments()),
  ])
  assert_eq(tracked.values(), [Some(Json::string("看😀!板"))])
  let remove = @opgrain.Operation::single(
    @opgrain.Component::new(
      [Key("tasks"), Index(1)],
      ListDelete({ "title": "看😀!板" }),
    ),
  )
  let lost = engine.advance_tracking(tracked, [remove])
  assert_eq(lost.alive(), 0)
  assert_eq(lost.losses()[0].unwrap().reason, ListItemRemoved)
  assert_eq(tracked.alive(), 1)
}

///|
test "iterative snapshot diff and comparison support deep objects and absent roots" {
  let engine = @opgrain.Engine::new()
  let source = "{\"child\":".repeat(1500)
  let tail = "}".repeat(1500)
  let options = { ..@opgrain.DecodeOptions::default(), max_depth: 1600, }
  let before = @opgrain.Snapshot::new(
    Some(@opgrain.decode_json(source + "1" + tail, options~)),
  )
  let after = @opgrain.Snapshot::new(
    Some(@opgrain.decode_json(source + "2" + tail, options~)),
  )
  let diff = engine.diff_snapshots(before, after, options={
    ..@opgrain.IterativeDiffOptions::default(),
    max_depth: 1600,
  })
  assert_true(diff.after().equivalent(after))
  let comparison = before.compare(after, limits={
    ..@opgrain.ComparisonLimits::default(),
    max_depth: 1600,
  })
  assert_eq(comparison.differences().length(), 1)
  assert_eq(comparison.differences()[0].path().length(), 1500)
  assert_eq(comparison.differences()[0].before(), Some(Json::number(1)))
  let absent = @opgrain.Snapshot::new(None)
  let null = @opgrain.Snapshot::new(Some(Json::null()))
  assert_false(absent.equivalent(null))
  assert_true(engine.diff_snapshots(absent, null).after().equivalent(null))
}

///|
test "iterative array diffs preserve unchanged suffixes and finite-number deltas" {
  let engine = @opgrain.Engine::new()
  let cases : Array[(Json, Json)] = [
    ([1, 2, 3, 4], [1, 8, 4]),
    ([1, 2, 4], [1, 8, 9, 10, 4]),
    ([1, 2, 3], []),
    ([], [1, 2, 3]),
    ([{ "x": 1 }, "a"], [{ "x": 2 }, "abc"]),
  ]
  for (before, after) in cases {
    let before = @opgrain.Snapshot::new(Some(before))
    let after = @opgrain.Snapshot::new(Some(after))
    assert_true(engine.diff_snapshots(before, after).after().equivalent(after))
  }
}

///|
test "standalone text0 has upstream insertion priority and composition behavior" {
  let left = @opgrain.TextOperation::new([InsertText(1, "甲")])
  let right = @opgrain.TextOperation::new([InsertText(1, "乙")])
  let (a, b) = left.transform_pair(right)
  assert_eq(b.apply(left.apply("ab")), "a甲乙b")
  assert_eq(a.apply(right.apply("ab")), "a甲乙b")
  assert_eq(left.compose(b).apply("ab"), "a甲乙b")
  assert_eq(
    left.transform(right, Right).to_json(),
    right.transform_pair(left).1.to_json(),
  )
}
