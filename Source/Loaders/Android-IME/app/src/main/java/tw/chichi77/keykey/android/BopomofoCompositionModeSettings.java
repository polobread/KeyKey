package tw.chichi77.keykey.android;

import android.content.Context;
import android.content.SharedPreferences;

final class BopomofoCompositionModeSettings {
    static final String KEY_MODE = "bopomofo_composition_mode";
    static final String KEY_BIGRAM_ENABLED = "smart_bigram_enabled";
    private static final String SMART = "smart";
    private static final String TRADITIONAL = "traditional";

    private BopomofoCompositionModeSettings() {}

    static BopomofoCompositionMode mode(Context context) {
        return modeFromValue(preferences(context).getString(KEY_MODE, SMART));
    }

    static void setMode(Context context, BopomofoCompositionMode mode) {
        preferences(context).edit().putString(KEY_MODE, valueForMode(mode)).apply();
    }

    static boolean bigramEnabled(Context context) {
        return preferences(context).getBoolean(KEY_BIGRAM_ENABLED, true);
    }

    static void setBigramEnabled(Context context, boolean enabled) {
        preferences(context).edit().putBoolean(KEY_BIGRAM_ENABLED, enabled).apply();
    }

    static BopomofoCompositionMode modeFromValue(String value) {
        return TRADITIONAL.equals(value)
                ? BopomofoCompositionMode.TRADITIONAL : BopomofoCompositionMode.SMART;
    }

    static String valueForMode(BopomofoCompositionMode mode) {
        return mode == BopomofoCompositionMode.TRADITIONAL ? TRADITIONAL : SMART;
    }

    static SharedPreferences preferences(Context context) {
        return context.getSharedPreferences(CandidateWindowSettings.PREFERENCES_NAME,
                Context.MODE_PRIVATE);
    }
}
