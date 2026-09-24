package tw.chichi77.keykey.android;

import java.util.ArrayList;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

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
        private final boolean discardComposingText;

        Result(String committedText, boolean deleteBeforeCursor, boolean sendEnter,
                boolean discardComposingText) {
            this.committedText = committedText;
            this.deleteBeforeCursor = deleteBeforeCursor;
            this.sendEnter = sendEnter;
            this.discardComposingText = discardComposingText;
        }

        String committedText() { return committedText; }
        boolean deleteBeforeCursor() { return deleteBeforeCursor; }
        boolean sendEnter() { return sendEnter; }
        boolean discardComposingText() { return discardComposingText; }

        static Result update() { return new Result("", false, false, false); }
        static Result commit(String text) { return new Result(text, false, false, false); }
        static Result delete() { return new Result("", true, false, false); }
        static Result enter() { return new Result("", false, true, false); }
        static Result discardComposition() { return new Result("", false, false, true); }
    }

    private final CinDictionary dictionary;
    private final SmartMandarinSource smartSource;
    private final BopomofoReading reading = new BopomofoReading();
    private AssociatedPhraseDictionary associatedPhrases = AssociatedPhraseDictionary.empty();
    private List<String> candidates = List.of();
    private int page;
    private int highlightedIndex;
    private InputMode inputMode = InputMode.BOPOMOFO;
    private boolean shifted;
    private boolean temporaryEnglish;
    private boolean showingAssociatedPhrases;
    private boolean hardwareFullWidth;
    private EnumSet<InputMode> allowedInputModes = EnumSet.allOf(InputMode.class);
    private BopomofoCompositionMode compositionMode;
    private final List<String> smartReadings = new ArrayList<>();
    private SmartMandarinComposition smartComposition;
    private final Map<Integer, String> smartOverrides = new HashMap<>();
    private boolean showingSmartCandidates;

    BopomofoEngine(CinDictionary dictionary) {
        this(dictionary, null, BopomofoCompositionMode.TRADITIONAL);
    }

    BopomofoEngine(CinDictionary dictionary, SmartMandarinSource smartSource,
                   BopomofoCompositionMode compositionMode) {
        this.dictionary = dictionary;
        this.smartSource = smartSource;
        this.compositionMode = smartSource == null
                ? BopomofoCompositionMode.TRADITIONAL : compositionMode;
    }

    Result setCompositionMode(BopomofoCompositionMode mode) {
        if (mode == compositionMode) return Result.update();
        Result result = finishCompositionForModeSwitch();
        compositionMode = mode == BopomofoCompositionMode.SMART && smartSource == null
                ? BopomofoCompositionMode.TRADITIONAL : mode;
        return result;
    }

    void setAssociatedPhraseDictionary(AssociatedPhraseDictionary dictionary) {
        associatedPhrases = dictionary == null ? AssociatedPhraseDictionary.empty() : dictionary;
        if (showingAssociatedPhrases) clearComposition();
    }

    void setAllowedInputModes(Set<InputMode> allowed, InputMode preferred) {
        setAllowedInputModes(allowed, preferred, false);
    }

    void setAllowedInputModes(Set<InputMode> allowed, InputMode preferred,
                              boolean selectPreferred) {
        EnumSet<InputMode> next = allowed == null || allowed.isEmpty()
                ? EnumSet.allOf(InputMode.class) : EnumSet.copyOf(allowed);
        allowedInputModes = next;
        if (temporaryEnglish && !next.contains(InputMode.BOPOMOFO)) {
            temporaryEnglish = false;
        }
        if (selectPreferred || !next.contains(inputMode)) {
            clearComposition();
            inputMode = next.contains(preferred) ? preferred : next.iterator().next();
            shifted = false;
            temporaryEnglish = false;
        }
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
        return applyHardwareWidth(character(key, false));
    }

    Result handleHardwareSpace() {
        prepareForHardwareInput();
        return applyHardwareWidth(space());
    }

    Result toggleHardwareLanguage() {
        prepareForHardwareInput();
        Result result = finishCompositionForModeSwitch();
        inputMode = inputMode == InputMode.BOPOMOFO
                ? InputMode.ENGLISH : InputMode.BOPOMOFO;
        shifted = false;
        return result;
    }

    Result toggleHardwareWidth() {
        prepareForHardwareInput();
        hardwareFullWidth = !hardwareFullWidth;
        return Result.update();
    }

    Result commitHardwarePunctuation(String punctuation) {
        prepareForHardwareInput();
        if (!reading.isEmpty() && compositionMode != BopomofoCompositionMode.SMART) {
            return Result.update();
        }
        return Result.commit(finishCompositionForModeSwitch().committedText() + punctuation);
    }

    Result showHardwareSymbols() {
        prepareForHardwareInput();
        if (!reading.isEmpty() && compositionMode != BopomofoCompositionMode.SMART) {
            return Result.update();
        }
        return symbols();
    }

    void prepareForHardwareInput() {
        if (temporaryEnglish) endTemporaryEnglish();
    }

    Result space() {
        if (compositionMode == BopomofoCompositionMode.SMART
                && inputMode == InputMode.BOPOMOFO) {
            if (!reading.isEmpty()) return finishSmartReading();
            if (!smartReadings.isEmpty()) {
                changePage(1);
                return Result.update();
            }
        }
        if (!candidates.isEmpty()) {
            changePage(1);
            return Result.update();
        }
        if (inputMode != InputMode.BOPOMOFO || reading.isEmpty()) return Result.commit(" ");
        return query();
    }

    Result enter() {
        if (showingAssociatedPhrases) {
            clearComposition();
            return Result.enter();
        }
        if (compositionMode == BopomofoCompositionMode.SMART
                && inputMode == InputMode.BOPOMOFO && hasComposition()) {
            if (!reading.isEmpty()) {
                Result result = finishSmartReading();
                if (!reading.isEmpty()) return result;
            }
            return commitSmartComposition();
        }
        if (!candidates.isEmpty()) return selectHighlightedCandidate();
        if (!reading.isEmpty()) return query();
        return Result.enter();
    }

    Result backspace() {
        if (compositionMode == BopomofoCompositionMode.SMART
                && inputMode == InputMode.BOPOMOFO) {
            if (!reading.isEmpty()) {
                reading.backspace();
                candidates = List.of();
                showingSmartCandidates = false;
                page = 0;
                return Result.update();
            }
            if (!smartReadings.isEmpty()) {
                smartReadings.remove(smartReadings.size() - 1);
                smartOverrides.keySet().removeIf(index -> index >= smartReadings.size());
                rebuildSmartComposition();
                return smartReadings.isEmpty()
                        ? Result.discardComposition() : Result.update();
            }
        }
        if (!candidates.isEmpty()) {
            candidates = List.of();
            showingAssociatedPhrases = false;
            highlightedIndex = 0;
        }
        if (!reading.isEmpty()) {
            reading.backspace();
            page = 0;
            return reading.isEmpty() ? Result.discardComposition() : Result.update();
        }
        return Result.delete();
    }

    Result escape() {
        return clearComposition() ? Result.discardComposition() : Result.update();
    }

    Result selectDisplayedCandidate(int displayedIndex) {
        int absoluteIndex = page * CANDIDATES_PER_PAGE + displayedIndex;
        if (absoluteIndex < 0 || absoluteIndex >= candidates.size()) return Result.update();
        String selected = candidates.get(absoluteIndex);
        if (compositionMode == BopomofoCompositionMode.SMART
                && showingSmartCandidates && !smartReadings.isEmpty()) {
            smartSource.learnSelection(smartReadings, smartReadings.size() - 1,
                    selected, smartComposition);
            smartOverrides.put(smartReadings.size() - 1, selected);
            rebuildSmartComposition();
            return Result.update();
        }
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

    String composingText() {
        if (compositionMode != BopomofoCompositionMode.SMART) return reading.displayText();
        return (smartComposition == null ? "" : smartComposition.text())
                + reading.displayText();
    }

    boolean hasComposition() {
        return !composingText().isEmpty();
    }

    BopomofoCompositionMode compositionMode() {
        return compositionMode;
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

    boolean isHardwareFullWidth() {
        return hardwareFullWidth;
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
            if (compositionMode == BopomofoCompositionMode.SMART) {
                candidates = List.of();
                showingAssociatedPhrases = false;
                showingSmartCandidates = false;
                reading.combine(key);
                return reading.hasTone() ? finishSmartReading() : Result.update();
            }
            String prefix = commitFirstCandidateIfNeeded();
            reading.combine(key);
            Result result = reading.hasTone() ? query() : Result.update();
            if (!prefix.isEmpty()) {
                return new Result(prefix + result.committedText(), false, false, false);
            }
            return result;
        }

        if (!reading.isEmpty()) {
            if (compositionMode == BopomofoCompositionMode.SMART) {
                return Result.commit(finishCompositionForModeSwitch().committedText() + rawKey);
            }
            return Result.update();
        }
        if (compositionMode == BopomofoCompositionMode.SMART && !smartReadings.isEmpty()) {
            return Result.commit(finishCompositionForModeSwitch().committedText() + rawKey);
        }
        if (!candidates.isEmpty()) {
            String prefix = commitFirstCandidateIfNeeded();
            return Result.commit(prefix + rawKey);
        }
        return Result.commit(String.valueOf(rawKey));
    }

    private Result applyHardwareWidth(Result result) {
        if (!hardwareFullWidth || result.committedText().isEmpty()) return result;
        String text = toFullWidth(result.committedText());
        return new Result(text, result.deleteBeforeCursor(), result.sendEnter(),
                result.discardComposingText());
    }

    static String toFullWidth(String text) {
        StringBuilder converted = new StringBuilder(text.length());
        for (int index = 0; index < text.length(); index++) {
            char character = text.charAt(index);
            if (character == ' ') converted.append('\u3000');
            else if (character >= '!' && character <= '~') {
                converted.append((char) (character - '!' + '\uFF01'));
            } else converted.append(character);
        }
        return converted.toString();
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

    private Result finishSmartReading() {
        if (smartSource == null || reading.isEmpty()) return Result.update();
        String dictionaryQuery = reading.queryKey();
        String query = reading.languageModelKey();
        ArrayList<String> trialReadings = new ArrayList<>(smartReadings);
        trialReadings.add(query);
        if (smartSource.compose(trialReadings, smartOverrides) == null) {
            candidates = dictionary.candidates(dictionaryQuery);
            showingSmartCandidates = false;
            page = 0;
            highlightedIndex = 0;
            return Result.update();
        }
        smartReadings.add(query);
        reading.clear();
        rebuildSmartComposition();
        return Result.update();
    }

    private void rebuildSmartComposition() {
        if (smartSource == null) return;
        smartComposition = smartSource.compose(smartReadings, smartOverrides);
        if (smartReadings.isEmpty() || smartComposition == null) {
            candidates = List.of();
            showingSmartCandidates = false;
        } else {
            candidates = smartSource.candidates(smartReadings, smartReadings.size() - 1,
                    smartComposition);
            showingSmartCandidates = !candidates.isEmpty();
        }
        showingAssociatedPhrases = false;
        page = 0;
        highlightedIndex = 0;
    }

    private Result commitSmartComposition() {
        String text = smartComposition == null ? "" : smartComposition.text();
        if (smartComposition != null && !text.isEmpty()) {
            smartSource.learnConfirmedComposition(smartComposition);
        }
        clearComposition();
        return text.isEmpty() ? Result.update() : Result.commit(text);
    }

    Result finishCompositionForModeSwitch() {
        if (compositionMode == BopomofoCompositionMode.SMART
                && inputMode == InputMode.BOPOMOFO && hasComposition()) {
            if (!reading.isEmpty()) finishSmartReading();
            if (reading.isEmpty()) return commitSmartComposition();

            // Preserve an unfinished syllable if the language model cannot convert it.
            String prefix = smartComposition == null ? "" : smartComposition.text();
            String text = prefix + reading.displayText();
            if (smartComposition != null) smartSource.learnConfirmedComposition(smartComposition);
            clearComposition();
            return Result.commit(text);
        }
        return clearComposition() ? Result.discardComposition() : Result.update();
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
        Result result = finishCompositionForModeSwitch();
        if (temporaryEnglish) {
            temporaryEnglish = false;
            shifted = false;
            return result;
        }
        inputMode = nextAllowedMode(inputMode);
        shifted = false;
        return result;
    }

    private InputMode nextAllowedMode(InputMode current) {
        InputMode candidate = current;
        do {
            candidate = switch (candidate) {
                case BOPOMOFO -> InputMode.ENGLISH;
                case ENGLISH -> InputMode.NUMBER;
                case NUMBER -> InputMode.BOPOMOFO;
            };
        } while (!allowedInputModes.contains(candidate));
        return candidate;
    }

    private Result touchShift() {
        Result result = finishCompositionForModeSwitch();
        if (temporaryEnglish) {
            endTemporaryEnglish();
        } else if (inputMode == InputMode.BOPOMOFO
                && allowedInputModes.contains(InputMode.ENGLISH)) {
            inputMode = InputMode.ENGLISH;
            temporaryEnglish = true;
            shifted = false;
        } else if (inputMode == InputMode.ENGLISH) {
            shifted = !shifted;
        } else {
            shifted = !shifted;
        }
        return result;
    }

    private void endTemporaryEnglish() {
        inputMode = allowedInputModes.contains(InputMode.BOPOMOFO)
                ? InputMode.BOPOMOFO : allowedInputModes.iterator().next();
        temporaryEnglish = false;
        shifted = false;
    }

    private Result symbols() {
        Result result = finishCompositionForModeSwitch();
        candidates = SYMBOLS;
        showingAssociatedPhrases = false;
        highlightedIndex = 0;
        return result;
    }

    private Result emojis() {
        Result result = finishCompositionForModeSwitch();
        candidates = EMOJIS;
        showingAssociatedPhrases = false;
        highlightedIndex = 0;
        return result;
    }

    private boolean clearComposition() {
        boolean hadReading = hasComposition();
        reading.clear();
        smartReadings.clear();
        smartComposition = null;
        smartOverrides.clear();
        showingSmartCandidates = false;
        candidates = List.of();
        page = 0;
        highlightedIndex = 0;
        showingAssociatedPhrases = false;
        return hadReading;
    }
}
