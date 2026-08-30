package tw.chichi77.keykey.android;

import android.content.Context;
import android.content.SharedPreferences;

final class KeyPreviewSettings {
    private static final String PREFERENCES_NAME = "ime_settings";
    static final String KEY_ENABLED = "key_preview_enabled";

    private KeyPreviewSettings() {}

    static boolean enabled(Context context) {
        return preferences(context).getBoolean(KEY_ENABLED, true);
    }

    static void setEnabled(Context context, boolean enabled) {
        preferences(context).edit().putBoolean(KEY_ENABLED, enabled).apply();
    }

    private static SharedPreferences preferences(Context context) {
        return context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE);
    }
}
