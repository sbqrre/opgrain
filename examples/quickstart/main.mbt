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
