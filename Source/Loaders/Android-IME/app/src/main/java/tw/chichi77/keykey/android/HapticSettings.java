package tw.chichi77.keykey.android;

import android.content.Context;

final class HapticSettings {
    private static final int[] DURATIONS_MS = {0, 1, 2, 3, 5, 10, 20, 30, 50, 100};
    private static final int[] LEGACY_DURATIONS_MS = {0, 10, 20, 30, 50, 80, 100, 150, 200};

    static final String KEY_HAPTIC_LEVEL = "haptic_level";
    static final String KEY_HAPTIC_DURATION_MS = "haptic_duration_ms";

    private HapticSettings() {}

    static int durationMs(Context context) { return durationMs(context, true); }

    static int durationMs(Context context, boolean virtual) {
        return nearestDurationMs(KeyboardSettingsProfile.preferences(context)
                .getInt(KeyboardSettingsProfile.key(virtual, KEY_HAPTIC_DURATION_MS), 0));
    }

    static void setDurationMs(Context context, int durationMs) { setDurationMs(context, durationMs, true); }

    static void setDurationMs(Context context, int durationMs, boolean virtual) {
        KeyboardSettingsProfile.preferences(context).edit()
                .putInt(KeyboardSettingsProfile.key(virtual, KEY_HAPTIC_DURATION_MS), nearestDurationMs(durationMs))
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

}
