package tw.chichi77.keykey.android;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.LinkedHashSet;
import java.util.Set;

final class PhraseSettings {
    private static final String PREFERENCES_NAME = "ime_settings";
    private static final String KEY_ENABLED_COLLECTIONS = "enabled_phrase_collections";
    private static final String DEFAULT_COLLECTION = "McBopomofo";

    private PhraseSettings() {}

    static Set<String> enabledCollections(Context context) {
        SharedPreferences preferences = preferences(context);
        if (!preferences.contains(KEY_ENABLED_COLLECTIONS)) {
            return Set.of(DEFAULT_COLLECTION);
        }
        Set<String> stored = preferences.getStringSet(KEY_ENABLED_COLLECTIONS, Set.of());
        return stored == null ? Set.of() : new LinkedHashSet<>(stored);
    }

    static void setEnabledCollections(Context context, Set<String> collections) {
        preferences(context).edit()
                .putStringSet(KEY_ENABLED_COLLECTIONS, new LinkedHashSet<>(collections))
                .apply();
    }

    static Set<String> baseCollectionOnly() {
        return Set.of(DEFAULT_COLLECTION);
    }

    private static SharedPreferences preferences(Context context) {
        return context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE);
    }
}
