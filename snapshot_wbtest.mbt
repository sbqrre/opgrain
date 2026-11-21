///|
test "persistent updates share untouched branches and copy their ancestors" {
  let base = Snapshot::new(
    Some(
      parse_json(
        "{\"tasks\":[{\"points\":1},{\"points\":2}],\"metadata\":{\"title\":\"Board\"}}",
      ),
    ),
  )
  let op = Operation::parse("[{\"p\":[\"tasks\",0,\"points\"],\"na\":1}]")
  let next = Engine::new().apply_snapshot(base, op)
  guard base.value is Some(Object(old)) && next.value is Some(Object(new)) else {
    fail("root")
  }
  assert_false(physical_equal(old, new))
  assert_true(same_container(old["metadata"], new["metadata"]))
  guard old["tasks"] is Array(before) && new["tasks"] is Array(after) else {
    fail("tasks")
  }
  assert_false(physical_equal(before, after))
  assert_false(same_container(before[0], after[0]))
  assert_true(same_container(before[1], after[1]))
}

///|
test "revision overflow fails before applying any operation" {
  let journal = Engine::new().journal(Some(Json::number(1)))
  journal.base_revision = 2147483647
  let op = Operation::parse("[{\"p\":[],\"na\":1}]")
  try journal.append(op) catch {
    RevisionOverflow => ()
    error => raise error
  } noraise {
    _ => fail("revision overflow accepted")
  }
  assert_eq(journal.head(), 2147483647)
  assert_eq(journal.snapshot(), Some(Json::number(1)))
  assert_false(journal.busy)
}
