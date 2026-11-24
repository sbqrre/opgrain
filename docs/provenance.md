# 实现、生成语料与依赖的来源

opgrain 是由 sbqrre 维护的 MoonBit JSON0 实现。实现过程中使用了 AI 辅助编写、审阅和调试；项目以可读源码、固定上游对照、回归测试及真实运行结果验证输出。Git 提交身份不替代上游版权与来源声明。

## 固定的语义参考

参考项目为 [ottypes/json0](https://github.com/ottypes/json0)，版本是 npm `ot-json0@1.1.0`，发布源码对应提交 [83222f417762be0e8672adb16657f0b8ba514d0d](https://github.com/ottypes/json0/tree/83222f417762be0e8672adb16657f0b8ba514d0d)。

上游发布包 README 的 License 节声明 MIT，版权为 `Copyright 2011 ottypes library contributors`；同一包的 `package.json` 中 `license` 为 `ISC`。这是实际存在的元数据差异。本项目如实保留两项信息，随代码提供 README 原始许可正文，不把元数据字段当成删除上游声明的依据。[完整许可副本](../LICENSES/ot-json0-1.1.0.txt) 与 [汇总声明](../THIRD_PARTY_NOTICES.md) 随发布包分发。

| 来源 | 本项目中的范围与适配 |
| --- | --- |
| 上游 `lib/json0.js` 的组件和公开 API | `operation.mbt`、`apply.mbt`、`compose.mbt`、`invert.mbt`；保留组件字段和有效操作语义，以 MoonBit 枚举、有限 Double、类型化路径和结构化错误实现 |
| 上游 `lib/json0.js` 的组件转换与 `lib/bootstrapTransform.js` | `transform.mbt`；保留左右优先级、拆分组件及顺序交叉转换规则 |
| 上游 `lib/text0.js` | `text0.mbt`、`text_transform.mbt`；保留 text0 载荷与 UTF-16 单元语义，并为旧式 `si/sd` 委托提供适配 |
| 上游确定性 CoffeeScript 测试 | `test/oracle/fixtures.mjs` 执行固定版本测试并捕获输入、输出；`upstream_data_wbtest.mbt` 保存语料，`upstream_wbtest.mbt` 在 MoonBit 中执行等价断言 |
| 上游随机测试生成器及通用 `ot-fuzzer@1.3.1` | Node 测试侧固定依赖并记录种子；其生成场景进入固定测试语料，不把 fuzzer 当作 MoonBit 核心实现 |

MoonBit 核心是独立运行的实现，不在运行时加载或调用 JavaScript 上游。持久快照、草稿、预算、分支、重定位、归档、投影、分组撤销、索引列表差分及文本差分等辅助接口是本项目围绕 JSON0 的扩展；其 API 不声称由 JavaScript JSON0 上游提供。JSON0 兼容目标与已知边界见 [语义文档](semantics.md)。

## 生成文件与复现

| 文件 | 生成来源 | 复现命令 |
| --- | --- | --- |
| `upstream_data_wbtest.mbt` | 固定的上游测试及合法操作生成器；种子 `opgrain-20261118` | `npm --prefix test/oracle ci --ignore-scripts`，随后 `npm --prefix test/oracle run fixtures` |
| `pkg.generated.mbti` | 本库公开类型及签名，由 MoonBit 工具链生成 | `moon info --frozen .` |
| `test/oracle/package-lock.json` | Node 测试开发依赖的准确版本、来源地址、完整性摘要和许可元数据 | `npm --prefix test/oracle ci --ignore-scripts` 使用它安装；该命令不重新生成锁文件 |

运行 `npm --prefix test/oracle run fixtures -- --check` 只核对固定语料是否可复现。随机失败现场和运行日志写到系统临时目录，不作为固定语料提交。测试语料、生成接口和例子不计入手写核心源码规模。

`ot-fuzzer@1.3.1` 的 README 同样声明 MIT，版权为 `Copyright 2011-2014 ottypes library contributors`，而包元数据标为 ISC；[其许可正文](../LICENSES/ot-fuzzer-1.3.1.txt) 也保留。这些说明针对测试数据与工具的来源，不把 fuzzer 的 JavaScript 实现包装成本库提供的 MoonBit 功能。

## 其他开发依赖

Mocha、CoffeeScript 及其传递依赖只用于测试开发，准确依赖树以锁文件为准。安装后的开发依赖保留其自身授权文件；`node_modules`、测试驱动和 Node 对照程序不进入 MoonBit 发布包。MoonBit 核心依赖来自工具链的 `moonbitlang/core`；本仓库不将这些依赖源码复制为自身实现。

[根 LICENSE](../LICENSE) 适用于本项目自身贡献；上述上游来源继续保留各自的版权和许可声明。没有同步服务器、数据库、编辑器、商业素材或私有来源代码作为库的运行依赖。
