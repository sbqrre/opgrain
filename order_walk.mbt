///|
fn OrderTree::keys(self : OrderTree) -> Array[String] {
  let output = []
  let stack = []
  let mut cursor = self.root
  while cursor is Some(_) || !stack.is_empty() {
    while cursor is Some(node) {
      stack.push(node)
      cursor = node.left
    }
    let node = stack.pop().unwrap()
    output.push(node.key)
    cursor = node.right
  }
  output
}

///|
fn build_order(
  keys : Array[String],
  start : Int32,
  end : Int32,
  parent : String?,
  nodes : Map[String, OrderNode],
) -> OrderNode? {
  if start == end {
    return None
  }
  let middle = start + (end - start) / 2
  let node = OrderNode::{
    key: keys[middle],
    left: None,
    right: None,
    parent,
    height: 1,
    size: 1,
  }
  nodes[node.key] = node
  node.left = build_order(keys, start, middle, Some(node.key), nodes)
  node.right = build_order(keys, middle + 1, end, Some(node.key), nodes)
  node.refresh()
  Some(node)
}
