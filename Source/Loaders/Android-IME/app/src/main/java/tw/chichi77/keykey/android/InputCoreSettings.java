// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
package tw.chichi77.keykey.android;

import android.content.Context;
import java.util.UUID;

/** Core preference and per-core user-data notifications share the existing IME settings. */
final class InputCoreSettings {
    static final String KEY_CORE = "input_core";
    static final String KEY_USER_DATA_PREFIX = "input_core_user_data.";
    private InputCoreSettings() {}

    static InputCore core(Context context) {
        return InputCore.fromRaw(CandidateWindowSettings.preferences(context)
                .getString(KEY_CORE, InputCore.JAVA.rawName));
    }
    static void setCore(Context context, InputCore core) {
        CandidateWindowSettings.preferences(context).edit().putString(KEY_CORE, core.rawName).apply();
    }
    static void notifyUserDataChanged(Context context, InputCore core) {
        CandidateWindowSettings.preferences(context).edit()
                .putString(KEY_USER_DATA_PREFIX + core.rawName, UUID.randomUUID().toString()).apply();
    }
}
