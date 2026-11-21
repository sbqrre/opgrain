///|
extern "js" fn read_input() -> String =
  #| () => process.getBuiltinModule("node:fs").readFileSync(0, "utf8")

///|
fn required(
  fields : Map[String, Json],
  key : String,
) -> Json raise @opgrain.OpError {
  guard fields.get(key) is Some(value) else {
    raise @opgrain.InvalidJson("missing request field: " + key)
  }
  value
}

///|
fn side_of(value : Json) -> @opgrain.Side raise @opgrain.OpError {
  match value {
    String("left") => Left
    String("right") => Right
    _ => raise @opgrain.InvalidJson("invalid transform side")
  }
}

///|
fn operation(
  fields : Map[String, Json],
  key : String,
) -> @opgrain.Operation raise @opgrain.OpError {
  @opgrain.Operation::from_json(required(fields, key))
}

///|
fn evaluate(engine : @opgrain.Engine, request : Json) -> Json? raise {
  guard request is Object(fields) &&
    fields.get("command") is Some(String(command)) else {
    raise @opgrain.InvalidJson("expected a request with a command")
  }
  match command {
    "apply" =>
      engine.apply_optional(fields.get("snapshot"), operation(fields, "op"))
    "applySnapshot" =>
      engine
      .apply_snapshot(
        @opgrain.Snapshot::new(fields.get("snapshot")),
        operation(fields, "op"),
      )
      .to_json()
    "applySnapshotVerified" =>
      engine
      .apply_snapshot_verified(
        @opgrain.Snapshot::new(fields.get("snapshot")),
        operation(fields, "op"),
      )
      .to_json()
    "mergeHistories" => {
      fn operations(
        key : String,
      ) -> Array[@opgrain.Operation] raise @opgrain.OpError {
        guard required(fields, key) is Array(items) else {
          raise @opgrain.InvalidJson("expected operation batches")
        }
        items.map(item => @opgrain.Operation::from_json(item))
      }
      let merged = engine.merge_histories(
        fields.get("snapshot"),
        operations("left"),
        operations("right"),
      )
      Some(
        Json::object(
          Map([
            ("snapshot", merged.snapshot().unwrap()),
            (
              "left",
              Json::array(
                merged.histories().left_after_right().map(op => op.to_json()),
              ),
            ),
            (
              "right",
              Json::array(
                merged.histories().right_after_left().map(op => op.to_json()),
              ),
            ),
          ]),
        ),
      )
    }
    "diff" => {
      let list_identity_key = match fields.get("listIdentityKey") {
        Some(String(key)) => Some(key)
        _ => None
      }
      let options = { ..@opgrain.DiffOptions::default(), list_identity_key, }
      Some(
        engine
        .diff(fields.get("snapshot"), fields.get("other"), options~)
        .to_json(),
      )
    }
    "compose" =>
      Some(
        engine
        .compose(operation(fields, "op"), operation(fields, "other"))
        .to_json(),
      )
    "invert" => Some(engine.invert(operation(fields, "op")).to_json())
    "normalize" => Some(engine.normalize(required(fields, "op")).to_json())
    "transform" =>
      Some(
        engine
        .transform(
          operation(fields, "op"),
          operation(fields, "other"),
          side_of(required(fields, "side")),
        )
        .to_json(),
      )
    "transformX" => {
      let (left, right) = engine.transform_x(
        operation(fields, "op"),
        operation(fields, "other"),
      )
      Some(Json::array([left.to_json(), right.to_json()]))
    }
    _ => raise @opgrain.InvalidJson("unknown request command")
  }
}

///|
fn run_batch() -> Unit raise @opgrain.OpError {
  guard @opgrain.parse_json(read_input()) is Array(requests) else {
    raise @opgrain.InvalidJson("expected an array of requests")
  }
  let engine = @opgrain.Engine::new()
  let results = requests.map(request => {
    try evaluate(engine, request) catch {
      error =>
        Json::object(Map([("error", Json::string(@debug.to_string(error)))]))
    } noraise {
      Some(value) =>
        Json::object(Map([("present", Json::boolean(true)), ("value", value)]))
      None => Json::object(Map([("present", Json::boolean(false))]))
    }
  })
  println(@opgrain.stringify_json(Json::array(results)))
}

///|
fn main {
  run_batch() catch {
    error => abort(@debug.to_string(error))
  }
}
