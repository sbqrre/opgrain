# 看板工作负载基准

在同一台 Intel Core i7-9700（3.00 GHz）、Windows 10 x64（10.0.19045）上测量。工具链为 moon 0.1.20261104、moonc v0.10.20+65efd5b93，Node v24.19.0。全部使用 release 构建。

每项先执行 3 次预热，再收集 9 批样本。每批循环次数由工作负载固定，记录每次调用的微秒数并取批次中位数。表中的数值均为微秒，保留两位小数。Node 版本影响 JS 目标，Wasm 使用同一套工具链的 moonrun。这些数字描述本机合成看板工作负载，尚无线上用户流量基准。

## 与既有实现比较

基准版本固定为 `b265a148628b096c29e0e0b3547e6f230c43f04e`。将完全相同的 `benchmarks/main.mbt` 驱动分别应用于基准版本和 0.2.0，文档与操作在计时前构造。单元格依次表示基准版本与 0.2.0 的中位耗时。


| 工作负载 | native | JS | Wasm | Wasm GC |
| --- | ---: | ---: | ---: | ---: |
| apply-100 | 166.36 → 119.99 | 66.14 → 56.31 | 157.75 → 120.62 | 35.16 → 25.53 |
| apply-1000 | 1731.84 → 1260.22 | 702.91 → 589.22 | 1420.50 → 1133.26 | 340.06 → 293.25 |
| verified-1000 | 1715.74 → 1221.87 | 680.57 → 547.36 | 1436.38 → 1133.72 | 318.26 → 238.73 |
| journal-1000x30 | 63180.80 → 1278.10 | 28673.80 → 935.80 | 49411.90 → 1404.70 | 24046.40 → 243.90 |
| diff-identity-100 | 577.84 → 293.64 | 337.77 → 242.51 | 619.10 → 366.83 | 161.36 → 124.61 |
| diff-identity-1000 | 6452.27 → 3191.97 | 2999.03 → 1755.10 | 5284.00 → 2981.80 | 1662.30 → 1031.13 |
| transform-move-title | 1.35 → 1.30 | 1.42 → 1.40 | 2.40 → 2.47 | 0.99 → 0.98 |
| compose | 0.32 → 0.30 | 0.43 → 0.83 | 0.45 → 0.45 | 0.27 → 0.28 |
| wire-parse-1000 | 8234.50 → 8298.00 | 6326.05 → 6801.55 | 6921.75 → 7554.65 | 3676.30 → 4403.10 |
| wire-stringify-1000 | 2278.15 → 2382.95 | 1525.45 → 1841.90 | 2114.10 → 2218.80 | 875.25 → 894.35 |

## 持久快照接口

| 工作负载 | native | JS | Wasm | Wasm GC |
| --- | ---: | ---: | ---: | ---: |
| snapshot-verified-1000 | 4.82 | 6.98 | 8.43 | 1.92 |
| snapshot-verified-10000 | 52.73 | 37.49 | 84.13 | 9.42 |
| journal-handle-1000x100 | 582.78 | 542.22 | 864.70 | 184.34 |
| compact-1000x100 | 602.26 | 434.98 | 808.68 | 147.20 |
| exact-undo-1000 | 577.05 | 190.86 | 423.83 | 173.40 |

## 复现

```sh
node benchmarks/run.mjs
node benchmarks/run.mjs js
node benchmarks/compare.mjs js
```

`run.mjs` 输出平台、CPU、工具链版本和两组基准的 JSON。可传入 native、js、wasm、wasm-gc 的一个或多个目标。`compare.mjs` 使用本地 Git 中的固定基准提交导出临时源码，再复制相同的兼容驱动。它分别运行旧版与当前源码，输出每项的原始最小值、中位数、最大值和比值。复现比较需要完整提交历史、Git、MoonBit，以及 Windows 的 tar 或其他平台的 unzip。

100/1000 张卡片均包含 id、带中文与 emoji 的 title、points 及两个 labels。一次 apply 给第 50 张卡片增加 0.5 工分。journal-1000x30 包含从外部 JSON 创建历史和追加 30 次编辑的总成本，旧检查点一直保留。diff-identity 从第 50 张卡片移动到首位的两份快照生成差量，唯一键设为 id。transform 将这次移动与同一卡片的标题插入转换。compose 组合两次工分增量。wire 项使用 1000 张卡片的整个文档。

持久快照组在计时前构造句柄。snapshot-verified 计入路径复制及旧值校验，返回不透明句柄。journal-handle 和 compact 的输入为既有句柄，后者还将保留区间推进到第 80 版。exact-undo 包含应用正向、构造逆操作、实际撤销并比较恢复结果。导出完整 JSON 的成本需单独计算。

历史追加的收益来自共享未编辑分支，差量生成也减少了不必要的整文档复制。解析、序列化和很短的操作受额外校验、分配、JIT 与垃圾回收影响，一部分样本高于旧版。短调用的最小值、中位数和最大值可能差异明显，复测脚本保留三者。CI 只检查基准可执行及其结果校验，不设置绝对耗时门槛。

## 0.3.0 操作生成与跟踪实测

2026-11-23，在 Windows 10.0.19045、Intel Core i7-9700 3.00GHz、Node v24.19.0 上实际运行。MoonBit CLI 0.1.20261104，moonc v0.10.20+65efd5b93，moonrun 0.1.20261104。全部 release 构建，每项先预热 3 次，再计时 9 批；表中为每次调用的微秒数。运行 `node benchmarks/run.mjs` 同时复现原负载、持久快照负载和新增算法负载；单独运行 `moon run benchmarks/algorithms --target js --release --frozen` 可只复现新负载。

下列数据是确定性的合成任务看板和任务说明文本，不是线上用户延迟或吞吐量承诺。列表输入为 1,000 张卡片向左轮转一位，标题包含中文、emoji 和组合字符。两个列表生成器都验证应用结果；旧的顺序生成器执行 999 次移动，新索引生成器执行 1 次。计时只包含操作生成，不包含最终整份 JSON 导出或网络成本，输入校验与复制包含在内。

跟踪负载为 1,000 张卡片、100 个节点锚点和一个工分增量。旧接口的输入导出与输出副本计入成本；持久接口保留不透明快照，因此这组差异也包含所有权模型的成本，不能解释为纯变换算法加速。文本负载为 200 行中的一行变化；行级差分需分割整段文本，在这组数据上明显慢于利用共同前后缀的直接 UTF-16 差分。它不被作为默认更快的算法宣传。编解码负载包含整份 JSON 导出、编码、解码及预算检查。
| 目标 | 工作负载 | min μs | median μs | max μs |
| --- | --- | ---: | ---: | ---: |
| native | keyed-diff-sequential-rotate-1000 | 12067.40 | 13742.00 | 20142.80 |
| native | keyed-diff-indexed-rotate-1000 | 4210.36 | 4749.44 | 5079.20 |
| native | text-unit-diff-200-lines | 21.40 | 21.46 | 23.38 |
| native | text-line-diff-200-lines | 1219.75 | 1244.09 | 1312.72 |
| native | tracking-detached-1000-tasks-100-anchors | 2050.30 | 2189.79 | 2303.30 |
| native | tracking-persistent-1000-tasks-100-anchors | 31.28 | 32.36 | 36.14 |
| native | bounded-codec-1000-tasks | 30193.70 | 32748.98 | 34099.20 |
| js | keyed-diff-sequential-rotate-1000 | 10599.10 | 14919.20 | 16280.30 |
| js | keyed-diff-indexed-rotate-1000 | 2199.60 | 2496.82 | 3854.38 |
| js | text-unit-diff-200-lines | 39.51 | 49.13 | 112.41 |
| js | text-line-diff-200-lines | 318.70 | 342.57 | 430.79 |
| js | tracking-detached-1000-tasks-100-anchors | 648.61 | 685.16 | 1045.34 |
| js | tracking-persistent-1000-tasks-100-anchors | 16.52 | 20.03 | 35.68 |
| js | bounded-codec-1000-tasks | 8535.16 | 9158.80 | 10991.34 |
| wasm | keyed-diff-sequential-rotate-1000 | 18972.20 | 20084.50 | 23485.50 |
| wasm | keyed-diff-indexed-rotate-1000 | 3924.72 | 4003.40 | 4796.46 |
| wasm | text-unit-diff-200-lines | 33.38 | 36.10 | 91.12 |
| wasm | text-line-diff-200-lines | 220.34 | 232.97 | 284.22 |
| wasm | tracking-detached-1000-tasks-100-anchors | 1652.29 | 1718.40 | 1987.49 |
| wasm | tracking-persistent-1000-tasks-100-anchors | 38.23 | 42.21 | 68.11 |
| wasm | bounded-codec-1000-tasks | 18839.36 | 19297.12 | 20677.92 |
| wasm-gc | keyed-diff-sequential-rotate-1000 | 3070.20 | 4215.10 | 5097.10 |
| wasm-gc | keyed-diff-indexed-rotate-1000 | 1899.52 | 2111.56 | 2935.70 |
| wasm-gc | text-unit-diff-200-lines | 18.98 | 21.75 | 24.04 |
| wasm-gc | text-line-diff-200-lines | 100.26 | 109.58 | 177.41 |
| wasm-gc | tracking-detached-1000-tasks-100-anchors | 332.92 | 371.70 | 473.39 |
| wasm-gc | tracking-persistent-1000-tasks-100-anchors | 9.32 | 10.57 | 20.34 |
| wasm-gc | bounded-codec-1000-tasks | 6497.38 | 7177.44 | 9047.98 |
