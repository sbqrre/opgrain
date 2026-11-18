///|
fn add_payload(snapshot : Json, payload : Json) -> Json raise @opgrain.OpError {
  guard snapshot is Number(value, ..) &&
    payload is Object(fields) &&
    fields.get("delta") is Some(Number(delta, ..)) else {
    raise @opgrain.InvalidComponent(0, "expected an additive payload")
  }
  Json::number(value + delta)
}

///|
fn payload_delta(payload : Json) -> Double raise @opgrain.OpError {
  guard add_payload(Json::number(0.0), payload) is Number(delta, ..) else {
    raise @opgrain.InvalidComponent(0, "expected a number")
  }
  delta
}

///|
fn delta_payload(delta : Double) -> Json {
  Json::object(Map([("delta", Json::number(delta))]))
}

///|
test "registered non-array subtype delegates all four operations" {
  let engine = @opgrain.Engine::new()
  engine.register_subtype("delta", {
    apply: add_payload,
    compose: (first, second) => {
      delta_payload(payload_delta(first) + payload_delta(second))
    },
    invert: payload => delta_payload(-payload_delta(payload)),
    transform: (payload, _, _) => payload,
  })
  let a = @opgrain.Operation::parse(
    "[{\"p\":[],\"t\":\"delta\",\"o\":{\"delta\":2}}]",
  )
  let b = @opgrain.Operation::parse(
    "[{\"p\":[],\"t\":\"delta\",\"o\":{\"delta\":3}}]",
  )
  let original = Json::number(1.0)
  let combined = engine.compose(a, b)
  let updated = engine.apply(original, combined)
  assert_eq(updated, Json::number(6.0))
  assert_eq(engine.apply(updated, engine.invert(combined)), original)
  let (left, right) = engine.transform_x(a, b)
  assert_eq(engine.apply(engine.apply(original, b), left), updated)
  assert_eq(engine.apply(engine.apply(original, a), right), updated)
  try @opgrain.apply(original, a) catch {
    @opgrain.UnknownSubtype("delta") => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("a fresh engine should have its own registry")
  }
}

///|
test "mixed legacy and explicit text preserve the upstream boundary" {
  let base = Json::string("x")
  let legacy = @opgrain.Operation::parse("[{\"p\":[0],\"si\":\"L\"}]")
  let explicit = @opgrain.Operation::parse(
    "[{\"p\":[],\"t\":\"text0\",\"o\":[{\"p\":0,\"i\":\"R\"}]}]",
  )
  let (left, right) = @opgrain.transform_x(legacy, explicit)
  assert_eq(
    @opgrain.apply(@opgrain.apply(base, legacy), right),
    Json::string("RLx"),
  )
  assert_eq(
    @opgrain.apply(@opgrain.apply(base, explicit), left),
    Json::string("LRx"),
  )
}

///|
test "binary64 rounding matches upstream even when a property premise fails" {
  let base = @opgrain.parse_json("10000000000000000")
  let a = @opgrain.Operation::parse("[{\"p\":[],\"na\":-10000000000000000}]")
  let b = @opgrain.Operation::parse("[{\"p\":[],\"na\":1}]")
  assert_eq(@opgrain.apply(@opgrain.apply(base, a), b), Json::number(1.0))
  assert_eq(@opgrain.apply(base, @opgrain.compose(a, b)), Json::number(0.0))
  assert_eq(
    @opgrain.parse_json("9007199254740993"),
    Json::number(9007199254740992.0),
  )
  let overflowing = @opgrain.Operation::parse("[{\"p\":[],\"na\":1e308}]")
  try @opgrain.apply(@opgrain.parse_json("1e308"), overflowing) catch {
    @opgrain.NonFiniteNumber => ()
    _ => fail("unexpected overflow error")
  } noraise {
    _ => fail("a non-finite result cannot be exchanged")
  }
}

///|
test "incremental results and operation payloads are detached" {
  let operation = @opgrain.Operation::parse(
    "[{\"p\":[0],\"li\":[1]},{\"p\":[0,0],\"na\":2}]",
  )
  let inputs = operation.to_json()
  if inputs is Array(components) &&
    components[0] is Object(fields) &&
    fields.get("li") is Some(Array(items)) {
    items[0] = Json::number(99.0)
  }
  let snapshots : Array[Json?] = []
  let result = @opgrain.Engine::new().incremental_apply(
    Some(Json::array([])),
    operation,
    (_, doc) => snapshots.push(doc),
  )
  assert_eq(snapshots[0], Some(@opgrain.parse_json("[[1]]")))
  assert_eq(result, Some(@opgrain.parse_json("[[3]]")))
}
