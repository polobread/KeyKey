package tw.chichi77.keykey.android;

import android.content.Context;
import android.content.SharedPreferences;

final class HapticSettings {
    private static final int[] DURATIONS_MS = {0, 1, 2, 3, 5, 10, 20, 30, 50, 100};
    private static final int[] LEGACY_DURATIONS_MS = {0, 10, 20, 30, 50, 80, 100, 150, 200};

    private static final String PREFERENCES_NAME = "ime_settings";
    private static final String KEY_HAPTIC_LEVEL = "haptic_level";
    private static final String KEY_HAPTIC_DURATION_MS = "haptic_duration_ms";

    private HapticSettings() {}

    static int durationMs(Context context) {
        SharedPreferences preferences = preferences(context);
        if (preferences.contains(KEY_HAPTIC_DURATION_MS)) {
            return nearestDurationMs(preferences.getInt(KEY_HAPTIC_DURATION_MS, 0));
        }
        int legacyLevel = Math.max(0, Math.min(LEGACY_DURATIONS_MS.length - 1,
                preferences.getInt(KEY_HAPTIC_LEVEL, 0)));
        return nearestDurationMs(LEGACY_DURATIONS_MS[legacyLevel]);
    }

    static void setDurationMs(Context context, int durationMs) {
        preferences(context).edit()
                .putInt(KEY_HAPTIC_DURATION_MS, nearestDurationMs(durationMs))
                .remove(KEY_HAPTIC_LEVEL)
                .apply();
    }

    static int maxSelectionIndex() {
        return DURATIONS_MS.length - 1;
    }

    static int durationMsForSelection(int index) {
        return DURATIONS_MS[Math.max(0, Math.min(maxSelectionIndex(), index))];
    }

    static int selectionForDurationMs(int durationMs) {
        int boundedDurationMs = Math.max(0, Math.min(100, durationMs));
        int closest = 0;
        for (int index = 1; index < DURATIONS_MS.length; index++) {
            if (Math.abs(DURATIONS_MS[index] - boundedDurationMs)
                    < Math.abs(DURATIONS_MS[closest] - boundedDurationMs)) {
                closest = index;
            }
        }
        return closest;
    }

    private static int nearestDurationMs(int durationMs) {
        return durationMsForSelection(selectionForDurationMs(durationMs));
    }

    static int legacyDurationMsForLevel(int level) {
        int safeLevel = Math.max(0, Math.min(LEGACY_DURATIONS_MS.length - 1, level));
        return nearestDurationMs(LEGACY_DURATIONS_MS[safeLevel]);
    }

    private static SharedPreferences preferences(Context context) {
        return context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE);
    }
}
