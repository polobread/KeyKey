package tw.chichi77.keykey.android;

import java.util.List;

final class BopomofoEngine {
    static final int CANDIDATES_PER_PAGE = 9;
    enum InputMode { BOPOMOFO, ENGLISH, NUMBER }
    private static final List<String> SYMBOLS = List.of(
            "，", "。", "、", "？", "！", "：", "；", "「", "」",
            "『", "』", "（", "）", "【", "】", "〔", "〕", "…",
            "—", "～", "·", "‧", "‥", "※", "＊", "＃", "＠",
            "＆", "％", "＋", "－", "×", "÷", "＝", "≠", "±",
            "＜", "＞", "≤", "≥", "≈", "∞", "√", "∑", "∫",
            "°", "℃", "℉", "㎜", "㎝", "㎞", "㎎", "㎏", "㎡",
            "＄", "￠", "￡", "￥", "€", "₩", "₹", "₽", "¢",
            "←", "→", "↑", "↓", "↔", "↕", "↖", "↗", "↘",
            "↙", "⇒", "⇔", "✓", "✔", "✕", "✖", "★", "☆",
            "●", "○", "■", "□", "▲", "△", "▼", "▽", "◆");
    private static final List<String> EMOJIS = List.of(
            "😀", "😃", "😄", "😁", "😆", "😅", "😂", "😊", "😍",
            "🥰", "😘", "😎", "🤩", "🥳", "🙂", "😉", "😋", "🤔",
            "😭", "😢", "😡", "😱", "😴", "🤢", "🤮", "🥺", "🤣",
            "👍", "👎", "👌", "✌️", "🤞", "👏", "🙏", "💪", "👋",
            "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "💯", "🎉",
            "🍎", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐", "🍒",
            "🍔", "🍟", "🍕", "🌭", "🍿", "🍩", "🍪", "🎂", "☕",
            "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨",
            "🌞", "🌙", "⭐", "🌈", "🔥", "💧", "🌸", "🌹", "🍀",
            "🚗", "🚌", "🚆", "✈️", "🚀", "🏠", "🎁", "🎈", "🔔");

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
    private AssociatedPhraseDictionary associatedPhrases = AssociatedPhraseDictionary.empty();
    private List<String> candidates = List.of();
    private int page;
    private int highlightedIndex;
    private InputMode inputMode = InputMode.BOPOMOFO;
    private boolean shifted;
    private boolean temporaryEnglish;
    private boolean showingAssociatedPhrases;

    BopomofoEngine(CinDictionary dictionary) {
        this.dictionary = dictionary;
    }

    void setAssociatedPhraseDictionary(AssociatedPhraseDictionary dictionary) {
        associatedPhrases = dictionary == null ? AssociatedPhraseDictionary.empty() : dictionary;
        if (showingAssociatedPhrases) clearComposition();
    }

    Result handleSoftKey(String key) {
        boolean restoreBopomofo = temporaryEnglish
                && !key.equals("SHIFT") && !key.equals("MODE");
        Result result = switch (key) {
            case "MODE" -> cycleInputMode();
            case "SHIFT" -> touchShift();
            case "BACKSPACE" -> backspace();
            case "SPACE" -> space();
            case "ENTER" -> enter();
            case "ESCAPE" -> escape();
            case "SYMBOL" -> symbols();
            case "EMOJI" -> emojis();
            default -> key.length() == 1 ? character(key.charAt(0), true) : Result.update();
        };
        if (restoreBopomofo) endTemporaryEnglish();
        return result;
    }

    Result handleHardwareCharacter(char key) {
        prepareForHardwareInput();
        return character(key, false);
    }

    Result toggleHardwareLanguage() {
        prepareForHardwareInput();
        clearComposition();
        inputMode = inputMode == InputMode.BOPOMOFO
                ? InputMode.ENGLISH : InputMode.BOPOMOFO;
        shifted = false;
        return Result.update();
    }

    Result commitHardwarePunctuation(String punctuation) {
        prepareForHardwareInput();
        if (!reading.isEmpty()) return Result.update();
        clearComposition();
        return Result.commit(punctuation);
    }

    Result showHardwareSymbols() {
        prepareForHardwareInput();
        if (!reading.isEmpty()) return Result.update();
        return symbols();
    }

    void prepareForHardwareInput() {
        if (temporaryEnglish) endTemporaryEnglish();
    }

    Result space() {
        if (!candidates.isEmpty()) {
            changePage(1);
            return Result.update();
        }
        if (inputMode != InputMode.BOPOMOFO || reading.isEmpty()) return Result.commit(" ");
        return query();
    }

    Result enter() {
        if (!candidates.isEmpty()) return selectHighlightedCandidate();
        if (!reading.isEmpty()) return query();
        return Result.enter();
    }

    Result backspace() {
        if (!candidates.isEmpty()) {
            candidates = List.of();
            showingAssociatedPhrases = false;
            highlightedIndex = 0;
        }
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
        if (showingAssociatedPhrases) {
            clearComposition();
            return Result.commit(selected);
        }
        return commitPrimaryCandidate(selected, true);
    }

    Result selectHighlightedCandidate() {
        return selectDisplayedCandidate(highlightedIndex);
    }

    void moveHighlight(int delta) {
        if (candidates.isEmpty() || delta == 0) return;
        int absoluteIndex = page * CANDIDATES_PER_PAGE + highlightedIndex;
        int nextIndex = Math.floorMod(absoluteIndex + delta, candidates.size());
        page = nextIndex / CANDIDATES_PER_PAGE;
        highlightedIndex = nextIndex % CANDIDATES_PER_PAGE;
    }

    private Result commitPrimaryCandidate(String selected, boolean showAssociatedPhrases) {
        clearComposition();
        if (showAssociatedPhrases) {
            candidates = associatedPhrases.candidates(selected);
            this.showingAssociatedPhrases = !candidates.isEmpty();
        }
        return Result.commit(selected);
    }

    void changePage(int delta) {
        int pages = pageCount();
        if (pages == 0) {
            page = 0;
            highlightedIndex = 0;
            return;
        }
        page = Math.floorMod(page + delta, pages);
        highlightedIndex = 0;
    }

    void reset() {
        clearComposition();
        if (temporaryEnglish) inputMode = InputMode.BOPOMOFO;
        temporaryEnglish = false;
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

    int highlightedIndex() {
        int displayedCount = displayedCandidates().size();
        return displayedCount == 0 ? -1 : Math.min(highlightedIndex, displayedCount - 1);
    }

    boolean isEnglishMode() {
        return inputMode == InputMode.ENGLISH;
    }

    InputMode inputMode() {
        return inputMode;
    }

    boolean isShifted() {
        return shifted;
    }

    boolean isTemporaryEnglish() {
        return temporaryEnglish;
    }

    boolean isShowingAssociatedPhrases() {
        return showingAssociatedPhrases;
    }

    private Result character(char rawKey, boolean fromTouch) {
        char key = Character.toLowerCase(rawKey);
        if (inputMode == InputMode.ENGLISH) {
            char output = fromTouch && shifted && Character.isLetter(rawKey)
                    ? Character.toUpperCase(rawKey) : rawKey;
            return Result.commit(String.valueOf(output));
        }
        if (inputMode == InputMode.NUMBER) return Result.commit(String.valueOf(rawKey));

        if (!fromTouch && !showingAssociatedPhrases
                && !candidates.isEmpty() && key >= '1' && key <= '9') {
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
        showingAssociatedPhrases = false;
        page = 0;
        highlightedIndex = 0;
        if (candidates.size() == 1) {
            String only = candidates.get(0);
            return commitPrimaryCandidate(only, true);
        }
        return Result.update();
    }

    private String commitFirstCandidateIfNeeded() {
        if (candidates.isEmpty()) return "";
        if (showingAssociatedPhrases) {
            clearComposition();
            return "";
        }
        String first = candidates.get(page * CANDIDATES_PER_PAGE);
        clearComposition();
        return first;
    }

    private Result cycleInputMode() {
        clearComposition();
        if (temporaryEnglish) {
            temporaryEnglish = false;
            shifted = false;
            return Result.update();
        }
        inputMode = switch (inputMode) {
            case BOPOMOFO -> InputMode.ENGLISH;
            case ENGLISH -> InputMode.NUMBER;
            case NUMBER -> InputMode.BOPOMOFO;
        };
        shifted = false;
        return Result.update();
    }

    private Result touchShift() {
        clearComposition();
        if (temporaryEnglish) {
            endTemporaryEnglish();
        } else if (inputMode == InputMode.BOPOMOFO) {
            inputMode = InputMode.ENGLISH;
            temporaryEnglish = true;
            shifted = false;
        } else if (inputMode == InputMode.ENGLISH) {
            shifted = !shifted;
        } else {
            shifted = !shifted;
        }
        return Result.update();
    }

    private void endTemporaryEnglish() {
        inputMode = InputMode.BOPOMOFO;
        temporaryEnglish = false;
        shifted = false;
    }

    private Result symbols() {
        clearComposition();
        candidates = SYMBOLS;
        showingAssociatedPhrases = false;
        highlightedIndex = 0;
        return Result.update();
    }

    private Result emojis() {
        clearComposition();
        candidates = EMOJIS;
        showingAssociatedPhrases = false;
        highlightedIndex = 0;
        return Result.update();
    }

    private void clearComposition() {
        reading.clear();
        candidates = List.of();
        page = 0;
        highlightedIndex = 0;
        showingAssociatedPhrases = false;
    }
}
