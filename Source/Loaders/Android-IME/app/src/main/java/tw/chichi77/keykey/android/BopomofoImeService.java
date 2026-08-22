package tw.chichi77.keykey.android;

import android.content.Intent;
import android.content.res.Configuration;
import android.inputmethodservice.InputMethodService;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.view.KeyEvent;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;

import java.io.IOException;
import java.io.InputStream;
import java.util.LinkedHashSet;
import java.util.Set;

public final class BopomofoImeService extends InputMethodService
        implements BopomofoKeyboardView.Listener {
    private BopomofoEngine engine;
    private BopomofoKeyboardView keyboardView;
    private Vibrator vibrator;
    private Set<String> loadedPhraseCollections;
    private final Set<Integer> pressedControlShortcutKeys = new LinkedHashSet<>();

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
        updateKeyboardMode();
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
        reloadPhraseDictionary();
        if (!restarting && engine != null) engine.reset();
        refreshKeyboard();
    }

    @Override
    public void onStartInputView(EditorInfo info, boolean restarting) {
        super.onStartInputView(info, restarting);
        reloadPhraseDictionary();
        refreshKeyboard();
    }

    @Override
    public void onFinishInput() {
        if (engine != null) engine.reset();
        pressedControlShortcutKeys.clear();
        super.onFinishInput();
    }

    @Override
    public void onConfigurationChanged(Configuration newConfig) {
        super.onConfigurationChanged(newConfig);
        updateKeyboardMode();
    }

    @Override
    public void onKey(String key) {
        if (key.equals("SETTINGS")) {
            Intent intent = new Intent(this, SettingsActivity.class);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
            return;
        }
        apply(engine.handleSoftKey(key));
    }

    @Override
    public void onCandidate(int displayedIndex) {
        apply(engine.selectDisplayedCandidate(displayedIndex));
    }

    @Override
    public void onPage(int delta) {
        engine.changePage(delta);
        refreshKeyboard();
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (isHardwareControlShortcut(keyCode, event)) {
            pressedControlShortcutKeys.add(keyCode);
            if (event.getRepeatCount() == 0) applyHardwareControlShortcut(keyCode);
            return true;
        }
        if (event.isCtrlPressed() || event.isAltPressed() || event.isMetaPressed()) {
            return super.onKeyDown(keyCode, event);
        }
        engine.prepareForHardwareInput();
        int candidateIndex = topRowDigitIndex(keyCode);
        if (engine.isShowingAssociatedPhrases() && event.isShiftPressed()
                && candidateIndex >= 0) {
            apply(engine.selectDisplayedCandidate(candidateIndex));
            return true;
        }
        switch (keyCode) {
            case KeyEvent.KEYCODE_DEL -> apply(engine.backspace());
            case KeyEvent.KEYCODE_SPACE -> apply(engine.space());
            case KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> {
                if (engine.isShowingAssociatedPhrases()) apply(engine.escape());
                else apply(engine.enter());
            }
            case KeyEvent.KEYCODE_ESCAPE -> apply(engine.escape());
            case KeyEvent.KEYCODE_PAGE_UP -> {
                engine.changePage(-1);
                refreshKeyboard();
            }
            case KeyEvent.KEYCODE_PAGE_DOWN -> {
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
        if (pressedControlShortcutKeys.remove(keyCode)
                || isHardwareControlShortcut(keyCode, event)) {
            return true;
        }
        return super.onKeyUp(keyCode, event);
    }

    private boolean isHardwareControlShortcut(int keyCode, KeyEvent event) {
        if (!event.isCtrlPressed() || event.isAltPressed()
                || event.isMetaPressed() || event.isShiftPressed()) {
            return false;
        }
        return keyCode == KeyEvent.KEYCODE_SPACE
                || keyCode == KeyEvent.KEYCODE_COMMA
                || keyCode == KeyEvent.KEYCODE_PERIOD
                || keyCode == KeyEvent.KEYCODE_0
                || keyCode == KeyEvent.KEYCODE_1;
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
        InputConnection connection = getCurrentInputConnection();
        if (connection == null) {
            refreshKeyboard();
            return;
        }

        if (result.deleteBeforeCursor()) deletePreviousGrapheme(connection);
        if (!result.committedText().isEmpty()) {
            connection.commitText(result.committedText(), 1);
        }
        if (result.sendEnter()) {
            connection.sendKeyEvent(new KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER));
            connection.sendKeyEvent(new KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER));
        }

        if (engine.readingText().isEmpty()) connection.finishComposingText();
        else connection.setComposingText(engine.readingText(), 1);
        refreshKeyboard();
    }

    private void deletePreviousGrapheme(InputConnection connection) {
        CharSequence beforeCursor = connection.getTextBeforeCursor(64, 0);
        int characterCount = TextDeletion.previousGraphemeLength(beforeCursor);
        if (characterCount > 0) connection.deleteSurroundingText(characterCount, 0);
        else connection.deleteSurroundingTextInCodePoints(1, 0);
    }

    private void refreshKeyboard() {
        if (keyboardView == null || engine == null) return;
        keyboardView.setState(engine.displayedCandidates(), engine.readingText(),
                engine.inputMode(), engine.isShifted(), engine.isTemporaryEnglish(),
                engine.page(), engine.pageCount());
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
        if (keyboardView == null) return;
        Configuration configuration = getResources().getConfiguration();
        boolean hardwareKeyboard = configuration.keyboard != Configuration.KEYBOARD_NOKEYS
                && configuration.hardKeyboardHidden == Configuration.HARDKEYBOARDHIDDEN_NO;
        if (hardwareKeyboard) {
            keyboardView.setMode(BopomofoKeyboardView.Mode.HARDWARE);
        } else if (configuration.orientation == Configuration.ORIENTATION_LANDSCAPE) {
            keyboardView.setMode(BopomofoKeyboardView.Mode.LANDSCAPE);
        } else {
            keyboardView.setMode(BopomofoKeyboardView.Mode.PORTRAIT);
        }
    }
}
