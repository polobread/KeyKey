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
import android.view.inputmethod.InputConnection;

import java.io.IOException;
import java.io.InputStream;
import java.util.LinkedHashSet;
import java.util.Set;

public final class BopomofoImeService extends InputMethodService
        implements BopomofoKeyboardView.Listener, FloatingCandidateWindow.Listener,
        SharedPreferences.OnSharedPreferenceChangeListener {
    private BopomofoEngine engine;
    private BopomofoKeyboardView keyboardView;
    private FloatingCandidateWindow floatingCandidateWindow;
    private Vibrator vibrator;
    private Set<String> loadedPhraseCollections;
    private boolean hardwareKeyboard;
    private boolean floatingCandidatesEnabled;
    private boolean floatingCandidateWindowAvailable = true;
    private CandidateWindowSettings.Layout floatingCandidateLayout =
            CandidateWindowSettings.Layout.VERTICAL;
    private RectF cursorAnchor;
    private final Set<Integer> pressedHardwareShortcutKeys = new LinkedHashSet<>();
    private final Set<Integer> pressedCandidateKeys = new LinkedHashSet<>();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private InputFieldPolicy fieldPolicy = InputFieldPolicy.DEFAULT;
    private int lastSelectionStart = -1;
    private int lastSelectionEnd = -1;
    private int selectionMutationGeneration;
    private boolean awaitingOwnSelectionUpdate;
    private String appliedComposingText = "";

    @Override
    public void onCreate() {
        super.onCreate();
        CinDictionary dictionary;
        try {
            InputStream bopomofo = getAssets().open("bpmf-ext.cin");
            InputStream punctuation = getAssets().open("bpmf-punctuations.cin");
            dictionary = CinDictionary.load(bopomofo, punctuation);
        } catch (IOException error) {
            dictionary = CinDictionary.empty();
        }
        engine = new BopomofoEngine(dictionary);
        reloadPhraseDictionary();
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
        cursorAnchor = null;
        lastSelectionStart = attribute == null ? -1 : attribute.initialSelStart;
        lastSelectionEnd = attribute == null ? -1 : attribute.initialSelEnd;
        cancelExpectedSelectionUpdate();
        reloadPhraseDictionary();
        InputFieldPolicy nextPolicy = InputFieldPolicy.from(attribute);
        boolean layoutChanged = !fieldPolicy.hasSameLayout(nextPolicy);
        fieldPolicy = nextPolicy;
        if (engine != null) {
            if (!restarting) {
                engine.reset();
                appliedComposingText = "";
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
        reloadPhraseDictionary();
        InputFieldPolicy nextPolicy = InputFieldPolicy.from(info);
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
        if (engine != null) engine.reset();
        pressedHardwareShortcutKeys.clear();
        pressedCandidateKeys.clear();
        cursorAnchor = null;
        lastSelectionStart = -1;
        lastSelectionEnd = -1;
        appliedComposingText = "";
        cancelExpectedSelectionUpdate();
        hideFloatingCandidates();
        super.onFinishInput();
    }

    @Override
    public void onWindowHidden() {
        hideFloatingCandidates();
        super.onWindowHidden();
    }

    @Override
    public void onDestroy() {
        CandidateWindowSettings.preferences(this)
                .unregisterOnSharedPreferenceChangeListener(this);
        SupporterState.preferences(this)
                .unregisterOnSharedPreferenceChangeListener(this);
        mainHandler.removeCallbacksAndMessages(null);
        hideFloatingCandidates();
        super.onDestroy();
    }

    @Override
    public void onConfigurationChanged(Configuration newConfig) {
        super.onConfigurationChanged(newConfig);
        cursorAnchor = null;
        updateKeyboardMode();
        requestCursorAnchorUpdates();
        refreshKeyboard();
    }

    @Override
    public void onUpdateCursorAnchorInfo(CursorAnchorInfo cursorAnchorInfo) {
        super.onUpdateCursorAnchorInfo(cursorAnchorInfo);
        cursorAnchor = insertionMarkerBounds(cursorAnchorInfo);
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

        if (awaitingOwnSelectionUpdate) {
            cancelExpectedSelectionUpdate();
            return;
        }
        if (!selectionChanged || engine == null
                || (engine.readingText().isEmpty() && engine.pageCount() == 0)) {
            return;
        }

        engine.reset();
        appliedComposingText = "";
        InputConnection connection = getCurrentInputConnection();
        if (connection != null) connection.finishComposingText();
        refreshKeyboard();
    }

    @Override
    public void onSharedPreferenceChanged(SharedPreferences preferences, String key) {
        if (SupporterState.KEY_SUPPORTER.equals(key)) {
            refreshKeyboard();
            return;
        }
        if (KeyPreviewSettings.KEY_ENABLED.equals(key)) {
            refreshKeyboard();
            return;
        }
        if (!CandidateWindowSettings.KEY_FLOATING_ENABLED.equals(key)
                && !CandidateWindowSettings.KEY_LAYOUT.equals(key)) return;
        floatingCandidateWindowAvailable = CandidateWindowSettings.floatingEnabled(this);
        updateKeyboardMode();
        requestCursorAnchorUpdates();
        refreshKeyboard();
    }

    @Override
    public void onKey(String key) {
        if (key.equals("SETTINGS")) {
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
        if (!fieldPolicy.isKeyEnabled(key, engine.inputMode(), engine.isShifted())) return;
        apply(engine.handleSoftKey(key), key.equals("ENTER"));
    }

    @Override
    public void onCandidate(int displayedIndex) {
        apply(engine.selectDisplayedCandidate(displayedIndex));
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
        switch (keyCode) {
            case KeyEvent.KEYCODE_DEL -> apply(engine.backspace());
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
        if (pressedCandidateKeys.remove(keyCode)) return true;
        if (pressedHardwareShortcutKeys.remove(keyCode)
                || isHardwareControlShortcut(keyCode, event)
                || isHardwareWidthShortcut(keyCode, event)) {
            return true;
        }
        return super.onKeyUp(keyCode, event);
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

        String nextReading = engine.readingText();
        boolean committedText = !result.committedText().isEmpty();
        boolean updateComposingText = !nextReading.isEmpty()
                && (!nextReading.equals(appliedComposingText)
                        || committedText || result.deleteBeforeCursor());
        boolean finishComposingText = nextReading.isEmpty()
                && (!appliedComposingText.isEmpty() || committedText);
        boolean changesSelection = result.deleteBeforeCursor() || committedText
                || result.discardComposingText() || updateComposingText;
        boolean keepsActiveState = !engine.readingText().isEmpty() || engine.pageCount() > 0;
        if (changesSelection && keepsActiveState) expectOwnSelectionUpdate();

        connection.beginBatchEdit();
        try {
            if (result.deleteBeforeCursor()) deletePreviousGrapheme(connection);
            if (committedText) {
                connection.commitText(result.committedText(), 1);
            }
            if (result.discardComposingText()) {
                // finishComposingText() preserves the underlined text. Committing an empty
                // replacement removes the composing region and finishes it in one operation.
                connection.commitText("", 1);
                appliedComposingText = "";
            } else if (finishComposingText) {
                connection.finishComposingText();
                appliedComposingText = "";
            } else if (updateComposingText) {
                connection.setComposingText(nextReading, 1);
                appliedComposingText = nextReading;
            }
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
        keyboardView.setKeyPreviewEnabled(KeyPreviewSettings.enabled(this));
        keyboardView.setState(engine.displayedCandidates(), engine.readingText(),
                engine.inputMode(), engine.isShifted(), engine.isTemporaryEnglish(),
                engine.isHardwareFullWidth(), SupporterState.shouldShowSupportPrompt(this),
                engine.page(), engine.pageCount(), fieldPolicy);
        if (isFloatingCandidateMode() && floatingCandidateWindow != null) {
            floatingCandidateWindow.update(engine.displayedCandidates(),
                    engine.highlightedIndex(), floatingCandidateLayout, cursorAnchor);
        } else {
            hideFloatingCandidates();
        }
    }

    private void reloadPhraseDictionary() {
        if (engine == null) return;
        Set<String> enabled = new LinkedHashSet<>(PhraseSettings.enabledCollections(this));
        if (enabled.equals(loadedPhraseCollections)) return;
        AssociatedPhraseDictionary dictionary;
        try {
            dictionary = AssociatedPhraseDictionary.load(getAssets(), enabled);
        } catch (IOException error) {
            dictionary = AssociatedPhraseDictionary.empty();
        }
        engine.setAssociatedPhraseDictionary(dictionary);
        loadedPhraseCollections = enabled;
    }

    private void updateKeyboardMode() {
        Configuration configuration = getResources().getConfiguration();
        hardwareKeyboard = configuration.keyboard != Configuration.KEYBOARD_NOKEYS
                && configuration.hardKeyboardHidden == Configuration.HARDKEYBOARDHIDDEN_NO;
        floatingCandidatesEnabled = CandidateWindowSettings.floatingEnabled(this);
        floatingCandidateLayout = CandidateWindowSettings.layout(this);
        if (keyboardView == null) return;
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

    private void requestCursorAnchorUpdates() {
        InputConnection connection = getCurrentInputConnection();
        if (connection == null) return;
        if (!isFloatingCandidateMode()) {
            connection.requestCursorUpdates(0);
            cursorAnchor = null;
            return;
        }
        int mode = InputConnection.CURSOR_UPDATE_IMMEDIATE
                | InputConnection.CURSOR_UPDATE_MONITOR;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            connection.requestCursorUpdates(mode,
                    InputConnection.CURSOR_UPDATE_FILTER_INSERTION_MARKER);
        } else {
            connection.requestCursorUpdates(mode);
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
        if (floatingCandidateWindow != null) floatingCandidateWindow.hide();
    }
}
