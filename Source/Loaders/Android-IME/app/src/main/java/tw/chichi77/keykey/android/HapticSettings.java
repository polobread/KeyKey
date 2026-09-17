package tw.chichi77.keykey.android;

import android.content.Context;
import android.content.SharedPreferences;

final class HapticSettings {
    static final int MAX_DURATION_MS = 100;
    private static final int[] LEGACY_DURATIONS_MS = {0, 10, 20, 30, 50, 80, 100, 150, 200};

    private static final String PREFERENCES_NAME = "ime_settings";
    private static final String KEY_HAPTIC_LEVEL = "haptic_level";
    private static final String KEY_HAPTIC_DURATION_MS = "haptic_duration_ms";

    private HapticSettings() {}

    static int durationMs(Context context) {
        SharedPreferences preferences = preferences(context);
        if (preferences.contains(KEY_HAPTIC_DURATION_MS)) {
            return clampDurationMs(preferences.getInt(KEY_HAPTIC_DURATION_MS, 0));
        }
        int legacyLevel = Math.max(0, Math.min(LEGACY_DURATIONS_MS.length - 1,
                preferences.getInt(KEY_HAPTIC_LEVEL, 0)));
        return clampDurationMs(LEGACY_DURATIONS_MS[legacyLevel]);
    }

    static void setDurationMs(Context context, int durationMs) {
        preferences(context).edit()
                .putInt(KEY_HAPTIC_DURATION_MS, clampDurationMs(durationMs))
                .remove(KEY_HAPTIC_LEVEL)
                .apply();
    }

    static int clampDurationMs(int durationMs) {
        return Math.max(0, Math.min(MAX_DURATION_MS, durationMs));
    }

    static int legacyDurationMsForLevel(int level) {
        int safeLevel = Math.max(0, Math.min(LEGACY_DURATIONS_MS.length - 1, level));
        return clampDurationMs(LEGACY_DURATIONS_MS[safeLevel]);
    }

    private static SharedPreferences preferences(Context context) {
        return context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE);
    }
}
