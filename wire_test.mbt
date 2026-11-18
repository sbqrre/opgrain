///|
test "escaped surrogate keys and private-use strings remain distinct" {
  let wire =
    #|{"\ud800":1,"\ue000d800":2,"\udc00":3,"中":"\ue000\udc00"}
  let escaped =
    #|{"\ud800":1,"\ue000d800":2,"\udc00":3,"\u4e2d":"\ue000\udc00"}
  let value = @opgrain.parse_json(wire)
  assert_eq(@opgrain.stringify_json(value), escaped)
  assert_eq(@opgrain.parse_json(escaped), value)
}

///|
test "literal and escaped Unicode keys follow the same JSON identity" {
  let wire =
    #|{"😀":1,"\ud83d\ude00":2,"quote":"\u0022","raw":"\u005c"}
  let expected =
    #|{"\ud83d\ude00":2,"quote":"\u0022","raw":"\u005c"}
  assert_eq(@opgrain.stringify_json(@opgrain.parse_json(wire)), expected)
}
