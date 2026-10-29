package tw.chichi77.keykey.android;

import java.util.List;
import java.util.Set;
import java.util.function.Consumer;
import java.util.function.Function;
import java.util.function.Predicate;

/** FE transaction ownership around the required Rust adapter; never selects a backend. */
final class HostInputEngine implements InputEngine {
    private final GuanyinmaInputEngine rust;
    private boolean pendingHostEffects, closed;
    private String transactionError;

    HostInputEngine(String modelPath, String userDatabasePath, ChineseInputMethod method,
            BopomofoKeyboardLayout layout, TableInputOptions options, boolean spaceSelects,
            boolean useBigrams, Predicate<String> filter) {
        rust = new GuanyinmaInputEngine(modelPath, userDatabasePath, method, layout, options,
                spaceSelects, useBigrams, false, filter);
    }
    private InputEngine backend() { return rust; }
    String coreError() { return transactionError != null ? transactionError : rust.lastError(); }
    void acknowledgeHostEffects() { pendingHostEffects = false; transactionError = null; }
    /** A new host discards state and cannot receive a previous host's effects. */
    void abandonHostEffects() {
        InputEngineModeState state = rust.inputModeState();
        pendingHostEffects = false;
        transactionError = null;
        rust.reset();
        if (rust.lastError() != null || !rust.restoreInputModeState(state)) {
            throw new IllegalStateException("無法清除前個欄位的輸入狀態：" + rust.lastError());
        }
    }
    private boolean ready() {
        if (closed) throw new IllegalStateException("Guanyinma input engine is closed");
        if (!pendingHostEffects) return true;
        transactionError = "目前欄位尚未接受前次輸入，請重新點選文字欄位。";
        return false;
    }
    private InputEngine.Result perform(Function<InputEngine, InputEngine.Result> action) {
        if (!ready()) return InputEngine.Result.update();
        InputEngine.Result result = action.apply(rust);
        pendingHostEffects = !result.committedText().isEmpty() || result.deleteBeforeCursor()
                || result.sendEnter() || result.discardComposingText();
        return result;
    }
    private void update(Consumer<InputEngine> action) { if (ready()) action.accept(rust); }
    private boolean select(Predicate<InputEngine> action) { return ready() && action.test(rust); }
    @Override public void setCandidateFilter(Predicate<String> filter) { update(engine -> engine.setCandidateFilter(filter)); }
    @Override public void setSpaceSelectsCandidates(boolean enabled) { update(engine -> engine.setSpaceSelectsCandidates(enabled)); }
    @Override public boolean spaceSelectsCandidates() { return backend().spaceSelectsCandidates(); }
    @Override public void setUseBigrams(boolean enabled) { update(engine -> engine.setUseBigrams(enabled)); }
    @Override public ChineseInputMethod chineseInputMethod() { return backend().chineseInputMethod(); }
    @Override public TableInputOptions tableOptions() { return backend().tableOptions(); }
    @Override public void setTableOptions(TableInputOptions options) { update(engine -> engine.setTableOptions(options)); }
    @Override public InputEngine.Result setChineseInputMethod(ChineseInputMethod method) {
        return perform(engine -> engine.setChineseInputMethod(method));
    }
    @Override public InputEngine.Result setCompositionMode(BopomofoCompositionMode mode) {
        return perform(engine -> engine.setCompositionMode(mode));
    }
    @Override public BopomofoKeyboardLayout keyboardLayout() { return backend().keyboardLayout(); }
    @Override public InputEngine.Result setKeyboardLayout(BopomofoKeyboardLayout layout) { return perform(engine -> engine.setKeyboardLayout(layout)); }
    @Override public void setAssociatedPhraseDictionary(AssociatedPhraseDictionary value) { update(engine -> engine.setAssociatedPhraseDictionary(value)); }
    @Override public void setAllowedInputModes(Set<InputEngine.InputMode> modes, InputEngine.InputMode preferred) { setAllowedInputModes(modes, preferred, false); }
    @Override public void setAllowedInputModes(Set<InputEngine.InputMode> modes, InputEngine.InputMode preferred, boolean selectPreferred) {
        update(engine -> engine.setAllowedInputModes(modes, preferred, selectPreferred));
    }
    @Override public InputEngine.Result handleSoftKey(String key) { return perform(engine -> engine.handleSoftKey(key)); }
    @Override public InputEngine.Result handleHardwareCharacter(char key) { return perform(engine -> engine.handleHardwareCharacter(key)); }
    @Override public InputEngine.Result commitHardwareLiteral(char key) { return perform(engine -> engine.commitHardwareLiteral(key)); }
    @Override public InputEngine.Result handleHardwareSpace() { return perform(InputEngine::handleHardwareSpace); }
    @Override public InputEngine.Result toggleHardwareLanguage() { return perform(InputEngine::toggleHardwareLanguage); }
    @Override public InputEngine.Result toggleHardwareWidth() { return perform(InputEngine::toggleHardwareWidth); }
    @Override public InputEngine.Result commitHardwarePunctuation(String value) { return perform(engine -> engine.commitHardwarePunctuation(value)); }
    @Override public InputEngine.Result showHardwareSymbols() { return perform(InputEngine::showHardwareSymbols); }
    @Override public void prepareForHardwareInput() { update(InputEngine::prepareForHardwareInput); }
    @Override public void setHardwareTouchSmartEditing(boolean enabled) { update(engine -> engine.setHardwareTouchSmartEditing(enabled)); }
    @Override public void setHardwareSmartEditing(boolean enabled) { update(engine -> engine.setHardwareSmartEditing(enabled)); }
    @Override public InputEngine.Result space() { return perform(InputEngine::space); }
    @Override public InputEngine.Result openSmartCandidates() { return perform(InputEngine::openSmartCandidates); }
    @Override public InputEngine.Result enter() { return perform(InputEngine::enter); }
    @Override public InputEngine.Result backspace() { return perform(InputEngine::backspace); }
    @Override public InputEngine.Result escape() { return perform(InputEngine::escape); }
    @Override public InputEngine.Result selectDisplayedCandidate(int index) { return perform(engine -> engine.selectDisplayedCandidate(index)); }
    @Override public InputEngine.Result selectHighlightedCandidate() { return perform(InputEngine::selectHighlightedCandidate); }
    @Override public void moveHighlight(int delta) { update(engine -> engine.moveHighlight(delta)); }
    @Override public void changePage(int delta) { update(engine -> engine.changePage(delta)); }
    @Override public boolean moveSmartCompositionCursor(int delta) { return select(engine -> engine.moveSmartCompositionCursor(delta)); }
    @Override public int smartCompositionCursor() { return backend().smartCompositionCursor(); }
    @Override public List<String> touchSmartCells() { return backend().touchSmartCells(); }
    @Override public List<String> touchSmartCells(int count) { return backend().touchSmartCells(count); }
    @Override public int touchSmartEditableCount() { return backend().touchSmartEditableCount(); }
    @Override public boolean selectTouchSmartCell(int index) { return select(engine -> engine.selectTouchSmartCell(index)); }
    @Override public int composingCaretUtf16Offset() { return backend().composingCaretUtf16Offset(); }
    @Override public void reset() { update(InputEngine::reset); }
    @Override public String readingText() { return backend().readingText(); }
    @Override public String composingText() { return backend().composingText(); }
    @Override public String completedSmartText() { return backend().completedSmartText(); }
    @Override public boolean hasComposition() { return backend().hasComposition(); }
    @Override public boolean isTouchSmartComposition() { return backend().isTouchSmartComposition(); }
    @Override public BopomofoCompositionMode compositionMode() { return backend().compositionMode(); }
    @Override public List<String> displayedCandidates() { return backend().displayedCandidates(); }
    @Override public int page() { return backend().page(); }
    @Override public int pageCount() { return backend().pageCount(); }
    @Override public int highlightedIndex() { return backend().highlightedIndex(); }
    @Override public boolean isEnglishMode() { return backend().isEnglishMode(); }
    @Override public InputEngine.InputMode inputMode() { return backend().inputMode(); }
    @Override public boolean isShifted() { return backend().isShifted(); }
    @Override public boolean isTemporaryEnglish() { return backend().isTemporaryEnglish(); }
    @Override public boolean isHardwareFullWidth() { return backend().isHardwareFullWidth(); }
    @Override public boolean isShowingAssociatedPhrases() { return backend().isShowingAssociatedPhrases(); }
    @Override public boolean isShowingSmartCandidates() { return backend().isShowingSmartCandidates(); }
    @Override public InputEngine.Result finishCompositionForModeSwitch() { return perform(InputEngine::finishCompositionForModeSwitch); }
    @Override public InputEngine.Result finishCompositionForInputHandoff() { return perform(InputEngine::finishCompositionForInputHandoff); }
    @Override public InputEngine.Result refreshUserData() { return perform(InputEngine::refreshUserData); }
    @Override public boolean restoreInputModeState(InputEngineModeState state) { return select(engine -> engine.restoreInputModeState(state)); }
    @Override public void close() { if (!closed) { closed = true; pendingHostEffects = false; rust.close(); } }
}
