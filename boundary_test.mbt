///|
test "every UTF-16 code unit survives the JSON wire codec" {
  let text = String::from_array(
    Array::makei(65536, unit => unit.unsafe_to_char()),
  )
  let encoded = @opgrain.stringify_json(Json::string(text))
  assert_eq(@opgrain.parse_json(encoded), Json::string(text))
  let marker = @opgrain.parse_json(
    "\"\\ue000d800\\ue000dc00\\ue000e000\\ud800\"",
  )
  assert_eq(@opgrain.parse_json(@opgrain.stringify_json(marker)), marker)
}

///|
test "malformed JSON always returns a structured parse error" {
  let control = String::from_array(['"', (1).unsafe_to_char(), '"'])
  for
    source in [
      "", "[", "{", "true false", "01", "1.", "[,]", "[1,]", "{\"x\":}", "\"\\u12\"",
      "\"\\ud800\\uZZZZ\"", "\"\\q\"", "\"unterminated", control,
    ] {
    try @opgrain.parse_json(source) catch {
      @opgrain.InvalidJson(_) => ()
      error => raise error
    } noraise {
      _ => fail("accepted malformed input " + source)
    }
  }
}

///|
test "wire writing is iterative and parser depth failures are explicit" {
  let mut nested = Json::null()
  for _ in 0..<4000 {
    nested = Json::array([nested])
  }
  let encoded = @opgrain.stringify_json(nested)
  assert_eq(encoded.length(), 8004)
  try @opgrain.parse_json(encoded) catch {
    @opgrain.InvalidJson(_) => ()
    error => raise error
  } noraise {
    _ => fail("expected the core parser nesting limit")
  }
}

///|
test "all five-item move pairs converge and preserve their original snapshots" {
  let engine = @opgrain.Engine::new()
  let base = Json::array(
    Array::makei(5, i => {
      Json::object(Map([("id", Json::number(i.to_double()))]))
    }),
  )
  let original = @opgrain.Snapshot::new(Some(base))
  for from_left in 0..<5 {
    for to_left in 0..<5 {
      for from_right in 0..<5 {
        for to_right in 0..<5 {
          let left_draft = engine.draft_snapshot(original)
          let right_draft = engine.draft_snapshot(original)
          left_draft.move_item([Index(from_left)], to_left)
          right_draft.move_item([Index(from_right)], to_right)
          let left = left_draft.operation()
          let right = right_draft.operation()
          let (left_prime, right_prime) = engine.transform_x(left, right)
          let left_first = engine.apply_snapshot_verified(
            left_draft.snapshot_handle(),
            right_prime,
          )
          let right_first = engine.apply_snapshot_verified(
            right_draft.snapshot_handle(),
            left_prime,
          )
          assert_eq(left_first.to_json(), right_first.to_json())
          assert_eq(
            engine
            .apply_snapshot_verified(left_first, engine.invert(right_prime))
            .to_json(),
            left_draft.snapshot(),
          )
        }
      }
    }
  }
  assert_eq(original.to_json(), Some(base))
}

///|
test "Unicode splice pairs converge at every legal offset in either text encoding" {
  let engine = @opgrain.Engine::new()
  for
    source in [
      "\"中文\"", "\"😀e\\u0301\"", "\"\\ud800x\\udc00\"", "\"\\ue000e000\"",
    ] {
    let base = @opgrain.parse_json(source)
    guard base is String(text) else { fail("text") }
    for encoding in [@opgrain.TextEncoding::Legacy, Text0] {
      for start in 0..<(text.length() + 1) {
        for end in start..<(text.length() + 1) {
          for position in 0..<(text.length() + 1) {
            let left = engine.draft(Some(base))
            left.splice_text([], start, end - start, "修😀", encoding~)
            let right = engine.draft(Some(base))
            right.splice_text([], position, 0, "é", encoding~)
            let merged = engine.merge_histories(
              Some(base),
              [left.operation()],
              [right.operation()],
            )
            let (a, b) = engine.transform_x(left.operation(), right.operation())
            assert_eq(
              engine.apply(left.snapshot().unwrap(), b),
              merged.snapshot().unwrap(),
            )
            assert_eq(
              engine.apply(right.snapshot().unwrap(), a),
              merged.snapshot().unwrap(),
            )
            assert_eq(
              engine.apply_verified(
                left.snapshot(),
                engine.invert(left.operation()),
              ),
              Some(base),
            )
          }
        }
      }
    }
  }
}

///|
test "finite number extremes retain direct apply semantics" {
  let engine = @opgrain.Engine::new()
  let zero = @opgrain.Operation::parse("[{\"p\":[],\"na\":0}]")
  for
    wire in [
      "5e-324", "-5e-324", "1.7976931348623157e308", "-1.7976931348623157e308", "9007199254740991",
      "9007199254740992", "-0",
    ] {
    let value = @opgrain.parse_json(wire)
    assert_eq(engine.apply(value, zero), value)
    assert_eq(
      engine
      .apply_snapshot_verified(@opgrain.Snapshot::new(Some(value)), zero)
      .to_json(),
      Some(value),
    )
  }
  let original = Json::object(Map([("points", Json::number(1.0e-20))]))
  let after = Json::object(Map([("points", Json::number(1.0))]))
  let options = { ..@opgrain.DiffOptions::default(), prefer_number_add: true, }
  let delta = engine.diff(Some(original), Some(after), options~)
  assert_eq(
    engine.apply_verified(Some(after), engine.invert(delta)),
    Some(original),
  )
}

///|
test "cyclic objects are rejected while repeated sibling aliases are independently copied" {
  let fields : Map[String, Json] = Map([])
  let items = [Json::object(fields)]
  fields["back"] = Json::array(items)
  try @opgrain.Snapshot::new(Some(Json::object(fields))) catch {
    @opgrain.InvalidJson(_) => ()
    error => raise error
  } noraise {
    _ => fail("mutual cycle accepted")
  }
  let card = Json::object(Map([("points", Json::number(1))]))
  let original = @opgrain.Snapshot::new(Some(Json::array([card, card])))
  let increment = @opgrain.Operation::parse("[{\"p\":[0,\"points\"],\"na\":1}]")
  let after = @opgrain.Engine::new().apply_snapshot(original, increment)
  assert_eq(after.read([Index(0), Key("points")]), Json::number(2))
  assert_eq(after.read([Index(1), Key("points")]), Json::number(1))
  assert_eq(original.read([Index(0), Key("points")]), Json::number(1))
}

///|
test "compaction failure cannot advance history or discard retained revisions" {
  let engine = @opgrain.Engine::new()
  let journal = engine.journal(Some(Json::array([Json::string("A")])))
  let insert = @opgrain.Operation::parse("[{\"p\":[1],\"li\":\"B\"}]")
  ignore(journal.append(insert))
  journal.compact(1)
  let before = journal.snapshot()
  try journal.integrate(0, [insert]) catch {
    @opgrain.InvalidRevisionRange(0, 1, 1) => ()
    error => raise error
  } noraise {
    _ => fail("expired base accepted")
  }
  assert_eq(journal.head(), 1)
  assert_eq(journal.oldest_revision(), 1)
  assert_eq(journal.snapshot(), before)
}

///|
test "cycle detection keeps ancestors across the recursive-to-iterative boundary" {
  for depth in [63, 64, 65, 128] {
    let fields : Map[String, Json] = Map([])
    let root = Json::object(fields)
    let mut nested = root
    for _ in 0..<depth {
      nested = Json::array([nested])
    }
    fields["child"] = nested
    try @opgrain.Snapshot::new(Some(root)) catch {
      @opgrain.InvalidJson(_) => ()
      error => raise error
    } noraise {
      _ => fail("cross-boundary cycle accepted")
    }
    try @opgrain.stringify_json(root) catch {
      @opgrain.InvalidJson(_) => ()
      error => raise error
    } noraise {
      _ => fail("cross-boundary cycle serialized")
    }
  }
}
