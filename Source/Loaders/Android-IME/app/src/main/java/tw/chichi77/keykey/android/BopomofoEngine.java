package tw.chichi77.keykey.android;

import java.util.ArrayList;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

final class BopomofoEngine {
    static final int CANDIDATES_PER_PAGE = 9;
    static final int TOUCH_SMART_EDITABLE_LIMIT = 9;
    static final int HARDWARE_SMART_EDITABLE_LIMIT = 10;
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
        static Result commitAndEnter(String text) { return new Result(text, false, true, false); }
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
    private final Map<Integer, SmartMandarinSelection> smartOverrides = new HashMap<>();
    private int smartCursor;
    private int smartCandidateStart;
    private List<SmartMandarinCandidate> smartCandidateOptions = List.of();
    private boolean hardwareSmartEditing;
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
        setHardwareSmartEditing(true);
    }

    void setHardwareSmartEditing(boolean enabled) {
        if (compositionMode != BopomofoCompositionMode.SMART || enabled == hardwareSmartEditing) {
            return;
        }
        hardwareSmartEditing = enabled;
        if (!smartReadings.isEmpty()) {
            rebuildSmartComposition();
        }
    }

    Result space() {
        if (compositionMode == BopomofoCompositionMode.SMART
                && inputMode == InputMode.BOPOMOFO) {
            if (!reading.isEmpty()) return finishSmartReading();
            if (!smartReadings.isEmpty()) {
                if (!showingSmartCandidates) {
                    showHardwareSmartCandidates();
                } else {
                    changePage(1);
                }
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
            if (hardwareSmartEditing && showingSmartCandidates) {
                return selectHighlightedCandidate();
            }
            if (!hardwareSmartEditing) {
                return Result.commitAndEnter(finishCompositionForModeSwitch().committedText());
            }
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
                if (smartCursor == 0) return Result.update();
                int removed = smartCursor - 1;
                smartReadings.remove(removed);
                smartCursor = removed;
                shiftSmartOverridesAfterRemoving(removed);
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
        if (hardwareSmartEditing && compositionMode == BopomofoCompositionMode.SMART) {
            if (showingSmartCandidates) {
                candidates = List.of();
                smartCandidateOptions = List.of();
                showingSmartCandidates = false;
                page = 0;
                highlightedIndex = 0;
            } else if (!reading.isEmpty()) {
                reading.clear();
            }
            return hasComposition() ? Result.update() : Result.discardComposition();
        }
        return clearComposition() ? Result.discardComposition() : Result.update();
    }

    Result selectDisplayedCandidate(int displayedIndex) {
        int absoluteIndex = page * CANDIDATES_PER_PAGE + displayedIndex;
        if (absoluteIndex < 0 || absoluteIndex >= candidates.size()) return Result.update();
        String selected = candidates.get(absoluteIndex);
        if (compositionMode == BopomofoCompositionMode.SMART
                && showingSmartCandidates && !smartReadings.isEmpty()) {
            if (absoluteIndex >= smartCandidateOptions.size()) return Result.update();
            SmartMandarinCandidate candidate = smartCandidateOptions.get(absoluteIndex);
            smartSource.learnSelection(smartReadings, smartCandidateStart,
                    candidate, smartComposition);
            int end = smartCandidateStart + candidate.length();
            smartOverrides.entrySet().removeIf(entry -> entry.getKey() < end
                    && smartCandidateStart < entry.getKey() + entry.getValue().length());
            smartOverrides.put(smartCandidateStart,
                    new SmartMandarinSelection(candidate.length(), candidate.text()));
            if (hardwareSmartEditing) smartCursor = end;
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

    boolean moveSmartCompositionCursor(int delta) {
        if (smartCompositionCursor() < 0 || !reading.isEmpty()) return false;
        smartCursor = Math.max(0, Math.min(smartReadings.size(), smartCursor + delta));
        candidates = List.of();
        smartCandidateOptions = List.of();
        showingSmartCandidates = false;
        page = 0;
        highlightedIndex = 0;
        return true;
    }

    int smartCompositionCursor() {
        return hardwareSmartEditing && compositionMode == BopomofoCompositionMode.SMART
                && !smartReadings.isEmpty() ? smartCursor : -1;
    }

    List<String> touchSmartCells() {
        if (compositionMode != BopomofoCompositionMode.SMART
                || inputMode != InputMode.BOPOMOFO || hardwareSmartEditing) return List.of();
        ArrayList<String> cells = new ArrayList<>();
        if (smartComposition != null) {
            for (SmartMandarinSegment segment : smartComposition.segments()) {
                int[] points = segment.text().codePoints().toArray();
                for (int offset = 0; offset < segment.length(); offset++) {
                    int start = offset * points.length / segment.length();
                    int end = (offset + 1) * points.length / segment.length();
                    cells.add(new String(points, start, end - start));
                }
            }
        }
        reading.displayText().codePoints().forEach(point -> {
            if (cells.size() < 11) cells.add(new String(Character.toChars(point)));
            else cells.set(10, cells.get(10) + new String(Character.toChars(point)));
        });
        return List.copyOf(cells);
    }

    int touchSmartEditableCount() {
        return smartReadings.size();
    }

    boolean selectTouchSmartCell(int index) {
        if (compositionMode != BopomofoCompositionMode.SMART
                || inputMode != InputMode.BOPOMOFO || hardwareSmartEditing
                || index < 0 || index >= smartReadings.size()) return false;
        if (showingSmartCandidates && smartCandidateStart == index) {
            candidates = List.of();
            smartCandidateOptions = List.of();
            showingSmartCandidates = false;
            return true;
        }
        showSmartCandidatesAt(index);
        return true;
    }

    int composingCaretUtf16Offset() {
        if (smartComposition == null || smartCompositionCursor() < 0 || !reading.isEmpty()) {
            return composingText().length();
        }
        int offset = 0;
        for (SmartMandarinSegment segment : smartComposition.segments()) {
            if (smartCursor >= segment.start() + segment.length()) {
                offset += segment.text().length();
            } else if (smartCursor > segment.start()) {
                int points = segment.text().codePointCount(0, segment.text().length());
                int count = (smartCursor - segment.start()) * points / segment.length();
                offset += segment.text().offsetByCodePoints(0, count);
                break;
            } else {
                break;
            }
        }
        return offset;
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

    String completedSmartText() {
        return smartComposition == null ? "" : smartComposition.text();
    }

    boolean hasComposition() {
        return !composingText().isEmpty();
    }

    boolean isTouchSmartComposition() {
        return compositionMode == BopomofoCompositionMode.SMART
                && inputMode == InputMode.BOPOMOFO && !hardwareSmartEditing;
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

    boolean isShowingSmartCandidates() {
        return showingSmartCandidates;
    }

    private Result character(char rawKey, boolean fromTouch) {
        char key = Character.toLowerCase(rawKey);
        if (inputMode == InputMode.ENGLISH) {
            char output = fromTouch && shifted && Character.isLetter(rawKey)
                    ? Character.toUpperCase(rawKey) : rawKey;
            return Result.commit(String.valueOf(output));
        }
        if (inputMode == InputMode.NUMBER) return Result.commit(String.valueOf(rawKey));

        if (!fromTouch && compositionMode == BopomofoCompositionMode.SMART
                && rawKey >= 'A' && rawKey <= 'Z') {
            // A shifted letter is literal hardware input, not the reading key
            // printed on the same physical key.
            if (!reading.isEmpty()) return Result.update();
            return Result.commit(finishCompositionForModeSwitch().committedText() + rawKey);
        }

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
        trialReadings.add(smartCursor, query);
        Map<Integer, SmartMandarinSelection> shifted = shiftedSmartOverridesAfterInserting(smartCursor);
        if (smartSource.composeSelections(trialReadings, shifted) == null) {
            if (!hardwareSmartEditing) {
                candidates = dictionary.candidates(dictionaryQuery);
                showingSmartCandidates = false;
                page = 0;
                highlightedIndex = 0;
            }
            // Hardware editing must retain its sentence and reading if the
            // language model cannot compose this syllable.
            return Result.update();
        }
        smartReadings.clear();
        smartReadings.addAll(trialReadings);
        smartOverrides.clear();
        smartOverrides.putAll(shifted);
        smartCursor++;
        reading.clear();
        rebuildSmartComposition();
        int editableLimit = hardwareSmartEditing
                ? HARDWARE_SMART_EDITABLE_LIMIT : TOUCH_SMART_EDITABLE_LIMIT;
        if (smartReadings.size() > editableLimit) {
            return hardwareSmartEditing
                    ? evictFirstHardwareSmartSegment() : evictFirstTouchSmartSegment();
        }
        return Result.update();
    }

    private Result evictFirstTouchSmartSegment() {
        if (smartComposition == null || smartComposition.segments().isEmpty()) {
            return Result.update();
        }
        SmartMandarinSegment first = smartComposition.segments().get(0);
        if (first.length() <= 0 || first.text().isEmpty()) return Result.update();
        // Match the desktop walker: retain the following node's chosen text
        // when its preceding context leaves the editable window.
        SmartMandarinSegment next = smartComposition.segments().size() > 1
                ? smartComposition.segments().get(1) : null;
        String committed = first.text();
        smartReadings.subList(0, first.length()).clear();
        Map<Integer, SmartMandarinSelection> shifted = new HashMap<>();
        for (Map.Entry<Integer, SmartMandarinSelection> entry : smartOverrides.entrySet()) {
            if (entry.getKey() >= first.length()) {
                shifted.put(entry.getKey() - first.length(), entry.getValue());
            }
        }
        smartOverrides.clear();
        smartOverrides.putAll(shifted);
        if (next != null) {
            smartOverrides.put(0, new SmartMandarinSelection(next.length(), next.text()));
        }
        smartCursor = Math.max(0, smartCursor - first.length());
        rebuildSmartComposition();
        return Result.commit(committed);
    }

    private Result evictFirstHardwareSmartSegment() {
        if (smartComposition == null || smartComposition.segments().isEmpty()) {
            return Result.update();
        }
        int count = smartSource.evictionLength(smartReadings, smartComposition);
        if (count <= 0 || count > smartReadings.size()) return Result.update();
        // Match the desktop walker: retain the following node's chosen text
        // when its preceding context leaves the editable window.
        SmartMandarinSegment next = null;
        StringBuilder committed = new StringBuilder();
        for (SmartMandarinSegment segment : smartComposition.segments()) {
            if (segment.start() < count) committed.append(segment.text());
            else if (segment.start() == count) {
                next = segment;
                break;
            }
        }
        if (committed.length() == 0) return Result.update();
        smartReadings.subList(0, count).clear();
        Map<Integer, SmartMandarinSelection> shifted = new HashMap<>();
        for (Map.Entry<Integer, SmartMandarinSelection> entry : smartOverrides.entrySet()) {
            if (entry.getKey() >= count) {
                shifted.put(entry.getKey() - count, entry.getValue());
            }
        }
        smartOverrides.clear();
        smartOverrides.putAll(shifted);
        if (next != null) {
            smartOverrides.put(0, new SmartMandarinSelection(next.length(), next.text()));
        }
        smartCursor = Math.max(0, smartCursor - count);
        rebuildSmartComposition();
        return Result.commit(committed.toString());
    }

    private void rebuildSmartComposition() {
        if (smartSource == null) return;
        smartComposition = smartSource.composeSelections(smartReadings, smartOverrides);
        candidates = List.of();
        smartCandidateOptions = List.of();
        showingSmartCandidates = false;
        showingAssociatedPhrases = false;
        page = 0;
        highlightedIndex = 0;
    }

    private void showHardwareSmartCandidates() {
        showSmartCandidatesAt(Math.min(smartCursor, smartReadings.size() - 1));
    }

    private void showSmartCandidatesAt(int index) {
        if (smartSource == null || smartReadings.isEmpty()) return;
        smartCandidateStart = index;
        smartCandidateOptions = smartSource.candidateOptions(smartReadings,
                smartCandidateStart, smartComposition);
        ArrayList<String> texts = new ArrayList<>();
        for (SmartMandarinCandidate candidate : smartCandidateOptions) {
            texts.add(candidate.text());
        }
        candidates = List.copyOf(texts);
        showingSmartCandidates = !candidates.isEmpty();
        page = 0;
        highlightedIndex = 0;
    }

    private Map<Integer, SmartMandarinSelection> shiftedSmartOverridesAfterInserting(int index) {
        Map<Integer, SmartMandarinSelection> shifted = new HashMap<>();
        for (Map.Entry<Integer, SmartMandarinSelection> entry : smartOverrides.entrySet()) {
            int start = entry.getKey();
            SmartMandarinSelection selection = entry.getValue();
            if (start >= index) shifted.put(start + 1, selection);
            else if (start + selection.length() <= index) shifted.put(start, selection);
        }
        return shifted;
    }

    private void shiftSmartOverridesAfterRemoving(int index) {
        Map<Integer, SmartMandarinSelection> shifted = new HashMap<>();
        for (Map.Entry<Integer, SmartMandarinSelection> entry : smartOverrides.entrySet()) {
            int start = entry.getKey();
            SmartMandarinSelection selection = entry.getValue();
            if (start > index) shifted.put(start - 1, selection);
            else if (start + selection.length() <= index) shifted.put(start, selection);
        }
        smartOverrides.clear();
        smartOverrides.putAll(shifted);
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
            String evictedText = reading.isEmpty() ? "" : finishSmartReading().committedText();
            if (reading.isEmpty()) {
                String committed = commitSmartComposition().committedText();
                return evictedText.isEmpty() && committed.isEmpty()
                        ? Result.update() : Result.commit(evictedText + committed);
            }

            // Preserve an unfinished syllable if the language model cannot convert it.
            String prefix = smartComposition == null ? "" : smartComposition.text();
            String text = evictedText + prefix + reading.displayText();
            if (smartComposition != null) smartSource.learnConfirmedComposition(smartComposition);
            clearComposition();
            return Result.commit(text);
        }
        return clearComposition() ? Result.discardComposition() : Result.update();
    }

    Result finishCompositionForInputHandoff() {
        if (!isTouchSmartComposition() || !hasComposition()) return Result.update();
        return finishCompositionForModeSwitch();
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
        smartCursor = 0;
        smartCandidateStart = 0;
        smartCandidateOptions = List.of();
        hardwareSmartEditing = false;
        showingSmartCandidates = false;
        candidates = List.of();
        page = 0;
        highlightedIndex = 0;
        showingAssociatedPhrases = false;
        return hadReading;
    }
}
