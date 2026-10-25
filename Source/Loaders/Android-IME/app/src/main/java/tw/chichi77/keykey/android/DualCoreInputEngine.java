package tw.chichi77.keykey.android;

import java.util.EnumSet;
import java.util.List;
import java.util.Set;
import java.util.function.Consumer;
import java.util.function.Function;
import java.util.function.Predicate;

/** Same FE, independent Java/Rust state and storage, and no event replay. */
final class DualCoreInputEngine implements InputEngine {
    private final BopomofoEngine legacy;
    private final String modelPath, userDatabasePath;
    private Predicate<String> candidateFilter;
    private GuanyinmaInputEngine rust;
    private InputCore activeCore = InputCore.JAVA, requestedCore;
    // Preserve FE intent even when the Java backend cannot provide Smart mode.
    private ChineseInputMethod requestedMethod;
    private String coreError;
    private boolean pendingHostEffects, closed, useBigrams = true;
    private boolean hardwareSmartEditing, hardwareTouchSmartEditing;
    private AssociatedPhraseDictionary associated = AssociatedPhraseDictionary.empty();
    private EnumSet<BopomofoEngine.InputMode> allowedModes = EnumSet.allOf(BopomofoEngine.InputMode.class);

    DualCoreInputEngine(BopomofoEngine legacy, String modelPath, String userDatabasePath,
            InputCore preferredCore, Predicate<String> filter) {
        this.legacy = legacy; this.modelPath = modelPath; this.userDatabasePath = userDatabasePath;
        requestedMethod = legacy.chineseInputMethod();
        requestedCore = preferredCore == null ? InputCore.JAVA : preferredCore;
        candidateFilter = filter == null ? text -> true : filter;
        legacy.setCandidateFilter(candidateFilter); switchIfReady();
    }
    private InputEngine backend() { return activeCore == InputCore.JAVA ? legacy : rust; }
    InputCore activeCore() { return activeCore; }
    InputCore requestedCore() { return requestedCore; }
    String coreError() { return coreError; }
    void requestCore(InputCore value) {
        requestedCore = value == null ? InputCore.JAVA : value;
        if (requestedCore == InputCore.JAVA && activeCore == InputCore.JAVA) coreError = null;
        switchIfReady();
    }
    void acknowledgeHostEffects() { pendingHostEffects = false; switchIfReady(); }
    /** A new host cannot receive effects created for the previous connection. */
    void abandonHostEffects() {
        InputEngineModeState state = backend().inputModeState();
        pendingHostEffects = false;
        if (rust != null) { rust.close(); rust = null; }
        legacy.reset(); activeCore = InputCore.JAVA;
        legacy.setChineseInputMethod(requestedMethod);
        legacy.setAllowedInputModes(allowedModes, state.mode, true);
        legacy.restoreInputModeState(state); switchIfReady();
    }
    private boolean safe() { return !closed && !pendingHostEffects && !backend().hasComposition() && backend().displayedCandidates().isEmpty(); }
    private void switchIfReady() {
        if (!safe() || requestedCore == activeCore) return;
        try {
            InputEngine previous = backend();
            if (requestedCore == InputCore.GUANYINMA && rust == null) {
                rust = new GuanyinmaInputEngine(modelPath, userDatabasePath, requestedMethod,
                        previous.keyboardLayout(), previous.tableOptions(), previous.spaceSelectsCandidates(),
                        useBigrams, hardwareSmartEditing, candidateFilter);
            }
            InputEngine target = requestedCore == InputCore.JAVA ? legacy : rust;
            target.setChineseInputMethod(requestedMethod);
            target.setKeyboardLayout(previous.keyboardLayout());
            target.setTableOptions(previous.tableOptions());
            target.setSpaceSelectsCandidates(previous.spaceSelectsCandidates());
            target.setUseBigrams(useBigrams);
            target.setHardwareTouchSmartEditing(hardwareTouchSmartEditing);
            target.setHardwareSmartEditing(hardwareSmartEditing);
            target.setAssociatedPhraseDictionary(associated);
            InputEngineModeState state = previous.inputModeState();
            target.setAllowedInputModes(allowedModes, state.mode, true);
            if (!target.restoreInputModeState(state) || (target == rust && rust.lastError() != null)) {
                throw new IllegalStateException(target == rust ? rust.lastError() : "無法還原鍵盤模式。");
            }
            activeCore = requestedCore; coreError = null;
        } catch (RuntimeException | LinkageError error) {
            String message = error.getMessage();
            coreError = "Guanyinma 無法啟用：" + (message == null ? error.getClass().getSimpleName() : message);
        }
    }
    private void updateError() { if (activeCore == InputCore.GUANYINMA) coreError = rust.lastError() == null ? null : "Guanyinma：" + rust.lastError(); }
    private BopomofoEngine.Result perform(Function<InputEngine, BopomofoEngine.Result> action) {
        switchIfReady(); BopomofoEngine.Result result = action.apply(backend());
        pendingHostEffects |= !result.committedText().isEmpty() || result.deleteBeforeCursor() || result.sendEnter() || result.discardComposingText();
        updateError(); return result;
    }
    private void update(Consumer<InputEngine> action) { switchIfReady(); action.accept(backend()); updateError(); switchIfReady(); }
    private boolean select(Predicate<InputEngine> action) { switchIfReady(); boolean result = action.test(backend()); updateError(); return result; }
    void resetActiveCoreLearning() { if (activeCore == InputCore.GUANYINMA) rust.resetLearning(); }
    @Override public void setCandidateFilter(Predicate<String> value) {
        if (value == null) return;
        candidateFilter = value; legacy.setCandidateFilter(value);
        if (rust != null) { rust.setCandidateFilter(value); updateError(); }
    }
    @Override public void setSpaceSelectsCandidates(boolean enabled) { update(engine -> engine.setSpaceSelectsCandidates(enabled)); }
    @Override public boolean spaceSelectsCandidates() { return backend().spaceSelectsCandidates(); }
    @Override public void setUseBigrams(boolean enabled) { useBigrams = enabled; update(engine -> engine.setUseBigrams(enabled)); }
    @Override public ChineseInputMethod chineseInputMethod() { return backend().chineseInputMethod(); }
    @Override public void setTableCandidateSource(TableCandidateSource source) { legacy.setTableCandidateSource(source); }
    @Override public TableInputOptions tableOptions() { return backend().tableOptions(); }
    @Override public void setTableOptions(TableInputOptions options) { update(engine -> engine.setTableOptions(options)); }
    @Override public BopomofoEngine.Result setChineseInputMethod(ChineseInputMethod method) {
        requestedMethod = method;
        return perform(engine -> engine.setChineseInputMethod(method));
    }
    @Override public BopomofoEngine.Result setCompositionMode(BopomofoCompositionMode mode) {
        requestedMethod = mode == BopomofoCompositionMode.SMART ? ChineseInputMethod.SMART : ChineseInputMethod.TRADITIONAL;
        return perform(engine -> engine.setCompositionMode(mode));
    }
    @Override public BopomofoKeyboardLayout keyboardLayout() { return backend().keyboardLayout(); }
    @Override public BopomofoEngine.Result setKeyboardLayout(BopomofoKeyboardLayout layout) { return perform(engine -> engine.setKeyboardLayout(layout)); }
    @Override public void setAssociatedPhraseDictionary(AssociatedPhraseDictionary value) {
        associated = value == null ? AssociatedPhraseDictionary.empty() : value;
        legacy.setAssociatedPhraseDictionary(associated); if (rust != null) rust.setAssociatedPhraseDictionary(associated);
    }
    @Override public void setAllowedInputModes(Set<BopomofoEngine.InputMode> modes, BopomofoEngine.InputMode preferred) { setAllowedInputModes(modes, preferred, false); }
    @Override public void setAllowedInputModes(Set<BopomofoEngine.InputMode> modes, BopomofoEngine.InputMode preferred, boolean selectPreferred) {
        allowedModes = modes == null || modes.isEmpty() ? EnumSet.allOf(BopomofoEngine.InputMode.class) : EnumSet.copyOf(modes);
        update(engine -> engine.setAllowedInputModes(modes, preferred, selectPreferred));
    }
    @Override public BopomofoEngine.Result handleSoftKey(String key) { return perform(engine -> engine.handleSoftKey(key)); }
    @Override public BopomofoEngine.Result handleHardwareCharacter(char key) { hardwareSmartEditing = !hardwareTouchSmartEditing; return perform(engine -> engine.handleHardwareCharacter(key)); }
    @Override public BopomofoEngine.Result commitHardwareLiteral(char key) { hardwareSmartEditing = !hardwareTouchSmartEditing; return perform(engine -> engine.commitHardwareLiteral(key)); }
    @Override public BopomofoEngine.Result handleHardwareSpace() { hardwareSmartEditing = !hardwareTouchSmartEditing; return perform(InputEngine::handleHardwareSpace); }
    @Override public BopomofoEngine.Result toggleHardwareLanguage() { hardwareSmartEditing = !hardwareTouchSmartEditing; return perform(InputEngine::toggleHardwareLanguage); }
    @Override public BopomofoEngine.Result toggleHardwareWidth() { hardwareSmartEditing = !hardwareTouchSmartEditing; return perform(InputEngine::toggleHardwareWidth); }
    @Override public BopomofoEngine.Result commitHardwarePunctuation(String value) { hardwareSmartEditing = !hardwareTouchSmartEditing; return perform(engine -> engine.commitHardwarePunctuation(value)); }
    @Override public BopomofoEngine.Result showHardwareSymbols() { hardwareSmartEditing = !hardwareTouchSmartEditing; return perform(InputEngine::showHardwareSymbols); }
    @Override public void prepareForHardwareInput() { hardwareSmartEditing = !hardwareTouchSmartEditing; update(InputEngine::prepareForHardwareInput); }
    @Override public void setHardwareTouchSmartEditing(boolean enabled) { hardwareTouchSmartEditing = enabled; update(engine -> engine.setHardwareTouchSmartEditing(enabled)); }
    @Override public void setHardwareSmartEditing(boolean enabled) { hardwareSmartEditing = enabled; update(engine -> engine.setHardwareSmartEditing(enabled)); }
    @Override public BopomofoEngine.Result space() { return perform(InputEngine::space); }
    @Override public BopomofoEngine.Result openSmartCandidates() { return perform(InputEngine::openSmartCandidates); }
    @Override public BopomofoEngine.Result enter() { return perform(InputEngine::enter); }
    @Override public BopomofoEngine.Result backspace() { return perform(InputEngine::backspace); }
    @Override public BopomofoEngine.Result escape() { return perform(InputEngine::escape); }
    @Override public BopomofoEngine.Result selectDisplayedCandidate(int index) { return perform(engine -> engine.selectDisplayedCandidate(index)); }
    @Override public BopomofoEngine.Result selectHighlightedCandidate() { return perform(InputEngine::selectHighlightedCandidate); }
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
    @Override public BopomofoEngine.InputMode inputMode() { return backend().inputMode(); }
    @Override public boolean isShifted() { return backend().isShifted(); }
    @Override public boolean isTemporaryEnglish() { return backend().isTemporaryEnglish(); }
    @Override public boolean isHardwareFullWidth() { return backend().isHardwareFullWidth(); }
    @Override public boolean isShowingAssociatedPhrases() { return backend().isShowingAssociatedPhrases(); }
    @Override public boolean isShowingSmartCandidates() { return backend().isShowingSmartCandidates(); }
    @Override public BopomofoEngine.Result finishCompositionForModeSwitch() { return perform(InputEngine::finishCompositionForModeSwitch); }
    @Override public BopomofoEngine.Result finishCompositionForInputHandoff() { return perform(InputEngine::finishCompositionForInputHandoff); }
    @Override public BopomofoEngine.Result refreshUserData() { return perform(InputEngine::refreshUserData); }
    @Override public boolean restoreInputModeState(InputEngineModeState state) { return select(engine -> engine.restoreInputModeState(state)); }
    @Override public void close() { closed = true; if (rust != null) { rust.close(); rust = null; } activeCore = InputCore.JAVA; legacy.close(); }
}
