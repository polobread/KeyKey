package tw.chichi77.keykey.android;

import android.content.Context;
import android.content.SharedPreferences;

final class ChineseInputMethodSettings {
    static final String KEY_METHOD = "chinese_input_method";
    static ChineseInputMethod method(Context context) {
        String raw = preferences(context).getString(KEY_METHOD, "");
        try { return ChineseInputMethod.valueOf(raw); }
        catch (IllegalArgumentException ignored) {
            return BopomofoCompositionModeSettings.mode(context) == BopomofoCompositionMode.TRADITIONAL
                    ? ChineseInputMethod.TRADITIONAL : ChineseInputMethod.SMART;
        }
    }
    static SharedPreferences preferences(Context context) { return CandidateWindowSettings.preferences(context); }
    static void setMethod(Context context, ChineseInputMethod method) {
        // One edit: listeners never observe a new legacy mode with an old method.
        SharedPreferences.Editor editor = preferences(context).edit().putString(KEY_METHOD, method.name());
        if (!method.isTable()) editor.putString(BopomofoCompositionModeSettings.KEY_MODE,
                method == ChineseInputMethod.SMART ? "smart" : "traditional");
        editor.apply();
    }
    static TableInputOptions options(Context context, ChineseInputMethod method) {
        TableInputOptions result = new TableInputOptions(method);
        SharedPreferences p = preferences(context);
        String key = "table_options." + method.name() + ".";
        result.queryAtMaximum = p.getBoolean(key + "maximum", result.queryAtMaximum);
        result.clearOnError = p.getBoolean(key + "clear", result.clearOnError);
        result.composeWhileTyping = p.getBoolean(key + "realtime", false);
        result.dynamicFrequency = p.getBoolean(key + "learning", result.dynamicFrequency);
        result.punctuation = p.getInt(key + "punctuation", 0);
        return result;
    }
    static void setOptions(Context context, ChineseInputMethod method, TableInputOptions options) {
        String key = "table_options." + method.name() + ".";
        preferences(context).edit().putBoolean(key + "maximum", options.queryAtMaximum)
                .putBoolean(key + "clear", options.clearOnError)
                .putBoolean(key + "realtime", options.composeWhileTyping)
                .putBoolean(key + "learning", options.dynamicFrequency)
                .putInt(key + "punctuation", options.punctuation).apply();
    }
}
