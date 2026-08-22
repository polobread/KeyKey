package tw.chichi77.keykey.android;

import android.content.Context;
import android.content.SharedPreferences;

final class HapticSettings {
    private static final int[] DURATIONS_MS = {0, 10, 20, 30, 50, 80, 100, 150, 200};
    static final int LEVEL_COUNT = DURATIONS_MS.length;
    static final int MAX_LEVEL = LEVEL_COUNT - 1;

    private static final String PREFERENCES_NAME = "ime_settings";
    private static final String KEY_HAPTIC_LEVEL = "haptic_level";

    private HapticSettings() {}

    static int level(Context context) {
        return preferences(context).getInt(KEY_HAPTIC_LEVEL, 0);
    }

    static void setLevel(Context context, int level) {
        preferences(context).edit().putInt(KEY_HAPTIC_LEVEL, clampLevel(level)).apply();
    }

    static int durationMs(Context context) {
        return durationMsForLevel(level(context));
    }

    static int durationMsForLevel(int level) {
        return DURATIONS_MS[clampLevel(level)];
    }

    private static int clampLevel(int level) {
        return Math.max(0, Math.min(MAX_LEVEL, level));
    }

    private static SharedPreferences preferences(Context context) {
        return context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE);
    }
}
