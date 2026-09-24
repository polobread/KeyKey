package tw.chichi77.keykey.android;

import android.content.Context;
import android.content.SharedPreferences;

final class BopomofoCompositionModeSettings {
    static final String KEY_MODE = "bopomofo_composition_mode";
    private static final String SMART = "smart";
    private static final String TRADITIONAL = "traditional";

    private BopomofoCompositionModeSettings() {}

    static BopomofoCompositionMode mode(Context context) {
        return modeFromValue(preferences(context).getString(KEY_MODE, SMART));
    }

    static void setMode(Context context, BopomofoCompositionMode mode) {
        preferences(context).edit().putString(KEY_MODE, valueForMode(mode)).apply();
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
