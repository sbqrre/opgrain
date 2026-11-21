///|
fn board(size : Int32) -> Json {
  let tasks = Array::makei(size, i => {
    Json::object(
      Map([
        ("id", Json::string("task-\{i}")),
        ("title", Json::string("复核 😀 é \{i}")),
        ("points", Json::number(i.to_double())),
        (
          "labels",
          Json::array([Json::string("review"), Json::string("release")]),
        ),
      ]),
    )
  })
  Json::object(Map([("tasks", Json::array(tasks))]))
}

///|
fn measured(
  name : String,
  iterations : Int32,
  work : () -> Unit raise,
) -> Json raise {
  for _ in 0..<3 {
    work()
  }
  let samples = []
  for _ in 0..<9 {
    let clock = @bench.monotonic_clock_start()
    for _ in 0..<iterations {
      work()
    }
    samples.push(@bench.monotonic_clock_end(clock) / iterations.to_double())
  }
  samples.sort()
  Json::object(
    Map([
      ("name", Json::string(name)),
      ("iterations", Json::number(iterations.to_double())),
      ("samples", Json::number(samples.length().to_double())),
      ("unit", Json::string("us")),
      ("min", Json::number(samples[0])),
      ("median", Json::number(samples[4])),
      ("max", Json::number(samples[8])),
    ]),
  )
}

///|
fn benchmark() -> Unit raise {
  let engine = @opgrain.Engine::new()
  let small = board(100)
  let large = board(1000)
  let op = @opgrain.Operation::parse(
    "[{\"p\":[\"tasks\",50,\"points\"],\"na\":0.5}]",
  )
  let left = @opgrain.Operation::parse("[{\"p\":[\"tasks\",50],\"lm\":0}]")
  let right = @opgrain.Operation::parse(
    "[{\"p\":[\"tasks\",50,\"title\",2],\"si\":\"!\"}]",
  )
  let options = {
    ..@opgrain.DiffOptions::default(),
    list_identity_key: Some("id"),
  }
  let small_next = engine.apply(small, left)
  let large_next = engine.apply(large, left)
  let wire = @opgrain.stringify_json(large)
  let mut observed = Json::null()
  let mut operation_count = 0
  let results = [
    measured("apply-100", 50, () => observed = engine.apply(small, op)),
    measured("apply-1000", 20, () => observed = engine.apply(large, op)),
    measured("verified-1000", 20, () => {
      observed = engine.apply_verified(Some(large), op).unwrap()
    }),
    measured("journal-1000x30", 1, () => {
      let journal = engine.journal(Some(large))
      for _ in 0..<30 {
        operation_count = journal.append(op)
      }
    }),
    measured("diff-identity-100", 10, () => {
      operation_count = engine
        .diff(Some(small), Some(small_next), options~)
        .length()
    }),
    measured("diff-identity-1000", 3, () => {
      operation_count = engine
        .diff(Some(large), Some(large_next), options~)
        .length()
    }),
    measured("transform-move-title", 300, () => {
      let (a, b) = engine.transform_x(left, right)
      operation_count = a.length() + b.length()
    }),
    measured("compose", 300, () => {
      operation_count = engine.compose(op, op).length()
    }),
    measured("wire-parse-1000", 2, () => observed = @opgrain.parse_json(wire)),
    measured("wire-stringify-1000", 2, () => {
      operation_count = @opgrain.stringify_json(large).length()
    }),
  ]
  guard observed != Json::null() && operation_count > 0 else {
    abort("benchmark work was discarded")
  }
  println(@opgrain.stringify_json(Json::array(results)))
}

///|
fn main {
  benchmark() catch {
    error => abort(@debug.to_string(error))
  }
}
