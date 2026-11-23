///|
pub(all) struct TextDiffOptions {
  max_cells : Int64
  max_units : Int32
}

///|
pub fn TextDiffOptions::default() -> TextDiffOptions {
  { max_cells: 4000000L, max_units: 1000000, }
}

///|
pub(all) struct TextDiffMetrics {
  prefix_units : Int32
  suffix_units : Int32
  matched_units : Int32
  compared_cells : Int64
  exact_alignment : Bool
}

///|
pub struct TextDiff {
  priv operation : TextOperation
  priv metrics : TextDiffMetrics
}

///|
pub fn TextDiff::operation(self : TextDiff) -> TextOperation {
  self.operation
}

///|
pub fn TextDiff::metrics(self : TextDiff) -> TextDiffMetrics {
  self.metrics
}

///|
#derive(@debug.Debug)
pub(all) suberror TextDiffError {
  InvalidTextDiffOptions
  TextDiffInputLimit(Int32, Int32)
}

///|
pub extend TextDiffError with @debug.Debug::{to_repr}

///|
priv struct TextAlignmentBudget {
  maximum : Int64
  mut used : Int64
}

///|
priv struct AlignmentTask {
  old_start : Int32
  old_end : Int32
  new_start : Int32
  new_end : Int32
}

///|
fn alignment_row(
  before : String,
  after : String,
  task : AlignmentTask,
  reverse : Bool,
  budget : TextAlignmentBudget,
) -> Array[Int32]? {
  let width = task.new_end - task.new_start
  let height = task.old_end - task.old_start
  let cells = width.to_int64() * height.to_int64()
  guard cells <= budget.maximum - budget.used else { return None }
  budget.used += cells
  let row = Array::make(width + 1, 0)
  for i in 0..<height {
    let old_index = if reverse {
      task.old_end - i - 1
    } else {
      task.old_start + i
    }
    let mut diagonal = 0
    for j in 0..<width {
      let next = row[j + 1]
      let new_index = if reverse {
        task.new_end - j - 1
      } else {
        task.new_start + j
      }
      row[j + 1] = if before[old_index] == after[new_index] {
        diagonal + 1
      } else {
        row[j].max(next)
      }
      diagonal = next
    }
  }
  Some(row)
}

///|
/// Hirschberg alignment uses linear row storage and an explicit task stack.
fn align_text(
  before : String,
  after : String,
  task : AlignmentTask,
  budget : TextAlignmentBudget,
) -> Array[(Int32, Int32)]? {
  let matches = []
  let pending = [task]
  while pending.pop() is Some(task) {
    if task.old_start == task.old_end || task.new_start == task.new_end {
      continue
    }
    if task.old_end - task.old_start == 1 {
      for index in task.new_start..<task.new_end {
        guard budget.used < budget.maximum else { return None }
        budget.used += 1
        if before[task.old_start] == after[index] {
          matches.push((task.old_start, index))
          break
        }
      }
      continue
    }
    let middle = task.old_start + (task.old_end - task.old_start) / 2
    guard alignment_row(
        before,
        after,
        { ..task, old_end: middle, },
        false,
        budget,
      )
      is Some(front) else {
      return None
    }
    guard alignment_row(
        before,
        after,
        { ..task, old_start: middle, },
        true,
        budget,
      )
      is Some(back) else {
      return None
    }
    let width = task.new_end - task.new_start
    let mut best = -1
    let mut split = 0
    for index in 0..<(width + 1) {
      let score = front[index] + back[width - index]
      if score > best {
        best = score
        split = index
      }
    }
    let new_middle = task.new_start + split
    pending.push({ ..task, old_start: middle, new_start: new_middle, })
    pending.push({ ..task, old_end: middle, new_end: new_middle, })
  }
  Some(matches)
}

///|
fn text_diff_gap(
  edits : Array[TextEdit],
  before : String,
  after : String,
  old_start : Int32,
  old_end : Int32,
  new_start : Int32,
  new_end : Int32,
  position : Int32,
) -> Unit {
  if old_end > old_start {
    edits.push({
      position,
      insert: false,
      text: code_slice(before, old_start, old_end),
    })
  }
  if new_end > new_start {
    edits.push({
      position,
      insert: true,
      text: code_slice(after, new_start, new_end),
    })
  }
}

///|
/// Align UTF-16 units exactly within a cell budget. On exhaustion, replace the
/// unmatched middle. Both paths preserve isolated surrogates and valid JSON0.
pub fn diff_text(
  before : String,
  after : String,
  options~ : TextDiffOptions = TextDiffOptions::default(),
) -> TextDiff raise TextDiffError {
  guard options.max_cells >= 0L && options.max_units >= 0 else {
    raise InvalidTextDiffOptions
  }
  for length in [before.length(), after.length()] {
    guard length <= options.max_units else {
      raise TextDiffInputLimit(length, options.max_units)
    }
  }
  let mut prefix = 0
  let shortest = before.length().min(after.length())
  while prefix < shortest && before[prefix] == after[prefix] {
    prefix += 1
  }
  let mut suffix = 0
  while suffix < shortest - prefix &&
        before[before.length() - suffix - 1] ==
        after[after.length() - suffix - 1] {
    suffix += 1
  }
  let task = AlignmentTask::{
    old_start: prefix,
    old_end: before.length() - suffix,
    new_start: prefix,
    new_end: after.length() - suffix,
  }
  let budget = TextAlignmentBudget::{ maximum: options.max_cells, used: 0L, }
  let aligned = align_text(before, after, task, budget)
  let edits = []
  let mut matched = prefix + suffix
  match aligned {
    None =>
      text_diff_gap(
        edits,
        before,
        after,
        task.old_start,
        task.old_end,
        task.new_start,
        task.new_end,
        prefix,
      )
    Some(matches) => {
      let mut old_start = prefix
      let mut new_start = prefix
      let mut position = prefix
      for (old_index, new_index) in matches {
        text_diff_gap(
          edits, before, after, old_start, old_index, new_start, new_index, position,
        )
        position += new_index - new_start + 1
        old_start = old_index + 1
        new_start = new_index + 1
      }
      text_diff_gap(
        edits,
        before,
        after,
        old_start,
        task.old_end,
        new_start,
        task.new_end,
        position,
      )
      matched += matches.length()
    }
  }
  {
    operation: { edits, },
    metrics: {
      prefix_units: prefix,
      suffix_units: suffix,
      matched_units: matched,
      compared_cells: budget.used,
      exact_alignment: aligned is Some(_),
    },
  }
}
