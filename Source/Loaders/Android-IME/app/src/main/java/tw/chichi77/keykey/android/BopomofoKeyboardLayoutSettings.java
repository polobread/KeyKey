package tw.chichi77.keykey.android;

import android.content.Context;

final class BopomofoKeyboardLayoutSettings {
    static final String KEY_LAYOUT = "bopomofo_keyboard_layout";
    private BopomofoKeyboardLayoutSettings() {}
    static BopomofoKeyboardLayout layout(Context context) { return layout(context, true); }
    static BopomofoKeyboardLayout layout(Context context, boolean virtual) {
        return BopomofoKeyboardLayout.fromValue(KeyboardSettingsProfile.preferences(context)
                .getString(KeyboardSettingsProfile.key(virtual, KEY_LAYOUT), "Standard"));
    }
    static void setLayout(Context context, BopomofoKeyboardLayout layout) { setLayout(context, layout, true); }
    static void setLayout(Context context, BopomofoKeyboardLayout layout, boolean virtual) {
        KeyboardSettingsProfile.preferences(context).edit()
                .putString(KeyboardSettingsProfile.key(virtual, KEY_LAYOUT), layout.value).apply();
    }
}
