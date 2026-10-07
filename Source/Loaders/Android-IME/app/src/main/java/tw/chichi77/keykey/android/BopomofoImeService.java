package tw.chichi77.keykey.android;

import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.RectF;
import android.content.res.Configuration;
import android.inputmethodservice.InputMethodService;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.view.KeyEvent;
import android.view.View;
import android.view.inputmethod.CursorAnchorInfo;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.ExtractedText;
import android.view.inputmethod.ExtractedTextRequest;
import android.view.inputmethod.InputConnection;

import java.io.IOException;
import java.io.InputStream;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class BopomofoImeService extends InputMethodService
        implements BopomofoKeyboardView.Listener, FloatingCandidateWindow.Listener,
        SharedPreferences.OnSharedPreferenceChangeListener {
    private BopomofoEngine engine;
    private SmartMandarinStore smartMandarinStore;
    private SmartMandarinUserData smartUserData;
    private BopomofoKeyboardView keyboardView;
    private FloatingCandidateWindow floatingCandidateWindow;
    private Vibrator vibrator;
    private Set<String> loadedPhraseCollections;
    private Set<String> pendingPhraseCollections;
    private volatile int phraseLoadGeneration;
    private boolean hardwareKeyboard;
    private boolean floatingCandidatesEnabled;
    private boolean floatingCandidateWindowAvailable = true;
    private CandidateWindowSettings.Layout floatingCandidateLayout =
            CandidateWindowSettings.Layout.VERTICAL;
    private RectF cursorAnchor;
    private static final int MAX_CURSOR_ANCHOR_RETRIES = 1;
    private static final long CURSOR_ANCHOR_RETRY_DELAY_MS = 300;
    private int cursorAnchorRetryCount;
    private boolean cursorAnchorRequestPending;
    private boolean floatingCandidatesVisible;
    private final Runnable cursorAnchorRetry = this::retryCursorAnchorUpdates;
    private final Set<Integer> pressedHardwareShortcutKeys = new LinkedHashSet<>();
    private final Set<Integer> pressedCandidateKeys = new LinkedHashSet<>();
    private final Set<Integer> pressedNavigationKeys = new LinkedHashSet<>();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final BackspaceRepeater hardwareBackspaceRepeater =
            new BackspaceRepeater(mainHandler);
    private boolean hardwareBackspaceHeld;
    private final ExecutorService dictionaryLoader = Executors.newSingleThreadExecutor(runnable -> {
        Thread thread = new Thread(runnable, "KeyKey dictionary loader");
        thread.setPriority(Thread.NORM_PRIORITY - 1);
        return thread;
    });
    private InputFieldPolicy fieldPolicy = InputFieldPolicy.DEFAULT;
    private boolean fieldPolicyUnlocked;
    private int lastSelectionStart = -1;
    private int lastSelectionEnd = -1;
    private int selectionMutationGeneration;
    private boolean awaitingOwnSelectionUpdate;
    private String appliedComposingText = "";
    private final TouchSmartHostTextState touchHostText = new TouchSmartHostTextState();
    private int composingRegionStart = -1;
    private int expectedSmartSelection = -1;

    @Override
    public void onCreate() {
        super.onCreate();
        CinDictionary dictionary;
        try (InputStream index = getAssets().open("bpmf-index.kki")) {
            dictionary = CinDictionary.loadIndexed(index);
        } catch (IOException error) {
            try (InputStream bopomofo = getAssets().open("bpmf-ext.cin");
                 InputStream punctuation = getAssets().open("bpmf-punctuations.cin")) {
                dictionary = CinDictionary.load(bopomofo, punctuation);
            } catch (IOException fallbackError) {
                dictionary = CinDictionary.empty();
            }
        }
        try {
            smartUserData = SmartMandarinUserData.open(this);
            smartMandarinStore = SmartMandarinStore.open(this, smartUserData);
            smartMandarinStore.setBigramEnabled(
                    BopomofoCompositionModeSettings.bigramEnabled(this));
        } catch (IOException | RuntimeException error) {
            smartMandarinStore = null;
        }
        engine = new BopomofoEngine(dictionary, smartMandarinStore,
                BopomofoCompositionModeSettings.mode(this));
        engine.setKeyboardLayout(BopomofoKeyboardLayoutSettings.layout(this));
        if (smartMandarinStore != null) engine.setTableCandidateSource(new TableCandidateStore(
                smartMandarinStore.tableDatabase(), getSharedPreferences("table_learning", MODE_PRIVATE)));
        engine.setChineseInputMethod(ChineseInputMethodSettings.method(this));
        engine.tableOptions = ChineseInputMethodSettings.options(this, engine.chineseInputMethod());
        schedulePhraseDictionaryReload();
        vibrator = getSystemService(Vibrator.class);
        CandidateWindowSettings.preferences(this)
                .registerOnSharedPreferenceChangeListener(this);
        SupporterState.preferences(this)
                .registerOnSharedPreferenceChangeListener(this);
    }

    @Override
    public void onPress() {
        int durationMs = HapticSettings.durationMs(this);
        if (durationMs > 0 && vibrator != null && vibrator.hasVibrator()) {
            vibrator.vibrate(VibrationEffect.createOneShot(
                    durationMs, VibrationEffect.DEFAULT_AMPLITUDE));
        }
    }

    @Override
    public View onCreateInputView() {
        keyboardView = new BopomofoKeyboardView(this);
        keyboardView.setListener(this);
        floatingCandidateWindow = new FloatingCandidateWindow(this, keyboardView, this);
        updateKeyboardMode();
        requestCursorAnchorUpdates();
        refreshKeyboard();
        return keyboardView;
    }

    @Override
    public boolean onEvaluateInputViewShown() {
        super.onEvaluateInputViewShown();
        return true;
    }

    @Override
    public boolean onEvaluateFullscreenMode() {
        return false;
    }

    @Override
    public void onStartInput(EditorInfo attribute, boolean restarting) {
        super.onStartInput(attribute, restarting);
        stopHardwareBackspace();
        if (!restarting) fieldPolicyUnlocked = false;
        resetCursorAnchor();
        lastSelectionStart = attribute == null ? -1 : attribute.initialSelStart;
        lastSelectionEnd = attribute == null ? -1 : attribute.initialSelEnd;
        cancelExpectedSelectionUpdate();
        schedulePhraseDictionaryReload();
        InputFieldPolicy nextPolicy = InputFieldPolicy.from(attribute);
        if (fieldPolicyUnlocked) nextPolicy = nextPolicy.unrestricted();
        boolean layoutChanged = !fieldPolicy.hasSameLayout(nextPolicy);
        fieldPolicy = nextPolicy;
        if (engine != null) {
            if (!restarting) {
                engine.reset();
                appliedComposingText = "";
                touchHostText.reset();
                composingRegionStart = -1;
                expectedSmartSelection = -1;
            }
            engine.setAllowedInputModes(fieldPolicy.allowedModes(), fieldPolicy.preferredMode(),
                    layoutChanged);
        }
        updateKeyboardMode();
        requestCursorAnchorUpdates();
        refreshKeyboard();
    }

    @Override
    public void onStartInputView(EditorInfo info, boolean restarting) {
        super.onStartInputView(info, restarting);
        stopHardwareBackspace();
        schedulePhraseDictionaryReload();
        InputFieldPolicy nextPolicy = InputFieldPolicy.from(info);
        if (fieldPolicyUnlocked) nextPolicy = nextPolicy.unrestricted();
        boolean layoutChanged = !fieldPolicy.hasSameLayout(nextPolicy);
        fieldPolicy = nextPolicy;
        if (engine != null) {
            engine.setAllowedInputModes(fieldPolicy.allowedModes(), fieldPolicy.preferredMode(),
                    layoutChanged);
        }
        updateKeyboardMode();
        requestCursorAnchorUpdates();
        refreshKeyboard();
    }

    @Override
    public void onFinishInput() {
        stopHardwareBackspace();
        commitPendingComposition();
        if (engine != null) engine.reset();
        pressedHardwareShortcutKeys.clear();
        pressedCandidateKeys.clear();
        pressedNavigationKeys.clear();
        resetCursorAnchor();
        lastSelectionStart = -1;
        lastSelectionEnd = -1;
        appliedComposingText = "";
        touchHostText.reset();
        composingRegionStart = -1;
        expectedSmartSelection = -1;
        fieldPolicyUnlocked = false;
        cancelExpectedSelectionUpdate();
        hideFloatingCandidates();
        super.onFinishInput();
    }

    @Override
    public void onFinishInputView(boolean finishingInput) {
        commitPendingComposition();
        super.onFinishInputView(finishingInput);
    }

    @Override
    public void onWindowHidden() {
        stopHardwareBackspace();
        commitPendingComposition();
        hideFloatingCandidates();
        super.onWindowHidden();
    }

    private void commitPendingComposition() {
        if (engine == null || !engine.hasComposition()
                || getCurrentInputConnection() == null) return;
        apply(engine.finishCompositionForInputHandoff());
    }

    @Override
    public void onDestroy() {
        stopHardwareBackspace();
        CandidateWindowSettings.preferences(this)
                .unregisterOnSharedPreferenceChangeListener(this);
        SupporterState.preferences(this)
                .unregisterOnSharedPreferenceChangeListener(this);
        if (smartMandarinStore != null) {
            smartMandarinStore.close();
            smartMandarinStore = null;
        }
        if (smartUserData != null) {
            smartUserData.close();
            smartUserData = null;
        }
        phraseLoadGeneration++;
        dictionaryLoader.shutdownNow();
        mainHandler.removeCallbacksAndMessages(null);
        hideFloatingCandidates();
        super.onDestroy();
    }

    @Override
    public void onConfigurationChanged(Configuration newConfig) {
        super.onConfigurationChanged(newConfig);
        stopHardwareBackspace();
        resetCursorAnchor();
        updateKeyboardMode();
        requestCursorAnchorUpdates();
        refreshKeyboard();
    }

    @Override
    public void onUpdateCursorAnchorInfo(CursorAnchorInfo cursorAnchorInfo) {
        super.onUpdateCursorAnchorInfo(cursorAnchorInfo);
        cursorAnchor = insertionMarkerBounds(cursorAnchorInfo);
        if (cursorAnchor != null) {
            cursorAnchorRequestPending = false;
            mainHandler.removeCallbacks(cursorAnchorRetry);
        } else if (floatingCandidatesVisible && !cursorAnchorRequestPending) {
            cursorAnchorRequestPending = true;
            cursorAnchorRetryCount = 0;
            mainHandler.postDelayed(cursorAnchorRetry, CURSOR_ANCHOR_RETRY_DELAY_MS);
        }
        if (floatingCandidateWindow != null) {
            floatingCandidateWindow.updateCursorAnchor(cursorAnchor);
        }
    }

    @Override
    public void onUpdateSelection(int oldSelStart, int oldSelEnd,
                                  int newSelStart, int newSelEnd,
                                  int candidatesStart, int candidatesEnd) {
        super.onUpdateSelection(oldSelStart, oldSelEnd, newSelStart, newSelEnd,
                candidatesStart, candidatesEnd);
        boolean selectionChanged = lastSelectionStart >= 0 && lastSelectionEnd >= 0
                ? newSelStart != lastSelectionStart || newSelEnd != lastSelectionEnd
                : newSelStart != oldSelStart || newSelEnd != oldSelEnd;
        lastSelectionStart = newSelStart;
        lastSelectionEnd = newSelEnd;
        if (candidatesStart >= 0 && engine != null && engine.hasComposition()) {
            composingRegionStart = candidatesStart;
        }

        boolean expectedSmartCursor = expectedSmartSelection >= 0
                && newSelStart == expectedSmartSelection
                && newSelEnd == expectedSmartSelection;
        if (expectedSmartCursor) expectedSmartSelection = -1;

        if (awaitingOwnSelectionUpdate || expectedSmartCursor) {
            return;
        }
        if (!selectionChanged || engine == null
                || (!engine.hasComposition() && engine.pageCount() == 0)) {
            return;
        }

        commitPendingComposition();
        engine.reset();
        appliedComposingText = "";
        touchHostText.reset();
        composingRegionStart = -1;
        expectedSmartSelection = -1;
        InputConnection connection = getCurrentInputConnection();
        if (connection != null) connection.finishComposingText();
        refreshKeyboard();
    }

    @Override
    public void onSharedPreferenceChanged(SharedPreferences preferences, String key) {
        if (key == null || ChineseInputMethodSettings.KEY_METHOD.equals(key) || key.startsWith("table_options.")) {
            if (engine != null) {
                if (key == null || key.startsWith("table_options.")) apply(engine.finishCompositionForModeSwitch());
                apply(engine.setChineseInputMethod(ChineseInputMethodSettings.method(this)));
                engine.tableOptions = ChineseInputMethodSettings.options(this, engine.chineseInputMethod());
            }
            refreshKeyboard();
            return;
        }
        if (BopomofoKeyboardLayoutSettings.KEY_LAYOUT.equals(key)) {
            if (engine != null) apply(engine.setKeyboardLayout(BopomofoKeyboardLayoutSettings.layout(this)));
            refreshKeyboard();
            return;
        }
        if (BopomofoCompositionModeSettings.KEY_MODE.equals(key)) {
            if (engine != null) {
                apply(engine.setChineseInputMethod(ChineseInputMethodSettings.method(this)));
                engine.tableOptions = ChineseInputMethodSettings.options(this, engine.chineseInputMethod());
            }
            refreshKeyboard();
            return;
        }
        if (BopomofoCompositionModeSettings.KEY_BIGRAM_ENABLED.equals(key)) {
            if (smartMandarinStore != null) {
                smartMandarinStore.setBigramEnabled(
                        BopomofoCompositionModeSettings.bigramEnabled(this));
            }
            // Preserve visible text and finish the old candidate session before
            // using a different scoring policy. Traditional input is unaffected.
            if (engine != null && engine.compositionMode() == BopomofoCompositionMode.SMART
                    && engine.inputMode() == BopomofoEngine.InputMode.BOPOMOFO) {
                apply(engine.finishCompositionForModeSwitch());
            } else {
                refreshKeyboard();
            }
            return;
        }
        if (SupporterState.KEY_SUPPORTER.equals(key)) {
            refreshKeyboard();
            return;
        }
        if (KeyPreviewSettings.KEY_ENABLED.equals(key)) {
            refreshKeyboard();
            return;
        }
        if (CandidateColorSettings.KEY_COLOR.equals(key)) {
            refreshKeyboard();
            return;
        }
        if (PhraseSettings.KEY_ENABLED_COLLECTIONS.equals(key)) {
            schedulePhraseDictionaryReload();
            return;
        }
        if (KeyboardBottomSpaceSettings.isSettingKey(key)) {
            updateKeyboardBottomSpace();
            return;
        }
        if (KeyboardSizeSettings.isSizeKey(key)) {
            updateKeyboardSize();
            return;
        }
        if (!CandidateWindowSettings.KEY_FLOATING_ENABLED.equals(key)
                && !CandidateWindowSettings.KEY_LAYOUT.equals(key)
                && !CandidateWindowSettings.KEY_NUMBER_ROW.equals(key)) return;
        floatingCandidateWindowAvailable = CandidateWindowSettings.floatingEnabled(this);
        updateKeyboardMode();
        requestCursorAnchorUpdates();
        refreshKeyboard();
    }

    @Override
    public void onKey(String key) {
        if (key.equals("HARDWARE_NUMBER_SHIFT")) {
            keyboardView.toggleHardwareNumberShift();
            return;
        }
        if (key.equals("HARDWARE_SYMBOL")) {
            apply(engine.showHardwareSymbols());
            return;
        }
        if (key.startsWith(BopomofoKeyboardView.HARDWARE_LITERAL_PREFIX)
                && key.length() == BopomofoKeyboardView.HARDWARE_LITERAL_PREFIX.length() + 1) {
            apply(engine.commitHardwareLiteral(key.charAt(key.length() - 1)));
            return;
        }
        if (key.equals("SETTINGS")) {
            apply(engine.finishCompositionForModeSwitch());
            Intent intent = new Intent(this, SettingsActivity.class);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
            return;
        }
        if (key.equals("HARDWARE_LANGUAGE")) {
            apply(engine.toggleHardwareLanguage());
            return;
        }
        if (key.equals("HARDWARE_WIDTH")) {
            apply(engine.toggleHardwareWidth());
            return;
        }
        if (key.equals("MODE") && fieldPolicy.isRestricted()) {
            fieldPolicyUnlocked = true;
            fieldPolicy = fieldPolicy.unrestricted();
            engine.setAllowedInputModes(fieldPolicy.allowedModes(),
                    fieldPolicy.preferredMode(), false);
        }
        if (!fieldPolicy.isKeyEnabled(key, engine.inputMode(), engine.isShifted())) return;
        apply(engine.handleSoftKey(key), key.equals("ENTER"));
    }

    @Override
    public void onCandidate(int displayedIndex) {
        apply(engine.selectDisplayedCandidate(displayedIndex));
    }

    @Override
    public void onSmartCell(int index) {
        if (engine.selectTouchSmartCell(index)) refreshKeyboard();
    }

    @Override
    public void onWindowUnavailable(CandidateWindowSettings.Failure failure) {
        if (!floatingCandidateWindowAvailable) return;
        floatingCandidateWindowAvailable = false;
        CandidateWindowSettings.disableForFailure(this, failure);
        updateKeyboardMode();
        refreshKeyboard();
    }

    @Override
    public void onPage(int delta) {
        engine.changePage(delta);
        refreshKeyboard();
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_DEL && hardwareBackspaceHeld) return true;
        if (keyCode != KeyEvent.KEYCODE_DEL && hardwareBackspaceHeld) stopHardwareBackspace();
        if (event.getRepeatCount() > 0 && (pressedCandidateKeys.contains(keyCode)
                || pressedHardwareShortcutKeys.contains(keyCode))) {
            return true;
        }
        if (isHardwareControlShortcut(keyCode, event)) {
            pressedHardwareShortcutKeys.add(keyCode);
            if (event.getRepeatCount() == 0) applyHardwareControlShortcut(keyCode);
            return true;
        }
        if (isHardwareWidthShortcut(keyCode, event)) {
            pressedHardwareShortcutKeys.add(keyCode);
            if (event.getRepeatCount() == 0) apply(engine.toggleHardwareWidth());
            return true;
        }
        if (event.isCtrlPressed() || event.isAltPressed() || event.isMetaPressed()) {
            return super.onKeyDown(keyCode, event);
        }
        engine.prepareForHardwareInput();
        boolean candidatesVisible = engine.pageCount() > 0;
        int candidateIndex = topRowDigitIndex(keyCode);
        boolean shiftPressed = HardwareShortcut.isShiftPressed(event.getMetaState());
        if (engine.isShowingAssociatedPhrases() && shiftPressed
                && candidateIndex >= 0) {
            pressedCandidateKeys.add(keyCode);
            apply(engine.selectDisplayedCandidate(candidateIndex));
            return true;
        }
        if (candidatesVisible && !engine.isShowingAssociatedPhrases()
                && !shiftPressed && candidateIndex >= 0) {
            pressedCandidateKeys.add(keyCode);
            apply(engine.selectDisplayedCandidate(candidateIndex));
            return true;
        }
        if (isFloatingCandidateMode() && candidatesVisible
                && handleFloatingCandidateNavigation(keyCode)) {
            pressedCandidateKeys.add(keyCode);
            return true;
        }
        if (engine.smartCompositionCursor() >= 0) {
            switch (keyCode) {
                case KeyEvent.KEYCODE_DPAD_LEFT -> {
                    pressedNavigationKeys.add(keyCode);
                    engine.moveSmartCompositionCursor(-1);
                    apply(BopomofoEngine.Result.update());
                    return true;
                }
                case KeyEvent.KEYCODE_DPAD_RIGHT -> {
                    pressedNavigationKeys.add(keyCode);
                    engine.moveSmartCompositionCursor(1);
                    apply(BopomofoEngine.Result.update());
                    return true;
                }
                case KeyEvent.KEYCODE_DPAD_UP -> {
                    pressedNavigationKeys.add(keyCode);
                    if (engine.isShowingSmartCandidates()) {
                        engine.moveHighlight(-1);
                        refreshKeyboard();
                    } else {
                        engine.moveSmartCompositionCursor(-1);
                        apply(BopomofoEngine.Result.update());
                    }
                    return true;
                }
                case KeyEvent.KEYCODE_DPAD_DOWN -> {
                    pressedNavigationKeys.add(keyCode);
                    if (engine.isShowingSmartCandidates()) {
                        engine.moveHighlight(1);
                        refreshKeyboard();
                    } else {
                        apply(engine.handleHardwareSpace());
                    }
                    return true;
                }
                default -> { }
            }
        }
        switch (keyCode) {
            case KeyEvent.KEYCODE_DEL -> {
                apply(engine.backspace());
                hardwareBackspaceHeld = true;
                hardwareBackspaceRepeater.start(() -> {
                    if (engine == null || getCurrentInputConnection() == null) {
                        stopHardwareBackspace();
                        return;
                    }
                    apply(engine.backspace());
                });
            }
            case KeyEvent.KEYCODE_SPACE -> {
                if (candidatesVisible) pressedCandidateKeys.add(keyCode);
                apply(engine.handleHardwareSpace());
            }
            case KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> {
                if (candidatesVisible) pressedCandidateKeys.add(keyCode);
                apply(engine.enter());
            }
            case KeyEvent.KEYCODE_ESCAPE -> {
                if (candidatesVisible) pressedCandidateKeys.add(keyCode);
                apply(engine.escape());
            }
            case KeyEvent.KEYCODE_PAGE_UP -> {
                if (candidatesVisible) pressedCandidateKeys.add(keyCode);
                engine.changePage(-1);
                refreshKeyboard();
            }
            case KeyEvent.KEYCODE_PAGE_DOWN -> {
                if (candidatesVisible) pressedCandidateKeys.add(keyCode);
                engine.changePage(1);
                refreshKeyboard();
            }
            default -> {
                int unicode = event.getUnicodeChar();
                if (unicode == 0 || Character.isISOControl(unicode)) {
                    return super.onKeyDown(keyCode, event);
                }
                apply(engine.handleHardwareCharacter((char) unicode));
            }
        }
        return true;
    }

    @Override
    public boolean onKeyUp(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_DEL && hardwareBackspaceHeld) {
            stopHardwareBackspace();
            return true;
        }
        if (pressedCandidateKeys.remove(keyCode)) return true;
        if (pressedNavigationKeys.remove(keyCode)) return true;
        if (pressedHardwareShortcutKeys.remove(keyCode)
                || isHardwareControlShortcut(keyCode, event)
                || isHardwareWidthShortcut(keyCode, event)) {
            return true;
        }
        return super.onKeyUp(keyCode, event);
    }

    private void stopHardwareBackspace() {
        hardwareBackspaceRepeater.stop();
        hardwareBackspaceHeld = false;
    }

    private boolean isHardwareControlShortcut(int keyCode, KeyEvent event) {
        return HardwareShortcut.isControlShortcut(keyCode, event.getMetaState());
    }

    private boolean isHardwareWidthShortcut(int keyCode, KeyEvent event) {
        return HardwareShortcut.isWidthToggle(keyCode, event.getMetaState());
    }

    private void applyHardwareControlShortcut(int keyCode) {
        switch (keyCode) {
            case KeyEvent.KEYCODE_SPACE -> apply(engine.toggleHardwareLanguage());
            case KeyEvent.KEYCODE_COMMA -> apply(engine.commitHardwarePunctuation("，"));
            case KeyEvent.KEYCODE_PERIOD -> apply(engine.commitHardwarePunctuation("。"));
            case KeyEvent.KEYCODE_0, KeyEvent.KEYCODE_1 -> apply(engine.showHardwareSymbols());
            default -> { }
        }
    }

    private int topRowDigitIndex(int keyCode) {
        if (keyCode < KeyEvent.KEYCODE_1 || keyCode > KeyEvent.KEYCODE_9) return -1;
        return keyCode - KeyEvent.KEYCODE_1;
    }

    private void apply(BopomofoEngine.Result result) {
        apply(result, false);
    }

    private void apply(BopomofoEngine.Result result, boolean softEnter) {
        InputConnection connection = getCurrentInputConnection();
        if (connection == null) {
            refreshKeyboard();
            return;
        }

        if (engine.isTouchSmartComposition() || !touchHostText.editableText().isEmpty()) {
            applyTouchSmart(connection, result, softEnter);
            return;
        }

        String nextReading = engine.composingText();
        boolean committedText = !result.committedText().isEmpty();
        boolean updateComposingText = !nextReading.isEmpty()
                && (!nextReading.equals(appliedComposingText)
                        || committedText || result.deleteBeforeCursor());
        boolean finishComposingText = nextReading.isEmpty()
                && (!appliedComposingText.isEmpty() || committedText);
        boolean changesSelection = result.deleteBeforeCursor() || committedText
                || result.discardComposingText() || updateComposingText;
        boolean keepsActiveState = engine.hasComposition() || engine.pageCount() > 0;
        if (changesSelection && keepsActiveState) expectOwnSelectionUpdate();

        connection.beginBatchEdit();
        try {
            if (result.deleteBeforeCursor()) deletePreviousGrapheme(connection);
            if (committedText) {
                connection.commitText(result.committedText(), 1);
                composingRegionStart = -1;
            }
            if (result.discardComposingText()) {
                // finishComposingText() preserves the underlined text. Committing an empty
                // replacement removes the composing region and finishes it in one operation.
                connection.commitText("", 1);
                appliedComposingText = "";
                composingRegionStart = -1;
            } else if (finishComposingText) {
                connection.finishComposingText();
                appliedComposingText = "";
                composingRegionStart = -1;
            } else if (updateComposingText) {
                if (composingRegionStart < 0 && lastSelectionStart >= 0) {
                    composingRegionStart = lastSelectionStart;
                }
                connection.setComposingText(nextReading, 1);
                appliedComposingText = nextReading;
            }
        } finally {
            connection.endBatchEdit();
        }

        if (engine.smartCompositionCursor() >= 0 && !nextReading.isEmpty()) {
            // setComposingText can only put the cursor outside the replacement.
            // Move it inside the marked sentence with setSelection instead.
            if (updateComposingText) {
                ExtractedText extracted = connection.getExtractedText(
                        new ExtractedTextRequest(), 0);
                if (extracted != null && extracted.selectionStart >= 0) {
                    composingRegionStart = extracted.startOffset
                            + extracted.selectionStart - nextReading.length();
                }
            }
            if (composingRegionStart >= 0) {
                int position = composingRegionStart + engine.composingCaretUtf16Offset();
                expectOwnSelectionUpdate();
                expectedSmartSelection = position;
                if (!connection.setSelection(position, position)) expectedSmartSelection = -1;
            }
        }

        if (result.sendEnter()) {
            boolean performedAction = softEnter && fieldPolicy.hasEditorAction()
                    && connection.performEditorAction(fieldPolicy.editorAction());
            if (!performedAction) {
                connection.sendKeyEvent(new KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER));
                connection.sendKeyEvent(new KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER));
            }
        }
        refreshKeyboard();
    }

    private void applyTouchSmart(InputConnection connection, BopomofoEngine.Result result,
                                 boolean softEnter) {
        TouchSmartHostTextState.Edit edit;
        if (engine.isTouchSmartComposition() && engine.hasComposition()) {
            edit = touchHostText.update(engine.completedSmartText(), result.committedText());
        } else if (engine.isTouchSmartComposition() && result.committedText().isEmpty()
                && !result.deleteBeforeCursor() && !result.sendEnter()) {
            edit = touchHostText.cancel();
        } else {
            edit = touchHostText.finish(result.committedText());
        }

        boolean changesSelection = !edit.isEmpty() || result.deleteBeforeCursor()
                || result.sendEnter();
        if (changesSelection && (engine.hasComposition() || engine.pageCount() > 0)) {
            expectOwnSelectionUpdate();
        }
        connection.beginBatchEdit();
        try {
            if (!appliedComposingText.isEmpty()) {
                connection.commitText("", 1);
                appliedComposingText = "";
                composingRegionStart = -1;
            }
            if (edit.deleteCount() > 0) {
                connection.deleteSurroundingText(edit.deleteCount(), 0);
            }
            if (!edit.insertion().isEmpty()) connection.commitText(edit.insertion(), 1);
            if (result.deleteBeforeCursor()) deletePreviousGrapheme(connection);
        } finally {
            connection.endBatchEdit();
        }

        if (result.sendEnter()) {
            boolean performedAction = softEnter && fieldPolicy.hasEditorAction()
                    && connection.performEditorAction(fieldPolicy.editorAction());
            if (!performedAction) {
                connection.sendKeyEvent(new KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER));
                connection.sendKeyEvent(new KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER));
            }
        }
        refreshKeyboard();
    }

    private void expectOwnSelectionUpdate() {
        awaitingOwnSelectionUpdate = true;
        int generation = ++selectionMutationGeneration;
        mainHandler.postDelayed(() -> {
            if (selectionMutationGeneration == generation) {
                awaitingOwnSelectionUpdate = false;
            }
        }, 200);
    }

    private void cancelExpectedSelectionUpdate() {
        selectionMutationGeneration++;
        awaitingOwnSelectionUpdate = false;
    }

    private void deletePreviousGrapheme(InputConnection connection) {
        CharSequence beforeCursor = connection.getTextBeforeCursor(64, 0);
        int characterCount = TextDeletion.previousGraphemeLength(beforeCursor);
        if (characterCount > 0) connection.deleteSurroundingText(characterCount, 0);
        else connection.deleteSurroundingTextInCodePoints(1, 0);
    }

    private void refreshKeyboard() {
        if (keyboardView == null || engine == null) return;
        keyboardView.setChineseInputMethod(engine.chineseInputMethod());
        keyboardView.setKeyboardLayout(engine.keyboardLayout());
        keyboardView.setKeyPreviewEnabled(KeyPreviewSettings.enabled(this));
        updateKeyboardSize();
        CandidateColorSettings.CandidateColor candidateColor = CandidateColorSettings.color(this);
        keyboardView.setCandidateHighlightColors(
                CandidateColorSettings.backgroundColor(candidateColor),
                CandidateColorSettings.textColor(candidateColor));
        boolean supportPromptVisible = SupporterState.shouldShowSupportPrompt(this);
        boolean smartBopomofo = engine.chineseInputMethod() == ChineseInputMethod.SMART
                && engine.compositionMode() == BopomofoCompositionMode.SMART
                && engine.inputMode() == BopomofoEngine.InputMode.BOPOMOFO;
        keyboardView.setAssociatedPhrasesVisible(engine.isShowingAssociatedPhrases());
        keyboardView.setState(engine.displayedCandidates(), engine.composingText(),
                engine.compositionMode() == BopomofoCompositionMode.SMART
                        && engine.inputMode() == BopomofoEngine.InputMode.BOPOMOFO,
                engine.touchSmartCells(), engine.touchSmartEditableCount(),
                engine.inputMode(), engine.isShifted(), engine.isTemporaryEnglish(),
                engine.isHardwareFullWidth(), supportPromptVisible,
                engine.page(), engine.pageCount(),
                engine.isShowingAssociatedPhrases() ? -1 : engine.highlightedIndex(), fieldPolicy);
        if (isFloatingCandidateMode() && floatingCandidateWindow != null) {
            boolean candidatesVisible = !engine.displayedCandidates().isEmpty();
            boolean openingCandidates = candidatesVisible && !floatingCandidatesVisible;
            floatingCandidatesVisible = candidatesVisible;
            if (openingCandidates) {
                // A request accepted during IME binding can lose its monitor on Android 8.
                // Re-arm it when opening candidates, even if an older anchor is available.
                cursorAnchorRetryCount = 0;
                requestCursorAnchorUpdates();
            }
            if (!candidatesVisible) mainHandler.removeCallbacks(cursorAnchorRetry);
            floatingCandidateWindow.update(engine.displayedCandidates(),
                    engine.highlightedIndex(), floatingCandidateLayout, cursorAnchor,
                    supportPromptVisible && smartBopomofo);
        } else {
            hideFloatingCandidates();
        }
    }

    private void schedulePhraseDictionaryReload() {
        if (engine == null || dictionaryLoader.isShutdown()) return;
        Set<String> enabled = new LinkedHashSet<>(PhraseSettings.enabledCollections(this));
        if (enabled.equals(loadedPhraseCollections)) {
            if (pendingPhraseCollections != null
                    && !enabled.equals(pendingPhraseCollections)) {
                phraseLoadGeneration++;
                pendingPhraseCollections = null;
            }
            return;
        }
        if (enabled.equals(pendingPhraseCollections)) {
            return;
        }
        pendingPhraseCollections = Set.copyOf(enabled);
        int generation = ++phraseLoadGeneration;
        dictionaryLoader.execute(() -> {
            if (generation != phraseLoadGeneration) return;
            AssociatedPhraseDictionary dictionary;
            try {
                dictionary = AssociatedPhraseDictionary.load(getAssets(), enabled);
            } catch (IOException error) {
                dictionary = AssociatedPhraseDictionary.empty();
            }
            AssociatedPhraseDictionary loadedDictionary = dictionary;
            mainHandler.post(() -> {
                if (generation != phraseLoadGeneration || engine == null) return;
                engine.setAssociatedPhraseDictionary(loadedDictionary);
                loadedPhraseCollections = Set.copyOf(enabled);
                pendingPhraseCollections = null;
                refreshKeyboard();
            });
        });
    }

    private void updateKeyboardSize() {
        if (keyboardView == null) return;
        keyboardView.setTouchKeyboardHeightPercents(
                KeyboardSizeSettings.portraitPercent(this),
                KeyboardSizeSettings.landscapePercent(this));
    }

    private void updateKeyboardBottomSpace() {
        if (keyboardView == null) return;
        keyboardView.setBottomSpaceEnabled(KeyboardBottomSpaceSettings.touchEnabled(this),
                KeyboardBottomSpaceSettings.hardwareEnabled(this));
    }

    private void updateKeyboardMode() {
        Configuration configuration = getResources().getConfiguration();
        hardwareKeyboard = configuration.keyboard != Configuration.KEYBOARD_NOKEYS
                && configuration.hardKeyboardHidden == Configuration.HARDKEYBOARDHIDDEN_NO;
        if (engine != null) engine.setHardwareSmartEditing(hardwareKeyboard);
        floatingCandidatesEnabled = CandidateWindowSettings.floatingEnabled(this);
        floatingCandidateLayout = CandidateWindowSettings.layout(this);
        if (keyboardView == null) return;
        updateKeyboardBottomSpace();
        keyboardView.setHardwareNumberRowEnabled(CandidateWindowSettings.numberRowEnabled(this));
        if (hardwareKeyboard) {
            keyboardView.setMode(isFloatingCandidateMode()
                    ? BopomofoKeyboardView.Mode.HARDWARE_FLOATING
                    : BopomofoKeyboardView.Mode.HARDWARE);
        } else if (configuration.orientation == Configuration.ORIENTATION_LANDSCAPE) {
            keyboardView.setMode(BopomofoKeyboardView.Mode.LANDSCAPE);
        } else {
            keyboardView.setMode(BopomofoKeyboardView.Mode.PORTRAIT);
        }
        if (!isFloatingCandidateMode()) hideFloatingCandidates();
    }

    private boolean isFloatingCandidateMode() {
        return hardwareKeyboard && floatingCandidatesEnabled && floatingCandidateWindowAvailable;
    }

    private boolean handleFloatingCandidateNavigation(int keyCode) {
        boolean vertical = floatingCandidateLayout == CandidateWindowSettings.Layout.VERTICAL;
        if ((vertical && keyCode == KeyEvent.KEYCODE_DPAD_UP)
                || (!vertical && keyCode == KeyEvent.KEYCODE_DPAD_LEFT)) {
            engine.moveHighlight(-1);
            refreshKeyboard();
            return true;
        }
        if ((vertical && keyCode == KeyEvent.KEYCODE_DPAD_DOWN)
                || (!vertical && keyCode == KeyEvent.KEYCODE_DPAD_RIGHT)) {
            engine.moveHighlight(1);
            refreshKeyboard();
            return true;
        }
        if ((vertical && keyCode == KeyEvent.KEYCODE_DPAD_LEFT)
                || (!vertical && keyCode == KeyEvent.KEYCODE_DPAD_UP)) {
            engine.changePage(-1);
            refreshKeyboard();
            return true;
        }
        if ((vertical && keyCode == KeyEvent.KEYCODE_DPAD_RIGHT)
                || (!vertical && keyCode == KeyEvent.KEYCODE_DPAD_DOWN)) {
            engine.changePage(1);
            refreshKeyboard();
            return true;
        }
        return false;
    }

    private void resetCursorAnchor() {
        mainHandler.removeCallbacks(cursorAnchorRetry);
        cursorAnchorRetryCount = 0;
        cursorAnchorRequestPending = false;
        cursorAnchor = null;
        floatingCandidatesVisible = false;
    }

    private void retryCursorAnchorUpdates() {
        if (!cursorAnchorRequestPending || !floatingCandidatesVisible
                || !isFloatingCandidateMode() || getCurrentInputConnection() == null) return;
        if (cursorAnchorRetryCount >= MAX_CURSOR_ANCHOR_RETRIES) {
            onWindowUnavailable(CandidateWindowSettings.Failure.CURSOR_ANCHOR);
            return;
        }
        cursorAnchorRetryCount++;
        requestCursorAnchorUpdates();
    }

    private void requestCursorAnchorUpdates() {
        mainHandler.removeCallbacks(cursorAnchorRetry);
        InputConnection connection = getCurrentInputConnection();
        if (connection == null) return;
        if (!isFloatingCandidateMode()) {
            connection.requestCursorUpdates(0);
            resetCursorAnchor();
            return;
        }
        cursorAnchorRequestPending = true;
        int mode = InputConnection.CURSOR_UPDATE_IMMEDIATE
                | InputConnection.CURSOR_UPDATE_MONITOR;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            connection.requestCursorUpdates(mode,
                    InputConnection.CURSOR_UPDATE_FILTER_INSERTION_MARKER);
        } else {
            connection.requestCursorUpdates(mode);
        }
        // Only judge failure while candidates are needed. An accepted request can
        // still produce no callback; give it one retry, then disable floating mode.
        if (floatingCandidatesVisible && cursorAnchorRequestPending) {
            mainHandler.postDelayed(cursorAnchorRetry, CURSOR_ANCHOR_RETRY_DELAY_MS);
        }
    }

    private RectF insertionMarkerBounds(CursorAnchorInfo information) {
        if (information == null) return null;
        int flags = information.getInsertionMarkerFlags();
        if ((flags & CursorAnchorInfo.FLAG_HAS_INVISIBLE_REGION) != 0
                && (flags & CursorAnchorInfo.FLAG_HAS_VISIBLE_REGION) == 0) return null;
        float horizontal = information.getInsertionMarkerHorizontal();
        float top = information.getInsertionMarkerTop();
        float bottom = information.getInsertionMarkerBottom();
        if (!Float.isFinite(horizontal) || !Float.isFinite(top) || !Float.isFinite(bottom)) {
            return null;
        }
        float[] points = {horizontal, top, horizontal, bottom};
        information.getMatrix().mapPoints(points);
        return new RectF(points[0], Math.min(points[1], points[3]),
                points[2], Math.max(points[1], points[3]));
    }

    private void hideFloatingCandidates() {
        floatingCandidatesVisible = false;
        mainHandler.removeCallbacks(cursorAnchorRetry);
        if (floatingCandidateWindow != null) floatingCandidateWindow.hide();
    }
}
