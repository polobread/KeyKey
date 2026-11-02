package tw.chichi77.keykey.android;

import java.util.List;
import java.util.Set;
import java.util.function.Predicate;

/** The native FE contract. It contains no scoring or phonetic algorithm. */
interface InputEngine extends AutoCloseable {
    int CANDIDATES_PER_PAGE = 9;
    int TOUCH_SMART_EDITABLE_LIMIT = 9;
    int HARDWARE_SMART_EDITABLE_LIMIT = 10;
    enum InputMode { BOPOMOFO, ENGLISH, NUMBER }
    List<String> SYMBOLS = List.of(
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
    List<String> EMOJIS = List.of(
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

    final class Result {
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

    static List<String> symbolCandidates() { return SYMBOLS; }
    static List<String> emojiCandidates() { return EMOJIS; }
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


    void setCandidateFilter(Predicate<String> filter);
    void setSpaceSelectsCandidates(boolean enabled);
    boolean spaceSelectsCandidates();
    void setUseBigrams(boolean enabled);
    ChineseInputMethod chineseInputMethod();
    TableInputOptions tableOptions();
    void setTableOptions(TableInputOptions options);
    InputEngine.Result setChineseInputMethod(ChineseInputMethod method);
    InputEngine.Result setCompositionMode(BopomofoCompositionMode mode);
    BopomofoKeyboardLayout keyboardLayout();
    InputEngine.Result setKeyboardLayout(BopomofoKeyboardLayout layout);
    void setAssociatedPhraseDictionary(AssociatedPhraseDictionary dictionary);
    void setAllowedInputModes(Set<InputEngine.InputMode> allowed, InputEngine.InputMode preferred);
    void setAllowedInputModes(Set<InputEngine.InputMode> allowed, InputEngine.InputMode preferred, boolean selectPreferred);
    InputEngine.Result handleSoftKey(String key);
    InputEngine.Result handleHardwareCharacter(char key);
    InputEngine.Result commitHardwareLiteral(char key);
    InputEngine.Result handleHardwareSpace();
    InputEngine.Result toggleHardwareLanguage();
    InputEngine.Result toggleHardwareWidth();
    InputEngine.Result commitHardwarePunctuation(String punctuation);
    InputEngine.Result showHardwareSymbols();
    void prepareForHardwareInput();
    void setHardwareTouchSmartEditing(boolean enabled);
    void setHardwareSmartEditing(boolean enabled);
    InputEngine.Result space();
    InputEngine.Result openSmartCandidates();
    InputEngine.Result enter();
    InputEngine.Result backspace();
    InputEngine.Result escape();
    InputEngine.Result selectDisplayedCandidate(int index);
    InputEngine.Result selectHighlightedCandidate();
    void moveHighlight(int delta);
    void changePage(int delta);
    boolean moveSmartCompositionCursor(int delta);
    int smartCompositionCursor();
    List<String> touchSmartCells();
    List<String> touchSmartCells(int cellCount);
    int touchSmartEditableCount();
    boolean selectTouchSmartCell(int index);
    int composingCaretUtf16Offset();
    void reset();
    String readingText();
    String composingText();
    String completedSmartText();
    boolean hasComposition();
    boolean isTouchSmartComposition();
    BopomofoCompositionMode compositionMode();
    List<String> displayedCandidates();
    int page();
    int pageCount();
    int highlightedIndex();
    boolean isEnglishMode();
    InputEngine.InputMode inputMode();
    boolean isShifted();
    boolean isTemporaryEnglish();
    boolean isHardwareFullWidth();
    boolean isShowingAssociatedPhrases();
    boolean isShowingSmartCandidates();
    InputEngine.Result finishCompositionForModeSwitch();
    InputEngine.Result finishCompositionForInputHandoff();
    InputEngine.Result refreshUserData();
    boolean restoreInputModeState(InputEngineModeState state);
    default InputEngineModeState inputModeState() {
        return new InputEngineModeState(inputMode(), isShifted(), isTemporaryEnglish(), isHardwareFullWidth());
    }
    @Override void close();
    static TableInputOptions copyOptions(TableInputOptions source) {
        TableInputOptions copy = new TableInputOptions(ChineseInputMethod.CANGJIE);
        copy.queryAtMaximum = source.queryAtMaximum; copy.clearOnError = source.clearOnError;
        copy.composeWhileTyping = source.composeWhileTyping; copy.prefixCandidates = source.prefixCandidates;
        copy.dynamicFrequency = source.dynamicFrequency; copy.punctuation = source.punctuation;
        return copy;
    }
}
