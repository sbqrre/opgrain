///|
pub(all) struct ListDiffMetrics {
  retained : Int32
  inserted : Int32
  deleted : Int32
  moved : Int32
  changed_items : Int32
}

///|
pub struct ListDiff {
  priv operation : Operation
  priv metrics : ListDiffMetrics
}

///|
pub fn ListDiff::operation(self : ListDiff) -> Operation {
  self.operation
}

///|
pub fn ListDiff::metrics(self : ListDiff) -> ListDiffMetrics {
  self.metrics
}

///|
/// Generate keyed-list edits without materializing a document after each move.
/// Unique string identifiers are required on both sides.
pub fn Engine::diff_keyed_list(
  self : Engine,
  before : Array[Json],
  after : Array[Json],
  key : String,
  path~ : Array[PathSegment] = [],
  options~ : DiffOptions = DiffOptions::default(),
) -> ListDiff raise OpError {
  let path = checked_path(path)
  let before = copy_checked_json(Json::array(before))
  let after = copy_checked_json(Json::array(after))
  guard before is Array(before) && after is Array(after) else {
    abort("array copy")
  }
  guard list_identity(before, key) is Some(previous) &&
    list_identity(after, key) is Some(next) else {
    raise InvalidPath(path, "keyed lists require unique string identifiers")
  }
  let tree = OrderTree::new(previous.order)
  let components = []
  let mut deleted = 0
  for offset in 0..<previous.order.length() {
    let index = previous.order.length() - offset - 1
    let id = previous.order[index]
    if !next.items.contains(id) {
      let at = tree.remove(id)
      components.push(Component::{
        path: child_path(path, Index(at)),
        action: ListEdit(None, previous.items.get(id)),
      })
      deleted += 1
    }
  }
  let surviving = previous.order.filter(id => next.items.contains(id))
  let keep = retained_order(surviving, next.order)
  let mut anchor : String? = None
  let mut inserted = 0
  let mut moved = 0
  for offset in 0..<next.order.length() {
    let id = next.order[next.order.length() - offset - 1]
    if !previous.items.contains(id) {
      let destination = match anchor {
        Some(anchor) => tree.rank(anchor)
        None => order_size(tree.root)
      }
      tree.insert(destination, id)
      components.push({
        path: child_path(path, Index(destination)),
        action: ListEdit(next.items.get(id), None),
      })
      inserted += 1
    } else if !keep.contains(id) {
      let source = tree.rank(id)
      let destination = match anchor {
        Some(anchor) => {
          let rank = tree.rank(anchor)
          if source < rank {
            rank - 1
          } else {
            rank
          }
        }
        None => order_size(tree.root) - 1
      }
      if source != destination {
        ignore(tree.relocate(id, destination))

        components.push({
          path: child_path(path, Index(source)),
          action: Move(destination),
        })
        moved += 1
      }
    }
    anchor = Some(id)
  }
  guard tree.keys() == next.order else {
    raise InvalidJson("indexed list reconciliation produced inconsistent order")
  }
  let mut changed_items = 0
  for index, id in next.order {
    if previous.items.get(id) is Some(old) &&
      next.items.get(id) is Some(value) &&
      old != value {
      let operation = self.diff(Some(old), Some(value), options~)
      let prefix = child_path(path, Index(index))
      for component in operation.with_prefix(prefix).components {
        components.push(component)
      }
      changed_items += 1
    }
  }
  {
    operation: { components, },
    metrics: {
      retained: keep.length(),
      inserted,
      deleted,
      moved,
      changed_items,
    },
  }
}

///|
/// Generate a keyed-list edit selected from an immutable document.
pub fn Engine::diff_keyed_subtree(
  self : Engine,
  snapshot : Snapshot,
  path : Path,
  target : Array[Json],
  key : String,
  options~ : DiffOptions = DiffOptions::default(),
) -> ListDiff raise OpError {
  guard lookup_value(snapshot.value, path.segments, path.length())
    is Array(before) else {
    raise InvalidPath(path.segments(), "keyed diff requires a list")
  }
  self.diff_keyed_list(before, target, key, path=path.segments, options~)
}
