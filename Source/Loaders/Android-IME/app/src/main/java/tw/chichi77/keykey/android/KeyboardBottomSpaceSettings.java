package tw.chichi77.keykey.android;

import android.content.Context;
import android.content.SharedPreferences;

final class KeyboardBottomSpaceSettings {
    static final String KEY_TOUCH_ENABLED = "touch_keyboard_bottom_space_enabled";
    static final String KEY_HARDWARE_ENABLED = "hardware_candidate_bottom_space_enabled";

    private KeyboardBottomSpaceSettings() {}

    static boolean touchEnabled(Context context) {
        return preferences(context).getBoolean(KEY_TOUCH_ENABLED, true);
    }

    static boolean hardwareEnabled(Context context) {
        return preferences(context).getBoolean(KEY_HARDWARE_ENABLED, true);
    }

    static void setTouchEnabled(Context context, boolean enabled) {
        preferences(context).edit().putBoolean(KEY_TOUCH_ENABLED, enabled).apply();
    }

    static void setHardwareEnabled(Context context, boolean enabled) {
        preferences(context).edit().putBoolean(KEY_HARDWARE_ENABLED, enabled).apply();
    }

    static boolean isSettingKey(String key) {
        return KEY_TOUCH_ENABLED.equals(key) || KEY_HARDWARE_ENABLED.equals(key);
    }

    private static SharedPreferences preferences(Context context) {
        return CandidateWindowSettings.preferences(context);
    }
}
