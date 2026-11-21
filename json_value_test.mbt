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

///|
test "container checks report the same error as apply" {
  let list = Json::array([])
  let object = Json::object(Map([]))
  @opgrain.check_list(list)
  @opgrain.check_obj(object)
  try @opgrain.check_list(object) catch {
    @opgrain.InvalidPath([], "expected a list") => ()
    _ => fail("wrong list error")
  } noraise {
    _ => fail("expected a type error")
  }
  try @opgrain.check_obj(list) catch {
    @opgrain.InvalidPath([], "expected an object") => ()
    _ => fail("wrong object error")
  } noraise {
    _ => fail("expected a type error")
  }
  let path =
    #|{"items":{}}
  let op =
    #|[{"p":["items",0],"li":true}]
  try
    @opgrain.apply(@opgrain.parse_json(path), @opgrain.Operation::parse(op))
  catch {
    @opgrain.InvalidPath(
      [@opgrain.Key("items"), @opgrain.Index(0)],
      "expected a list",
    ) => ()
    _ => fail("wrong apply error")
  } noraise {
    _ => fail("expected invalid list path")
  }
}
