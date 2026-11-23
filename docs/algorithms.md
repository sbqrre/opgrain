
# 从看板快照生成和解释操作

这些接口生成或执行标准 JSON0 组件。它们是上游核心代数之外的本地辅助 API；生成器的输出不承诺与某个 JavaScript 差分工具逐字相同。

## 按卡片 ID 重排

将 `[a,b,c,d]` 改成 `[b,c,d,a]`：

```moonbit
let plan = engine.diff_keyed_list(before, after, "id", path=[Key("tasks")])
let operation = plan.operation()
let updated = engine.apply_snapshot_verified(snapshot, operation)
```

这组数据生成 `{"p":["tasks",0],"lm":3}`。两侧元素都必须是对象，并具有唯一的字符串 ID；不满足条件返回 `InvalidPath`。ID 可以为空字符串，唯一性仍按字符串精确比较。

算法先按逆序删除消失的 ID，在保留 ID 的原位置序列上求最长递增子序列，再从目标列表末尾向前插入新项、移动不在子序列中的项。带子树大小的 AVL 树提供当前位置查询。父链接保存 ID，通过索引表查找，避免形成父子对象引用环。结构规划复杂度为 O((n+m) log(n+m))，空间 O(n+m)。项目内容变化仍由普通 `diff` 递归生成；其成本另计。输入复制、输出载荷复制及最终文档应用也另计，列表应用仍需要复制数组。

`ListDiff.metrics()` 报告保留、插入、删除、移动和内容变化数量。这里的保留数量是结构规划采用的递增子序列长度。只讨论唯一 ID 的结构重排时，移动数量由所保留的递增子序列决定；对象内部的编辑不计为移动。

## UTF-16 文本差分

`diff_text(before, after)` 保留共同前后缀，对中段执行 Hirschberg 对齐，使用线性行存储和显式任务栈。位置和匹配单位始终是 UTF-16 code unit，包括单独代理项。不是字素簇差分。

`TextDiffOptions` 的默认上限为 4,000,000 个比较单元格、每个输入 1,000,000 个 UTF-16 单元。对齐预算耗尽时，丢弃未完成的中段对齐，输出该中段的删除与插入；`metrics().exact_alignment` 为 false。共同前后缀继续保留。比较次数不会超过预算，但输入扫描、输出构造、字符串复制仍需要时间。

`diff_text_lines` 先对保留换行符的整行对齐，再细化变化区域。CR、LF 和 CRLF 的原始拼写保留。整行矩阵有单独的 `alignment_cells` 上限，区域细化共享 `text_cells`。对局部短变化，整行分割可能比直接 UTF-16 差分更慢，见基准。

返回的 `TextOperation` 提供 `apply`、`compose`、`invert`、`normalize`、`transform_pair`、单侧 `transform` 和位置转换。`as_json0(Path, encoding~)` 将独立 text0 操作放回文档路径；默认显式 `text0`，可选旧文本表示。仍需遵守兼容性文档中关于混合文本表示的限制。

`TextIndex` 明确转换 UTF-16、Unicode 码点和 UTF-8 字节边界。拆开代理对或 UTF-8 序列的偏移会报错；遇到单独代理项也报错，因为它不能被表示为合法 Unicode 标量的 UTF-8 序列。这不限制核心 JSON0 操作对原始 UTF-16 单元的支持。行号、列号均从 0 开始，列使用 UTF-16 单元。CRLF 中间偏移归入前一行，下一行起点不能用前一行的列号别名表示。`source_position` 是面向 JSON 错误诊断的另一接口，行列从 1 开始。

## 显式栈快照差分与比较

`engine.diff_snapshots(before, after)` 接收不透明的 `Snapshot`，返回 `SnapshotDiff`。对象键按排序顺序处理；普通数组保留相同前后缀，在中段按位置配对，再处理多余插入和删除。它避免分配整个列表的二次对齐矩阵，但不推断卡片 ID，不保证最短编辑序列。需要 ID 移动时使用 `diff_keyed_list`。

文本区域共享对齐预算；可选择精确可逆的数字增量。默认最多访问 1,000,000 个待比较位置、生成 100,000 个组件、进入 1,024 层路径。超过限制报错，不返回部分操作。生成完成后，实际验证每个旧值并检查目标快照一致。

`Snapshot.equivalent` 用显式栈比较完整的已校验快照，区分缺失根和 JSON null。`compare` 返回按路径排序的叶级差异、前后值和类型变化；访问、差异数或深度超限时返回 `ComparisonBudget`，不会把未完成的比较标成相等。导出的差异值是副本。`Operation.wire_equivalent` 忽略 JSON 对象键排列顺序，但保留组件顺序和载荷表示差异。

## 观察一次更新

`trace_apply`、`trace_batches` 返回组件边界上的持久快照。`ChangeRecord` 保存批次下标、组件下标、源路径和目标路径；列表插入没有旧值，删除没有新值，移动的新路径使用目标下标。旧文本组件的值路径指向整个字符串。

`preview_merge` 真正执行两边的原始操作和两条转换路径，拒绝不收敛或无法应用的结果。`Operation.interactions` 只是保守的静态候选关系：后续组件可能已使用移动后的路径，不应把它当成完整冲突判断。`write_roots` 将列表坐标变化扩展到其容器；它不是权限或完整依赖分析。

`Snapshot.project(patterns)` 查询可见路径，`update_projection` 比较更新前后同一路径的值。列表移动可能在多个路径产生变化；它不按应用 ID 合并变化。`edit_selection` 在原快照上读取副本、生成携带旧值的替换并准备撤销。父子重叠匹配在回调执行前拒绝。

`Snapshot.track` 或 `apply_tracked_snapshot` 可跟随节点、光标和文本范围，`advance_tracking` 在持久快照上继续跟踪。`LocationLoss` 保留首次丢失的批次、组件和原因。新增的锚点从当前快照开始。`project_text` 从一组 JSON0 组件中提取某个标题的独立文本操作，跟随列表移动；节点替换、删除和不透明子类型会明确拒绝。提取结果用于观察，不替代原历史。

完整类型与签名以根目录 `pkg.generated.mbti` 为准。
