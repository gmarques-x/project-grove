/// What to do when a name already exists where an item is going.
public enum Conflict {
    public enum Choice: Equatable, Sendable { case replace, keepBoth, skip }
}
