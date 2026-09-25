package tw.chichi77.keykey.android;

/** The committed host-text suffix that touch Smart Mandarin may still change. */
final class TouchSmartHostTextState {
    record Edit(int deleteCount, String insertion) {
        boolean isEmpty() { return deleteCount == 0 && insertion.isEmpty(); }
    }

    private String editableText = "";

    String editableText() { return editableText; }

    Edit update(String newText, String evictedPrefix) {
        String oldText;
        String desiredText;
        if (!evictedPrefix.isEmpty() && editableText.startsWith(evictedPrefix)) {
            oldText = editableText.substring(evictedPrefix.length());
            desiredText = newText;
        } else {
            oldText = editableText;
            desiredText = evictedPrefix + newText;
        }
        Edit edit = difference(oldText, desiredText);
        editableText = newText;
        return edit;
    }

    Edit finish(String text) {
        Edit edit = difference(editableText, text);
        editableText = "";
        return edit;
    }

    Edit cancel() { return finish(""); }

    void reset() { editableText = ""; }

    private static Edit difference(String oldText, String newText) {
        int oldEnd = 0;
        int newEnd = 0;
        while (oldEnd < oldText.length() && newEnd < newText.length()) {
            int oldCodePoint = oldText.codePointAt(oldEnd);
            int newCodePoint = newText.codePointAt(newEnd);
            if (oldCodePoint != newCodePoint) break;
            oldEnd += Character.charCount(oldCodePoint);
            newEnd += Character.charCount(newCodePoint);
        }
        return new Edit(oldText.length() - oldEnd, newText.substring(newEnd));
    }
}
