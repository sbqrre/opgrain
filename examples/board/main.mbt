///|
fn demonstrate(
  title : String,
  initial : String,
  left_source : String,
  right_source : String,
  expected : String,
  show_undo~ : Bool = false,
) -> Unit raise @opgrain.OpError {
  let base = @opgrain.parse_json(initial)
  let left = @opgrain.Operation::parse(left_source)
  let right = @opgrain.Operation::parse(right_source)
  let (left_after_right, right_after_left) = @opgrain.transform_x(left, right)
  let after_left = @opgrain.apply(base, left)
  let after_right = @opgrain.apply(base, right)
  let left_first = @opgrain.apply(after_left, right_after_left)
  let right_first = @opgrain.apply(after_right, left_after_right)
  if left_first != right_first || left_first != @opgrain.parse_json(expected) {
    abort(title + "：两条执行顺序应得到预期看板")
  }
  let undo_left = @opgrain.invert(left_after_right)
  let restored = @opgrain.apply(right_first, undo_left)
  if restored != after_right {
    abort(title + "：撤销转换后的左操作应恢复右侧状态")
  }
  println(title)
  println("右操作后应用左操作 " + left_after_right.stringify())
  println("左操作后应用右操作 " + right_after_left.stringify())
  println("最终看板 " + @opgrain.stringify_json(left_first))
  if show_undo {
    println("撤销左操作 " + undo_left.stringify())
    println("撤销后的看板 " + @opgrain.stringify_json(restored))
  }
}

///|
fn show_board() -> Unit raise @opgrain.OpError {
  demonstrate(
    "移动卡片时另一端修改标题", "{\"tasks\":[{\"title\":\"A\"},{\"title\":\"B\"}]}",
    "[{\"p\":[\"tasks\",0],\"lm\":1}]", "[{\"p\":[\"tasks\",0,\"title\",1],\"si\":\"!\"}]",
    "{\"tasks\":[{\"title\":\"B\"},{\"title\":\"A!\"}]}",
  )
  demonstrate(
    "两端都在列表头部新增卡片", "{\"tasks\":[\"Review\"]}", "[{\"p\":[\"tasks\",0],\"li\":\"Test\"}]",
    "[{\"p\":[\"tasks\",0],\"li\":\"Publish\"}]", "{\"tasks\":[\"Test\",\"Publish\",\"Review\"]}",
  )
  demonstrate(
    "两端同时重分配负责人", "{\"tasks\":[{\"owner\":null}]}", "[{\"p\":[\"tasks\",0,\"owner\"],\"od\":null,\"oi\":\"Wei\"}]",
    "[{\"p\":[\"tasks\",0,\"owner\"],\"od\":null,\"oi\":\"Lin\"}]", "{\"tasks\":[{\"owner\":\"Wei\"}]}",
  )
  demonstrate(
    "删除卡片时另一端调整工分",
    "{\"tasks\":[{\"title\":\"Review\",\"points\":2}]}",
    "[{\"p\":[\"tasks\",0],\"ld\":{\"title\":\"Review\",\"points\":2}}]",
    "[{\"p\":[\"tasks\",0,\"points\"],\"na\":3}]",
    "{\"tasks\":[]}",
    show_undo=true,
  )
  demonstrate(
    "一端删除标题片段，另一端在 emoji 后插入", "{\"tasks\":[{\"title\":\"😀待办\"}]}",
    "[{\"p\":[\"tasks\",0,\"title\"],\"t\":\"text0\",\"o\":[{\"p\":0,\"d\":\"😀待\"}]}]",
    "[{\"p\":[\"tasks\",0,\"title\"],\"t\":\"text0\",\"o\":[{\"p\":2,\"i\":\"!\"}]}]",
    "{\"tasks\":[{\"title\":\"!办\"}]}",
  )
}

///|
fn main {
  show_board() catch {
    error => abort(@debug.to_string(error))
  }
}
