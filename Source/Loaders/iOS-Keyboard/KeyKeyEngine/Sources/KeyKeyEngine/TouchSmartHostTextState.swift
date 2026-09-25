/// Tracks the editable tail after it has been inserted as ordinary host text.
/// Text evicted from the touch window remains in the document and is no longer
/// part of the range replaced by later candidate changes or Backspace.
public struct TouchSmartHostTextState {
    public struct Edit: Equatable {
        public let deleteCount: Int
        public let insertion: String

        public var isEmpty: Bool { deleteCount == 0 && insertion.isEmpty }
    }

    public private(set) var editableText = ""

    public init() {}

    public mutating func update(to newText: String, evictedPrefix: String = "") -> Edit {
        let oldText: String
        let desiredText: String
        if !evictedPrefix.isEmpty, editableText.hasPrefix(evictedPrefix) {
            oldText = String(editableText.dropFirst(evictedPrefix.count))
            desiredText = newText
        } else {
            oldText = editableText
            desiredText = evictedPrefix + newText
        }
        let edit = Self.difference(from: oldText, to: desiredText)
        editableText = newText
        return edit
    }

    public mutating func finish(with text: String) -> Edit {
        let edit = Self.difference(from: editableText, to: text)
        editableText = ""
        return edit
    }

    public mutating func cancel() -> Edit {
        finish(with: "")
    }

    public mutating func reset() {
        editableText = ""
    }

    private static func difference(from oldText: String, to newText: String) -> Edit {
        let shared = zip(oldText, newText).prefix { $0 == $1 }.count
        return Edit(
            deleteCount: oldText.count - shared,
            insertion: String(newText.dropFirst(shared))
        )
    }
}
