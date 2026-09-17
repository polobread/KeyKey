package tw.chichi77.keykey.android;

import android.content.Context;
import android.content.SharedPreferences;

final class KeyboardSizeSettings {
    static final int MIN_PERCENT = 50;
    static final int MAX_PERCENT = 200;
    static final int DEFAULT_PERCENT = 100;
    static final String KEY_PORTRAIT_PERCENT = "touch_keyboard_portrait_height_percent";
    static final String KEY_LANDSCAPE_PERCENT = "touch_keyboard_landscape_height_percent";

    private static final String PREFERENCES_NAME = "ime_settings";

    private KeyboardSizeSettings() {}

    static int portraitPercent(Context context) {
        return readPercent(context, KEY_PORTRAIT_PERCENT);
    }

    static int landscapePercent(Context context) {
        return readPercent(context, KEY_LANDSCAPE_PERCENT);
    }

    static void setPortraitPercent(Context context, int percent) {
        setPercent(context, KEY_PORTRAIT_PERCENT, percent);
    }

    static void setLandscapePercent(Context context, int percent) {
        setPercent(context, KEY_LANDSCAPE_PERCENT, percent);
    }

    static boolean isSizeKey(String key) {
        return KEY_PORTRAIT_PERCENT.equals(key) || KEY_LANDSCAPE_PERCENT.equals(key);
    }

    static int clampPercent(int percent) {
        return Math.max(MIN_PERCENT, Math.min(MAX_PERCENT, percent));
    }

    private static int readPercent(Context context, String key) {
        return clampPercent(preferences(context).getInt(key, DEFAULT_PERCENT));
    }

    private static void setPercent(Context context, String key, int percent) {
        preferences(context).edit().putInt(key, clampPercent(percent)).apply();
    }

    private static SharedPreferences preferences(Context context) {
        return context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE);
    }
}
