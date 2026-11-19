package tw.chichi77.keykey.android;

import android.content.Context;
import android.content.SharedPreferences;

final class ChineseInputMethodSettings {
    static final String KEY_METHOD = "chinese_input_method";
    static final String KEY_SIMPLIFIED_CHINESE_OUTPUT = "simplified_chinese_output";
    static ChineseInputMethod method(Context context) { return method(context, true); }
    static ChineseInputMethod method(Context context, boolean virtual) {
        String raw = preferences(context).getString(KeyboardSettingsProfile.key(virtual, KEY_METHOD), "SMART");
        try { return ChineseInputMethod.valueOf(raw); }
        catch (IllegalArgumentException ignored) { return ChineseInputMethod.SMART; }
    }
    static SharedPreferences preferences(Context context) { return KeyboardSettingsProfile.preferences(context); }
    static void setMethod(Context context, ChineseInputMethod method) { setMethod(context, method, true); }
    static void setMethod(Context context, ChineseInputMethod method, boolean virtual) {
        preferences(context).edit().putString(KeyboardSettingsProfile.key(virtual, KEY_METHOD), method.name()).apply();
    }
    static boolean simplifiedChineseOutput(Context context) { return simplifiedChineseOutput(context, true); }
    static boolean simplifiedChineseOutput(Context context, boolean virtual) {
        return preferences(context).getBoolean(KeyboardSettingsProfile.key(virtual, KEY_SIMPLIFIED_CHINESE_OUTPUT), false);
    }
    static void setSimplifiedChineseOutput(Context context, boolean enabled) { setSimplifiedChineseOutput(context, enabled, true); }
    static void setSimplifiedChineseOutput(Context context, boolean enabled, boolean virtual) {
        preferences(context).edit().putBoolean(KeyboardSettingsProfile.key(virtual, KEY_SIMPLIFIED_CHINESE_OUTPUT), enabled).apply();
    }
    static TableInputOptions options(Context context, ChineseInputMethod method) { return options(context, method, false); }
    static TableInputOptions options(Context context, ChineseInputMethod method, boolean virtual) {
        TableInputOptions result = new TableInputOptions(method);
        SharedPreferences saved = preferences(context);
        String key = KeyboardSettingsProfile.key(virtual, "table_options." + method.name() + ".");
        result.queryAtMaximum = saved.getBoolean(key + "maximum", result.queryAtMaximum);
        result.clearOnError = saved.getBoolean(key + "clear", result.clearOnError);
        result.composeWhileTyping = saved.getBoolean(key + "realtime", method == ChineseInputMethod.CANGJIE && virtual);
        result.prefixCandidates = method == ChineseInputMethod.CANGJIE && saved.getBoolean(key + "prefix", virtual);
        result.dynamicFrequency = saved.getBoolean(key + "learning", result.dynamicFrequency);
        result.punctuation = saved.getInt(key + "punctuation", 0);
        if (result.composeWhileTyping) result.clearOnError = false;
        return result;
    }
    static void setOptions(Context context, ChineseInputMethod method, TableInputOptions options) { setOptions(context, method, options, false); }
    static void setOptions(Context context, ChineseInputMethod method, TableInputOptions options, boolean virtual) {
        String key = KeyboardSettingsProfile.key(virtual, "table_options." + method.name() + ".");
        preferences(context).edit().putBoolean(key + "maximum", options.queryAtMaximum)
                .putBoolean(key + "learning", options.dynamicFrequency).putInt(key + "punctuation", options.punctuation)
                .putBoolean(key + "clear", options.clearOnError && !options.composeWhileTyping)
                .putBoolean(key + "realtime", options.composeWhileTyping)
                .putBoolean(key + "prefix", options.prefixCandidates).apply();
    }
}
