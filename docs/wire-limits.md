
# JSON 线格式、路径与执行预算

## 类型化指令

`Component::new(path, Instruction)` 与 `Component::from_json` 使用相同的路径和载荷校验。`ObjectReplace(before,after)` 和 `ListReplace(before,after)` 明确先旧后新，线格式仍输出 `od/oi` 或 `ld/li`。`instruction()` 导出载荷副本；`Operation::single`、`concat` 和 `slice` 保留顺序组件。

`with_prefix` / `without_prefix` 修改路径并重新校验组件形状。根对象编辑不能直接放到以列表下标结束的前缀下；列表编辑或旧文本组件移除其最后下标也不能形成合法的根操作。前者返回错误，后者返回 None。需要编辑列表项时应使用相应 List 指令。

`Path` 保留对象键和数组下标的类型区别。`Snapshot.resolve_pointer` 按实际容器解释 JSON Pointer 的 token，支持 `~0`、`~1`，不把 `"0"` 一律当数组下标。列表下标必须为规范的非负 Int32。默认只解析现有位置；启用 `allow_missing_leaf` 时，最后一个对象键可以不存在，最后的列表下标可等于列表长度，末尾 `-` 也会解析为该长度。中间路径仍必须存在。解析只返回路径，不会执行插入。`to_pointer` 的文本自身无法保留键/下标类型，回读时仍需文档。这些读取辅助接口不把库改成 JSON Patch 引擎。

## 有界 JSON 解码

`decode_json(source, options~)` 使用显式容器栈和严格 JSON 语法。默认接受重复对象键的最后一个值，可设置 `reject_duplicate_keys` 拒绝。字符串保留所有 UTF-16 单元；数字使用有限 binary64，不接受 NaN、Infinity 或转换后溢出的数值。下溢和无法精确表示的小数按实际浮点转换处理，不承诺保留输入数字的十进制拼写。

| DecodeOptions | 默认值 | 含义 |
| --- | ---: | --- |
| max_depth | 1,024 | 同时打开的容器层数 |
| max_values | 1,000,000 | JSON 值数量，容器也计入 |
| max_string_units | 16,777,216 | 每个键或字符串的 UTF-16 单元 |
| max_input_units | 67,108,864 | 整段输入的 UTF-16 单元 |

`JsonSyntax`、`JsonLimit`、`DuplicateMember` 和数值溢出错误携带 UTF-16 偏移。选项必须非负。`JsonInput` 是有界的分块输入累积器，`finish` 才执行解析；它不是逐 token 的增量解析器。累积器溢出不保存该块，`reset` 可复用。

原有 `parse_json` / `stringify_json` 继续保留其兼容入口和错误类型。`Operation.decode` 可以使用新解码选项，组件合法性仍由 JSON0 模型校验。

## 有界 JSON 输出

`encode_json` 返回字符串，`encode_json_to(value,sink,options~)` 按 UTF-16 单元分块输出。默认转义非 ASCII、无缩进、保持对象遍历顺序、每块 4,096 单元、总计最多 67,108,864 单元。可选键排序、0–16 空格缩进和可读 Unicode 输出。

可读输出保留合法代理对，单独代理项始终转义。块边界可能位于代理对之间，调用方拼接后才获得完整字符串；若要逐块编码为 UTF-8，必须自行保留末尾高代理项。排序并不构成密码学标准规范化格式。

输出开始前校验并复制输入，防止 sink 修改原 JSON 容器影响遍历。超过输出预算或 sink 自身失败时，外部 sink 可能已经接收到前缀；调用方若需要原子输出，应先使用返回完整字符串的 `encode_json`。

## 操作与文档预算

`Operation.metrics` 报告组件、路径、载荷节点、字符串单元及移动数量。`Snapshot.metrics` 统计已校验文档，深度以根为 0；对象键计入字符串单元，字符串值计入字符串数量。

`check_operation_limits` 检查组件、路径和载荷预算，以及可选的子类型名单、根编辑和旧文本开关。`apply_limited` 还检查初始及每一步文档，默认文档最多 1,000,000 个值、1,024 层路径深度和 67,108,864 个字符串单元。一次先增长再删除的操作也必须在中间状态满足限制。它不是权限系统，路径上的业务规则应由接入方决定。

`Snapshot.test_condition` 与 `apply_when` 提供路径存在、相等、数值范围、长度、文本包含及唯一字符串 ID 等条件。条件最大嵌套 256 层，每次最多访问 100,000 个条件节点。前置、应用或后置条件失败时不返回更新后的快照；已有快照不变。条件与自定义子类型回调的外部副作用不在回滚范围内。

`Operation.pack` 根据组件数、序列化 UTF-16 单元和载荷节点数拆成连续批次，计入每个数组的括号和逗号。不改变组件顺序，不在批次之间执行规范化，无法单独装入的组件会报错。返回值可 `flatten`，或用 `replay_packed` 校验各批次。

`ApplyCursor` 保存不透明的原始快照和组件偏移。`advance(count)` 返回新游标，每步检查旧值和文档预算；失败不移动原游标。它适用于调用方按组件数安排执行时间，但不保证每个组件成本相等。`seek` 可从原始检查点重放到绝对组件偏移，`checkpoints` 保留有界步骤的句柄。
