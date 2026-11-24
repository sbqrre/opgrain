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

opgrain 提供兼容 JSON0 线格式的 MoonBit JSON 并发操作引擎，适用于交换和转换任务看板的数据操作。核心库不调用 JavaScript 上游；同步服务器、网络传输、权限、数据库和完整编辑器由接入方提供。

### 操作入口

`Operation::parse` 从 JSON0 操作数组读取已校验的组件。用 `apply` 得到新文档，`compose` 合并同一条历史中的连续操作，`invert` 构造逆操作。用 `transform_x` 计算一对并发操作，或用 `transform` 和明确的 `Left` / `Right` 计算单侧结果。

在新调用方中安装已发布版本：

```sh
moon new board-client --user sbqrre --name board-client
cd board-client
moon add sbqrre/opgrain@0.3.1
```

把 `cmd/main/moon.pkg` 设为：

```moonbit
import {
  "sbqrre/opgrain",
}

pkgtype(kind: "executable")
```

把 `cmd/main/main.mbt` 设为以下完整程序：

```moonbit
///|
fn main {
  try {
    let board = @opgrain.parse_json("{\"tasks\":[\"Review\"]}")
    let operation = @opgrain.Operation::parse(
      "[{\"p\":[\"tasks\",1],\"li\":\"Publish\"}]",
    )
    let next = @opgrain.apply(board, operation)
    println(@opgrain.stringify_json(next))
  } catch {
    _ => abort("board operation failed")
  }
}
```

执行 `moon run cmd/main --target js`，输出 `{"tasks":["Review","Publish"]}`。本仓库中相同程序位于 [examples/quickstart](examples/quickstart/main.mbt)，可直接运行 `moon run examples/quickstart --target js --frozen`。上方 `sbqrre/board-client` 仅是本地示例模块名，不需要发布该调用方。

从源码依赖时，将库和调用方放入同一个 `moon.work`，具体配置见 [源码依赖](docs/semantics.md#从源代码依赖)。

处理离线看板时，可以用 `Engine::draft` 记录真实旧值，或用 `Engine::diff` 从两份快照生成 JSON0 操作。示例的第六个案例将卡片移动与离线标题编辑合并，跟随标题光标，再用 `Journal::revert` 撤销移动并保留标题编辑。详见 [快照编辑、合并与位置跟踪](docs/editing.md)。

需要保留多个看板版本时，`Snapshot` 句柄共享未编辑分支，`Draft::transaction` 原子提交一组修改，`Journal::compact` 按绝对版本号压缩旧历史。`prepare_edit` 可以用实际旧值构造并验证撤销。示例还演示批量发布任务、压缩后的离线编辑合并，以及浮点舍入后的工分撤销，共 9 个基础案例。见 [快照、事务与历史压缩](docs/snapshots.md)。

按卡片 ID 重排可以使用 `diff_keyed_list`，文本差分支持 UTF-16 单元和整行细化，深层快照可使用显式栈差分与比较。`BranchPair`、`RebaseBuffer` 和 `UndoHistory` 提供本地分支预览、待定操作重定位和分组撤销。新增四个可运行看板案例，合计 13 个；见 [操作生成与观察](docs/algorithms.md)、[本地历史](docs/local-history.md) 和 [线格式与预算](docs/wire-limits.md)。

### 互通与边界

基准是 [`ot-json0@1.1.0`](https://github.com/ottypes/json0/tree/83222f417762be0e8672adb16657f0b8ba514d0d) 的发布源码。支持数字增量、对象和列表编辑、列表移动、旧式文本操作及显式 `text0`。每个 `Engine` 可以注册自己的 JSON 子类型。

文本偏移按 UTF-16 代码单元计算。含单独代理项的线格式请用库的 `parse_json` / `stringify_json`。同一文本位置混用旧式操作和显式 `text0` 时，上游存在不收敛的组合。数字使用二进制双精度，舍入会影响组合和求逆。详见 [API 与兼容性](docs/semantics.md)。

### 可复现验证

```sh
npm --prefix test/oracle ci --ignore-scripts
npm --prefix test/oracle run docs
npm --prefix test/oracle test
npm --prefix test/oracle run fixtures -- --check
npm --prefix test/oracle run live
npm --prefix test/oracle run extended
npm --prefix test/oracle run optimized
npm --prefix test/oracle run package-smoke
moon check --frozen --deny-warn --target js
moon build --frozen --deny-warn --target js --release
moon test --frozen --deny-warn --target native
moon test --frozen --deny-warn --target js
moon test --frozen --deny-warn --target wasm
moon test --frozen --deny-warn --target wasm-gc
```

MoonBit 套件读取 Node 生成的固定语料。比较操作数组时忽略 JSON 对象键的排列顺序，并单独检查应用后的语义。Node.js 只用于生成和复核测试数据。测试范围和复现细节见 [测试方法](docs/verification.md)。

基准覆盖 100、1,000 和 10,000 张卡片，使用 release 构建并记录 9 批计时。运行 `node benchmarks/run.mjs` 可测量当前版本，`node benchmarks/compare.mjs js` 可与固定历史版本比较。本机实测表与成本说明见 [看板工作负载基准](docs/benchmarks.md)。

### 源码与许可

源码保持一个根库包，按职责分文件；[源码导航](docs/layout.md) 说明核心、示例、测试、生成语料和开发工具的边界。`node test/oracle/source-size.mjs` 分开报告各类 MoonBit 源码，核心规模不包含测试、示例或生成接口。

本项目自身贡献采用 [MIT](LICENSE)。JSON0、text0 及上游测试来源、版本与改写范围见 [来源说明](docs/provenance.md)；上游版权和完整许可文本保留在 [第三方声明](THIRD_PARTY_NOTICES.md) 及 `LICENSES/` 中。上游 README 与包元数据的 MIT/ISC 差异也如实记录。[版本记录](CHANGELOG.md) 描述已发布版本。
