///|
test "reject nonfinite values supplied through the Json API" {
  let invalid = Json::array([Json::number(1.0 / 0.0)])
  let empty = @opgrain.Operation::parse("[]")
  let component = Json::object(Map([("p", Json::array([])), ("oi", invalid)]))
  try @opgrain.apply(invalid, empty) catch {
    @opgrain.NonFiniteNumber => ()
    _ => fail("wrong snapshot error")
  } noraise {
    _ => fail("expected invalid snapshot")
  }
  try @opgrain.Component::from_json(component) catch {
    @opgrain.NonFiniteNumber => ()
    _ => fail("wrong payload error")
  } noraise {
    _ => fail("expected invalid payload")
  }
}

///|
test "reject cycles but allow a shared input subtree" {
  let items : Array[Json] = []
  let cyclic = Json::array(items)
  items.push(cyclic)
  try @opgrain.stringify_json(cyclic) catch {
    @opgrain.InvalidJson(_) => ()
    _ => fail("wrong cycle error")
  } noraise {
    _ => fail("expected invalid JSON cycle")
  }
  let child = Json::array([Json::null()])
  let shared = Json::array([child, child])
  assert_eq(@opgrain.stringify_json(shared), "[[null],[null]]")
}
