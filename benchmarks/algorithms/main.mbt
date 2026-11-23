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
  {
    "name": name,
    "iterations": iterations,
    "samples": 9,
    "unit": "us",
    "min": samples[0],
    "median": samples[4],
    "max": samples[8],
  }
}

///|
fn cards(count : Int32) -> Array[Json] {
  Array::makei(count, index => {
    "id": "task-" + index.to_string(),
    "title": "复核😀é",
    "points": index,
  })
}

///|
fn run_benchmarks() -> Unit raise {
  let engine = @opgrain.Engine::new()
  let before = cards(1000)
  let after = before[1:].to_owned()
  after.push(before[0])
  let options = {
    ..@opgrain.DiffOptions::default(),
    list_identity_key: Some("id"),
  }
  let original = engine.diff(
    Some(Json::array(before)),
    Some(Json::array(after)),
    options~,
  )
  let indexed = engine.diff_keyed_list(before, after, "id")
  guard engine.apply(Json::array(before), original) == Json::array(after) &&
    engine.apply(Json::array(before), indexed.operation()) == Json::array(after) &&
    indexed.metrics().moved == 1 else {
    abort("list benchmark semantic mismatch")
  }
  let source = "Review 😀 é — 复核任务\n".repeat(200)
  let target = "Review 😀 é — 复核任务\n".repeat(100) +
    "Approve 😀 é — 发布任务\n" +
    "Review 😀 é — 复核任务\n".repeat(99)
  let snapshot = @opgrain.Snapshot::new(
    Some({ "title": source, "tasks": Json::array(before) }),
  )
  let changed = @opgrain.Operation::parse(
    "[{\"p\":[\"tasks\",10,\"points\"],\"na\":0.5}]",
  )
  let anchors = Array::makei(100, index => {
    @opgrain.Location::Node([Key("tasks"), Index(index)])
  })
  let mut operation = @opgrain.Operation::empty()
  let mut text_operation = @opgrain.TextOperation::empty()
  let mut observed = snapshot
  let results = [
    measured("keyed-diff-sequential-rotate-1000", 1, () => {
      operation = engine.diff(
        Some(Json::array(before)),
        Some(Json::array(after)),
        options~,
      )
    }),
    measured("keyed-diff-indexed-rotate-1000", 5, () => {
      operation = engine.diff_keyed_list(before, after, "id").operation()
    }),
    measured("text-unit-diff-200-lines", 20, () => {
      text_operation = @opgrain.diff_text(source, target).operation()
    }),
    measured("text-line-diff-200-lines", 20, () => {
      text_operation = @opgrain.diff_text_lines(source, target).operation()
    }),
    measured("tracking-detached-1000-tasks-100-anchors", 10, () => {
      ignore(engine.apply_tracked(snapshot.to_json(), changed, anchors))
    }),
    measured("tracking-persistent-1000-tasks-100-anchors", 50, () => {
      observed = engine
        .apply_tracked_snapshot(snapshot, changed, anchors)
        .snapshot()
    }),
    measured("bounded-codec-1000-tasks", 5, () => {
      ignore(
        @opgrain.decode_json(@opgrain.encode_json(snapshot.to_json().unwrap())),
      )
    }),
  ]
  guard operation.length() > 0 &&
    text_operation.apply(source) == target &&
    observed.read([Key("tasks"), Index(10), Key("points")]) == 10.5 else {
    abort("benchmark result mismatch")
  }
  println(@opgrain.stringify_json(Json::array(results)))
}

///|
fn main {
  run_benchmarks() catch {
    error => abort(@debug.to_string(error))
  }
}
