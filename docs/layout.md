# 从操作找到实现

`sbqrre/opgrain` 的库是根目录的一个 MoonBit 包：`moon.mod` 声明模块，`moon.pkg` 声明根包依赖，同目录的 `.mbt` 共享包内私有类型与辅助算法。下面按职责导航，而不是把相互依赖的内部实现拆成多个公开包。

| 要理解的行为 | 实现入口 |
| --- | --- |
| 组件形状、路径类型、线格式、类型化构造 | [operation.mbt](../operation.mbt)、[instruction.mbt](../instruction.mbt)、[path.mbt](../path.mbt) |
| 应用、旧值核验与可恢复执行 | [apply.mbt](../apply.mbt)、[verify.mbt](../verify.mbt)、[apply_cursor.mbt](../apply_cursor.mbt) |
| JSON0 组合、规范化、求逆、左右转换 | [compose.mbt](../compose.mbt)、[invert.mbt](../invert.mbt)、[transform.mbt](../transform.mbt) |
| text0、旧文本表示及 UTF-16 索引 | [text0.mbt](../text0.mbt)、[text_transform.mbt](../text_transform.mbt)、[text_encoding.mbt](../text_encoding.mbt)、[text_coordinates.mbt](../text_coordinates.mbt) |
| JSON 复制、代理项线格式、预算与比较 | [json_value.mbt](../json_value.mbt)、[wire.mbt](../wire.mbt)、[decoder.mbt](../decoder.mbt)、[encoder.mbt](../encoder.mbt)、[resources.mbt](../resources.mbt)、[comparison.mbt](../comparison.mbt) |
| 草稿、持久快照与差分生成 | [draft.mbt](../draft.mbt)、[snapshot.mbt](../snapshot.mbt)、[diff.mbt](../diff.mbt)、[iterative_diff.mbt](../iterative_diff.mbt)、[indexed_diff.mbt](../indexed_diff.mbt)、[text_diff.mbt](../text_diff.mbt) |
| 列表重排索引与对齐算法 | [order_tree.mbt](../order_tree.mbt)、[order_walk.mbt](../order_walk.mbt)、[alignment.mbt](../alignment.mbt) |
| 历史、事务、分支、重定位和撤销 | [history.mbt](../history.mbt)、[journal.mbt](../journal.mbt)、[transaction.mbt](../transaction.mbt)、[branch_pair.mbt](../branch_pair.mbt)、[rebase_buffer.mbt](../rebase_buffer.mbt)、[undo.mbt](../undo.mbt)、[undo_history.mbt](../undo_history.mbt)、[archive.mbt](../archive.mbt) |
| 路径查询、条件、影响候选、投影和位置跟踪 | [query.mbt](../query.mbt)、[conditions.mbt](../conditions.mbt)、[footprint.mbt](../footprint.mbt)、[projection.mbt](../projection.mbt)、[trace.mbt](../trace.mbt)、[tracking.mbt](../tracking.mbt)、[tracked_snapshot.mbt](../tracked_snapshot.mbt) |

完整公开 API 签名由 `moon info --frozen .` 生成到 [pkg.generated.mbti](../pkg.generated.mbti)。它是接口产物，不作为手写实现规模计算。
示例、基准和测试驱动包生成的接口不属于库 API，通过 `.gitignore` 排除；根库的接口文件继续跟踪并由 CI 检查差异。

## 库以外的代码

- [examples/quickstart](../examples/quickstart/main.mbt) 是 README 的完整最小调用方，直接运行后输出更新后的任务列表。
- [examples/board](../examples/board/main.mbt) 保留十三个有断言的看板案例，覆盖并发冲突与本地历史操作。
- 根目录的 `*_test.mbt` 从调用方视角测试公开 API；`*_wbtest.mbt` 可以访问内部实现。
- [upstream_data_wbtest.mbt](../upstream_data_wbtest.mbt) 是固定上游测试及随机场景的生成语料；其生成命令、种子、许可见 [来源说明](provenance.md)。
- [test/oracle](../test/oracle/package.json) 固定 Node 开发依赖，用于上游对照、差分和包验证；[test/driver](../test/driver/main.mbt) 是供这些工具调用的 JS 目标测试程序。
- [benchmarks](../benchmarks/run.mjs) 保存可重现的计时代码；测量含义、机器环境和实际结果见 [基准文档](benchmarks.md)。

## 发布边界

[.moonignore](../.moonignore) 将根目录测试、上游语料、Node 对照工具、测试驱动、CI 和基准排除在发布包之外。许可证、必要的上游授权文本、正式文档、示例和核心源码随包保留。`package-smoke` 解包检查文件边界，再从独立 MoonBit 模块导入并运行四个目标。

统计命令 `node test/oracle/source-size.mjs` 单独报告库核心、手写测试、生成测试语料、示例、基准和测试驱动。比较项目规模时使用核心的 `effective`，不能将生成语料或生成接口相加作为核心实现量。
