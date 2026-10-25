package tw.chichi77.keykey.android;

import java.util.List;
import java.util.Set;
import java.util.function.Predicate;

/** The native FE contract. It contains no scoring or phonetic algorithm. */
interface InputEngine extends AutoCloseable {
    void setCandidateFilter(Predicate<String> filter);
    void setSpaceSelectsCandidates(boolean enabled);
    boolean spaceSelectsCandidates();
    void setUseBigrams(boolean enabled);
    ChineseInputMethod chineseInputMethod();
    void setTableCandidateSource(TableCandidateSource source);
    TableInputOptions tableOptions();
    void setTableOptions(TableInputOptions options);
    BopomofoEngine.Result setChineseInputMethod(ChineseInputMethod method);
    BopomofoEngine.Result setCompositionMode(BopomofoCompositionMode mode);
    BopomofoKeyboardLayout keyboardLayout();
    BopomofoEngine.Result setKeyboardLayout(BopomofoKeyboardLayout layout);
    void setAssociatedPhraseDictionary(AssociatedPhraseDictionary dictionary);
    void setAllowedInputModes(Set<BopomofoEngine.InputMode> allowed, BopomofoEngine.InputMode preferred);
    void setAllowedInputModes(Set<BopomofoEngine.InputMode> allowed, BopomofoEngine.InputMode preferred, boolean selectPreferred);
    BopomofoEngine.Result handleSoftKey(String key);
    BopomofoEngine.Result handleHardwareCharacter(char key);
    BopomofoEngine.Result commitHardwareLiteral(char key);
    BopomofoEngine.Result handleHardwareSpace();
    BopomofoEngine.Result toggleHardwareLanguage();
    BopomofoEngine.Result toggleHardwareWidth();
    BopomofoEngine.Result commitHardwarePunctuation(String punctuation);
    BopomofoEngine.Result showHardwareSymbols();
    void prepareForHardwareInput();
    void setHardwareTouchSmartEditing(boolean enabled);
    void setHardwareSmartEditing(boolean enabled);
    BopomofoEngine.Result space();
    BopomofoEngine.Result openSmartCandidates();
    BopomofoEngine.Result enter();
    BopomofoEngine.Result backspace();
    BopomofoEngine.Result escape();
    BopomofoEngine.Result selectDisplayedCandidate(int index);
    BopomofoEngine.Result selectHighlightedCandidate();
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
    BopomofoEngine.InputMode inputMode();
    boolean isShifted();
    boolean isTemporaryEnglish();
    boolean isHardwareFullWidth();
    boolean isShowingAssociatedPhrases();
    boolean isShowingSmartCandidates();
    BopomofoEngine.Result finishCompositionForModeSwitch();
    BopomofoEngine.Result finishCompositionForInputHandoff();
    BopomofoEngine.Result refreshUserData();
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
