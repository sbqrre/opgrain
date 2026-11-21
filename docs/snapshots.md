# 在看板版本之间保留快照

`Snapshot::new(Some(board))` 检查有限数值和循环引用，并复制外部输入。`None` 表示缺失的根。`read(path)` 返回独立 JSON 副本，`to_json()` 导出整份文档。`subtree(path)` 为一个已存在的子树建立不透明快照句柄。

```moonbit
let engine = @opgrain.Engine::new()
let initial = @opgrain.Snapshot::new(
  Some(@opgrain.parse_json("{\"tasks\":[{\"points\":2}]}")),
)
let operation = @opgrain.Operation::parse(
  "[{\"p\":[\"tasks\",0,\"points\"],\"na\":0.5}]",
)
let next = engine.apply_snapshot_verified(initial, operation)
println(@opgrain.stringify_json(initial.read([Key("tasks"), Index(0)])))
println(@opgrain.stringify_json(next.read([Key("tasks"), Index(0)])))
```

两个输出的工分分别为 2 和 2.5。更新时复制发生编辑的容器及其祖先，未修改的分支继续共享。句柄只通过返回副本的接口暴露可变 JSON，调用方无法改写历史中的容器。JSON0 中的列表用数组表示，复制一个有 n 项的列表仍需 O(n) 时间。路径更新成本取决于沿路各容器的大小，不能仅按路径深度计算。

`apply_snapshot` 使用基础 JSON0 应用语义。`apply_snapshot_verified` 同时校验对象和列表的删除旧值。`apply_snapshot_batches` 顺序校验多个批次，失败带有批次和组件下标。失败后已有快照仍可读取。普通 `apply`、`apply_optional` 与 `apply_verified` 继续接收 JSON，适用于需要一次性导出结果的调用方。

## 草稿事务

`engine.draft_snapshot(initial)` 从句柄开始编辑。每次编辑使用草稿当前的坐标。`snapshot_handle()` 可保存中间状态。`transaction` 接收一个独立候选草稿，回调成功后一次记录其操作，失败时整个候选分支不生效。

```moonbit
let draft = engine.draft_snapshot(initial)
let delta = draft.transaction(candidate => {
  candidate.add_number([Key("tasks"), Index(0), Key("points")], 0.5)
  candidate.set([Key("ready")], Json::boolean(true))
})
```

`splice_items(path, position, delete_count, values)` 原子地替换一段列表，记录实际被删除的值。`edit_subtype(path, name, payload)` 使用注册的子类型。事务回调中捕获原草稿并重入写入时返回 `DraftBusy`。这项检查保护同步回调的状态一致性。自定义回调造成的外部副作用由接入方管理。

## 检查点与压缩

`engine.journal_snapshot(initial)` 以句柄建立历史。`snapshot_handle_at(revision)` 读取指定版本的句柄，`snapshot_at(revision)` 读取完整 JSON 副本。每个历史版本按修改路径保留检查点，`merge_snapshot_histories` 可直接从共享的起点句柄转换两条分支。

`compact(through)` 将一个已存在的版本设置为新的最早可用版本，释放此前的历史记录。绝对版本号继续递增，调用方用 `oldest_revision()` 获取保留范围。以已压缩版本作为基点的 `integrate`、读版本、取操作与撤销会返回 `InvalidRevisionRange`。外部已保存的快照句柄继续有效，仍被这些句柄引用的容器也继续占用内存。压缩到当前 head 之后，下一次追加继续使用 head + 1。

草稿和历史在事务内拒绝回调重入写入。历史返回 `HistoryBusy`，版本溢出返回 `RevisionOverflow`。失败会解除重入检查状态，随后可重新操作。`Engine::fork()` 复制子类型注册表，便于为不同文档建立独立注册环境。回调函数引用仍保留其原来的闭包状态。

## 基于实际结果准备撤销

标准 `invert` 将数字增量取负。对于初值 1e-20 和增量 1，正向计算得到 1，再减 1 得到 0。调用 `engine.prepare_edit(initial, operation)` 可以在当前快照上执行操作，保留正向操作，构造逆操作并验证恢复结果。

`UndoableEdit` 提供 `operation()`、`inverse()` 和结果 `snapshot()`。当数字取负无法恢复原值时，逆操作在相应位置使用携带前后值的 JSON0 对象或列表替换。调用方应把这种撤销视为值替换，并使用 JSON0 的替换冲突规则。正向操作本身继续保留原先的 `na`。

无法应用的正向操作返回 `ForwardRejected`。子类型不提供可用的逆操作，或其逆操作无法恢复输入时，返回 `InverseRejected`、`UndoRejected` 或 `UndoDidNotRestore`。`prepare_edit` 会额外执行逆操作以验证结果，自定义子类型回调应具有确定性，并避免不可回滚的外部副作用。

## 深层 JSON 与线格式

JSON 复制、校验和序列化在前 64 层使用有界递归，超过后切换到显式工作栈。路径重建和线格式字符串恢复使用显式工作栈。回归覆盖通过 JSON API 构造的 4,000 层嵌套值及其编辑。当前核心 JSON 解析器采用默认 1,024 层嵌套限制，超限输入转换为 `InvalidJson`。差量递归、JSON 值比较和转换算法仍有递归路径，深层复制测试只验证所标明的接口。所有接口仍受可用内存及 Int32 下标范围约束。
