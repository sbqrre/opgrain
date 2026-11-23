///|
priv struct OrderNode {
  key : String
  mut left : OrderNode?
  mut right : OrderNode?
  mut parent : String?
  mut height : Int32
  mut size : Int32
}

///|
priv struct OrderTree {
  mut root : OrderNode?
  nodes : Map[String, OrderNode]
}

///|
fn order_height(node : OrderNode?) -> Int32 {
  match node {
    Some(node) => node.height
    None => 0
  }
}

///|
fn order_size(node : OrderNode?) -> Int32 {
  match node {
    Some(node) => node.size
    None => 0
  }
}

///|
fn OrderNode::refresh(self : OrderNode) -> Unit {
  self.height = 1 + order_height(self.left).max(order_height(self.right))
  self.size = 1 + order_size(self.left) + order_size(self.right)
}

///|
fn OrderNode::attach_left(self : OrderNode, node : OrderNode?) -> Unit {
  self.left = node
  if node is Some(node) {
    node.parent = Some(self.key)
  }
}

///|
fn OrderNode::attach_right(self : OrderNode, node : OrderNode?) -> Unit {
  self.right = node
  if node is Some(node) {
    node.parent = Some(self.key)
  }
}

///|
fn rotate_order_left(node : OrderNode) -> OrderNode {
  let promoted = node.right.unwrap()
  let parent = node.parent
  node.attach_right(promoted.left)
  promoted.attach_left(Some(node))
  promoted.parent = parent
  node.refresh()
  promoted.refresh()
  promoted
}

///|
fn rotate_order_right(node : OrderNode) -> OrderNode {
  let promoted = node.left.unwrap()
  let parent = node.parent
  node.attach_left(promoted.right)
  promoted.attach_right(Some(node))
  promoted.parent = parent
  node.refresh()
  promoted.refresh()
  promoted
}

///|
fn balance_order(node : OrderNode) -> OrderNode {
  node.refresh()
  let balance = order_height(node.left) - order_height(node.right)
  if balance > 1 {
    let left = node.left.unwrap()
    if order_height(left.left) < order_height(left.right) {
      node.attach_left(Some(rotate_order_left(left)))
    }
    rotate_order_right(node)
  } else if balance < -1 {
    let right = node.right.unwrap()
    if order_height(right.right) < order_height(right.left) {
      node.attach_right(Some(rotate_order_right(right)))
    }
    rotate_order_left(node)
  } else {
    node
  }
}

///|
fn insert_order(root : OrderNode?, rank : Int32, node : OrderNode) -> OrderNode {
  guard root is Some(root) else { return node }
  let left_size = order_size(root.left)
  if rank <= left_size {
    root.attach_left(Some(insert_order(root.left, rank, node)))
  } else {
    root.attach_right(
      Some(insert_order(root.right, rank - left_size - 1, node)),
    )
  }
  balance_order(root)
}

///|
fn take_order_min(root : OrderNode) -> (OrderNode?, OrderNode) {
  guard root.left is Some(left) else {
    let replacement = root.right
    if replacement is Some(node) {
      node.parent = root.parent
    }
    root.left = None
    root.right = None
    root.parent = None
    root.refresh()
    return (replacement, root)
  }
  let (remaining, minimum) = take_order_min(left)
  root.attach_left(remaining)
  (Some(balance_order(root)), minimum)
}

///|
fn remove_order(root : OrderNode, rank : Int32) -> (OrderNode?, OrderNode) {
  let left_size = order_size(root.left)
  if rank < left_size {
    let (remaining, removed) = remove_order(root.left.unwrap(), rank)
    root.attach_left(remaining)
    return (Some(balance_order(root)), removed)
  }
  if rank > left_size {
    let (remaining, removed) = remove_order(
      root.right.unwrap(),
      rank - left_size - 1,
    )
    root.attach_right(remaining)
    return (Some(balance_order(root)), removed)
  }
  let parent = root.parent
  let replacement = match (root.left, root.right) {
    (None, right) => right
    (left, None) => left
    (left, Some(right)) => {
      let (remaining, next) = take_order_min(right)
      next.attach_left(left)
      next.attach_right(remaining)
      Some(balance_order(next))
    }
  }
  if replacement is Some(node) {
    node.parent = parent
  }
  root.left = None
  root.right = None
  root.parent = None
  root.refresh()
  (replacement, root)
}

///|
fn OrderTree::new(keys : Array[String]) -> OrderTree {
  let nodes = Map([])
  let root = build_order(keys, 0, keys.length(), None, nodes)
  { root, nodes, }
}

///|
fn OrderTree::insert(self : OrderTree, rank : Int32, key : String) -> Unit {
  let node = OrderNode::{
    key,
    left: None,
    right: None,
    parent: None,
    height: 1,
    size: 1,
  }
  let root = insert_order(self.root, rank, node)
  root.parent = None
  self.root = Some(root)
  self.nodes[key] = node
}

///|
fn OrderTree::rank(self : OrderTree, key : String) -> Int32 {
  let mut node = self.nodes.get(key).unwrap()
  let mut rank = order_size(node.left)
  while node.parent is Some(parent_key) {
    let parent = self.nodes.get(parent_key).unwrap()
    if parent.right is Some(right) && physical_equal(right, node) {
      rank += 1 + order_size(parent.left)
    }
    node = parent
  }
  rank
}

///|
fn OrderTree::remove(self : OrderTree, key : String) -> Int32 {
  let rank = self.rank(key)
  let (root, _) = remove_order(self.root.unwrap(), rank)
  self.root = root
  if root is Some(node) {
    node.parent = None
  }
  self.nodes.remove(key)
  rank
}

///|
fn OrderTree::relocate(
  self : OrderTree,
  key : String,
  destination : Int32,
) -> Int32 {
  let rank = self.rank(key)
  let (root, node) = remove_order(self.root.unwrap(), rank)
  self.root = root
  if root is Some(node) {
    node.parent = None
  }
  let next = insert_order(self.root, destination, node)
  next.parent = None
  self.root = Some(next)
  rank
}

///|
/// Return a deterministic longest increasing subsequence of retained identifiers.
fn retained_order(
  before : Array[String],
  after : Array[String],
) -> Map[String, Bool] {
  let positions : Map[String, Int32] = Map([])
  for index, key in before {
    positions[key] = index
  }
  let keys = after.filter(key => positions.contains(key))
  let tails : Array[Int32] = []
  let previous = Array::make(keys.length(), -1)
  for index, key in keys {
    let rank = positions.get(key).unwrap()
    let mut low = 0
    let mut high = tails.length()
    while low < high {
      let middle = low + (high - low) / 2
      if positions.get(keys[tails[middle]]).unwrap() < rank {
        low = middle + 1
      } else {
        high = middle
      }
    }
    if low > 0 {
      previous[index] = tails[low - 1]
    }
    if low == tails.length() {
      tails.push(index)
    } else {
      tails[low] = index
    }
  }
  let retained : Map[String, Bool] = Map([])
  let mut cursor = tails.last().unwrap_or(-1)
  while cursor >= 0 {
    retained[keys[cursor]] = true
    cursor = previous[cursor]
  }
  retained
}
