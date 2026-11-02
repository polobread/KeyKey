// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
package tw.chichi77.keykey.android;

import android.content.Context;
import java.util.UUID;

/** Data-change notification only; there is no core-selection preference. */
final class UserDataNotifications {
    static final String KEY_CHANGED = "input_core_user_data.guanyinma";
    private UserDataNotifications() {}
    static void changed(Context context) {
        CandidateWindowSettings.preferences(context).edit()
                .putString(KEY_CHANGED, UUID.randomUUID().toString()).apply();
    }
}
