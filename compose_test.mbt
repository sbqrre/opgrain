///|
test "composition and inverse preserve an exact board edit" {
  let base = @opgrain.parse_json("{\"tasks\":[\"A\",\"B\"],\"points\":0}")
  let first = @opgrain.Operation::parse(
    "[{\"p\":[\"tasks\",0],\"lm\":1},{\"p\":[\"points\"],\"na\":1.25}]",
  )
  let second = @opgrain.Operation::parse(
    "[{\"p\":[\"points\"],\"na\":0.5},{\"p\":[\"tasks\",1,1],\"si\":\"!\"}]",
  )
  let combined = @opgrain.compose(first, second)
  let updated = @opgrain.apply(base, combined)
  assert_eq(updated, @opgrain.apply(@opgrain.apply(base, first), second))
  assert_eq(@opgrain.apply(updated, @opgrain.invert(combined)), base)
  assert_eq(combined.length(), 3)
}

///|
test "normalization defaults a root path and leaves the input alone" {
  let input = @opgrain.parse_json("{\"na\":1}")
  let operation = @opgrain.normalize(input)
  assert_eq(operation.to_json(), @opgrain.parse_json("[{\"p\":[],\"na\":1}]"))
  assert_eq(input, @opgrain.parse_json("{\"na\":1}"))
}

///|
test "compose legacy strings and invert explicit text0" {
  let first = @opgrain.Operation::parse("[{\"p\":[0],\"si\":\"a\"}]")
  let second = @opgrain.Operation::parse("[{\"p\":[1],\"si\":\"b\"}]")
  let combined = @opgrain.compose(first, second)
  assert_eq(
    combined.to_json(),
    @opgrain.parse_json("[{\"p\":[0],\"si\":\"ab\"}]"),
  )
  let text = @opgrain.Operation::parse(
    "[{\"p\":[],\"t\":\"text0\",\"o\":[{\"p\":1,\"d\":\"b\"},{\"p\":1,\"i\":\"c\"}]}]",
  )
  let base = Json::string("ab")
  assert_eq(
    @opgrain.apply(@opgrain.apply(base, text), @opgrain.invert(text)),
    base,
  )
}
