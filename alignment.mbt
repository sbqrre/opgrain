///|
/// A matching pair in two sequences, with indices in their original coordinate systems.
priv struct Anchor {
  before : Int32
  after : Int32
}

///|
priv struct AlignmentBudget {
  mut cells : Int32
}

///|
fn AlignmentBudget::reserve(
  self : AlignmentBudget,
  rows : Int32,
  cols : Int32,
) -> Bool {
  if self.cells <= 0 || rows >= self.cells || cols >= self.cells {
    return false
  }
  let width = cols + 1
  if rows + 1 > self.cells / width {
    return false
  }
  self.cells -= (rows + 1) * width
  true
}

///|
fn lcs_middle(
  before_end : Int32,
  after_end : Int32,
  start : Int32,
  matches : (Int32, Int32) -> Bool,
  budget : AlignmentBudget,
) -> Array[Anchor] {
  let rows = before_end - start
  let cols = after_end - start
  if rows == 0 || cols == 0 || !budget.reserve(rows, cols) {
    return []
  }
  let width = cols + 1
  let scores = Array::make((rows + 1) * width, 0)
  for row = rows - 1; row >= 0; row = row - 1 {
    for col = cols - 1; col >= 0; col = col - 1 {
      let slot = row * width + col
      scores[slot] = if matches(start + row, start + col) {
        1 + scores[slot + width + 1]
      } else {
        Int32::max(scores[slot + width], scores[slot + 1])
      }
    }
  }
  let anchors = []
  let mut row = 0
  let mut col = 0
  while row < rows && col < cols {
    let slot = row * width + col
    if matches(start + row, start + col) {
      anchors.push({ before: start + row, after: start + col, })
      row += 1
      col += 1
    } else if scores[slot + width] >= scores[slot + 1] {
      row += 1
    } else {
      col += 1
    }
  }
  anchors
}

///|
/// Keep identical ends even when the shared LCS budget is exhausted.
fn alignment(
  before_count : Int32,
  after_count : Int32,
  matches : (Int32, Int32) -> Bool,
  budget : AlignmentBudget,
) -> Array[Anchor] {
  let shortest = Int32::min(before_count, after_count)
  let mut prefix = 0
  while prefix < shortest && matches(prefix, prefix) {
    prefix += 1
  }
  let mut suffix = 0
  while suffix < shortest - prefix &&
        matches(before_count - suffix - 1, after_count - suffix - 1) {
    suffix += 1
  }
  let before_end = before_count - suffix
  let after_end = after_count - suffix
  let anchors = lcs_middle(before_end, after_end, prefix, matches, budget)
  // These boundary anchors leave the common prefix and suffix out of edit loops.
  anchors.insert(0, { before: prefix - 1, after: prefix - 1, })
  anchors.push({ before: before_end, after: after_end, })
  anchors
}
