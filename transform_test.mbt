///|
test "card edits follow a concurrent move" {
  let base = @opgrain.parse_json(
    "{\"tasks\":[{\"title\":\"A\"},{\"title\":\"B\"}]}",
  )
  let move_card = @opgrain.Operation::parse("[{\"p\":[\"tasks\",0],\"lm\":1}]")
  let edit = @opgrain.Operation::parse(
    "[{\"p\":[\"tasks\",0,\"title\",1],\"si\":\"!\"}]",
  )
  let (left, right) = @opgrain.transform_x(move_card, edit)
  assert_eq(left.to_json(), move_card.to_json())
  assert_eq(
    right.to_json(),
    @opgrain.parse_json("[{\"p\":[\"tasks\",1,\"title\",1],\"si\":\"!\"}]"),
  )
  assert_eq(
    @opgrain.apply(@opgrain.apply(base, move_card), right),
    @opgrain.apply(@opgrain.apply(base, edit), left),
  )
}

///|
test "parent deletion saves the concurrently edited value for inverse" {
  let remove = @opgrain.Operation::parse(
    "[{\"p\":[\"card\"],\"od\":{\"estimate\":1}}]",
  )
  let estimate = @opgrain.Operation::parse(
    "[{\"p\":[\"card\",\"estimate\"],\"na\":2}]",
  )
  let (left, right) = @opgrain.transform_x(remove, estimate)
  assert_eq(right.length(), 0)
  assert_eq(
    left.to_json(),
    @opgrain.parse_json("[{\"p\":[\"card\"],\"od\":{\"estimate\":3}}]"),
  )
}

///|
test "a concurrent insertion splits a text delete" {
  let a = @opgrain.Operation::parse("[{\"p\":[0],\"sd\":\"abc\"}]")
  let b = @opgrain.Operation::parse("[{\"p\":[1],\"si\":\"!\"}]")
  let (left, right) = @opgrain.transform_x(a, b)
  assert_eq(
    left.to_json(),
    @opgrain.parse_json("[{\"p\":[0],\"sd\":\"a\"},{\"p\":[1],\"sd\":\"bc\"}]"),
  )
  assert_eq(right.to_json(), @opgrain.parse_json("[{\"p\":[0],\"si\":\"!\"}]"))
}
