package tw.chichi77.keykey.android;

import android.content.res.Configuration;
import android.inputmethodservice.InputMethodService;
import android.view.KeyEvent;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;

import java.io.IOException;
import java.io.InputStream;

public final class BopomofoImeService extends InputMethodService
        implements BopomofoKeyboardView.Listener {
    private BopomofoEngine engine;
    private BopomofoKeyboardView keyboardView;

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
        if (!restarting && engine != null) engine.reset();
        refreshKeyboard();
    }

    @Override
    public void onFinishInput() {
        if (engine != null) engine.reset();
        super.onFinishInput();
    }

    @Override
    public void onConfigurationChanged(Configuration newConfig) {
        super.onConfigurationChanged(newConfig);
        updateKeyboardMode();
    }

    @Override
    public void onKey(String key) {
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
        if (event.isCtrlPressed() || event.isAltPressed() || event.isMetaPressed()) {
            return super.onKeyDown(keyCode, event);
        }
        switch (keyCode) {
            case KeyEvent.KEYCODE_DEL -> apply(engine.backspace());
            case KeyEvent.KEYCODE_SPACE -> apply(engine.space());
            case KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> apply(engine.enter());
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

    private void apply(BopomofoEngine.Result result) {
        InputConnection connection = getCurrentInputConnection();
        if (connection == null) {
            refreshKeyboard();
            return;
        }

        if (result.deleteBeforeCursor()) connection.deleteSurroundingText(1, 0);
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

    private void refreshKeyboard() {
        if (keyboardView == null || engine == null) return;
        keyboardView.setState(engine.displayedCandidates(), engine.readingText(),
                engine.isEnglishMode(), engine.isShifted(), engine.page(), engine.pageCount());
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
