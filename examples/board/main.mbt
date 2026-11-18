///|
fn show_board() -> Unit raise @opgrain.OpError {
  let snapshot = @opgrain.parse_json(
    "{\"tasks\":[{\"title\":\"A\"},{\"title\":\"B\"}]}",
  )
  let move_card = @opgrain.Operation::parse("[{\"p\":[\"tasks\",0],\"lm\":1}]")
  let rename_card = @opgrain.Operation::parse(
    "[{\"p\":[\"tasks\",0,\"title\",1],\"si\":\"!\"}]",
  )
  let (move_after_edit, edit_after_move) = @opgrain.transform_x(
    move_card, rename_card,
  )
  let move_first = @opgrain.apply(
    @opgrain.apply(snapshot, move_card),
    edit_after_move,
  )
  let edit_first = @opgrain.apply(
    @opgrain.apply(snapshot, rename_card),
    move_after_edit,
  )
  if move_first != edit_first {
    abort("Board edits should converge")
  }
  println(move_after_edit.stringify())
  println(edit_after_move.stringify())
  println(@opgrain.stringify_json(move_first))
}

///|
fn main {
  show_board() catch {
    error => abort(@debug.to_string(error))
  }
}
