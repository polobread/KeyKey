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
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.inputmethod.CursorAnchorInfo;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.ExtractedText;
import android.view.inputmethod.ExtractedTextRequest;
import android.view.inputmethod.InputConnection;
import android.view.inputmethod.InputMethodManager;

import java.io.File;
import java.io.IOException;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class BopomofoImeService extends InputMethodService
        implements BopomofoKeyboardView.Listener, FloatingCandidateWindow.Listener,
        SharedPreferences.OnSharedPreferenceChangeListener {
    private HostInputEngine engine;
    private String lastReportedCoreError;
    private boolean hostTransactionFailed;
    private BopomofoKeyboardView keyboardView;
    private KeyboardInputView keyboardInputView;
    private boolean pressedSizeControlsBack;
    private FloatingCandidateWindow floatingCandidateWindow;
    private Vibrator vibrator;
    private Set<String> loadedPhraseCollections;
    private Set<String> pendingPhraseCollections;
    private volatile int phraseLoadGeneration;
    private boolean hardwareKeyboard;
    private boolean tableVirtualKeyboard = true;
    private boolean hardwareCandidatesCollapsed;
    private boolean hardwareSmartTwoRows;
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
    // Sending a plain Enter may change editors before the physical KeyUp.
    // Keep its ownership across input-session callbacks until that KeyUp arrives.
    private final Set<Integer> pressedEnterKeys = new LinkedHashSet<>();
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
    private final KeyboardBottomControlsPolicy bottomControlsPolicy = new KeyboardBottomControlsPolicy();
    private WindowInsetsController captionController;
    private boolean captionHideRequested;
    private boolean updatingBottomControls;
    private boolean destroying;
    private boolean rebuildingForConfiguration;
    private WindowInsetsController.OnControllableInsetsChangedListener captionControlListener;

    @Override
    public void onCreate() {
        super.onCreate();
        openEngine();
        schedulePhraseDictionaryReload();
        vibrator = getSystemService(Vibrator.class);
        CandidateWindowSettings.preferences(this)
                .registerOnSharedPreferenceChangeListener(this);
        SupporterState.preferences(this)
                .registerOnSharedPreferenceChangeListener(this);
    }

    private void openEngine() {
        try {
            File model = SharedModelDatabase.install(this);
            ChineseInputMethod method = ChineseInputMethodSettings.method(this);
            engine = new HostInputEngine(model.getAbsolutePath(),
                    new File(getFilesDir(), GuanyinmaUserData.FILE_NAME).getAbsolutePath(), method,
                    BopomofoKeyboardLayoutSettings.layout(this),
                    ChineseInputMethodSettings.options(this, method, tableVirtualKeyboard),
                    BopomofoCompositionModeSettings.spaceSelectsCandidates(this),
                    BopomofoCompositionModeSettings.bigramEnabled(this),
                    CandidateGlyphSupport.shared()::canDisplay);
            // A recreated session has no FE association dictionary yet. Invalidate
            // old async callbacks and reload even when the selected sources match.
            phraseLoadGeneration++;
            loadedPhraseCollections = null;
            pendingPhraseCollections = null;
        } catch (IOException | RuntimeException | LinkageError error) {
            engine = null;
            android.util.Log.e("KeyKey", "Guanyinma core unavailable", error);
            android.widget.Toast.makeText(this, "無法啟用輸入核心，請重新啟用琦琦輸入法。",
                    android.widget.Toast.LENGTH_LONG).show();
        }
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
        // InputMethodService recreates this view during configuration changes.
        // Dispose the previous window before replacing its only owner reference.
        hideFloatingCandidates();
        dismissKeyboardSizeControls();
        keyboardView = new BopomofoKeyboardView(this);
        keyboardView.setListener(this);
        keyboardInputView = new KeyboardInputView(this, keyboardView);
        keyboardView.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener() {
            @Override public void onViewAttachedToWindow(View view) {
                if (view == keyboardView) updateKeyboardBottomControls();
            }
            @Override public void onViewDetachedFromWindow(View view) {
                if (view == keyboardView) releaseCaptionController();
            }
        });
        if (Build.VERSION.SDK_INT >= 36) {
            keyboardView.setOnApplyWindowInsetsListener((view, insets) -> {
                WindowInsets remaining = view.onApplyWindowInsets(insets);
                view.post(BopomofoImeService.this::updateKeyboardBottomControls);
                return remaining;
            });
        }
        floatingCandidateWindow = new FloatingCandidateWindow(this, keyboardView, this);
        updateKeyboardMode();
        requestCursorAnchorUpdates();
        refreshKeyboard();
        return keyboardInputView;
    }

    @Override
    public boolean onEvaluateInputViewShown() {
        super.onEvaluateInputViewShown();
        return !hardwareCandidatesCollapsed;
    }

    @Override
    public boolean onShowInputRequested(int flags, boolean configChange) {
        // Rotation or another configuration replay must not undo a manual hide.
        if (configChange && hardwareCandidatesCollapsed) return false;
        boolean restoreCollapsedCandidates = !configChange && hardwareCandidatesCollapsed;
        if (!configChange) hardwareCandidatesCollapsed = false;
        boolean show = super.onShowInputRequested(flags, configChange);
        // A fresh editor-tap request may be implicit with a physical keyboard.
        return show || restoreCollapsedCandidates;
    }

    @Override
    public boolean onEvaluateFullscreenMode() {
        return false;
    }

    @Override
    public void onStartInput(EditorInfo attribute, boolean restarting) {
        super.onStartInput(attribute, restarting);
        if (engine == null) openEngine();
        stopHardwareBackspace();
        if (!restarting) {
            fieldPolicyUnlocked = false;
            dismissKeyboardSizeControls();
        }
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
            boolean lostMarkedRange = restarting && !hostTransactionFailed
                    && !restoreMarkedComposition();
            boolean releasedRange = true;
            if (lostMarkedRange) {
                // The new connection cannot prove ownership of the old range.
                // Keep the host text, and never replay the old engine's commit.
                InputConnection connection = getCurrentInputConnection();
                releasedRange = connection != null && connection.finishComposingText();
            }
            if (!restarting || hostTransactionFailed || lostMarkedRange) {
                abandonHostEffects();
                hostTransactionFailed = !releasedRange;
                appliedComposingText = "";
                touchHostText.reset();
                composingRegionStart = -1;
                expectedSmartSelection = -1;
                if (engine != null) synchronizeInputPreferences();
            }
            if (engine != null) engine.setAllowedInputModes(fieldPolicy.allowedModes(), fieldPolicy.preferredMode(),
                    layoutChanged);
        }
        updateKeyboardMode();
        requestCursorAnchorUpdates();
        refreshKeyboard();
    }

    /** A restarted InputConnection may have finished its old composing span. */
    private boolean restoreMarkedComposition() {
        if (appliedComposingText.isEmpty() || engine.isTouchSmartComposition()
                || !touchHostText.editableText().isEmpty()) return true;
        InputConnection connection = getCurrentInputConnection();
        if (connection == null || composingRegionStart < 0) return false;
        ExtractedText current = connection.getExtractedText(new ExtractedTextRequest(), 0);
        if (current == null || current.text == null || current.startOffset < 0
                || current.partialStartOffset >= 0 || current.selectionStart < 0
                || current.selectionStart != current.selectionEnd
                || current.selectionEnd > current.text.length()
                || composingRegionStart > Integer.MAX_VALUE - appliedComposingText.length()) return false;
        long relativeStart = (long) composingRegionStart - current.startOffset;
        long relativeEnd = relativeStart + appliedComposingText.length();
        if (relativeStart < 0 || relativeEnd > current.text.length()
                || (!rebuildingForConfiguration && (current.selectionStart < relativeStart
                        || current.selectionStart > relativeEnd))
                || !appliedComposingText.equals(current.text.subSequence(
                        (int) relativeStart, (int) relativeEnd).toString())) return false;
        int end = composingRegionStart + appliedComposingText.length();
        expectOwnSelectionUpdate();
        if (!connection.setComposingRegion(composingRegionStart, end)) return false;
        // EditorInfo can contain the field's original selection after rotation.
        // Restore the retained engine caret, rather than that stale position.
        int caret = composingRegionStart + engine.composingCaretUtf16Offset();
        if (caret < composingRegionStart || caret > end
                || !connection.setSelection(caret, caret)) return false;
        lastSelectionStart = lastSelectionEnd = caret;
        expectedSmartSelection = caret;
        return true;
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
            if (engine != null) engine.setAllowedInputModes(fieldPolicy.allowedModes(), fieldPolicy.preferredMode(),
                    layoutChanged);
        }
        updateKeyboardMode();
        requestCursorAnchorUpdates();
        refreshKeyboard();
    }

    @Override
    public void onFinishInput() {
        dismissKeyboardSizeControls();
        stopHardwareBackspace();
        commitPendingComposition();
        if (engine != null) abandonHostEffects();
        hostTransactionFailed = false;
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
        dismissKeyboardSizeControls();
        commitPendingComposition();
        super.onFinishInputView(finishingInput);
    }

    @Override
    public void onWindowHidden() {
        dismissKeyboardSizeControls();
        stopHardwareBackspace();
        commitPendingComposition();
        hideFloatingCandidates();
        super.onWindowHidden();
    }

    @Override public void onWindowShown() {
        super.onWindowShown();
        updateKeyboardBottomControls();
    }

    @Override public void onCustomImeSwitcherButtonRequestedVisible(boolean visible) {
        bottomControlsPolicy.onCustomSwitcherRequested(visible);
        updateKeyboardBottomControls();
    }

    private void synchronizeInputPreferences() {
        // Preferences changed while a former host rejected effects are applied
        // only after that host's state was explicitly discarded.
        apply(engine.setChineseInputMethod(ChineseInputMethodSettings.method(this)));
        apply(engine.setKeyboardLayout(BopomofoKeyboardLayoutSettings.layout(this)));
        engine.setTableOptions(ChineseInputMethodSettings.options(this, engine.chineseInputMethod(), tableVirtualKeyboard));
        engine.setSpaceSelectsCandidates(BopomofoCompositionModeSettings.spaceSelectsCandidates(this));
        engine.setUseBigrams(BopomofoCompositionModeSettings.bigramEnabled(this));
    }

    private void abandonHostEffects() {
        if (engine == null) return;
        try {
            engine.abandonHostEffects();
        } catch (RuntimeException error) {
            android.util.Log.e("KeyKey", "Unable to discard previous host state", error);
            engine.close();
            engine = null;
            android.widget.Toast.makeText(this, "輸入核心無法重設，請重新點選文字欄位。",
                    android.widget.Toast.LENGTH_LONG).show();
        }
    }

    private void commitPendingComposition() {
        if (engine == null || !engine.hasComposition()
                || getCurrentInputConnection() == null) return;
        apply(engine.finishCompositionForInputHandoff());
    }

    private boolean finishCompositionForKeyboardHide() {
        InputConnection original = getCurrentInputConnection();
        if (engine == null || hostTransactionFailed || !engine.hasComposition()
                || original == null) return true;
        InputEngine.Result result = engine.finishCompositionForKeyboardHide();
        boolean completed = engine.coreError() == null && !engine.hasComposition();
        // Apply successful earlier effects once even if a later adapter step
        // failed. Do not hide into the generic handoff path after that failure.
        apply(result);
        return completed && !hostTransactionFailed && getCurrentInputConnection() == original;
    }

    @Override
    public void onDestroy() {
        destroying = true;
        releaseCaptionController();
        stopHardwareBackspace();
        CandidateWindowSettings.preferences(this)
                .unregisterOnSharedPreferenceChangeListener(this);
        SupporterState.preferences(this)
                .unregisterOnSharedPreferenceChangeListener(this);
        if (engine != null) { engine.close(); engine = null; }
        phraseLoadGeneration++;
        dictionaryLoader.shutdownNow();
        mainHandler.removeCallbacksAndMessages(null);
        hideFloatingCandidates();
        super.onDestroy();
    }

    @Override
    public void onConfigurationChanged(Configuration newConfig) {
        dismissKeyboardSizeControls();
        hideFloatingCandidates();
        resetCursorAnchor();
        rebuildingForConfiguration = true;
        try {
            super.onConfigurationChanged(newConfig);
        } finally {
            rebuildingForConfiguration = false;
        }
        stopHardwareBackspace();
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
        if (UserDataNotifications.KEY_CHANGED.equals(key)) {
            if (engine != null) apply(engine.refreshUserData());
            return;
        }
        if (key == null || ChineseInputMethodSettings.KEY_METHOD.equals(key) || key.startsWith("table_options.")) {
            if (engine != null) {
                if (key == null) engine.setSpaceSelectsCandidates(
                        BopomofoCompositionModeSettings.spaceSelectsCandidates(this));
                if (key == null || key.startsWith("table_options.")) apply(engine.finishCompositionForModeSwitch());
                apply(engine.setChineseInputMethod(ChineseInputMethodSettings.method(this)));
                engine.setTableOptions(ChineseInputMethodSettings.options(this, engine.chineseInputMethod(), tableVirtualKeyboard));
            }
            refreshKeyboard();
            return;
        }
        if (BopomofoKeyboardLayoutSettings.KEY_LAYOUT.equals(key)) {
            if (engine != null) apply(engine.setKeyboardLayout(BopomofoKeyboardLayoutSettings.layout(this)));
            refreshKeyboard();
            return;
        }
        if (BopomofoCompositionModeSettings.KEY_SPACE_SELECTS_CANDIDATES.equals(key)) {
            if (engine != null) engine.setSpaceSelectsCandidates(
                    BopomofoCompositionModeSettings.spaceSelectsCandidates(this));
            return;
        }
        if (BopomofoCompositionModeSettings.KEY_MODE.equals(key)) {
            if (engine != null) {
                apply(engine.setChineseInputMethod(ChineseInputMethodSettings.method(this)));
                engine.setTableOptions(ChineseInputMethodSettings.options(this, engine.chineseInputMethod(), tableVirtualKeyboard));
            }
            refreshKeyboard();
            return;
        }
        if (BopomofoCompositionModeSettings.KEY_BIGRAM_ENABLED.equals(key)) {
            if (engine != null && engine.compositionMode() == BopomofoCompositionMode.SMART
                    && engine.inputMode() == InputEngine.InputMode.BOPOMOFO) {
                apply(engine.finishCompositionForModeSwitch());
            }
            boolean enabled = BopomofoCompositionModeSettings.bigramEnabled(this);
            if (engine != null) engine.setUseBigrams(enabled);
            refreshKeyboard();
            return;
        }
        if (SupporterState.KEY_SUPPORTER.equals(key)) {
            refreshKeyboard();
            return;
        }
        if (KeyboardLayoutProfileSettings.isSettingKey(key)) {
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
        if (KeyboardBottomControlsSettings.KEY_ENABLED.equals(key)) {
            updateKeyboardBottomControls();
            return;
        }
        if (KeyboardSizeSettings.isSizeKey(key)) {
            updateKeyboardSize();
            return;
        }
        if (!CandidateWindowSettings.KEY_FLOATING_ENABLED.equals(key)
                && !CandidateWindowSettings.KEY_LAYOUT.equals(key)
                && !CandidateWindowSettings.KEY_NUMBER_ROW.equals(key)
                && !CandidateWindowSettings.KEY_SMART_TWO_ROWS.equals(key)) return;
        floatingCandidateWindowAvailable = CandidateWindowSettings.floatingEnabled(this);
        updateKeyboardMode();
        requestCursorAnchorUpdates();
        refreshKeyboard();
    }

    @Override
    public void onKey(String key) {
        if (key.equals("DISMISS")) {
            if (finishCompositionForKeyboardHide()) requestHideSelf(0);
            return;
        }
        if (key.equals("GLOBE")) {
            switchToNextKeyboard();
            return;
        }
        if (engine == null || hostTransactionFailed) return;
        if (key.equals("CLOSE_CANDIDATES")) {
            apply(engine.closeTouchSmartCandidates());
            return;
        }
        if (key.equals("HARDWARE_COLLAPSE")) {
            collapseHardwareCandidates();
            return;
        }
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
            if (keyboardInputView != null && keyboardView.isTouchMode()) {
                keyboardInputView.showSettingsMenu(this::openKeyboardSettings);
            } else {
                openKeyboardSettings();
            }
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
        useTableKeyboard(!hardwareKeyboard);
        apply(engine.handleSoftKey(key), key.equals("ENTER"));
    }

    private void openKeyboardSettings() {
        if (engine == null || hostTransactionFailed) return;
        apply(engine.finishCompositionForModeSwitch());
        Intent intent = new Intent(this, SettingsActivity.class);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        startActivity(intent);
    }

    private void dismissKeyboardSizeControls() {
        if (keyboardInputView != null) keyboardInputView.cancelResize();
    }

    @Override
    public void onCandidate(int displayedIndex) {
        if (engine == null || hostTransactionFailed) return;
        apply(engine.selectDisplayedCandidate(displayedIndex));
    }

    @Override
    public void onSmartCell(int index) {
        if (engine == null || hostTransactionFailed) return;
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
        if (engine == null || hostTransactionFailed) return;
        engine.changePage(delta);
        refreshKeyboard();
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            if (event.getRepeatCount() == 0) {
                pressedSizeControlsBack = keyboardInputView != null && keyboardInputView.hasSizeControls();
            }
            if (pressedSizeControlsBack) return true;
        } else {
            dismissKeyboardSizeControls();
        }
        if (event.getRepeatCount() == 0 && (keyCode == KeyEvent.KEYCODE_ENTER
                || keyCode == KeyEvent.KEYCODE_NUMPAD_ENTER)) {
            // The previous Up can be lost when switching input methods. A new
            // press must not inherit its ownership, including modified Enter.
            pressedEnterKeys.remove(keyCode);
            pressedCandidateKeys.remove(keyCode);
        }
        if (engine == null) return super.onKeyDown(keyCode, event);
        if (hostTransactionFailed) {
            if (keyCode == KeyEvent.KEYCODE_ENTER || keyCode == KeyEvent.KEYCODE_NUMPAD_ENTER) {
                pressedEnterKeys.add(keyCode);
            }
            return true;
        }
        // A key can arrive before the hardware configuration callback. Finish
        // the already-inserted touch tail before adopting marked host text.
        if (!hardwareSmartTwoRows && !touchHostText.editableText().isEmpty()
                && !KeyEvent.isModifierKey(keyCode) && keyCode != KeyEvent.KEYCODE_CAPS_LOCK
                && keyCode != KeyEvent.KEYCODE_NUM_LOCK && keyCode != KeyEvent.KEYCODE_SCROLL_LOCK) {
            commitPendingComposition();
        }
        useTableKeyboard(false);
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
                    apply(InputEngine.Result.update());
                    return true;
                }
                case KeyEvent.KEYCODE_DPAD_RIGHT -> {
                    pressedNavigationKeys.add(keyCode);
                    engine.moveSmartCompositionCursor(1);
                    apply(InputEngine.Result.update());
                    return true;
                }
                case KeyEvent.KEYCODE_DPAD_UP -> {
                    pressedNavigationKeys.add(keyCode);
                    if (engine.isShowingSmartCandidates()) {
                        engine.moveHighlight(-1);
                        refreshKeyboard();
                    } else {
                        engine.moveSmartCompositionCursor(-1);
                        apply(InputEngine.Result.update());
                    }
                    return true;
                }
                case KeyEvent.KEYCODE_DPAD_DOWN -> {
                    pressedNavigationKeys.add(keyCode);
                    if (engine.isShowingSmartCandidates()) {
                        engine.moveHighlight(1);
                        refreshKeyboard();
                    } else {
                        apply(engine.openSmartCandidates());
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
                    if (engine == null || hostTransactionFailed || getCurrentInputConnection() == null) {
                        stopHardwareBackspace();
                        return;
                    }
                    apply(engine.backspace());
                });
            }
            case KeyEvent.KEYCODE_FORWARD_DEL -> {
                boolean hadComposition = engine.hasComposition();
                apply(engine.deleteForward());
                if (!hadComposition) return super.onKeyDown(keyCode, event);
                pressedNavigationKeys.add(keyCode);
            }
            case KeyEvent.KEYCODE_SPACE -> {
                if (candidatesVisible) pressedCandidateKeys.add(keyCode);
                apply(engine.handleHardwareSpace());
            }
            case KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> {
                pressedEnterKeys.add(keyCode);
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
        if (keyCode == KeyEvent.KEYCODE_BACK && pressedSizeControlsBack) {
            pressedSizeControlsBack = false;
            if (!event.isCanceled()) dismissKeyboardSizeControls();
            return true;
        }
        if (pressedEnterKeys.remove(keyCode)) {
            pressedCandidateKeys.remove(keyCode);
            return true;
        }
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

    private void apply(InputEngine.Result result) {
        apply(result, false);
    }

    private void apply(InputEngine.Result result, boolean softEnter) {
        InputConnection connection = getCurrentInputConnection();
        if (connection == null || hostTransactionFailed) {
            if (!result.committedText().isEmpty() || result.deleteBeforeCursor()
                    || result.sendEnter() || result.discardComposingText()) hostTransactionFailed = true;
            refreshKeyboard();
            return;
        }

        boolean applied = false;
        try {
            applied = applyToConnection(connection, result, softEnter);
            if (!applied) {
                hostTransactionFailed = true;
                android.widget.Toast.makeText(this, "目前欄位未接受輸入，請重新點選文字欄位。",
                        android.widget.Toast.LENGTH_LONG).show();
            }
        } finally {
            // An absent/replaced host cannot acknowledge the old transaction.
            if (applied && connection == getCurrentInputConnection() && engine != null) {
                engine.acknowledgeHostEffects();
            }
            refreshKeyboard();
        }
    }

    private boolean applyToConnection(InputConnection connection, InputEngine.Result result,
                                      boolean softEnter) {
        if (engine.isTouchSmartComposition() || !touchHostText.editableText().isEmpty()) {
            return applyTouchSmart(connection, result, softEnter);
        }
        boolean accepted = true;

        String nextReading = engine.composingText();
        boolean committedText = !result.committedText().isEmpty();
        boolean updateComposingText = !nextReading.isEmpty()
                && (!nextReading.equals(appliedComposingText)
                        || committedText || result.deleteBeforeCursor());
        boolean finishComposingText = nextReading.isEmpty()
                && (!appliedComposingText.isEmpty() || committedText);
        boolean changesSelection = result.deleteBeforeCursor() || committedText
                || result.discardComposingText() || updateComposingText || result.sendEnter();
        if (changesSelection) expectOwnSelectionUpdate();

        connection.beginBatchEdit();
        try {
            if (result.deleteBeforeCursor()) accepted &= deletePreviousGrapheme(connection);
            if (committedText) {
                accepted &= connection.commitText(result.committedText(), 1);
                composingRegionStart = -1;
            }
            if (result.discardComposingText()) {
                // finishComposingText() preserves the underlined text. Committing an empty
                // replacement removes the composing region and finishes it in one operation.
                accepted &= connection.commitText("", 1);
                appliedComposingText = "";
                composingRegionStart = -1;
            } else if (finishComposingText) {
                // commitText already finishes the marked range. Only a real
                // remaining finish operation participates in acknowledgement.
                if (!committedText) accepted &= connection.finishComposingText();
                appliedComposingText = "";
                composingRegionStart = -1;
            } else if (updateComposingText) {
                if (composingRegionStart < 0 && lastSelectionStart >= 0) {
                    composingRegionStart = lastSelectionStart;
                }
                accepted &= connection.setComposingText(nextReading, 1);
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
                accepted &= connection.sendKeyEvent(new KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER));
                accepted &= connection.sendKeyEvent(new KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER));
            }
        }
        return accepted;
    }

    private boolean applyTouchSmart(InputConnection connection, InputEngine.Result result,
                                    boolean softEnter) {
        boolean accepted = true;
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
        if (changesSelection) expectOwnSelectionUpdate();
        connection.beginBatchEdit();
        try {
            if (!appliedComposingText.isEmpty()) {
                accepted &= connection.commitText("", 1);
                appliedComposingText = "";
                composingRegionStart = -1;
            }
            if (edit.deleteCount() > 0) {
                accepted &= connection.deleteSurroundingText(edit.deleteCount(), 0);
            }
            if (!edit.insertion().isEmpty()) accepted &= connection.commitText(edit.insertion(), 1);
            if (result.deleteBeforeCursor()) accepted &= deletePreviousGrapheme(connection);
        } finally {
            connection.endBatchEdit();
        }

        if (result.sendEnter()) {
            boolean performedAction = softEnter && fieldPolicy.hasEditorAction()
                    && connection.performEditorAction(fieldPolicy.editorAction());
            if (!performedAction) {
                accepted &= connection.sendKeyEvent(new KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER));
                accepted &= connection.sendKeyEvent(new KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER));
            }
        }
        return accepted;
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

    private boolean deletePreviousGrapheme(InputConnection connection) {
        CharSequence beforeCursor = connection.getTextBeforeCursor(64, 0);
        int characterCount = TextDeletion.previousGraphemeLength(beforeCursor);
        if (characterCount > 0) return connection.deleteSurroundingText(characterCount, 0);
        return connection.deleteSurroundingTextInCodePoints(1, 0);
    }

    private void refreshKeyboard() {
        if (keyboardView == null || engine == null) return;
        String coreError = engine.coreError();
        if (coreError != null && !coreError.equals(lastReportedCoreError)) {
            android.util.Log.w("KeyKey", coreError);
            String message = "Guanyinma 暫時無法完成操作。";
            android.widget.Toast.makeText(this, message, android.widget.Toast.LENGTH_LONG).show();
        }
        lastReportedCoreError = coreError;
        keyboardView.setLayoutProfile(KeyboardLayoutProfileSettings.profile(this));
        keyboardView.setLayoutOptions(KeyboardLayoutProfileSettings.keycapArea(this),
                KeyboardLayoutProfileSettings.fontSize(this),
                KeyboardLayoutProfileSettings.deletePosition(this));
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
                && engine.inputMode() == InputEngine.InputMode.BOPOMOFO;
        keyboardView.setAssociatedPhrasesVisible(engine.isShowingAssociatedPhrases());
        keyboardView.setState(engine.displayedCandidates(), engine.composingText(),
                engine.compositionMode() == BopomofoCompositionMode.SMART
                        && engine.inputMode() == InputEngine.InputMode.BOPOMOFO,
                engine.touchSmartCells(hardwareSmartTwoRows ? 9
                        : keyboardView.compositionCellCount()), engine.touchSmartEditableCount(),
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
        keyboardView.setTouchKeyboardSizes(
                KeyboardSizeSettings.size(this, false),
                KeyboardSizeSettings.size(this, true));
    }

    private void updateKeyboardBottomSpace() {
        if (keyboardView == null) return;
        keyboardView.setBottomSpaceEnabled(KeyboardBottomSpaceSettings.touchEnabled(this),
                KeyboardBottomSpaceSettings.hardwareEnabled(this));
    }

    private void updateKeyboardBottomControls() {
        if (keyboardView == null || updatingBottomControls || destroying) return;
        updatingBottomControls = true;
        try {
            boolean integrated = !hardwareKeyboard && KeyboardBottomControlsSettings.enabled(this);
            if (Build.VERSION.SDK_INT >= 36) {
                if (captionControlListener == null) captionControlListener = (controller, types) -> {
                    if (controller != captionController) return;
                    updateKeyboardBottomControls();
                };
                WindowInsetsController controller = keyboardView.getWindowInsetsController();
                if (controller != captionController) {
                    releaseCaptionController();
                    captionController = controller;
                    if (controller != null) controller.addOnControllableInsetsChangedListener(captionControlListener);
                }
                if (!integrated) restoreCaptionBar();
                else if (captionController != null && !captionHideRequested) {
                    WindowInsets insets = keyboardView.getRootWindowInsets();
                    // Do not take ownership of an already hidden, system-managed bar.
                    if (insets != null && insets.isVisible(WindowInsets.Type.captionBar())) {
                        captionHideRequested = true;
                        captionController.hide(WindowInsets.Type.captionBar());
                    }
                }
            }
            boolean globe = bottomControlsPolicy.showGlobe(Build.VERSION.SDK_INT >= 36);
            keyboardView.setIntegratedBottomControls(integrated, globe);
        } finally {
            updatingBottomControls = false;
        }
    }

    private void restoreCaptionBar() {
        if (Build.VERSION.SDK_INT >= 36 && captionController != null && captionHideRequested) {
            captionHideRequested = false;
            captionController.show(WindowInsets.Type.captionBar());
        }
    }

    private void releaseCaptionController() {
        if (Build.VERSION.SDK_INT < 36) return;
        boolean wasUpdating = updatingBottomControls;
        updatingBottomControls = true;
        try {
            restoreCaptionBar();
            if (captionController != null) captionController.removeOnControllableInsetsChangedListener(captionControlListener);
            captionController = null;
        } finally {
            updatingBottomControls = wasUpdating;
        }
    }

    @SuppressWarnings("deprecation")
    private void switchToNextKeyboard() {
        boolean switched = false;
        if (Build.VERSION.SDK_INT >= 28) switched = switchToNextInputMethod(false);
        else {
            InputMethodManager manager = getSystemService(InputMethodManager.class);
            if (manager != null && getWindow() != null && getWindow().getWindow() != null
                    && getWindow().getWindow().getAttributes().token != null)
                switched = manager.switchToNextInputMethod(getWindow().getWindow().getAttributes().token, false);
        }
        if (!switched) onInputMethodPicker();
    }

    @Override public void onInputMethodPicker() {
        InputMethodManager manager = getSystemService(InputMethodManager.class);
        if (manager != null) manager.showInputMethodPicker();
    }

    private void useTableKeyboard(boolean virtualKeyboard) {
        if (engine == null || tableVirtualKeyboard == virtualKeyboard) return;
        if (engine.chineseInputMethod().isTable()) apply(engine.finishCompositionForInputHandoff());
        tableVirtualKeyboard = virtualKeyboard;
        engine.setTableOptions(ChineseInputMethodSettings.options(this, engine.chineseInputMethod(), virtualKeyboard));
    }

    private void updateKeyboardMode() {
        Configuration configuration = getResources().getConfiguration();
        hardwareKeyboard = configuration.keyboard != Configuration.KEYBOARD_NOKEYS
                && configuration.hardKeyboardHidden == Configuration.HARDKEYBOARDHIDDEN_NO;
        useTableKeyboard(!hardwareKeyboard);
        if (!hardwareKeyboard) hardwareCandidatesCollapsed = false;
        floatingCandidatesEnabled = CandidateWindowSettings.floatingEnabled(this);
        floatingCandidateLayout = CandidateWindowSettings.layout(this);
        boolean nextSmartTwoRows = hardwareKeyboard && !isFloatingCandidateMode()
                && CandidateWindowSettings.smartTwoRowsEnabled(this);
        // Finish using the old host-text strategy before switching between
        // marked desktop composition and the touch keyboard's editable tail.
        boolean strategyChanged = engine != null && engine.compositionMode() == BopomofoCompositionMode.SMART
                && engine.isTouchSmartComposition() != (!hardwareKeyboard || nextSmartTwoRows);
        if (nextSmartTwoRows != hardwareSmartTwoRows || strategyChanged) commitPendingComposition();
        hardwareSmartTwoRows = nextSmartTwoRows;
        if (engine != null) {
            engine.setHardwareTouchSmartEditing(hardwareSmartTwoRows);
            engine.setHardwareSmartEditing(hardwareKeyboard && !hardwareSmartTwoRows);
        }
        if (keyboardView == null) return;
        updateKeyboardBottomSpace();
        keyboardView.setHardwareSmartTwoRowsEnabled(hardwareSmartTwoRows);
        keyboardView.setHardwareNumberRowEnabled(CandidateWindowSettings.numberRowEnabled(this));
        BopomofoKeyboardView.Mode nextMode;
        if (hardwareKeyboard) {
            nextMode = isFloatingCandidateMode()
                    ? BopomofoKeyboardView.Mode.HARDWARE_FLOATING
                    : BopomofoKeyboardView.Mode.HARDWARE;
        } else {
            nextMode = configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
                    ? BopomofoKeyboardView.Mode.LANDSCAPE : BopomofoKeyboardView.Mode.PORTRAIT;
        }
        if (keyboardView.mode() != nextMode) dismissKeyboardSizeControls();
        keyboardView.setMode(nextMode);
        if (!isFloatingCandidateMode()) hideFloatingCandidates();
        updateKeyboardBottomControls();
    }

    private boolean isFloatingCandidateMode() {
        return hardwareKeyboard && floatingCandidatesEnabled && floatingCandidateWindowAvailable;
    }

    private void collapseHardwareCandidates() {
        if (!hardwareKeyboard || isFloatingCandidateMode()) return;
        stopHardwareBackspace();
        if (!finishCompositionForKeyboardHide()) return;
        hardwareCandidatesCollapsed = true;
        hideFloatingCandidates();
        // Hide the IME window as well as its contents so Android returns the
        // candidate, number/symbol and bottom-reserve area to the host app.
        requestHideSelf(0);
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
