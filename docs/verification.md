# 重现 JSON0 测试

基准为 npm `ot-json0@1.1.0` 与其提交 `83222f417762be0e8672adb16657f0b8ba514d0d`。使用 Node 24 和 `test/oracle/package-lock.json` 中的依赖版本。

- `npm --prefix test/oracle test` 执行发布包内的 66 个测试。通用 `ot-fuzzer` 驱动两轮 JSON0 和一轮独立 text0 测试，共 4,000 次随机试验。此命令缺省种子为 `1`，可用 `SEED` 重跑。上游测试每次从独立临时目录启动，失败时输出保存现场的目录。
- `npm --prefix test/oracle run fixtures -- --check` 执行全部 63 个确定性上游测试并复核固定语料，另外调用上游的随机操作生成器。语料中的种子为 `opgrain-20261118`，含旧式文本、显式子类型、独立 text0 各 160 组。去掉 `-- --check` 可重新生成数据文件。
- `moon test` 实际用 MoonBit 运行语料，分别断言规范化操作、应用结果和属性。12 个使用了错误下标类型的上游转换探针，在本库中验证结构化失败；同一用例另有符合路径类型的变体，用于核对转换规则。
- `npm --prefix test/oracle run bridge` 启动 MoonBit 的 JS 测试入口，双向核对带单独 UTF-16 代理项的文档和操作，并把 MoonBit 生成的看板差量及缺失根操作交给 JavaScript 上游应用和求逆。
- `npm --prefix test/oracle run live` 现场生成并执行 4,000 组对照，覆盖旧式文本、显式子类型和根节点 `text0`。缺省种子为 `opgrain-live-1`，可用 `SEED` 重跑。脚本比较规范化操作，也让对端应用组合、求逆和转换产物。

线格式比较按 JavaScript JSON 序列化的值进行。例如给零增量求逆时，JavaScript 内存中的 `-0` 序列化为 `0`。冒烟测试固定覆盖了这个最小用例。

序列生成器从同一文档独立生成并发操作，并在操作结果上生成后继操作。应用和逆操作验证使用合法的删除内容。组合性质使用精确的小整数，单独保存浮点舍入反例。验证包含分片应用、组合结合性的语义、单侧与双侧转换、交叉转换两条历史，以及逆序撤销已转换的历史。

测试失败时，报告给出上游测试标题或生成器类别和用例序号。可在 [生成语料](../upstream_data_wbtest.mbt) 搜索该标题或类别与编号，提取输入和期望值。将一个 JSON 请求数组传给 `node test/oracle/oracle.mjs` 可单独重现 `apply`、`compose`、`invert`、`normalize`、`transform` 和 `transformX`，参数名见 [对照程序](../test/oracle/oracle.mjs)。将缩减后的用例加入 MoonBit 测试，保留随机种子对应的原始场景。

运行时差分失败时，可以把错误中的 JSON 对象交给以下命令。

```sh
node test/oracle/reduce.mjs < counterexample.json
```

缩减器尝试移除组件和根对象中无关的字段，每一步都会重新验证操作在上游可应用，并保留原来的失败类别。它把结果写到标准输出。多步操作需要保留差分报告中的初始 `snapshot`。

## 验证文档编辑接口

`draft_test.mbt` 检查缺失根与 JSON 空值、失效旧值、批次失败后的状态和拆分 UTF-16 代理项后的求逆。`diff_test.mbt` 使用 150 组固定种子的看板快照，分别检查不同对齐预算下的正向应用和逆操作，并固定覆盖卡片标识重复及数值舍入。`history_test.mbt` 覆盖多批次交叉转换、混合文本表示的转换、批次回滚、选择性撤销和浮点分歧。`tracking_test.mbt` 覆盖卡片移动与删除、光标插入附着方向、范围收缩及失效原因。以上测试随常规 `moon test` 在四个目标运行。

## 验证打包产物

`npm --prefix test/oracle run package-smoke` 运行 `moon package --frozen`，检查压缩包包含库、README 和许可证，并排除测试驱动与 CI 配置。脚本把压缩包解开到独立工作区，由另一个 MoonBit 模块导入它，并执行同位置插入的并发转换。验证对象是打包后交付给调用方的模块。
