///|
fn check_order_node(
  node : OrderNode?,
  parent : String?,
) -> (Int32, Int32) raise {
  guard node is Some(node) else { return (0, 0) }
  assert_eq(node.parent, parent)
  let (left_height, left_size) = check_order_node(node.left, Some(node.key))
  let (right_height, right_size) = check_order_node(node.right, Some(node.key))
  assert_true((left_height - right_height).abs() <= 1)
  assert_eq(node.height, 1 + left_height.max(right_height))
  assert_eq(node.size, 1 + left_size + right_size)
  (node.height, node.size)
}

///|
test "order-statistic tree invariants survive seeded removals reinsertion and relocations" {
  let expected = Array::makei(64, index => index.to_string())
  let tree = OrderTree::new(expected)
  let mut random = 1234567U
  for iteration in 0..<1000 {
    random = random * 1664525U + 1013904223U
    let source = (random % expected.length().reinterpret_as_uint()).reinterpret_as_int()
    let key = expected[source]
    random = random * 1664525U + 1013904223U
    let destination = (random % expected.length().reinterpret_as_uint()).reinterpret_as_int()
    if iteration % 3 == 0 {
      assert_eq(tree.remove(key), source)
      tree.insert(destination, key)
    } else {
      assert_eq(tree.relocate(key, destination), source)
    }
    ignore(expected.remove(source))
    expected.insert(destination, key)
    assert_eq(tree.keys(), expected)
    ignore(check_order_node(tree.root, None))
    for index, key in expected {
      assert_eq(tree.rank(key), index)
    }
  }
}
