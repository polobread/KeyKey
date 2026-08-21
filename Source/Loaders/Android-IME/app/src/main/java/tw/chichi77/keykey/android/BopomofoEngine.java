package tw.chichi77.keykey.android;

import java.util.List;

final class BopomofoEngine {
    static final int CANDIDATES_PER_PAGE = 9;
    private static final List<String> SYMBOLS =
            List.of("，", "。", "、", "？", "！", "：", "；", "「", "」", "…");
    private static final List<String> EMOJIS = List.of(
            "😀", "😃", "😄", "😁", "😆", "😅", "😂", "😊", "😍",
            "🥰", "😘", "😎", "🤩", "🥳", "🙂", "😉", "😋", "🤔",
            "😭", "😢", "😡", "😱", "😴", "🤢", "🤮", "🥺", "🤣",
            "👍", "👎", "👌", "✌️", "🤞", "👏", "🙏", "💪", "👋",
            "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "💯", "🎉");

    static final class Result {
        private final String committedText;
        private final boolean deleteBeforeCursor;
        private final boolean sendEnter;

        Result(String committedText, boolean deleteBeforeCursor, boolean sendEnter) {
            this.committedText = committedText;
            this.deleteBeforeCursor = deleteBeforeCursor;
            this.sendEnter = sendEnter;
        }

        String committedText() { return committedText; }
        boolean deleteBeforeCursor() { return deleteBeforeCursor; }
        boolean sendEnter() { return sendEnter; }

        static Result update() { return new Result("", false, false); }
        static Result commit(String text) { return new Result(text, false, false); }
        static Result delete() { return new Result("", true, false); }
        static Result enter() { return new Result("", false, true); }
    }

    private final CinDictionary dictionary;
    private final BopomofoReading reading = new BopomofoReading();
    private List<String> candidates = List.of();
    private int page;
    private boolean englishMode;
    private boolean shifted;

    BopomofoEngine(CinDictionary dictionary) {
        this.dictionary = dictionary;
    }

    Result handleSoftKey(String key) {
        return switch (key) {
            case "MODE" -> toggleLanguage();
            case "SHIFT" -> toggleShift();
            case "BACKSPACE" -> backspace();
            case "SPACE" -> space();
            case "ENTER" -> enter();
            case "ESCAPE" -> escape();
            case "SYMBOL" -> symbols();
            case "EMOJI" -> emojis();
            default -> key.length() == 1 ? character(key.charAt(0)) : Result.update();
        };
    }

    Result handleHardwareCharacter(char key) {
        return character(key);
    }

    Result space() {
        if (!candidates.isEmpty()) {
            changePage(1);
            return Result.update();
        }
        if (englishMode || reading.isEmpty()) return Result.commit(" ");
        return query();
    }

    Result enter() {
        if (!candidates.isEmpty()) return selectDisplayedCandidate(0);
        if (!reading.isEmpty()) return query();
        return Result.enter();
    }

    Result backspace() {
        if (!candidates.isEmpty()) candidates = List.of();
        if (!reading.isEmpty()) {
            reading.backspace();
            page = 0;
            return Result.update();
        }
        return Result.delete();
    }

    Result escape() {
        clearComposition();
        return Result.update();
    }

    Result selectDisplayedCandidate(int displayedIndex) {
        int absoluteIndex = page * CANDIDATES_PER_PAGE + displayedIndex;
        if (absoluteIndex < 0 || absoluteIndex >= candidates.size()) return Result.update();
        String selected = candidates.get(absoluteIndex);
        clearComposition();
        return Result.commit(selected);
    }

    void changePage(int delta) {
        int pages = pageCount();
        if (pages == 0) {
            page = 0;
            return;
        }
        page = Math.floorMod(page + delta, pages);
    }

    void reset() {
        clearComposition();
        shifted = false;
    }

    String readingText() {
        return reading.displayText();
    }

    List<String> displayedCandidates() {
        int start = page * CANDIDATES_PER_PAGE;
        if (start >= candidates.size()) return List.of();
        return candidates.subList(start, Math.min(candidates.size(), start + CANDIDATES_PER_PAGE));
    }

    int page() {
        return page;
    }

    int pageCount() {
        return (candidates.size() + CANDIDATES_PER_PAGE - 1) / CANDIDATES_PER_PAGE;
    }

    boolean isEnglishMode() {
        return englishMode;
    }

    boolean isShifted() {
        return shifted;
    }

    private Result character(char rawKey) {
        char key = Character.toLowerCase(rawKey);
        if (englishMode) {
            char output = shifted ? Character.toUpperCase(rawKey) : rawKey;
            shifted = false;
            return Result.commit(String.valueOf(output));
        }

        if (!candidates.isEmpty() && key >= '1' && key <= '9') {
            return selectDisplayedCandidate(key - '1');
        }

        if (BopomofoReading.isBopomofoKey(key)) {
            String prefix = commitFirstCandidateIfNeeded();
            reading.combine(key);
            Result result = reading.hasTone() ? query() : Result.update();
            if (!prefix.isEmpty()) {
                return new Result(prefix + result.committedText(), false, false);
            }
            return result;
        }

        if (!reading.isEmpty()) return Result.update();
        if (!candidates.isEmpty()) {
            String prefix = commitFirstCandidateIfNeeded();
            return Result.commit(prefix + rawKey);
        }
        return Result.commit(String.valueOf(rawKey));
    }

    private Result query() {
        candidates = dictionary.candidates(reading.queryKey());
        page = 0;
        if (candidates.size() == 1) {
            String only = candidates.get(0);
            clearComposition();
            return Result.commit(only);
        }
        return Result.update();
    }

    private String commitFirstCandidateIfNeeded() {
        if (candidates.isEmpty()) return "";
        String first = candidates.get(page * CANDIDATES_PER_PAGE);
        clearComposition();
        return first;
    }

    private Result toggleLanguage() {
        clearComposition();
        englishMode = !englishMode;
        shifted = false;
        return Result.update();
    }

    private Result toggleShift() {
        shifted = !shifted;
        return Result.update();
    }

    private Result commitLiteral(String text) {
        String prefix = commitFirstCandidateIfNeeded();
        if (!reading.isEmpty()) return Result.update();
        return Result.commit(prefix + text);
    }

    private Result symbols() {
        clearComposition();
        candidates = SYMBOLS;
        return Result.update();
    }

    private Result emojis() {
        clearComposition();
        candidates = EMOJIS;
        return Result.update();
    }

    private void clearComposition() {
        reading.clear();
        candidates = List.of();
        page = 0;
    }
}
