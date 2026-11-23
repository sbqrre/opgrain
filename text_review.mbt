///|
pub(all) struct TextExcerpt {
  start : Int32
  end : Int32
  text : String
}

///|
pub(all) struct TextChange {
  component : Int32
  offset : Int32
  inserted : String
  deleted : String
  before_position : SourcePosition
  after_position : SourcePosition
  before_context : TextExcerpt
  after_context : TextExcerpt
}

///|
pub struct TextTrace {
  priv before : String
  priv after : String
  priv changes : Array[TextChange]
}

///|
pub fn TextTrace::before(self : TextTrace) -> String {
  self.before
}

///|
pub fn TextTrace::after(self : TextTrace) -> String {
  self.after
}

///|
pub fn TextTrace::changes(self : TextTrace) -> Array[TextChange] {
  self.changes.copy()
}

///|
fn text_excerpt(
  text : String,
  start : Int32,
  length : Int32,
  context : Int32,
) -> TextExcerpt {
  let from = if context > start { 0 } else { start - context }
  let available = text.length() - start - length
  let end = start + length + context.min(available)
  { start: from, end, text: code_slice(text, from, end), }
}

///|
/// Return verified UTF-16 edit details in sequential component coordinates.
/// Context windows may split surrogate pairs; they preserve exact code units.
pub fn TextOperation::trace(
  self : TextOperation,
  source : String,
  context_units~ : Int32 = 20,
) -> TextTrace raise OpError {
  guard context_units >= 0 else { raise InvalidJson("negative text context") }
  let changes = []
  let mut current = source
  for index, edit in self.edits {
    let next = edit_string(current, edit, [])
    let deleted = if edit.insert { "" } else { edit.text }
    let inserted = if edit.insert { edit.text } else { "" }
    let before_position = source_position(current, edit.position)
    let after_position = source_position(next, edit.position)
    changes.push({
      component: index,
      offset: edit.position,
      inserted,
      deleted,
      before_position,
      after_position,
      before_context: text_excerpt(
        current,
        edit.position,
        deleted.length(),
        context_units,
      ),
      after_context: text_excerpt(
        next,
        edit.position,
        inserted.length(),
        context_units,
      ),
    })
    current = next
  }
  { before: source, after: current, changes, }
}

///|
priv struct LineTable {
  lines : Array[String]
  offsets : Array[Int32]
}

///|
fn text_lines(text : String) -> LineTable {
  let lines = []
  let offsets = [0]
  let mut start = 0
  let mut index = 0
  while index < text.length() {
    let unit = text[index].to_int()
    if unit == 13 || unit == 10 {
      index += 1
      if unit == 13 && index < text.length() && text[index].to_int() == 10 {
        index += 1
      }
      lines.push(code_slice(text, start, index))
      offsets.push(index)
      start = index
    } else {
      index += 1
    }
  }
  if start < text.length() {
    lines.push(code_slice(text, start, text.length()))
    offsets.push(text.length())
  }
  { lines, offsets, }
}

///|
pub(all) struct LineDiffOptions {
  alignment_cells : Int32
  text_cells : Int64
  max_units : Int32
}

///|
pub fn LineDiffOptions::default() -> LineDiffOptions {
  { alignment_cells: 1000000, text_cells: 4000000L, max_units: 1000000, }
}

///|
pub(all) struct LineDiffMetrics {
  before_lines : Int32
  after_lines : Int32
  matched_lines : Int32
  refined_regions : Int32
  fallback_regions : Int32
  text_cells : Int64
}

///|
pub struct LineDiff {
  priv operation : TextOperation
  priv metrics : LineDiffMetrics
}

///|
pub fn LineDiff::operation(self : LineDiff) -> TextOperation {
  self.operation
}

///|
pub fn LineDiff::metrics(self : LineDiff) -> LineDiffMetrics {
  self.metrics
}

///|
/// Match whole lines first, retaining CR/LF spelling, then align changed regions
/// by UTF-16 units. All regions share one refinement-cell budget.
pub fn diff_text_lines(
  before : String,
  after : String,
  options~ : LineDiffOptions = LineDiffOptions::default(),
) -> LineDiff raise TextDiffError {
  guard options.alignment_cells >= 0 &&
    options.text_cells >= 0L &&
    options.max_units >= 0 else {
    raise InvalidTextDiffOptions
  }
  for size in [before.length(), after.length()] {
    guard size <= options.max_units else {
      raise TextDiffInputLimit(size, options.max_units)
    }
  }
  let old = text_lines(before)
  let next = text_lines(after)
  let anchors = alignment(
    old.lines.length(),
    next.lines.length(),
    (left, right) => old.lines[left] == next.lines[right],
    { cells: options.alignment_cells, },
  )
  let edits = []
  let mut cells = 0L
  let mut matched_lines = old.lines.length()
  let mut refined_regions = 0
  let mut fallback_regions = 0
  for index in 1..<anchors.length() {
    let previous_anchor = anchors[index - 1]
    let anchor = anchors[index]
    let old_line = previous_anchor.before + 1
    let new_line = previous_anchor.after + 1
    let old_end = anchor.before
    let new_end = anchor.after
    matched_lines -= old_end - old_line
    let old_start_unit = old.offsets[old_line]
    let new_start_unit = next.offsets[new_line]
    let previous = code_slice(before, old_start_unit, old.offsets[old_end])
    let current = code_slice(after, new_start_unit, next.offsets[new_end])
    if previous != current {
      let region = diff_text(previous, current, options={
        max_cells: options.text_cells - cells,
        max_units: options.max_units,
      })
      cells += region.metrics.compared_cells
      if region.metrics.exact_alignment {
        refined_regions += 1
      } else {
        fallback_regions += 1
      }
      for edit in region.operation.edits {
        edits.push({ ..edit, position: edit.position + new_start_unit, })
      }
    }
  }
  {
    operation: { edits, },
    metrics: {
      before_lines: old.lines.length(),
      after_lines: next.lines.length(),
      matched_lines,
      refined_regions,
      fallback_regions,
      text_cells: cells,
    },
  }
}
