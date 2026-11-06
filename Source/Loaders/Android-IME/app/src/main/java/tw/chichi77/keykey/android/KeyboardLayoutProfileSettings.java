package tw.chichi77.keykey.android;

import android.content.Context;

final class KeyboardLayoutProfileSettings {
    static final String KEY_PROFILE = "keyboard_layout_profile";
    static final String KEY_KEYCAP_AREA = "keyboard_keycap_area";
    static final String KEY_LAYOUT = "keyboard_layout";
    static final String KEY_SPACING = "keyboard_keycap_spacing";
    static final String KEY_FONT_SIZE = "keyboard_font_size";
    static final String KEY_FONT_LEVEL = "keyboard_font_level";
    static final String KEY_DELETE_POSITION = "keyboard_delete_position";

    private KeyboardLayoutProfileSettings() {}

    static KeyboardLayoutProfile.VisualOptions options(Context context) {
        var preferences = CandidateWindowSettings.preferences(context);
        return KeyboardLayoutProfile.resolveOptions(preferences.getString(KEY_LAYOUT, null),
                preferences.getString(KEY_SPACING, null), preferences.getString(KEY_FONT_LEVEL, null),
                preferences.getString(KEY_DELETE_POSITION, null), preferences.getString(KEY_PROFILE, null),
                preferences.getString(KEY_KEYCAP_AREA, null), preferences.getString(KEY_FONT_SIZE, null));
    }

    static KeyboardLayoutProfile profile(Context context) {
        return options(context).layout();
    }

    static void setProfile(Context context, KeyboardLayoutProfile profile) {
        var current = options(context);
        setOptions(context, new KeyboardLayoutProfile.VisualOptions(profile, current.spacing(),
                current.fontSize(), current.deletePosition()));
    }

    static KeyboardLayoutProfile.KeycapArea keycapArea(Context context) {
        return options(context).spacing();
    }

    static void setKeycapArea(Context context, KeyboardLayoutProfile.KeycapArea area) {
        var current = options(context);
        setOptions(context, new KeyboardLayoutProfile.VisualOptions(current.layout(), area,
                current.fontSize(), current.deletePosition()));
    }

    static KeyboardLayoutProfile.FontSize fontSize(Context context) { return options(context).fontSize(); }

    static void setFontSize(Context context, KeyboardLayoutProfile.FontSize size) {
        var current = options(context);
        setOptions(context, new KeyboardLayoutProfile.VisualOptions(current.layout(), current.spacing(),
                size, current.deletePosition()));
    }

    static KeyboardLayoutProfile.DeletePosition deletePosition(Context context) {
        return KeyboardLayoutProfile.DeletePosition.forId(CandidateWindowSettings.preferences(context)
                .getString(KEY_DELETE_POSITION, KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER.id));
    }

    static void setDeletePosition(Context context, KeyboardLayoutProfile.DeletePosition position) {
        var current = options(context);
        setOptions(context, new KeyboardLayoutProfile.VisualOptions(current.layout(), current.spacing(),
                current.fontSize(), position));
    }

    private static void setOptions(Context context, KeyboardLayoutProfile.VisualOptions options) {
        // Materialize the whole migrated choice before changing any one part.
        CandidateWindowSettings.preferences(context).edit()
                .putString(KEY_LAYOUT, options.layout().id).putString(KEY_SPACING, options.spacing().id)
                .putString(KEY_FONT_LEVEL, options.fontSize().id)
                .putString(KEY_DELETE_POSITION, options.deletePosition().id).apply();
    }

    static boolean isSettingKey(String key) {
        return KEY_LAYOUT.equals(key) || KEY_SPACING.equals(key) || KEY_FONT_LEVEL.equals(key) || KEY_FONT_SIZE.equals(key)
                || KEY_DELETE_POSITION.equals(key) || KEY_PROFILE.equals(key) || KEY_KEYCAP_AREA.equals(key);
    }
}
