package tw.chichi77.keykey.android;

import android.content.Context;

final class BopomofoKeyboardLayoutSettings {
    static final String KEY_LAYOUT = "bopomofo_keyboard_layout";

    private BopomofoKeyboardLayoutSettings() {}

    static BopomofoKeyboardLayout layout(Context context) {
        return BopomofoKeyboardLayout.fromValue(
                CandidateWindowSettings.preferences(context).getString(KEY_LAYOUT, "Standard"));
    }

    static void setLayout(Context context, BopomofoKeyboardLayout layout) {
        CandidateWindowSettings.preferences(context).edit()
                .putString(KEY_LAYOUT, layout.value).apply();
    }
}
