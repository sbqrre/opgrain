///|
fn show_transactions() -> Unit raise {
  let engine = @opgrain.Engine::new()
  let base = @opgrain.Snapshot::new(
    Some(
      @opgrain.parse_json(
        "{\"tasks\":[\"Review\",\"Publish\"],\"ready\":false}",
      ),
    ),
  )
  let draft = engine.draft_snapshot(base)
  let delta = draft.transaction(candidate => {
    candidate.splice_items([Key("tasks")], 1, 1, [
      Json::string("Test"),
      Json::string("Release"),
    ])
    candidate.set([Key("ready")], Json::boolean(true))
  })
  let expected = @opgrain.parse_json(
    "{\"tasks\":[\"Review\",\"Test\",\"Release\"],\"ready\":true}",
  )
  guard draft.snapshot() == Some(expected) else { abort("批量编辑失败") }
  let retained = draft.snapshot_handle()
  try
    draft.transaction(candidate => {
      candidate.remove_item([Key("tasks"), Index(0)])
      candidate.remove([Key("missing")])
    })
  catch {
    @opgrain.InvalidPath(_, _) => ()
    error => raise error
  } noraise {
    _ => abort("失败事务被记录")
  }
  guard draft.snapshot() == retained.to_json() else {
    abort("失败事务改变了看板")
  }
  println("批量更新发布任务，后续失败事务完整回滚")
  println("事务操作 " + delta.stringify())
  println("事务后的看板 " + @opgrain.stringify_json(expected))
}

///|
fn show_compaction() -> Unit raise {
  let engine = @opgrain.Engine::new()
  let base = @opgrain.Snapshot::new(
    Some(@opgrain.parse_json("{\"tasks\":[{\"points\":2}]}")),
  )
  let journal = engine.journal_snapshot(base)
  let increment = @opgrain.Operation::parse(
    "[{\"p\":[\"tasks\",0,\"points\"],\"na\":0.5}]",
  )
  ignore(journal.append_all([increment, increment, increment]))
  let retained = journal.snapshot_handle_at(1)
  journal.compact(2)
  guard journal.oldest_revision() == 2 && journal.head() == 3 else {
    abort("压缩后版本编号错误")
  }
  guard retained.read([Key("tasks"), Index(0), Key("points")]) ==
    Json::number(2.5) else {
    abort("旧句柄失效")
  }
  ignore(journal.integrate(2, [increment]))
  guard journal.head() == 4 &&
    journal.snapshot() ==
    Some(@opgrain.parse_json("{\"tasks\":[{\"points\":4}]}")) else {
    abort("从保留版本合并失败")
  }
  println("压缩旧历史后从保留版本合并离线工分")
  println("最早可用版本 2，合并后版本 4")
  println("外部保存的版本 1 句柄仍可读取")
}

///|
fn show_exact_undo() -> Unit raise {
  let engine = @opgrain.Engine::new()
  let base = @opgrain.Snapshot::new(
    Some(@opgrain.parse_json("{\"tasks\":[{\"points\":1e-20}]}")),
  )
  let increment = @opgrain.Operation::parse(
    "[{\"p\":[\"tasks\",0,\"points\"],\"na\":1}]",
  )
  let edit = engine.prepare_edit(base, increment)
  let restored = engine.apply_snapshot_verified(edit.snapshot(), edit.inverse())
  guard restored.to_json() == base.to_json() else {
    abort("基于快照的撤销未恢复工分")
  }
  println("工分发生浮点舍入后用旧值精确撤销")
  println("正向操作 " + edit.operation().stringify())
  println("验证后的撤销操作 " + edit.inverse().stringify())
}
