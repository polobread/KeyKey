package tw.chichi77.keykey.android;

import android.content.Context;
import android.content.SharedPreferences;

final class CandidateWindowSettings {
    enum Layout { VERTICAL, HORIZONTAL }

    static final String PREFERENCES_NAME = "ime_settings";
    static final String KEY_FLOATING_ENABLED = "hardware_floating_candidates_enabled";
    static final String KEY_LAYOUT = "hardware_candidate_layout";

    private static final String LAYOUT_VERTICAL = "vertical";
    private static final String LAYOUT_HORIZONTAL = "horizontal";

    private CandidateWindowSettings() {}

    static boolean floatingEnabled(Context context) {
        return preferences(context).getBoolean(KEY_FLOATING_ENABLED, false);
    }

    static void setFloatingEnabled(Context context, boolean enabled) {
        preferences(context).edit().putBoolean(KEY_FLOATING_ENABLED, enabled).apply();
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
