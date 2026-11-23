///|
fn show_indexed_reorder() -> Unit raise {
  let engine = @opgrain.Engine::new()
  let before : Array[Json] = [
    { "id": "design", "points": 1 },
    { "id": "review", "points": 2 },
    { "id": "verify", "points": 3 },
    { "id": "publish", "points": 4 },
  ]
  let after = [before[1], before[2], before[3], before[0]]
  let plan = engine.diff_keyed_list(before, after, "id", path=[Key("tasks")])
  let document = @opgrain.Snapshot::new(Some({ "tasks": Json::array(before) }))
  let updated = engine.apply_snapshot_verified(document, plan.operation())
  guard plan.metrics().moved == 1 &&
    updated.read([Key("tasks")]) == Json::array(after) else {
    abort("索引重排结果错误")
  }
  println("四张任务卡片轮转，仅生成一次 JSON0 列表移动")
  println(plan.operation().stringify())
}

///|
fn show_branch_review() -> Unit raise {
  let engine = @opgrain.Engine::new()
  let snapshot = @opgrain.Snapshot::new(
    Some({ "tasks": [{ "id": "review", "title": "Review😀", "points": 1 }] }),
  )
  let pair = engine.branch_pair(
    snapshot,
    left_label="estimate",
    right_label="title",
  )
  let estimate = @opgrain.Operation::parse(
    "[{\"p\":[\"tasks\",0,\"points\"],\"na\":2}]",
  )
  let title = @opgrain.Operation::parse(
    "[{\"p\":[\"tasks\",0,\"title\",6],\"si\":\"!\"}]",
  )
  ignore(pair.append(Left, estimate))
  ignore(pair.append(Right, title))
  let preview = pair.preview()
  let merged = pair.accept(preview)
  guard merged.read([Key("tasks"), Index(0), Key("title")]) == "Review!😀" else {
    abort("分支合并标题错误")
  }
  let buffer = engine.rebase_buffer(snapshot)
  ignore(buffer.append(estimate))
  ignore(buffer.accept(buffer.preview([title])))
  guard buffer.snapshot().equivalent(merged) else {
    abort("待定操作重定位错误")
  }
  println("工分与标题在两个本地分支独立修改，预览后合并")
  println(
    @opgrain.encode_json(merged.to_json().unwrap(), options={
      ..@opgrain.EncodeOptions::default(),
      escape_non_ascii: false,
    }),
  )
}

///|
fn show_guarded_batch() -> Unit raise {
  let engine = @opgrain.Engine::new()
  let snapshot = @opgrain.Snapshot::new(
    Some({
      "tasks": [
        { "id": "review", "points": 1 },
        { "id": "publish", "points": 2 },
      ],
    }),
  )
  let selected = snapshot.select([
    ExactKey("tasks"),
    AnyIndex,
    ExactKey("points"),
  ])
  let prepared = engine.edit_selection(selected, (_, value) => {
    match value {
      Number(points, ..) => Json::number(points + 0.5)
      _ => raise @opgrain.InvalidJson("工分必须为数字")
    }
  })
  let path = @opgrain.Path::new([Key("tasks")])
  let checked = engine.apply_when(
    snapshot,
    prepared.operation(),
    [UniqueListKey(path, "id")],
    after=[LengthRange(path, 2, 2)],
  )
  let packed = prepared
    .operation()
    .pack(limits={ ..@opgrain.PackingLimits::default(), max_components: 1, })
  let checkpoints = engine.replay_packed(snapshot, packed)
  guard checkpoints.last().unwrap().equivalent(checked) else {
    abort("分批执行结果错误")
  }
  let journal = engine.journal_snapshot(snapshot)
  ignore(journal.append_all(packed.operations()))
  let archive = engine.decode_archive(journal.archive().encode())
  guard archive.head().equivalent(checked) else {
    abort("归档回放结果错误")
  }
  println(
    "批量调整两张卡片工分，检查唯一 ID，分批执行并校验归档",
  )
  println(@opgrain.stringify_json(archive.head().to_json().unwrap()))
}

///|
fn show_rebased_undo() -> Unit raise {
  let engine = @opgrain.Engine::new()
  let history = engine.undo_history(
    @opgrain.Snapshot::new(Some({ "points": 1 })),
  )
  let estimate = @opgrain.Operation::parse("[{\"p\":[\"points\"],\"na\":2}]")
  let adjustment = @opgrain.Operation::parse(
    "[{\"p\":[\"points\"],\"na\":0.5}]",
  )
  ignore(history.record(estimate, label="工分估算"))
  ignore(history.apply_external(adjustment))
  let undone = history.undo()
  guard undone.read([Key("points")]) == 1.5 else {
    abort("选择性撤销结果错误")
  }
  println(
    "撤销本地工分估算，保留另一份操作的 0.5 工分调整",
  )
  println(@opgrain.stringify_json(undone.to_json().unwrap()))
}
