///|
/// A checked JSON0 path. Object keys and list indices remain distinct.
#derive(@debug.Debug)
pub struct Path {
  priv segments : Array[PathSegment]
}

///|
pub extend Path with @debug.Debug::{to_repr}

///|
pub fn Path::new(segments : Array[PathSegment]) -> Path raise OpError {
  { segments: checked_path(segments), }
}

///|
pub fn Path::root() -> Path {
  { segments: [], }
}

///|
pub fn Path::from_json(value : Json) -> Path raise OpError {
  { segments: decode_path(value, 0), }
}

///|
pub fn Path::parse(source : String) -> Path raise OpError {
  Path::from_json(parse_json(source))
}

///|
pub fn Path::to_json(self : Path) -> Json {
  encode_path(self.segments)
}

///|
pub fn Path::segments(self : Path) -> Array[PathSegment] {
  self.segments.copy()
}

///|
pub fn Path::length(self : Path) -> Int32 {
  self.segments.length()
}

///|
pub fn Path::is_root(self : Path) -> Bool {
  self.segments.is_empty()
}

///|
pub fn Path::child_key(self : Path, key : String) -> Path {
  { segments: child_path(self.segments, Key(key)), }
}

///|
pub fn Path::child_index(self : Path, index : Int32) -> Path raise OpError {
  guard index >= 0 else {
    raise InvalidPath(self.segments.copy(), "negative child index")
  }
  { segments: child_path(self.segments, Index(index)), }
}

///|
pub fn Path::parent(self : Path) -> Path? {
  if self.is_root() {
    None
  } else {
    Some({ segments: parent_path(self.segments), })
  }
}

///|
pub fn Path::last(self : Path) -> PathSegment? {
  self.segments.last()
}

///|
pub fn Path::starts_with(self : Path, prefix : Path) -> Bool {
  has_prefix(self.segments, prefix.segments)
}

///|
pub fn Path::relative_to(self : Path, prefix : Path) -> Path? {
  if !self.starts_with(prefix) {
    return None
  }
  Some({
    segments: Array::makei(self.length() - prefix.length(), i => {
      self.segments[prefix.length() + i]
    }),
  })
}

///|
pub fn Path::join(self : Path, suffix : Path) -> Path {
  let segments = self.segments.copy()
  for segment in suffix.segments {
    segments.push(segment)
  }
  { segments, }
}

///|
pub fn Path::common_ancestor(self : Path, other : Path) -> Path {
  let mut length = 0
  let maximum = self.length().min(other.length())
  while length < maximum && self.segments[length] == other.segments[length] {
    length += 1
  }
  { segments: Array::makei(length, i => self.segments[i]), }
}

///|
pub fn Path::equal(self : Path, other : Path) -> Bool {
  self.segments == other.segments
}

///|
/// Resolve an existing value and return a detached copy.
pub fn Snapshot::at(self : Snapshot, path : Path) -> Json raise OpError {
  self.read(path.segments)
}

///|
/// Return false for a missing member, absent root, or out-of-range list index.
pub fn Snapshot::contains_path(self : Snapshot, path : Path) -> Bool {
  let mut current = self.value
  for segment in path.segments {
    current = match (current, segment) {
      (Some(Object(fields)), Key(key)) => fields.get(key)
      (Some(Array(items)), Index(index)) =>
        if index >= 0 && index < items.length() {
          Some(items[index])
        } else {
          None
        }
      _ => None
    }
    if current is None {
      return false
    }
  }
  current is Some(_)
}

///|
pub fn Snapshot::member_paths(
  self : Snapshot,
  path : Path,
) -> Array[Path] raise OpError {
  let value = lookup_value(self.value, path.segments, path.length())
  match value {
    Object(fields) => {
      let keys = []
      for key, _ in fields {
        keys.push(key)
      }
      keys.sort()
      keys.map(key => path.child_key(key))
    }
    Array(items) =>
      Array::makei(items.length(), i => {
        segments: child_path(path.segments, Index(i)),
      })
    _ => raise InvalidPath(path.segments.copy(), "value has no child members")
  }
}

///|
pub fn Snapshot::size_at(self : Snapshot, path : Path) -> Int32 raise OpError {
  match lookup_value(self.value, path.segments, path.length()) {
    Object(fields) => fields.length()
    Array(items) => items.length()
    String(text) => text.length()
    _ => raise InvalidPath(path.segments.copy(), "value has no length")
  }
}

///|
/// Find a unique string identity in a list. Duplicate matches are rejected.
pub fn Snapshot::find_identity(
  self : Snapshot,
  path : Path,
  key : String,
  identity : String,
) -> Path? raise OpError {
  let items = require_list(
    lookup_value(self.value, path.segments, path.length()),
    path.segments,
  )
  let mut found = None
  for index, item in items {
    if item is Object(fields) && fields.get(key) == Some(Json::string(identity)) {
      guard found is None else {
        raise InvalidPath(path.segments.copy(), "duplicate list identity")
      }
      found = Some({ segments: child_path(path.segments, Index(index)), })
    }
  }
  found
}
