
# 本地分支、待定操作与撤销

这些状态对象只保存内存中的快照与 JSON0 操作，不提供服务器、传输、持久化数据库或协作会话协议。状态对象复制子类型注册表成员，注册回调的闭包状态仍由接入方管理。回调应确定且避免不可回滚的外部副作用。

## 两条看板分支

`engine.branch_pair(snapshot, left_label~, right_label~)` 建立共享基点的两个分支。`append` / `append_all` 校验后保存每个批次的检查点；失败不保存部分结果。`rewind(side, count)` 回到该分支保留的批次数，仅改变内存状态。

`preview(text_encoding~)` 执行两侧历史的转换及收敛验证，左分支保留 JSON0 的 Left 优先级。`accept(preview)` 将共同结果变为新基点并清空两个分支的待合并历史。预览绑定对象及其代数代次；预览后任何修改、另一个对象的预览、已经接受过的预览都不能再次接受，返回 `StaleBranchPreview`。

`merge_many` 合并多条基于同一快照的历史，按给定顺序逐条集成。较早分支使用 Left；不承诺任意交换分支排列后结果相同。返回每条分支原操作、转换后贡献及前后快照。默认最多 64 条分支、1,000,000 个组件和 1,000,000 次批次交叉；转换可能拆分组件，保留输出也受组件上限约束。

## 待定操作重定位

`engine.rebase_buffer(base)` 保存尚未放入基点的本地批次。`append_all` 接收基于当前可见快照的连续操作。`preview(external)` 的外部批次必须基于 `base()`，而不是已包含待定操作的 `snapshot()`。它验证两条路径，并返回转换后的待定操作和可在原可见文档上应用的外部操作。

接受预览后，外部结果成为新的基点，待定操作重定位到它之上。`confirm_prefix(count)` 将一个已接受的待定前缀移入基点，不改变可见文档。如何确认、排序和交换这些批次由调用方处理，库不猜测外部版本。

## 带分组的撤销栈

`engine.undo_history(snapshot, capacity~)` 默认保留最多 1,000 组操作。`record(operation, label~, join_previous~)` 使用真实旧值准备逆操作；显式分组也验证实际组合结果，浮点重新结合改变结果时保留原始组件序列。`undo` / `redo` 重新准备并验证相反操作。`undo_labels` 和 `redo_labels` 按最近动作优先排列。

`apply_external` 接收已经基于当前可见快照的外部操作，逐层转换两个待执行的逆操作栈，再验证转换后整条栈是否仍可应用。不能形成有效栈时整体拒绝。外部操作、撤销、重做和清空会结束分组边界。新的本地有效操作清空重做栈；空操作不清空它。容量 0 时仍执行编辑，但不保存撤销。

数字逆操作可能使用携带前后值的替换，因此其并发裁决遵循 JSON0 替换规则，而不是加法。选择性撤销也会受自定义子类型可逆性和混合文本表示的限制。此 API 不宣称支持所有编辑意图下的通用选择性撤销。

`compose_verified(snapshot, operations)` 可以独立使用：先顺序校验输入，再验证上游式组合的实际结果。组合异常、旧值不再匹配或浮点重新结合造成差异时，返回原始顺序组件，`decision()` 为 `SequentialFallback`。该检查仅证明给定快照上的应用结果；它不是任意未来并发操作下的等价性证明。

## 可校验的历史归档

`Journal.archive()` / `archive_range(start,end)` 导出 `JournalArchive`：

```json
{
  "format": "opgrain.journal",
  "version": 1,
  "base_revision": 0,
  "base_present": false,
  "head_present": true,
  "head": {"tasks":[]},
  "operations": [[{"p":[],"oi":{"tasks":[]}}]]
}
```

存在根时必须有对应 `base` / `head` 字段；缺失根时必须省略。JSON null 是存在的根，不能用 null 代替缺失标志。未知字段、未知格式版本、非整数版本、版本溢出或伪造 head 都会拒绝。

`read_archive` 校验资源限制、回放标准 JSON0 操作并核对 head；`decode_archive` 还使用可配置 JSON 解码限制。`restore(engine)` 重新回放并恢复绝对版本号。`split(engine, revision)` 保留批次边界，生成两份可独立回放的连续归档。

这个封装是 opgrain 的本地导入导出格式。封装内的每个操作数组保持 JSON0 线格式；不能把整个封装直接当成 JSON0 操作发送。它没有签名、来源认证、存储或网络功能。
