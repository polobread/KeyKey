package tw.chichi77.keykey.android;

import android.content.Context;

final class KeyboardLayoutProfileSettings {
    static final String KEY_PROFILE = "keyboard_layout_profile";

    private KeyboardLayoutProfileSettings() {}

    static KeyboardLayoutProfile profile(Context context) {
        return KeyboardLayoutProfile.forId(CandidateWindowSettings.preferences(context)
                .getString(KEY_PROFILE, KeyboardLayoutProfile.FULL.id));
    }

    static void setProfile(Context context, KeyboardLayoutProfile profile) {
        CandidateWindowSettings.preferences(context).edit()
                .putString(KEY_PROFILE, profile.id).apply();
    }
}
