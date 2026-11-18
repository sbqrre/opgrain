# JSON0 操作与兼容性

`Operation` 由按顺序执行的组件构成。每个组件包含路径 `p` 和一组指令。对象键用字符串表示，列表下标和旧式文本偏移用非负整数表示。空路径指向根。

| 指令 | 行为 |
| --- | --- |
| `na` | 加上一个有限的二进制双精度数 |
| `oi` / `od` | 插入或删除对象属性，两者同时出现时执行替换 |
| `li` / `ld` | 插入或删除列表项，两者同时出现时执行替换 |
| `lm` | 在同一列表内移动项，目标是移除原项之后的插入下标 |
| `si` / `sd` | 在路径末尾的 UTF-16 偏移插入或删除文本 |
| `t` / `o` | 将相应路径的值和 JSON 载荷交给注册的子类型 |

保留删除或替换前的值能构造逆操作。应用对象或列表编辑时遵循上游对旧值载荷的处理，文本删除则检查文本片段是否匹配。对根执行 `od` 会得到缺失的根。需要表示这一状态时调用 `Engine::apply_optional`，其中 `None` 和 `Some(Json::null())` 含义不同。

## API

- `Operation::parse`、`Operation::from_json`、`Component::from_json` 读取线格式。`to_json` 和 `Operation::stringify` 写出操作。
- `normalize` 接收组件或组件数组，为缺失的路径补 `[]`，并按上游的追加规则合并相邻组件。`Engine::append` 将单个组件追加到现有操作。
- `create` 创建文档，缺省为 JSON `null`。`apply` 在独立副本上执行整条操作。`Operation::shatter` 拆成单组件操作。`Engine::incremental_apply` 为每一步传入独立的结果副本。
- `compose(a, b)` 要求 `b` 基于应用 `a` 后的文档。`invert` 反转组件顺序，再逐个反转组件。`Engine::invert_component` 用于单个组件。
- `transform_x(a, b)` 要求两条操作基于同一文档。返回 `(a_after_b, b_after_a)`。`transform` 和 `Engine::transform_component` 接受单侧优先级。
- `path_matches` 比较路径。`common_length_for_ops` 和 `can_op_affect_path` 提供与组件寻址规则一致的路径检查。
- `check_valid_op` 检查 JSON0 指令形状。`Engine::check_valid_op` 也检查子类型注册状态和内置 `text0` 载荷。

使用 `Engine::register_subtype` 注册 `apply`、`compose`、`invert`、`transform` 四个处理函数。回调接收独立数据副本，可以使用任意 JSON 形状的载荷。`transform` 返回空数组时删除该子类型组件，返回对象或标量时保留组件。注册同名处理器会替换现有委托。

## 从源代码依赖

将本库克隆到 `opgrain/`，并将调用方放在同级目录 `app/`。在共同的上级目录添加 `moon.work`。

```toml
members = ["opgrain", "app"]
```

在 `app/moon.mod` 中添加模块依赖。

```moonbit
import {
  "sbqrre/opgrain@0.1.0",
}
```

在需要调用库的 `moon.pkg` 中导入包。

```moonbit
import {
  "sbqrre/opgrain",
}
```

工作区使用 `opgrain/` 的源码解析这条依赖。调用代码通过 `@opgrain` 访问公开接口。

## 冲突规则

同位置列表插入时，左操作保留位置，右操作后移。同路径属性替换时，左侧存活并将被替换的载荷改成右侧插入值。删除父节点并发于修改子节点时，父节点删除会吸收子节点修改后的旧值，子节点操作被移除。列表移动会同时调整源及目标位置，作用于被移动值的子路径会一起移动。

旧式 `si` / `sd` 只在与同表示的文本操作相遇时一起委托给 `text0`。发布版在同一位置用 `si` 插入 `L`、用显式 `text0` 插入 `R` 时，基于 `"x"` 的两条路径会得到 `"RLx"` 和 `"LRx"`。同一个协作会话应在转换前统一文本表示。

## 值与错误

- 文本位置及长度使用 UTF-16。允许在 emoji 代理对中间插入，也能读写 JSON 转义中的单独代理项。使用库提供的 JSON 编解码器可保留这些单元。
- 数值使用 MoonBit `Double`。超过 `2^53 - 1` 的整数可能无法精确表示。舍入可能使合并结果不同于顺序应用，也可能使逆操作无法恢复原值。非有限结果返回 `NonFiniteNumber`。
- 路径索引和移动目标范围为非负 Int32。缺失路径、容器类型不符、越界、不合法组件和未知子类型返回 `OpError`。结构化错误类型独立于 JavaScript 异常消息。
- `apply` 不修改传入的文档和操作，返回的 JSON 容器独立于输入。整个批次失败时原文档保留。增量回调逐步执行，已调用的回调可以观察到此前成功的步骤。

核心库在 MoonBit 中执行，面向有序的 JSON0 操作和本地文档状态。
