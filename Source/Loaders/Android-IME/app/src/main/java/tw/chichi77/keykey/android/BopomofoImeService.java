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
import java.util.concurrent.Executor;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.BooleanSupplier;

public final class BopomofoImeService extends InputMethodService
        implements BopomofoKeyboardView.Listener, FloatingCandidateWindow.Listener,
        HardwareQuickSettingsWindow.Listener,
        SharedPreferences.OnSharedPreferenceChangeListener {
    private HostInputEngine engine;
    private String lastReportedCoreError;
    private boolean hostTransactionFailed;
    private boolean simplifiedChineseOutput;
    private SimplifiedChineseOutput simplifiedChineseConverter;
    private BopomofoKeyboardView keyboardView;
    private FloatingCandidateWindow floatingCandidateWindow;
    private HardwareQuickSettingsWindow hardwareQuickSettings;
    private Vibrator vibrator;
    private Set<String> loadedPhraseCollections;
    private Set<String> pendingPhraseCollections;
    private volatile int phraseLoadGeneration;
    private boolean hardwareKeyboard;
    private boolean tableVirtualKeyboard = true;
    private boolean inputPreferencesDirty;
    private boolean synchronizingInputPreferences;
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
    private volatile long cursorAnchorHostGeneration;
    private volatile long cursorAnchorRequestGeneration;
    private InputConnection cursorAnchorMonitorConnection;
    private long cursorAnchorMonitorHostGeneration;
    private boolean cursorAnchorMonitoring;
    private final ExecutorService cursorAnchorRequests = Executors.newSingleThreadExecutor(runnable ->
            new Thread(runnable, "KeyKey cursor anchor requests"));
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
    private final OwnSelectionTracker ownSelections = new OwnSelectionTracker();
    private boolean hostSelectionWriteStarted;
    private OwnSelectionTracker.Anchor pendingInitialAnchor;
    private String appliedComposingText = "";
    private boolean appliedTouchReading;
    // Chinese kept marked only until its real marked-end ACK supplies an anchor.
    // This is completed text, not an unresolved phonetic reading to cancel.
    private boolean appliedTouchAnchorProbe;
    private final TouchSmartHostTextState touchHostText = new TouchSmartHostTextState();
    private int composingRegionStart = -1;
    private boolean inputViewFinishingForHandoff;
    private final KeyboardBottomControlsPolicy bottomControlsPolicy = new KeyboardBottomControlsPolicy();
    private WindowInsetsController captionController;
    private boolean captionHideRequested;
    private boolean updatingBottomControls;
    private volatile boolean destroying;
    private boolean rebuildingForConfiguration;
    private WindowInsetsController.OnControllableInsetsChangedListener captionControlListener;

    @Override
    public void onCreate() {
        super.onCreate();
        KeyboardSettingsProfile.migrate(this);
        tableVirtualKeyboard = !hasHardwareKeyboard();
        hardwareKeyboard = !tableVirtualKeyboard;
        simplifiedChineseOutput = ChineseInputMethodSettings.simplifiedChineseOutput(this, tableVirtualKeyboard);
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
            ChineseInputMethod method = ChineseInputMethodSettings.method(this, tableVirtualKeyboard);
            engine = new HostInputEngine(model.getAbsolutePath(),
                    new File(getFilesDir(), GuanyinmaUserData.FILE_NAME).getAbsolutePath(), method,
                    BopomofoKeyboardLayoutSettings.layout(this, tableVirtualKeyboard),
                    ChineseInputMethodSettings.options(this, method, tableVirtualKeyboard),
                    BopomofoCompositionModeSettings.spaceSelectsCandidates(this, tableVirtualKeyboard),
                    BopomofoCompositionModeSettings.bigramEnabled(this, tableVirtualKeyboard),
                    CandidateGlyphSupport.shared()::canDisplay);
            engine.setHardwareOptions(HardwareSmartSettings.options(this));
            engine.setHardwareTouchSmartEditing(hardwareKeyboard && !CandidateWindowSettings.floatingEnabled(this)
                    && CandidateWindowSettings.smartTwoRowsEnabled(this));
            engine.setHardwareSmartEditing(hardwareKeyboard && (CandidateWindowSettings.floatingEnabled(this)
                    || !CandidateWindowSettings.smartTwoRowsEnabled(this)));
            synchronizeTouchPhoneticGrid();
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
        int durationMs = HapticSettings.durationMs(this, !hardwareKeyboard);
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
        dismissHardwareQuickSettings();
        keyboardView = new BopomofoKeyboardView(this);
        keyboardView.setListener(this);
        KeyboardInputView inputView = new KeyboardInputView(this, keyboardView);
        keyboardView.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener() {
            @Override public void onViewAttachedToWindow(View view) {
                if (view == keyboardView) updateKeyboardBottomControls();
            }
            @Override public void onViewDetachedFromWindow(View view) {
                if (view == keyboardView) releaseCaptionController();
            }
        });
        if (Build.VERSION.SDK_INT >= 36) {
            inputView.setOnApplyWindowInsetsListener((view, insets) -> {
                WindowInsets remaining = view.onApplyWindowInsets(insets);
                view.post(BopomofoImeService.this::updateKeyboardBottomControls);
                return remaining;
            });
        }
        floatingCandidateWindow = new FloatingCandidateWindow(this, keyboardView, this);
        hardwareQuickSettings = new HardwareQuickSettingsWindow(this, keyboardView, this);
        updateKeyboardMode();
        requestCursorAnchorUpdates();
        refreshKeyboard();
        return inputView;
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
        int retainedSelectionStart = lastSelectionStart;
        int retainedSelectionEnd = lastSelectionEnd;
        super.onStartInput(attribute, restarting);
        cursorAnchorHostGeneration++;
        if (engine == null) openEngine();
        stopHardwareBackspace();
        if (!restarting) {
            dismissHardwareQuickSettings();
            fieldPolicyUnlocked = false;
        }
        resetCursorAnchor();
        // A restarted EditorInfo may still contain the field's original caret.
        // Only its current IC snapshot can anchor new writes after a restart.
        lastSelectionStart = restarting || attribute == null ? -1 : attribute.initialSelStart;
        lastSelectionEnd = restarting || attribute == null ? -1 : attribute.initialSelEnd;
        ownSelections.clear();
        hostSelectionWriteStarted = false;
        pendingInitialAnchor = null;
        schedulePhraseDictionaryReload();
        InputFieldPolicy nextPolicy = InputFieldPolicy.from(attribute);
        if (fieldPolicyUnlocked) nextPolicy = nextPolicy.unrestricted();
        boolean layoutChanged = !fieldPolicy.hasSameLayout(nextPolicy);
        fieldPolicy = nextPolicy;
        if (engine != null) {
            boolean ownedMarkedRange = ownsMarkedComposition();
            InputConnection restartConnection = getCurrentInputConnection();
            long restartHost = cursorAnchorHostGeneration;
            long restartEpoch = ownSelections.epoch();
            boolean lostMarkedRange = restarting && !hostTransactionFailed
                    && !restoreMarkedComposition(restartConnection, retainedSelectionStart, retainedSelectionEnd);
            if (restartConnection != getCurrentInputConnection() || restartHost != cursorAnchorHostGeneration
                    || restartEpoch != ownSelections.epoch()) return;
            boolean releasedRange = true;
            if (lostMarkedRange && ownedMarkedRange) {
                // The new connection cannot prove ownership of the old range.
                // Keep the host text, and never replay the old engine's commit.
                InputConnection connection = getCurrentInputConnection();
                releasedRange = connection != null && connection.finishComposingText();
            }
            if (!restarting || hostTransactionFailed || lostMarkedRange) {
                abandonHostEffects();
                hostTransactionFailed = !releasedRange;
                appliedComposingText = "";
                appliedTouchReading = false;
                appliedTouchAnchorProbe = false;
                touchHostText.reset();
                composingRegionStart = -1;
                if (engine != null) synchronizeInputPreferences();
            }
            if (layoutChanged && appliedTouchReading) commitPendingComposition();
            if (engine != null && !hostTransactionFailed) {
                engine.setAllowedInputModes(fieldPolicy.allowedModes(), fieldPolicy.preferredMode(), layoutChanged);
            }
        }
        updateKeyboardMode();
        requestCursorAnchorUpdates();
        refreshKeyboard();
    }

    private boolean ownsMarkedComposition() {
        return !appliedComposingText.isEmpty() && (appliedTouchReading || appliedTouchAnchorProbe
                || (!engine.isTouchSmartComposition() && touchHostText.editableText().isEmpty()));
    }

    /** Refresh the actual caret once, sharing that snapshot with retained-range validation. */
    private boolean restoreMarkedComposition(InputConnection connection, int retainedStart, int retainedEnd) {
        boolean marked = ownsMarkedComposition();
        String editable = touchHostText.editableText();
        if (connection == null) return !marked && editable.isEmpty();
        long host = cursorAnchorHostGeneration;
        long epoch = ownSelections.epoch();
        ExtractedText current = null;
        try {
            current = connection.getExtractedText(new ExtractedTextRequest(), 0);
        } catch (RuntimeException unavailable) {
            // An unavailable snapshot never proves the old EditorInfo's caret.
        }
        if (connection != getCurrentInputConnection() || host != cursorAnchorHostGeneration
                || epoch != ownSelections.epoch()) return false;
        OwnSelectionTracker.Anchor anchor = current == null || current.text == null ? null
                : OwnSelectionTracker.Anchor.fromFullSnapshot(current.startOffset, current.text.length(),
                        current.partialStartOffset, current.partialEndOffset,
                        current.selectionStart, current.selectionEnd);
        if (anchor == null) return !marked && editable.isEmpty();
        // A query may dispatch a newer real selection on this same looper.
        if ((lastSelectionStart >= 0 || lastSelectionEnd >= 0)
                && (lastSelectionStart != anchor.start() || lastSelectionEnd != anchor.end())) return false;
        // A failed early restart probe must not spend the first actual write's
        // opportunity to obtain a current anchor. Valid restarts share this one.
        hostSelectionWriteStarted = true;
        lastSelectionStart = anchor.start();
        lastSelectionEnd = anchor.end();
        pendingInitialAnchor = anchor;
        if (!marked) {
            if (editable.isEmpty()) return true;
            // Ordinary touch Chinese is committed, but its mutable suffix is
            // owned only at the previously accepted caret, with identical text.
            long relativeEnd = (long) anchor.end() - current.startOffset;
            long relativeStart = relativeEnd - editable.length();
            return retainedStart == retainedEnd && anchor.start() == retainedStart
                    && anchor.end() == retainedEnd && relativeStart >= 0
                    && editable.contentEquals(current.text.subSequence((int) relativeStart, (int) relativeEnd));
        }
        if (composingRegionStart < 0 || anchor.start() != anchor.end()
                || composingRegionStart > Integer.MAX_VALUE - appliedComposingText.length()) return false;
        long relativeStart = (long) composingRegionStart - current.startOffset;
        long relativeEnd = relativeStart + appliedComposingText.length();
        if (relativeStart < 0 || relativeEnd > current.text.length()
                || (!rebuildingForConfiguration && (current.selectionStart < relativeStart
                        || current.selectionStart > relativeEnd))
                || !appliedComposingText.equals(current.text.subSequence(
                        (int) relativeStart, (int) relativeEnd).toString())) return false;
        if (appliedTouchReading) {
            long editableStart = relativeStart - editable.length();
            if (editableStart < 0 || !editable.contentEquals(current.text.subSequence(
                    (int) editableStart, (int) relativeStart))) return false;
        }
        int end = composingRegionStart + appliedComposingText.length();
        if (!setOwnComposingRegion(connection, composingRegionStart, end)) return false;
        // Restore the retained engine caret, rather than stale EditorInfo.
        int caret = appliedTouchReading || appliedTouchAnchorProbe ? end : composingRegionStart + engine.composingCaretUtf16Offset();
        return caret >= composingRegionStart && caret <= end && setOwnSelection(connection, caret, caret);
    }

    @Override
    public void onStartInputView(EditorInfo info, boolean restarting) {
        super.onStartInputView(info, restarting);
        inputViewFinishingForHandoff = false;
        stopHardwareBackspace();
        schedulePhraseDictionaryReload();
        InputFieldPolicy nextPolicy = InputFieldPolicy.from(info);
        if (fieldPolicyUnlocked) nextPolicy = nextPolicy.unrestricted();
        boolean layoutChanged = !fieldPolicy.hasSameLayout(nextPolicy);
        fieldPolicy = nextPolicy;
        if (engine != null) {
            if (layoutChanged && appliedTouchReading) commitPendingComposition();
            if (engine != null && !hostTransactionFailed) {
                engine.setAllowedInputModes(fieldPolicy.allowedModes(), fieldPolicy.preferredMode(), layoutChanged);
            }
        }
        updateKeyboardMode();
        requestCursorAnchorUpdates();
        refreshKeyboard();
    }

    @Override
    public void onFinishInput() {
        inputViewFinishingForHandoff = true;
        cursorAnchorHostGeneration++;
        dismissHardwareQuickSettings();
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
        appliedTouchReading = false;
        appliedTouchAnchorProbe = false;
        touchHostText.reset();
        composingRegionStart = -1;
        fieldPolicyUnlocked = false;
        ownSelections.clear();
        hideFloatingCandidates();
        super.onFinishInput();
    }

    @Override
    public void onFinishInputView(boolean finishingInput) {
        dismissHardwareQuickSettings();
        inputViewFinishingForHandoff = finishingInput || rebuildingForConfiguration;
        if (inputViewFinishingForHandoff) commitPendingComposition();
        else finishCompositionForKeyboardHide();
        super.onFinishInputView(finishingInput);
    }

    @Override
    public void onWindowHidden() {
        dismissHardwareQuickSettings();
        stopHardwareBackspace();
        if (inputViewFinishingForHandoff || rebuildingForConfiguration) commitPendingComposition();
        else finishCompositionForKeyboardHide();
        hideFloatingCandidates();
        super.onWindowHidden();
    }

    @Override public void onWindowShown() {
        super.onWindowShown();
        inputViewFinishingForHandoff = false;
        updateKeyboardBottomControls();
        if (keyboardView != null && keyboardView.isTouchMode()) {
            keyboardView.requestApplyInsets();
        }
    }

    @Override public void onCustomImeSwitcherButtonRequestedVisible(boolean visible) {
        bottomControlsPolicy.onCustomSwitcherRequested(visible);
        updateKeyboardBottomControls();
    }

    private void synchronizeInputPreferences() {
        inputPreferencesDirty = true;
        if (engine == null || hostTransactionFailed || synchronizingInputPreferences || engine.hasComposition()) return;
        synchronizingInputPreferences = true;
        inputPreferencesDirty = false;
        try {
            // All old host effects are already acknowledged before this boundary.
            apply(engine.setChineseInputMethod(ChineseInputMethodSettings.method(this, tableVirtualKeyboard)));
            apply(engine.setKeyboardLayout(BopomofoKeyboardLayoutSettings.layout(this, tableVirtualKeyboard)));
            engine.setTableOptions(ChineseInputMethodSettings.options(this, engine.chineseInputMethod(), tableVirtualKeyboard));
            engine.setSpaceSelectsCandidates(BopomofoCompositionModeSettings.spaceSelectsCandidates(this, tableVirtualKeyboard));
            engine.setUseBigrams(BopomofoCompositionModeSettings.bigramEnabled(this, tableVirtualKeyboard));
            engine.setHardwareOptions(HardwareSmartSettings.options(this));
            simplifiedChineseOutput = ChineseInputMethodSettings.simplifiedChineseOutput(this, tableVirtualKeyboard);
            synchronizeTouchPhoneticGrid();
            updateHardwareQuickSettings();
        } finally { synchronizingInputPreferences = false; }
    }

    private void synchronizeTouchPhoneticGrid() {
        if (engine == null || hostTransactionFailed) return;
        boolean enabled = (tableVirtualKeyboard || hardwareSmartTwoRows)
                && engine.chineseInputMethod() == ChineseInputMethod.SMART
                && BopomofoCompositionModeSettings.omitTone(this, tableVirtualKeyboard);
        if (enabled == engine.touchPhoneticGridEnabled()) return;
        commitPendingComposition();
        if (!hostTransactionFailed && !engine.hasComposition()) engine.setTouchPhoneticGrid(enabled);
    }

    private void abandonHostEffects() { abandonHostEffects(false); }

    private void abandonHostEffects(boolean preserveSelectionIntentions) {
        if (!preserveSelectionIntentions) ownSelections.clear();
        pendingInitialAnchor = null;
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
        if (engine == null || hostTransactionFailed || !engine.hasComposition()) return true;
        if (original == null) {
            // There is no host to accept a hide transaction. Discard its local
            // pending state rather than replaying it when a connection returns.
            abandonHostEffects();
            appliedComposingText = "";
            appliedTouchReading = false;
            appliedTouchAnchorProbe = false;
            touchHostText.reset();
            composingRegionStart = -1;
            lastSelectionStart = lastSelectionEnd = -1;
            return true;
        }
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
        ownSelections.clear();
        cursorAnchorHostGeneration++;
        cursorAnchorRequestGeneration++;
        cursorAnchorRequests.shutdownNow();
        dismissHardwareQuickSettings();
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
        dismissHardwareQuickSettings();
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
        if (destroying || !cursorAnchorMonitoring
                || cursorAnchorMonitorHostGeneration != cursorAnchorHostGeneration
                || cursorAnchorMonitorConnection != getCurrentInputConnection()) return;
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
        if (pendingInitialAnchor != null && candidatesStart == -1 && candidatesEnd == -1
                && newSelStart == pendingInitialAnchor.start() && newSelEnd == pendingInitialAnchor.end()
                && ((oldSelStart < 0 || oldSelEnd < 0)
                        || (oldSelStart == newSelStart && oldSelEnd == newSelEnd))) {
            // The initial snapshot can precede a delayed startup notification.
            // Observe it once without rewinding a subsequent accepted write;
            // a real reported movement from another position still falls through.
            pendingInitialAnchor = null;
            return;
        }
        OwnSelectionTracker.Match own = ownSelections.consume(newSelStart, newSelEnd, candidatesStart, candidatesEnd);
        if (own == OwnSelectionTracker.Match.SUPERSEDED) return;
        if (own == OwnSelectionTracker.Match.CURRENT) {
            lastSelectionStart = newSelStart;
            lastSelectionEnd = newSelEnd;
            if (candidatesStart >= 0) composingRegionStart = candidatesStart;
            if (candidatesStart >= 0 && appliedTouchAnchorProbe) scheduleTouchAnchorProbeFinish();
            return;
        }
        boolean noOwnedHostText = appliedComposingText.isEmpty() && touchHostText.editableText().isEmpty()
                && ownSelections.pendingCount() == 0;
        if ((lastSelectionStart < 0 || lastSelectionEnd < 0) && newSelStart >= 0 && newSelEnd >= 0
                && (oldSelStart < 0 || oldSelEnd < 0) && noOwnedHostText) {
            // A host may publish its first real selection after local phonetic
            // input starts. With no earlier position or owned host text this is
            // an initial observation, not evidence of an external cursor move.
            lastSelectionStart = newSelStart;
            lastSelectionEnd = newSelEnd;
            return;
        }
        boolean reportedNoMovement = oldSelStart >= 0 && oldSelEnd >= 0
                && oldSelStart == newSelStart && oldSelEnd == newSelEnd;
        boolean currentMarkedRange = !appliedComposingText.isEmpty() && composingRegionStart >= 0
                && candidatesStart == composingRegionStart
                && candidatesEnd == addKnownOffset(composingRegionStart, appliedComposingText.length());
        boolean unexpectedCurrentCaret = currentMarkedRange
                && (newSelStart != lastSelectionStart || newSelEnd != lastSelectionEnd);
        boolean probeCaretInsideMarked = appliedTouchAnchorProbe && candidatesStart >= 0
                && candidatesEnd >= candidatesStart
                && (long) candidatesEnd - candidatesStart == appliedComposingText.length()
                && newSelStart == newSelEnd && newSelStart >= candidatesStart
                && newSelEnd < candidatesEnd;
        if (reportedNoMovement && !unexpectedCurrentCaret && !probeCaretInsideMarked) {
            // An initial/duplicate old==new notification may lag behind our
            // accepted write. Its stale unmarked range is not a user move and
            // must not rewind the newer predicted caret or commit raw reading.
            if (noOwnedHostText) {
                lastSelectionStart = newSelStart;
                lastSelectionEnd = newSelEnd;
            }
            return;
        }
        boolean reportedMovement = oldSelStart >= 0 && oldSelEnd >= 0
                && (newSelStart != oldSelStart || newSelEnd != oldSelEnd);
        boolean selectionChanged = probeCaretInsideMarked || reportedMovement || (lastSelectionStart >= 0 && lastSelectionEnd >= 0
                ? newSelStart != lastSelectionStart || newSelEnd != lastSelectionEnd
                : newSelStart != oldSelStart || newSelEnd != oldSelEnd);
        // Idle notifications can establish an initially omitted EditorInfo
        // selection even when old==new. While composing, a duplicate ACK must
        // not overwrite a newer accepted caret or composing anchor.
        if (!selectionChanged) {
            if (engine == null || !engine.hasComposition()) {
                lastSelectionStart = newSelStart;
                lastSelectionEnd = newSelEnd;
            }
            return;
        }
        lastSelectionStart = newSelStart;
        lastSelectionEnd = newSelEnd;
        int previousComposingStart = composingRegionStart;
        if (candidatesStart >= 0 && engine != null && engine.hasComposition()) composingRegionStart = candidatesStart;
        if (engine == null || (!engine.hasComposition() && engine.pageCount() == 0)) return;

        boolean hadMarkedText = !appliedComposingText.isEmpty();
        boolean retainsOwnedMarkedRange = hadMarkedText && previousComposingStart >= 0
                && candidatesStart == previousComposingStart
                && candidatesEnd == addKnownOffset(previousComposingStart, appliedComposingText.length());
        if (appliedTouchAnchorProbe) {
            ProbeRelease release = releaseTouchAnchorProbeAfterCursorMove(previousComposingStart,
                    candidatesStart, candidatesEnd, newSelStart, newSelEnd);
            if (release == ProbeRelease.SUPERSEDED) return;
            if (release == ProbeRelease.UNVERIFIED) {
                // Do not let the next key overwrite a range whose ownership
                // cannot be verified. Rebinding the field is an explicit boundary.
                hostTransactionFailed = true;
                android.widget.Toast.makeText(this, "目前欄位未接受輸入，請重新點選文字欄位。",
                        android.widget.Toast.LENGTH_LONG).show();
                refreshKeyboard();
                return;
            }
            abandonHostEffects(true); // Keep the proven finish's pending ACK.
        } else if (appliedTouchReading) {
            ownSelections.clear();
            abandonHostEffects();
            releaseTouchReadingAfterCursorMove(previousComposingStart, candidatesStart, candidatesEnd,
                    newSelStart, newSelEnd);
        } else if (hadMarkedText && !retainsOwnedMarkedRange) {
            // The host already released/replaced our marked range. Re-committing
            // the old text would insert it again at the user's new caret.
            // Do not finish a different marked range now owned by the host.
            abandonHostEffects();
        } else {
            ownSelections.clear();
            commitPendingComposition();
            if (hostTransactionFailed || engine == null) { refreshKeyboard(); return; }
            engine.reset();
        }
        appliedComposingText = "";
        appliedTouchReading = false;
        appliedTouchAnchorProbe = false;
        touchHostText.reset();
        composingRegionStart = -1;
        refreshKeyboard();
    }

    private enum ProbeRelease { RELEASED, UNVERIFIED, SUPERSEDED }

    /** Release only a still-owned temporary Chinese span; never reinsert its text. */
    private ProbeRelease releaseTouchAnchorProbeAfterCursorMove(int previousStart, int start, int end,
            int selectionStart, int selectionEnd) {
        InputConnection connection = getCurrentInputConnection();
        long host = cursorAnchorHostGeneration;
        long epoch = ownSelections.epoch();
        String expected = appliedComposingText;
        if (connection == null || start < 0 || end < start
                || (long) end - start != expected.length()
                || selectionStart != selectionEnd || selectionStart < start || selectionEnd > end
                || (previousStart >= 0 ? start != previousStart
                        : !ownSelections.hasUnknownComposing(expected.length()))) return ProbeRelease.UNVERIFIED;
        int beforeCount = selectionStart - start;
        int afterCount = end - selectionEnd;
        CharSequence before, after;
        try {
            before = beforeCount == 0 ? "" : connection.getTextBeforeCursor(beforeCount, 0);
            after = afterCount == 0 ? "" : connection.getTextAfterCursor(afterCount, 0);
        } catch (RuntimeException unavailable) {
            return connection == getCurrentInputConnection() && host == cursorAnchorHostGeneration
                    && epoch == ownSelections.epoch() ? ProbeRelease.UNVERIFIED : ProbeRelease.SUPERSEDED;
        }
        if (connection != getCurrentInputConnection() || host != cursorAnchorHostGeneration
                || epoch != ownSelections.epoch()) return ProbeRelease.SUPERSEDED;
        if (before == null || after == null || before.length() < beforeCount || after.length() < afterCount
                || !expected.equals(before.subSequence(before.length() - beforeCount, before.length()).toString()
                        + after.subSequence(0, afterCount))) return ProbeRelease.UNVERIFIED;
        ownSelections.clear();
        long releaseEpoch = ownSelections.epoch();
        var intention = ownSelections.record(selectionStart, selectionEnd, -1, -1);
        boolean accepted = connection.finishComposingText();
        if (!accepted) ownSelections.reject(intention);
        if (connection != getCurrentInputConnection() || host != cursorAnchorHostGeneration
                || releaseEpoch != ownSelections.epoch()) return ProbeRelease.SUPERSEDED;
        return accepted ? ProbeRelease.RELEASED : ProbeRelease.UNVERIFIED;
    }

    private void releaseTouchReadingAfterCursorMove(int previousStart, int start, int end,
            int selectionStart, int selectionEnd) {
        InputConnection connection = getCurrentInputConnection();
        if (connection == null || previousStart < 0
                || previousStart > Integer.MAX_VALUE - appliedComposingText.length()) return;
        int previousEnd = previousStart + appliedComposingText.length();
        if (start >= 0 && (start != previousStart || end != previousEnd)) return;
        ExtractedText current = connection.getExtractedText(new ExtractedTextRequest(), 0);
        if (current == null || current.text == null || current.startOffset < 0
                || current.partialStartOffset >= 0) return;
        int relativeStart = previousStart - current.startOffset;
        int relativeEnd = previousEnd - current.startOffset;
        if (relativeStart < 0 || relativeEnd > current.text.length()
                || !appliedComposingText.contentEquals(current.text.subSequence(relativeStart, relativeEnd))) return;
        connection.beginBatchEdit();
        try {
            if (start < 0 && !setOwnComposingRegion(connection, previousStart, previousEnd)) return;
            if (commitOwnText(connection, "") && selectionStart >= 0 && selectionEnd >= 0) {
                int adjustedStart = selectionStart - Math.max(0, Math.min(selectionStart, previousEnd) - previousStart);
                int adjustedEnd = selectionEnd - Math.max(0, Math.min(selectionEnd, previousEnd) - previousStart);
                setOwnSelection(connection, adjustedStart, adjustedEnd);
            }
        } finally {
            connection.endBatchEdit();
        }
    }

    @Override
    public void onSharedPreferenceChanged(SharedPreferences preferences, String key) {
        if (key == null || key.startsWith("keyboard.")) {
            if (key == null || KeyboardSettingsProfile.belongsTo(key, tableVirtualKeyboard)) {
                synchronizeInputPreferences();
                refreshKeyboard();
            }
            return;
        }
        if (UserDataNotifications.KEY_CHANGED.equals(key)) {
            if (engine != null) apply(engine.refreshUserData());
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
        if (KeyboardBottomSpaceSettings.KEY_HARDWARE_ENABLED.equals(key)) {
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
        if (!key.equals("HARDWARE_LANGUAGE")) dismissHardwareQuickSettings();
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
            openKeyboardSettings();
            return;
        }
        if (key.equals("HARDWARE_LANGUAGE")) {
            if (canUseHardwareQuickSettings()) {
                hardwareQuickSettings.toggle(simplifiedChineseOutput, engine.chineseInputMethod(),
                        engine.inputMode() != InputEngine.InputMode.BOPOMOFO, engine.isHardwareFullWidth());
            }
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
        boolean omitTone = keyboardView != null && (keyboardView.isTouchMode() || hardwareSmartTwoRows)
                && engine.usesTouchPhoneticGrid();
        apply(engine.handleSoftKey(key, omitTone), key.equals("ENTER"));
    }

    @Override
    public void openKeyboardSettings() {
        if (engine == null || hostTransactionFailed) return;
        dismissHardwareQuickSettings();
        apply(engine.finishCompositionForModeSwitch());
        Intent intent = SettingsActivity.intent(this, !hardwareKeyboard);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        startActivity(intent);
    }

    @Override
    public void onScriptToggle() {
        if (canUseHardwareQuickSettings()) {
            commitPendingComposition();
            if (!hostTransactionFailed && !engine.hasComposition())
                ChineseInputMethodSettings.setSimplifiedChineseOutput(this, !simplifiedChineseOutput, false);
        }
    }

    @Override
    public void onInputModeSelected(ChineseInputMethod method) {
        if (!canUseHardwareQuickSettings()) return;
        engine.prepareForHardwareInput();
        if (method != null && method != engine.chineseInputMethod()) {
            commitPendingComposition();
            if (hostTransactionFailed || engine.hasComposition()) return;
            ChineseInputMethodSettings.setMethod(this, method, false);
        }
        boolean wantsEnglish = method == null;
        boolean english = engine.inputMode() != InputEngine.InputMode.BOPOMOFO;
        if (!hostTransactionFailed && wantsEnglish != english) {
            apply(engine.toggleHardwareLanguage());
        }
    }

    @Override
    public void onWidthToggle() {
        if (canUseHardwareQuickSettings()) apply(engine.toggleHardwareWidth());
    }

    private boolean canUseHardwareQuickSettings() {
        return hardwareQuickSettings != null && keyboardView.mode() == BopomofoKeyboardView.Mode.HARDWARE
                && !hardwareCandidatesCollapsed && engine != null && !hostTransactionFailed;
    }

    private void updateHardwareQuickSettings() {
        if (hardwareQuickSettings == null || !hardwareQuickSettings.isShowing()) return;
        if (!canUseHardwareQuickSettings()) {
            dismissHardwareQuickSettings();
            return;
        }
        hardwareQuickSettings.update(simplifiedChineseOutput, engine.chineseInputMethod(),
                engine.inputMode() != InputEngine.InputMode.BOPOMOFO, engine.isHardwareFullWidth());
    }

    private void dismissHardwareQuickSettings() {
        if (hardwareQuickSettings != null) hardwareQuickSettings.dismiss();
    }

    @Override
    public void onCandidate(int displayedIndex) {
        dismissHardwareQuickSettings();
        if (engine == null || hostTransactionFailed) return;
        apply(engine.selectDisplayedCandidate(displayedIndex));
    }

    @Override
    public void onSmartCell(int index) {
        dismissHardwareQuickSettings();
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
        dismissHardwareQuickSettings();
        if (engine == null || hostTransactionFailed) return;
        engine.changePage(delta);
        refreshKeyboard();
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        // System Back dismisses this input view; it is not a transition from
        // touch input to a physical keyboard or a request to commit raw reading.
        if (keyCode == KeyEvent.KEYCODE_BACK) return super.onKeyDown(keyCode, event);
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
        if (!hardwareSmartTwoRows && ((engine.isTouchSmartComposition() && engine.hasPendingPhoneticReading())
                || !touchHostText.editableText().isEmpty())
                && !KeyEvent.isModifierKey(keyCode) && keyCode != KeyEvent.KEYCODE_CAPS_LOCK
                && keyCode != KeyEvent.KEYCODE_NUM_LOCK && keyCode != KeyEvent.KEYCODE_SCROLL_LOCK) {
            commitPendingComposition();
            if (hostTransactionFailed || engine.hasPendingPhoneticReading()) return true;
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
                apply(engine.handleHardwareCharacter((char) unicode, event.isShiftPressed(), event.isCapsLockOn()));
            }
        }
        return true;
    }

    @Override
    public boolean onKeyUp(int keyCode, KeyEvent event) {
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
        long ownershipEpoch = ownSelections.epoch();
        try {
            applied = applyToConnection(connection, result, softEnter);
            if (!applied && connection == getCurrentInputConnection() && ownershipEpoch == ownSelections.epoch()) {
                hostTransactionFailed = true;
                android.widget.Toast.makeText(this, "目前欄位未接受輸入，請重新點選文字欄位。",
                        android.widget.Toast.LENGTH_LONG).show();
            }
        } finally {
            // An absent/replaced host cannot acknowledge the old transaction.
            if (applied && connection == getCurrentInputConnection() && ownershipEpoch == ownSelections.epoch() && engine != null) {
                engine.acknowledgeHostEffects();
            }
            refreshKeyboard();
        }
    }

    private boolean applyToConnection(InputConnection connection, InputEngine.Result result,
                                      boolean softEnter) {
        if (engine.isTouchSmartComposition() || appliedTouchReading || !touchHostText.editableText().isEmpty()) {
            return applyTouchSmart(connection, result, softEnter);
        }
        String nextReading = engine.composingText();
        boolean committedText = !result.committedText().isEmpty();
        boolean updateComposingText = !nextReading.isEmpty()
                && (!nextReading.equals(appliedComposingText)
                        || committedText || result.deleteBeforeCursor());
        boolean finishComposingText = nextReading.isEmpty()
                && (!appliedComposingText.isEmpty() || committedText);
        boolean writesHost = result.deleteBeforeCursor() || committedText || result.discardComposingText()
                || updateComposingText || finishComposingText || result.sendEnter();
        if (writesHost && !prepareInitialAnchorForWrite(connection)) return false;
        var ownBatch = ownSelections.beginBatch(lastSelectionStart, lastSelectionEnd, markedStart(), markedEnd());
        boolean positionedInBatch = false;
        boolean hostBatched = connection.beginBatchEdit();
        try {
            if (result.deleteBeforeCursor() && !deletePreviousGrapheme(connection)) return false;
            if (committedText) {
                if (!commitOwnText(connection, convertOutput(result.committedText()))) return false;
            }
            if (result.discardComposingText()) {
                // finishComposingText() preserves the underlined text. Committing an empty
                // replacement removes the composing region and finishes it in one operation.
                if (!commitOwnText(connection, "")) return false;
            } else if (finishComposingText) {
                // commitText already finishes the marked range. Only a real
                // remaining finish operation participates in acknowledgement.
                if (!committedText && !finishOwnComposingText(connection)) return false;
            } else if (updateComposingText) {
                if (!setOwnComposingText(connection, nextReading)) return false;
            }
            if (engine.smartCompositionCursor() >= 0 && !nextReading.isEmpty() && composingRegionStart >= 0) {
                // Keep the implicit end and the real core caret in one host batch.
                // A phrase replacement may otherwise leave unacknowledged
                // intermediate intentions even though the final caret is unchanged.
                int position = addKnownOffset(composingRegionStart, engine.composingCaretUtf16Offset());
                if (!setOwnSelection(connection, position, position)) return false;
                positionedInBatch = true;
            }
        } finally {
            connection.endBatchEdit();
        }

        if (!positionedInBatch && engine.smartCompositionCursor() >= 0 && !nextReading.isEmpty()
                && composingRegionStart >= 0) {
            // An actual marked callback can establish the anchor even when the
            // one initial snapshot was unavailable. Never issue a second query.
            int position = addKnownOffset(composingRegionStart, engine.composingCaretUtf16Offset());
            if (!setOwnSelection(connection, position, position)) return false;
        }
        if (hostBatched) ownSelections.finishBatch(ownBatch,
                lastSelectionStart, lastSelectionEnd, markedStart(), markedEnd());

        if (result.sendEnter()) {
            boolean performedAction = softEnter && fieldPolicy.hasEditorAction()
                    && connection.performEditorAction(fieldPolicy.editorAction());
            if (!performedAction) {
                if (!connection.sendKeyEvent(new KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER))) return false;
                if (!connection.sendKeyEvent(new KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER))) return false;
            }
        }
        return true;
    }

    private String convertOutput(String text) {
        if (!simplifiedChineseOutput || text.isEmpty()) return text;
        if (simplifiedChineseConverter == null) {
            simplifiedChineseConverter = SimplifiedChineseOutput.load(getAssets());
        }
        return simplifiedChineseConverter.convert(text);
    }

    private boolean applyTouchSmart(InputConnection connection, InputEngine.Result result,
                                    boolean softEnter) {
        String committedText = convertOutput(result.committedText());
        boolean writesHost = !committedText.isEmpty() || result.deleteBeforeCursor() || result.sendEnter()
                || !engine.completedSmartText().isEmpty() || !appliedComposingText.isEmpty()
                || (engine.usesTouchPhoneticGrid() && engine.hasPendingPhoneticReading());
        if (writesHost && !prepareInitialAnchorForWrite(connection)) return false;
        boolean unknownAnchor = lastSelectionStart < 0 || lastSelectionEnd < 0;
        boolean needsChineseAnchor = unknownAnchor && !engine.usesTouchPhoneticGrid()
                && engine.isTouchSmartComposition() && !engine.completedSmartText().isEmpty()
                && appliedComposingText.isEmpty();
        if (appliedTouchAnchorProbe || needsChineseAnchor) {
            return applyTouchChineseAnchorProbe(connection, result, committedText, softEnter);
        }
        TouchSmartHostTextState.Edit edit;
        if (engine.isTouchSmartComposition() && engine.hasComposition()) {
            edit = touchHostText.update(convertOutput(engine.completedSmartText()), committedText);
        } else if (engine.isTouchSmartComposition() && committedText.isEmpty()
                && !result.deleteBeforeCursor() && !result.sendEnter()) {
            edit = touchHostText.cancel();
        } else {
            edit = touchHostText.finish(committedText);
        }

        String rawReading = engine.usesTouchPhoneticGrid() && engine.hasPendingPhoneticReading()
                ? engine.readingText() : "";
        boolean editTail = !edit.isEmpty() || result.deleteBeforeCursor();
        boolean removeReading = !appliedComposingText.isEmpty()
                && (!appliedTouchReading || editTail || rawReading.isEmpty());
        boolean updateReading = !rawReading.isEmpty()
                && (removeReading || !rawReading.equals(appliedComposingText));
        var ownBatch = ownSelections.beginBatch(lastSelectionStart, lastSelectionEnd, markedStart(), markedEnd());
        boolean hostBatched = connection.beginBatchEdit();
        try {
            if (removeReading) {
                if (!commitOwnText(connection, "")) return false;
            }
            if (edit.deleteCount() > 0 && !deleteOwnSurroundingText(connection, edit.deleteCount())) {
                return false;
            }
            if (!edit.insertion().isEmpty() && !commitOwnText(connection, edit.insertion())) return false;
            if (result.deleteBeforeCursor() && !deletePreviousGrapheme(connection)) return false;
            if (updateReading) {
                if (!setOwnComposingText(connection, rawReading)) return false;
                appliedTouchReading = true;
            }
        } finally {
            connection.endBatchEdit();
            if (hostBatched) ownSelections.finishBatch(ownBatch,
                    lastSelectionStart, lastSelectionEnd, markedStart(), markedEnd());
        }

        if (result.sendEnter()) {
            boolean performedAction = softEnter && fieldPolicy.hasEditorAction()
                    && connection.performEditorAction(fieldPolicy.editorAction());
            if (!performedAction) {
                if (!connection.sendKeyEvent(new KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER))) return false;
                if (!connection.sendKeyEvent(new KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER))) return false;
            }
        }
        return true;
    }

    /**
     * Keep an unanchored completed Chinese suffix visible as one marked region.
     * Only its real marked-end ACK establishes the absolute caret. Further
     * Chinese updates replace that same region until the ACK is received.
     */
    private boolean applyTouchChineseAnchorProbe(InputConnection connection, InputEngine.Result result,
            String committedText, boolean softEnter) {
        String nextText = engine.isTouchSmartComposition() && engine.hasComposition()
                ? convertOutput(engine.completedSmartText()) : "";
        var ownBatch = ownSelections.beginBatch(lastSelectionStart, lastSelectionEnd, markedStart(), markedEnd());
        boolean hostBatched = connection.beginBatchEdit();
        try {
            if (!committedText.isEmpty() && !commitOwnText(connection, committedText)) return false;
            if (engine.isTouchSmartComposition() && engine.hasComposition()) {
                touchHostText.update(nextText, committedText);
                if (!nextText.isEmpty()) {
                    if (!appliedTouchAnchorProbe || !nextText.equals(appliedComposingText)) {
                        if (!setOwnComposingText(connection, nextText)) return false;
                        appliedTouchAnchorProbe = true;
                        appliedTouchReading = false;
                    }
                } else if (!appliedComposingText.isEmpty() && !commitOwnText(connection, "")) return false;
            } else {
                // Explicit finish/hide commits into this same marked region;
                // cancelling removes only the region, never the host prefix.
                if (committedText.isEmpty() && !appliedComposingText.isEmpty()
                        && !commitOwnText(connection, "")) return false;
                touchHostText.reset();
            }
            if (result.deleteBeforeCursor() && !deletePreviousGrapheme(connection)) return false;
        } finally {
            connection.endBatchEdit();
            if (hostBatched) ownSelections.finishBatch(ownBatch,
                    lastSelectionStart, lastSelectionEnd, markedStart(), markedEnd());
        }
        if (appliedTouchAnchorProbe) scheduleTouchAnchorProbeFinish();
        if (result.sendEnter()) {
            boolean performedAction = softEnter && fieldPolicy.hasEditorAction()
                    && connection.performEditorAction(fieldPolicy.editorAction());
            if (!performedAction) {
                if (!connection.sendKeyEvent(new KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER))) return false;
                if (!connection.sendKeyEvent(new KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER))) return false;
            }
        }
        return true;
    }

    private void scheduleTouchAnchorProbeFinish() {
        if (!appliedTouchAnchorProbe || composingRegionStart < 0 || lastSelectionStart < 0
                || ownSelections.pendingCount() != 0 || hostTransactionFailed) return;
        InputConnection connection = getCurrentInputConnection();
        if (connection == null) return;
        long host = cursorAnchorHostGeneration;
        long epoch = ownSelections.epoch();
        // Do not issue a second IC operation reentrantly from an ACK or a
        // restart's setComposingRegion. A newer key/host/selection supersedes it.
        mainHandler.post(() -> {
            if (!appliedTouchAnchorProbe || composingRegionStart < 0
                    || ownSelections.pendingCount() != 0 || hostTransactionFailed
                    || connection != getCurrentInputConnection() || host != cursorAnchorHostGeneration
                    || epoch != ownSelections.epoch()) return;
            var intention = ownSelections.record(lastSelectionStart, lastSelectionEnd, -1, -1);
            boolean accepted = connection.finishComposingText();
            if (!accepted) ownSelections.reject(intention);
            if (connection != getCurrentInputConnection() || host != cursorAnchorHostGeneration
                    || epoch != ownSelections.epoch()) return;
            if (!accepted) {
                hostTransactionFailed = true;
                android.widget.Toast.makeText(this, "目前欄位未接受輸入，請重新點選文字欄位。",
                        android.widget.Toast.LENGTH_LONG).show();
            } else {
                appliedComposingText = "";
                appliedTouchAnchorProbe = false;
                appliedTouchReading = false;
                composingRegionStart = -1;
            }
            refreshKeyboard();
        });
    }

    /** At most one first-write probe per IC epoch; a valid restart shares its anchor. */
    private boolean prepareInitialAnchorForWrite(InputConnection connection) {
        if (hostSelectionWriteStarted) return true;
        hostSelectionWriteStarted = true;
        if (lastSelectionStart >= 0 && lastSelectionEnd >= 0) return true;
        long host = cursorAnchorHostGeneration;
        long epoch = ownSelections.epoch();
        ExtractedText snapshot = null;
        try {
            snapshot = connection.getExtractedText(new ExtractedTextRequest(), 0);
        } catch (RuntimeException unavailable) {
            // An unavailable editor snapshot is not proof of an absolute zero.
        }
        if (connection != getCurrentInputConnection() || host != cursorAnchorHostGeneration
                || epoch != ownSelections.epoch()) return false;
        if (snapshot != null && snapshot.text != null
                && (lastSelectionStart < 0 || lastSelectionEnd < 0)) {
            OwnSelectionTracker.Anchor anchor = OwnSelectionTracker.Anchor.fromFullSnapshot(
                    snapshot.startOffset, snapshot.text.length(), snapshot.partialStartOffset, snapshot.partialEndOffset,
                    snapshot.selectionStart, snapshot.selectionEnd);
            if (anchor != null) {
                pendingInitialAnchor = anchor;
                lastSelectionStart = anchor.start();
                lastSelectionEnd = anchor.end();
            }
        }
        return true;
    }

    private static int addKnownOffset(int start, int count) {
        return start >= 0 && count >= 0 && start <= Integer.MAX_VALUE - count ? start + count : -1;
    }

    private int replacementStart() {
        if (!appliedComposingText.isEmpty()) return composingRegionStart;
        return Math.min(lastSelectionStart, lastSelectionEnd);
    }

    private int markedStart() { return appliedComposingText.isEmpty() ? -1 : composingRegionStart; }

    private int markedEnd() {
        return appliedComposingText.isEmpty() ? -1 : addKnownOffset(composingRegionStart, appliedComposingText.length());
    }

    private boolean setOwnComposingText(InputConnection connection, String text) {
        int start = replacementStart();
        int end = addKnownOffset(start, text.length());
        var intention = start >= 0 ? ownSelections.record(end, end, start, end)
                : ownSelections.recordUnknownComposing(text.length());
        if (!connection.setComposingText(text, 1)) {
            ownSelections.reject(intention);
            return false;
        }
        if (end >= 0) lastSelectionStart = lastSelectionEnd = end;
        if (start >= 0) composingRegionStart = start;
        appliedComposingText = text;
        return true;
    }

    private boolean commitOwnText(InputConnection connection, String text) {
        boolean finishesAnchorProbe = appliedTouchAnchorProbe;
        long epoch = ownSelections.epoch();
        int end = addKnownOffset(replacementStart(), text.length());
        var intention = ownSelections.record(end, end, -1, -1);
        if (!connection.commitText(text, 1)) {
            ownSelections.reject(intention);
            return false;
        }
        if (finishesAnchorProbe && connection == getCurrentInputConnection()
                && epoch == ownSelections.epoch()) ownSelections.releaseUnknownComposing();
        lastSelectionStart = lastSelectionEnd = end;
        appliedComposingText = "";
        appliedTouchReading = false;
        appliedTouchAnchorProbe = false;
        composingRegionStart = -1;
        return true;
    }

    private boolean finishOwnComposingText(InputConnection connection) {
        var intention = !appliedComposingText.isEmpty()
                ? ownSelections.record(lastSelectionStart, lastSelectionEnd, -1, -1) : null;
        if (!connection.finishComposingText()) {
            ownSelections.reject(intention);
            return false;
        }
        appliedComposingText = "";
        appliedTouchReading = false;
        appliedTouchAnchorProbe = false;
        composingRegionStart = -1;
        return true;
    }

    private boolean setOwnComposingRegion(InputConnection connection, int start, int end) {
        var intention = ownSelections.record(lastSelectionStart, lastSelectionEnd, start, end);
        if (!connection.setComposingRegion(start, end)) {
            ownSelections.reject(intention);
            return false;
        }
        composingRegionStart = start;
        return true;
    }

    private boolean setOwnSelection(InputConnection connection, int start, int end) {
        var intention = start != lastSelectionStart || end != lastSelectionEnd
                ? ownSelections.record(start, end, markedStart(), markedEnd()) : null;
        if (!connection.setSelection(start, end)) {
            ownSelections.reject(intention);
            return false;
        }
        lastSelectionStart = start;
        lastSelectionEnd = end;
        return true;
    }

    private boolean deleteOwnSurroundingText(InputConnection connection, int count) {
        int start = Math.min(lastSelectionStart, lastSelectionEnd);
        if (!appliedComposingText.isEmpty()) start = Math.min(start, composingRegionStart);
        int removed = start >= 0 ? Math.min(start, count) : -1;
        int nextStart = removed >= 0 ? lastSelectionStart - removed : -1;
        int nextEnd = removed >= 0 ? lastSelectionEnd - removed : -1;
        int markedStart = markedStart();
        int markedEnd = markedEnd();
        if (markedStart >= 0 && removed >= 0) {
            markedStart -= removed;
            markedEnd -= removed;
        }
        var intention = ownSelections.record(nextStart, nextEnd, markedStart, markedEnd);
        if (!connection.deleteSurroundingText(count, 0)) {
            ownSelections.reject(intention);
            return false;
        }
        lastSelectionStart = nextStart;
        lastSelectionEnd = nextEnd;
        if (!appliedComposingText.isEmpty()) composingRegionStart = markedStart;
        return true;
    }

    private boolean deletePreviousGrapheme(InputConnection connection) {
        CharSequence beforeCursor = connection.getTextBeforeCursor(64, 0);
        int characterCount = TextDeletion.previousGraphemeLength(beforeCursor);
        if (characterCount > 0) return deleteOwnSurroundingText(connection, characterCount);
        // Without the host's preceding UTF16 text the size of one codepoint is
        // unknown. Preserve the operation, but do not invent an absolute caret.
        boolean accepted = connection.deleteSurroundingTextInCodePoints(1, 0);
        if (accepted) lastSelectionStart = lastSelectionEnd = -1;
        return accepted;
    }

    private void refreshKeyboard() {
        if (inputPreferencesDirty && !synchronizingInputPreferences && engine != null && !engine.hasComposition())
            synchronizeInputPreferences();
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
        CandidateColorSettings.CandidateColor candidateColor = CandidateColorSettings.color(this, !hardwareKeyboard);
        keyboardView.setCandidateHighlightColors(
                CandidateColorSettings.backgroundColor(candidateColor),
                CandidateColorSettings.textColor(candidateColor));
        boolean supportPromptVisible = SupporterState.shouldShowSupportPrompt(this);
        boolean smartBopomofo = engine.chineseInputMethod() == ChineseInputMethod.SMART
                && engine.compositionMode() == BopomofoCompositionMode.SMART
                && engine.inputMode() == InputEngine.InputMode.BOPOMOFO;
        keyboardView.setAssociatedPhrasesVisible(engine.isShowingAssociatedPhrases());
        boolean phoneticPending = engine.hasPendingPhoneticReading();
        keyboardView.setPhoneticState((keyboardView.isTouchMode() || hardwareSmartTwoRows) && engine.usesTouchPhoneticGrid(),
                phoneticPending, engine.phoneticSpaceFirstTone());
        keyboardView.setState(engine.displayedCandidates(), engine.composingText(),
                engine.compositionMode() == BopomofoCompositionMode.SMART
                        && engine.inputMode() == InputEngine.InputMode.BOPOMOFO,
                engine.touchSmartCells(hardwareSmartTwoRows ? 9
                        : keyboardView.compositionCellCount()), engine.touchSmartEditableCount(),
                engine.inputMode(), engine.isShifted(), engine.isTemporaryEnglish(),
                engine.isHardwareFullWidth(), supportPromptVisible,
                engine.page(), engine.pageCount(),
                engine.isShowingAssociatedPhrases() ? -1 : engine.highlightedIndex(), fieldPolicy);
        updateHardwareQuickSettings();
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
        keyboardView.setHardwareBottomSpaceEnabled(KeyboardBottomSpaceSettings.hardwareEnabled(this));
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
        // Finish using the old reading layout and output script before adopting new preferences.
        commitPendingComposition();
        if (hostTransactionFailed || engine.hasComposition()) return;
        tableVirtualKeyboard = virtualKeyboard;
        synchronizeInputPreferences();
    }

    private boolean hasHardwareKeyboard() {
        Configuration configuration = getResources().getConfiguration();
        return configuration.keyboard != Configuration.KEYBOARD_NOKEYS
                && configuration.hardKeyboardHidden == Configuration.HARDKEYBOARDHIDDEN_NO;
    }

    private void updateKeyboardMode() {
        Configuration configuration = getResources().getConfiguration();
        boolean nextHardwareKeyboard = hasHardwareKeyboard();
        useTableKeyboard(!nextHardwareKeyboard);
        if (tableVirtualKeyboard == nextHardwareKeyboard) return; // the old host has not accepted its handoff
        hardwareKeyboard = nextHardwareKeyboard;
        if (!hardwareKeyboard) hardwareCandidatesCollapsed = false;
        floatingCandidatesEnabled = CandidateWindowSettings.floatingEnabled(this);
        floatingCandidateLayout = CandidateWindowSettings.layout(this);
        boolean nextSmartTwoRows = hardwareKeyboard && !isFloatingCandidateMode()
                && CandidateWindowSettings.smartTwoRowsEnabled(this);
        // Finish using the old host-text strategy before switching between
        // marked desktop composition and the touch keyboard's editable tail.
        boolean strategyChanged = engine != null && engine.compositionMode() == BopomofoCompositionMode.SMART
                && engine.isTouchSmartComposition() != (!hardwareKeyboard || nextSmartTwoRows);
        if (nextSmartTwoRows != hardwareSmartTwoRows || strategyChanged) {
            commitPendingComposition();
            if (hostTransactionFailed || (engine != null && engine.hasComposition())) return;
        }
        hardwareSmartTwoRows = nextSmartTwoRows;
        if (engine != null) {
            engine.setHardwareTouchSmartEditing(hardwareSmartTwoRows);
            engine.setHardwareSmartEditing(hardwareKeyboard && !hardwareSmartTwoRows);
        }
        synchronizeTouchPhoneticGrid();
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
        keyboardView.setMode(nextMode);
        if (nextMode != BopomofoKeyboardView.Mode.HARDWARE) dismissHardwareQuickSettings();
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
        cursorAnchorRequestGeneration++;
        cursorAnchorMonitoring = false;
        cursorAnchorMonitorConnection = null;
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
        if (destroying) return;
        InputConnection connection = getCurrentInputConnection();
        if (connection == null) return;
        boolean monitor = isFloatingCandidateMode();
        if (!monitor) resetCursorAnchor();
        else {
            cursorAnchorRequestPending = true;
            cursorAnchorMonitoring = true;
            cursorAnchorMonitorConnection = connection;
            cursorAnchorMonitorHostGeneration = cursorAnchorHostGeneration;
        }
        long hostGeneration = cursorAnchorHostGeneration;
        long requestGeneration = ++cursorAnchorRequestGeneration;
        int mode = monitor ? InputConnection.CURSOR_UPDATE_IMMEDIATE
                | InputConnection.CURSOR_UPDATE_MONITOR : 0;
        // RemoteInputConnection waits for the editor's reply. Our own App's
        // editor can share this main looper with the IME, so neither starting
        // nor cancelling its monitor may synchronously wait here.
        requestCursorUpdatesAsync(cursorAnchorRequests, mainHandler::post, connection, mode,
                () -> !destroying && cursorAnchorHostGeneration == hostGeneration
                        && cursorAnchorRequestGeneration == requestGeneration,
                () -> {
                    if (getCurrentInputConnection() != connection) return;
                    // Begin the callback grace period after the current request
                    // actually ran, not while it was waiting behind an old host.
                    if (monitor && floatingCandidatesVisible && cursorAnchorRequestPending) {
                        mainHandler.postDelayed(cursorAnchorRetry, CURSOR_ANCHOR_RETRY_DELAY_MS);
                    }
                });
    }

    static void requestCursorUpdatesAsync(Executor worker, Executor completionDispatcher,
            InputConnection connection, int mode, BooleanSupplier current, Runnable completed) {
        worker.execute(() -> {
            if (!current.getAsBoolean()) return;
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && mode != 0) {
                    connection.requestCursorUpdates(mode,
                            InputConnection.CURSOR_UPDATE_FILTER_INSERTION_MARKER);
                } else {
                    connection.requestCursorUpdates(mode);
                }
            } catch (RuntimeException error) {
                android.util.Log.w("KeyKey", "Cursor anchor request failed", error);
            }
            completionDispatcher.execute(() -> {
                if (current.getAsBoolean()) completed.run();
            });
        });
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
