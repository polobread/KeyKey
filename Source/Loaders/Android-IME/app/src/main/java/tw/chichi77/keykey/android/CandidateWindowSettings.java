package tw.chichi77.keykey.android;

import android.content.Context;
import android.content.SharedPreferences;

final class CandidateWindowSettings {
    enum Layout { VERTICAL, HORIZONTAL }
    enum Failure { TOKEN, ATTACH }

    static final String PREFERENCES_NAME = "ime_settings";
    static final String KEY_FLOATING_ENABLED = "hardware_floating_candidates_enabled";
    static final String KEY_LAYOUT = "hardware_candidate_layout";
    static final String KEY_FAILURE = "hardware_floating_candidates_failure";

    private static final String LAYOUT_VERTICAL = "vertical";
    private static final String LAYOUT_HORIZONTAL = "horizontal";

    private CandidateWindowSettings() {}

    static boolean floatingEnabled(Context context) {
        return preferences(context).getBoolean(KEY_FLOATING_ENABLED, false);
    }

    static void setFloatingEnabled(Context context, boolean enabled) {
        SharedPreferences.Editor editor = preferences(context).edit()
                .putBoolean(KEY_FLOATING_ENABLED, enabled);
        if (enabled) editor.remove(KEY_FAILURE);
        editor.apply();
    }

    static void disableForFailure(Context context, Failure failure) {
        preferences(context).edit()
                .putBoolean(KEY_FLOATING_ENABLED, false)
                .putString(KEY_FAILURE, failure.name())
                .apply();
    }

    static Failure failure(Context context) {
        String value = preferences(context).getString(KEY_FAILURE, null);
        if (Failure.TOKEN.name().equals(value)) return Failure.TOKEN;
        if (Failure.ATTACH.name().equals(value)) return Failure.ATTACH;
        return null;
    }

    static Layout layout(Context context) {
        return layoutFromValue(preferences(context).getString(KEY_LAYOUT, LAYOUT_VERTICAL));
    }

    static void setLayout(Context context, Layout layout) {
        preferences(context).edit().putString(KEY_LAYOUT, valueForLayout(layout)).apply();
    }

    static Layout layoutFromValue(String value) {
        return LAYOUT_HORIZONTAL.equals(value) ? Layout.HORIZONTAL : Layout.VERTICAL;
    }

    static String valueForLayout(Layout layout) {
        return layout == Layout.HORIZONTAL ? LAYOUT_HORIZONTAL : LAYOUT_VERTICAL;
    }

    static SharedPreferences preferences(Context context) {
        return context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE);
    }
}
