# opgrain

看板里有两张卡片。左端把第一张卡片移到第二张之后。右端看到的是同一份初始看板，在第一张卡的标题末尾加了一个感叹号。

```json
{"tasks":[{"title":"A"},{"title":"B"}]}
```

左操作 `[{"p":["tasks",0],"lm":1}]`。右操作 `[{"p":["tasks",0,"title",1],"si":"!"}]`。

`transform_x(left, right)` 返回以下两条操作，分别用于已经应用右操作、已经应用左操作的文档。

```json
[
  [{"p":["tasks",0],"lm":1}],
  [{"p":["tasks",1,"title",1],"si":"!"}]
]
```

右操作的卡片索引随移动变成 `1`。按任一顺序应用，最终文档都是 `{"tasks":[{"title":"B"},{"title":"A!"}]}`。运行 [看板示例](examples/board/main.mbt) 查看转换结果和最终文档。

```sh
moon run examples/board --target js
```

同一命令包含以下五个并发案例。每个案例都校验两条执行顺序得到预期看板，并检查撤销转换后的左操作能恢复右侧状态。

| 看板案例 | 可以观察到的转换规则 |
| --- | --- |
| 移动卡片时另一端修改标题 | 编辑路径随原卡片移动 |
| 两端都在列表头部新增卡片 | 同位置插入时左侧在前，右侧下标后移 |
| 两端同时重分配负责人 | 左侧替换获胜，并把右侧负责人记录为被替换值 |
| 删除卡片时另一端调整工分 | 删除载荷保留更新后的工分，撤销删除能恢复修改过的卡片 |
| 删除标题片段时另一端在 emoji 后插入 | `text0` 按 UTF-16 偏移拆分删除，保留并发插入 |

### 操作入口

`Operation::parse` 从 JSON0 操作数组读取已校验的组件。用 `apply` 得到新文档，`compose` 合并同一条历史中的连续操作，`invert` 构造逆操作。用 `transform_x` 计算一对并发操作，或用 `transform` 和明确的 `Left` / `Right` 计算单侧结果。

```moonbit
let board = @opgrain.parse_json("{\"tasks\":[\"Review\"]}")
let op = @opgrain.Operation::parse("[{\"p\":[\"tasks\",1],\"li\":\"Publish\"}]")
let next = @opgrain.apply(board, op)
println(@opgrain.stringify_json(next))
```

库模块名为 `sbqrre/opgrain`。从源代码使用时，把本库和调用方的模块放入同一个 `moon.work`，在调用方的 `moon.mod` 中声明 `"sbqrre/opgrain@0.1.0"`，并在 `moon.pkg` 中导入 `"sbqrre/opgrain"`。

处理离线看板时，可以用 `Engine::draft` 记录真实旧值，或用 `Engine::diff` 从两份快照生成 JSON0 操作。示例的第六个案例将卡片移动与离线标题编辑合并，跟随标题光标，再用 `Journal::revert` 撤销移动并保留标题编辑。详见 [快照编辑、合并与位置跟踪](docs/editing.md)。

### 互通与边界

基准是 [`ot-json0@1.1.0`](https://github.com/ottypes/json0/tree/83222f417762be0e8672adb16657f0b8ba514d0d) 的发布源码。支持数字增量、对象和列表编辑、列表移动、旧式文本操作及显式 `text0`。每个 `Engine` 可以注册自己的 JSON 子类型。

文本偏移按 UTF-16 代码单元计算。含单独代理项的线格式请用库的 `parse_json` / `stringify_json`。同一文本位置混用旧式操作和显式 `text0` 时，上游存在不收敛的组合。数字使用二进制双精度，舍入会影响组合和求逆。详见 [API 与兼容性](docs/semantics.md)。

### 可复现验证

```sh
npm --prefix test/oracle ci --ignore-scripts
npm --prefix test/oracle test
npm --prefix test/oracle run fixtures -- --check
npm --prefix test/oracle run live
npm --prefix test/oracle run package-smoke
moon test --frozen --deny-warn --target native
moon test --frozen --deny-warn --target js
moon test --frozen --deny-warn --target wasm
moon test --frozen --deny-warn --target wasm-gc
```

MoonBit 套件读取 Node 生成的固定语料。比较操作数组时忽略 JSON 对象键的排列顺序，并单独检查应用后的语义。Node.js 只用于生成和复核测试数据。测试范围和复现细节见 [测试方法](docs/verification.md)。
