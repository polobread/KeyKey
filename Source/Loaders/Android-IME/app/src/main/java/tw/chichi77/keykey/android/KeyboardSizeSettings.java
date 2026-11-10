package tw.chichi77.keykey.android;

import android.content.Context;
import android.content.SharedPreferences;

final class KeyboardSizeSettings {
    static final int MIN_PERCENT = 50;
    static final int MAX_PERCENT = 200;
    static final int DEFAULT_PERCENT = 100;
    static final float MAX_BOTTOM_GAP_DP = 72f;
    private static final int[] HEIGHT_PERCENTS = {50, 75, 90, 100, 110, 125, 150, 175, 200};
    static final String KEY_PORTRAIT_PERCENT = "touch_keyboard_portrait_height_percent";
    static final String KEY_LANDSCAPE_PERCENT = "touch_keyboard_landscape_height_percent";

    static final String KEY_PORTRAIT_SCALE = "touch_keyboard_portrait_height_scale";
    static final String KEY_LANDSCAPE_SCALE = "touch_keyboard_landscape_height_scale";
    static final String KEY_PORTRAIT_GAP = "touch_keyboard_portrait_bottom_gap_dp";
    static final String KEY_LANDSCAPE_GAP = "touch_keyboard_landscape_bottom_gap_dp";

    record Size(float heightScale, float bottomGapDp) {
        Size {
            heightScale = Float.isFinite(heightScale)
                    ? Math.max(MIN_PERCENT / 100f, Math.min(MAX_PERCENT / 100f, heightScale)) : 1f;
            bottomGapDp = Float.isFinite(bottomGapDp)
                    ? Math.max(0f, Math.min(MAX_BOTTOM_GAP_DP, bottomGapDp)) : 0f;
        }
    }
    static final Size DEFAULT_SIZE = new Size(1f, 0f);

    private static final String PREFERENCES_NAME = "ime_settings";

    private KeyboardSizeSettings() {}

    static int portraitPercent(Context context) {
        return Math.round(size(context, false).heightScale() * 100);
    }

    static int landscapePercent(Context context) {
        return Math.round(size(context, true).heightScale() * 100);
    }

    static void setPortraitPercent(Context context, int percent) {
        setPercent(context, KEY_PORTRAIT_PERCENT, KEY_PORTRAIT_SCALE, percent);
    }

    static void setLandscapePercent(Context context, int percent) {
        setPercent(context, KEY_LANDSCAPE_PERCENT, KEY_LANDSCAPE_SCALE, percent);
    }

    static boolean isSizeKey(String key) {
        return KEY_PORTRAIT_PERCENT.equals(key) || KEY_LANDSCAPE_PERCENT.equals(key)
                || KEY_PORTRAIT_SCALE.equals(key) || KEY_LANDSCAPE_SCALE.equals(key)
                || KEY_PORTRAIT_GAP.equals(key) || KEY_LANDSCAPE_GAP.equals(key);
    }

    static int clampPercent(int percent) {
        return Math.max(MIN_PERCENT, Math.min(MAX_PERCENT, percent));
    }

    static int maxSelectionIndex() {
        return HEIGHT_PERCENTS.length - 1;
    }

    static int percentForSelection(int index) {
        return HEIGHT_PERCENTS[Math.max(0, Math.min(maxSelectionIndex(), index))];
    }

    static int selectionForPercent(int percent) {
        int boundedPercent = clampPercent(percent);
        int closest = 0;
        for (int index = 1; index < HEIGHT_PERCENTS.length; index++) {
            if (Math.abs(HEIGHT_PERCENTS[index] - boundedPercent)
                    < Math.abs(HEIGHT_PERCENTS[closest] - boundedPercent)) {
                closest = index;
            }
        }
        return closest;
    }

    private static int nearestPercent(int percent) {
        return percentForSelection(selectionForPercent(percent));
    }

    static Size size(Context context, boolean landscape) {
        SharedPreferences prefs = preferences(context);
        String percentKey = landscape ? KEY_LANDSCAPE_PERCENT : KEY_PORTRAIT_PERCENT;
        float legacyScale = nearestPercent(prefs.getInt(percentKey, DEFAULT_PERCENT)) / 100f;
        return new Size(prefs.getFloat(landscape ? KEY_LANDSCAPE_SCALE : KEY_PORTRAIT_SCALE, legacyScale),
                prefs.getFloat(landscape ? KEY_LANDSCAPE_GAP : KEY_PORTRAIT_GAP, 0f));
    }

    static void setSize(Context context, boolean landscape, Size size) {
        preferences(context).edit()
                .putFloat(landscape ? KEY_LANDSCAPE_SCALE : KEY_PORTRAIT_SCALE, size.heightScale())
                .putFloat(landscape ? KEY_LANDSCAPE_GAP : KEY_PORTRAIT_GAP, size.bottomGapDp())
                .apply();
    }

    private static void setPercent(Context context, String percentKey, String scaleKey, int percent) {
        preferences(context).edit().putInt(percentKey, nearestPercent(percent)).remove(scaleKey).apply();
    }

    private static SharedPreferences preferences(Context context) {
        return context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE);
    }
}
