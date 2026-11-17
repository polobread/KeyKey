package tw.chichi77.keykey.android;

import android.content.Context;
import android.content.SharedPreferences;

final class KeyboardBottomSpaceSettings {
    static final String KEY_HARDWARE_ENABLED = "hardware_candidate_bottom_space_enabled";

    private KeyboardBottomSpaceSettings() {}

    static boolean hardwareEnabled(Context context) {
        return preferences(context).getBoolean(KEY_HARDWARE_ENABLED, true);
    }

    static void setHardwareEnabled(Context context, boolean enabled) {
        preferences(context).edit().putBoolean(KEY_HARDWARE_ENABLED, enabled).apply();
    }

    private static SharedPreferences preferences(Context context) {
        return CandidateWindowSettings.preferences(context);
    }
}
