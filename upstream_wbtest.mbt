///|
fn fixture_array(value : Json) -> Array[Json] raise OpError {
  guard value is Array(items) else {
    raise InvalidJson("fixture array expected")
  }
  items
}

///|
fn fixture_string(value : Json) -> String raise OpError {
  guard value is String(s) else { raise InvalidJson("fixture string expected") }
  s
}

///|
fn fixture_side(side : Json) -> Side {
  if side is String("right") {
    Right
  } else {
    Left
  }
}

///|
fn fixture_value(value : Json?, default_value : Json) -> Json {
  value.unwrap_or(default_value)
}

///|
fn fixture_json0(
  engine : Engine,
  command : String,
  args : Array[Json],
) -> Json raise OpError {
  match command {
    "create" => create(data=fixture_value(args.get(0), Json::null()))
    "apply" => engine.apply(args[0], Operation::from_json(args[1]))
    "compose" =>
      engine
      .compose(Operation::from_json(args[0]), Operation::from_json(args[1]))
      .to_json()
    "invert" => engine.invert(Operation::from_json(args[0])).to_json()
    "normalize" => engine.normalize(args[0]).to_json()
    "transform" =>
      engine
      .transform(
        Operation::from_json(args[0]),
        Operation::from_json(args[1]),
        fixture_side(args[2]),
      )
      .to_json()
    "transformX" => {
      let (left, right) = engine.transform_x(
        Operation::from_json(args[0]),
        Operation::from_json(args[1]),
      )
      Json::array([left.to_json(), right.to_json()])
    }
    _ => raise InvalidJson("unknown fixture command")
  }
}

///|
fn fixture_text0(command : String, args : Array[Json]) -> Json raise OpError {
  match command {
    "apply" => {
      let mut text = fixture_string(args[0])
      for edit in decode_text0(args[1]) {
        text = edit_string(text, edit, [])
      }
      Json::string(text)
    }
    "compose" =>
      encode_text0(compose_text0(decode_text0(args[0]), decode_text0(args[1])))
    "invert" => {
      let edits = decode_text0(args[0])
      edits.rev_in_place()
      encode_text0(edits.map(edit => { ..edit, insert: !edit.insert, }))
    }
    "normalize" => text0_normalize(args[0])
    "transform" =>
      encode_text0(
        transform_side(
          decode_text0(args[0]),
          decode_text0(args[1]),
          fixture_side(args[2]),
          transform_text0,
          (dest, c) => append_text0(dest, c),
        ),
      )
    "transformX" => {
      let (left, right) = transform_pair(
        decode_text0(args[0]),
        decode_text0(args[1]),
        transform_text0,
        (dest, c) => append_text0(dest, c),
      )
      Json::array([encode_text0(left), encode_text0(right)])
    }
    "transformCursor" =>
      Json::number(
        text0_transform_cursor(
          nonnegative_index(args[0], 0),
          args[1],
          side=fixture_side(fixture_value(args.get(2), Json::null())),
        ).to_double(),
      )
    _ => raise InvalidJson("unknown fixture text command")
  }
}

///|
fn fixture_check(actual : Json, expected : Json, label : String) -> Unit raise {
  if actual != expected {
    let received = stringify_json(actual)
    let wanted = stringify_json(expected)
    fail("\{label}: expected \{wanted}, received \{received}")
  }
}

///|
test "all fixed upstream JSON0 and text0 cases" {
  let engine = Engine::new()
  engine.register_subtype("mock", {
    apply: (doc, _) => doc,
    compose: (op, _) => op,
    invert: op => op,
    transform: (_, _, _) => parse_json("{\"mock\":true}"),
  })
  for row in fixture_array(parse_json(upstream_fixed)) {
    let record = fixture_array(row)
    let family = fixture_string(record[0])
    let title = fixture_string(record[1])
    let command = fixture_string(record[2])
    let args = fixture_array(record[3])
    let expect_invalid = record.get(5) is Some(String("InvalidComponent"))
    let output = try {
      if family == "text0" {
        fixture_text0(command, args)
      } else {
        fixture_json0(engine, command, args)
      }
    } catch {
      InvalidComponent(_, _) if expect_invalid => continue
      error =>
        fail(
          "\{title} \{command} \{fixture_array(row)[3].stringify()}: \{@debug.to_string(error)}",
        )
    }
    if expect_invalid {
      fail("\{title}: expected InvalidComponent")
    }
    fixture_check(output, record[4], title)
  }
}

///|
fn seeded_case(engine : Engine, record : Array[Json]) -> Unit raise {
  let family = fixture_string(record[0])
  let label = "\{family} case \{record[1].stringify()}"
  let base = record[2]
  let left = record[3]
  let right = record[4]
  let second = record[5]
  let third = record[6]
  let call = (command, args) => {
    if family == "text0" {
      fixture_text0(command, args)
    } else {
      fixture_json0(engine, command, args)
    }
  }
  let apply = (snapshot, op) => call("apply", [snapshot, op])
  let compose = (a, b) => call("compose", [a, b])
  let left_doc = apply(base, left)
  let right_doc = apply(base, right)
  fixture_check(left_doc, record[7], label + " apply left")
  fixture_check(right_doc, record[8], label + " apply right")
  let inverse = call("invert", [left])
  fixture_check(inverse, record[16], label + " inverse wire")
  fixture_check(apply(left_doc, inverse), base, label + " inverse effect")
  let combined = compose(left, second)
  fixture_check(combined, record[17], label + " compose wire")
  fixture_check(apply(base, combined), record[9], label + " compose effect")
  fixture_check(
    apply(left_doc, second),
    record[9],
    label + " sequential effect",
  )
  let l_assoc = apply(base, compose(combined, third))
  let r_assoc = apply(base, compose(left, compose(second, third)))
  fixture_check(l_assoc, record[10], label + " left association")
  fixture_check(r_assoc, record[10], label + " right association")
  let pair = fixture_array(call("transformX", [left, right]))
  fixture_check(pair[0], record[12], label + " paired left wire")
  fixture_check(pair[1], record[13], label + " paired right wire")
  fixture_check(
    call("transform", [left, right, Json::string("left")]),
    record[14],
    label + " left wire",
  )
  fixture_check(
    call("transform", [right, left, Json::string("right")]),
    record[15],
    label + " right wire",
  )
  let lr = apply(left_doc, pair[1])
  let rl = apply(right_doc, pair[0])
  fixture_check(lr, record[11], label + " converges after left")
  fixture_check(rl, record[11], label + " converges after right")
  fixture_check(
    apply(lr, call("invert", [pair[1]])),
    left_doc,
    label + " undo transformed operation",
  )
  let right_history = [right, record[18]]
  let left_history = []
  for original in [left, second, third] {
    let mut pending = original
    for i in 0..<right_history.length() {
      let prior = right_history[i]
      right_history[i] = call("transform", [
        prior,
        pending,
        Json::string("right"),
      ])
      pending = call("transform", [pending, prior, Json::string("left")])
    }
    left_history.push(pending)
  }
  let mut history_left = record[10]
  for edit in right_history {
    history_left = apply(history_left, edit)
  }
  let mut history_right = record[19]
  for edit in left_history {
    history_right = apply(history_right, edit)
  }
  fixture_check(history_left, record[20], label + " left history")
  fixture_check(history_right, record[20], label + " right history")
  right_history.rev_in_place()
  for edit in right_history {
    history_left = apply(history_left, call("invert", [edit]))
  }
  fixture_check(history_left, record[10], label + " undo transformed history")
  if family != "text0" {
    let mut fragmented = base
    for part in Operation::from_json(left).shatter() {
      fragmented = engine.apply(fragmented, part)
    }
    fixture_check(fragmented, left_doc, label + " shatter")
  }
}

///|
test "seeded differential and OT properties" {
  let engine = Engine::new()
  for row in fixture_array(parse_json(upstream_properties)) {
    seeded_case(engine, fixture_array(row))
  }
}
