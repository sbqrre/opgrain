///|
fn board(size : Int32) -> Json {
  Json::object(
    Map([
      (
        "tasks",
        Json::array(
          Array::makei(size, index => {
            Json::object(
              Map([
                ("id", Json::string("task-\{index}")),
                ("title", Json::string("复核 😀 é \{index}")),
                ("points", Json::number(index.to_double())),
                (
                  "labels",
                  Json::array([Json::string("review"), Json::string("release")]),
                ),
              ]),
            )
          }),
        ),
      ),
    ]),
  )
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
      ("samples", Json::number(9)),
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
  let snapshot = @opgrain.Snapshot::new(Some(board(1000)))
  let larger = @opgrain.Snapshot::new(Some(board(10000)))
  let op = @opgrain.Operation::parse(
    "[{\"p\":[\"tasks\",50,\"points\"],\"na\":0.5}]",
  )
  let mut observed = snapshot
  let mut revision = 0
  let results = [
    measured("snapshot-verified-1000", 200, () => {
      observed = engine.apply_snapshot_verified(snapshot, op)
    }),
    measured("snapshot-verified-10000", 100, () => {
      observed = engine.apply_snapshot_verified(larger, op)
    }),
    measured("journal-handle-1000x100", 5, () => {
      let journal = engine.journal_snapshot(snapshot)
      for _ in 0..<100 {
        revision = journal.append(op)
      }
    }),
    measured("compact-1000x100", 5, () => {
      let journal = engine.journal_snapshot(snapshot)
      for _ in 0..<100 {
        revision = journal.append(op)
      }
      journal.compact(80)
      revision = journal.oldest_revision()
    }),
    measured("exact-undo-1000", 50, () => {
      observed = engine.prepare_edit(snapshot, op).snapshot()
    }),
  ]
  guard observed.read([Key("tasks"), Index(50), Key("points")]) ==
    Json::number(50.5) &&
    revision > 0 else {
    abort("benchmark result mismatch")
  }
  println(@opgrain.stringify_json(Json::array(results)))
}

///|
fn main {
  benchmark() catch {
    error => abort(@debug.to_string(error))
  }
}
