package tw.chichi77.keykey.android;

import android.app.Activity;
import android.content.res.Configuration;
import android.os.Bundle;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.List;

public final class KeyboardResizeActivity extends Activity {
    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        boolean landscape = getResources().getConfiguration().orientation
                == Configuration.ORIENTATION_LANDSCAPE;
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setBackgroundColor(getColor(R.color.keykey_surface));
        UiInsets.applySystemPadding(page, 0, 0, 0, 0);

        TextView hint = new TextView(this);
        hint.setText(getString(R.string.keyboard_resize_hint, getString(landscape
                ? R.string.keyboard_resize_landscape : R.string.keyboard_resize_portrait)));
        hint.setTextSize(16);
        hint.setTextColor(getColor(R.color.keykey_blue_dark));
        int padding = Math.round(16 * getResources().getDisplayMetrics().density);
        hint.setPadding(padding, padding, padding, padding);
        page.addView(hint, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));

        BopomofoKeyboardView keyboard = new BopomofoKeyboardView(this);
        keyboard.setMode(landscape ? BopomofoKeyboardView.Mode.LANDSCAPE
                : BopomofoKeyboardView.Mode.PORTRAIT);
        keyboard.setLayoutProfile(KeyboardLayoutProfileSettings.profile(this));
        keyboard.setLayoutOptions(KeyboardLayoutProfileSettings.keycapArea(this),
                KeyboardLayoutProfileSettings.fontSize(this),
                KeyboardLayoutProfileSettings.deletePosition(this));
        keyboard.setTouchKeyboardSizes(KeyboardSizeSettings.size(this, false),
                KeyboardSizeSettings.size(this, true));
        keyboard.setBottomSpaceEnabled(KeyboardBottomSpaceSettings.touchEnabled(this), false);
        keyboard.setIntegratedBottomControls(KeyboardBottomControlsSettings.enabled(this), false);
        // The Activity already keeps the preview above the system navigation area.
        keyboard.setOnApplyWindowInsetsListener((view, insets) -> insets);
        keyboard.setOnTouchListener((view, event) -> true);

        ChineseInputMethod method = ChineseInputMethodSettings.method(this);
        boolean smart = method == ChineseInputMethod.SMART;
        keyboard.setChineseInputMethod(method);
        keyboard.setKeyboardLayout(BopomofoKeyboardLayoutSettings.layout(this));
        keyboard.setPhoneticState(smart && BopomofoCompositionModeSettings.omitTone(this), false, false);
        keyboard.setState(List.of(), "", smart, List.of(), 0, InputEngine.InputMode.BOPOMOFO,
                false, false, false, false, 0, 0, -1, InputFieldPolicy.DEFAULT);

        page.addView(new KeyboardResizeView(this, keyboard), new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
        setContentView(page);
    }
}
