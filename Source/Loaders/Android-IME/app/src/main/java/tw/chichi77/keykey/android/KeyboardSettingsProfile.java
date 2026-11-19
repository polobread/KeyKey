package tw.chichi77.keykey.android;

import android.content.Context;
import android.content.SharedPreferences;
import java.util.LinkedHashMap;
import java.util.Map;

/** Two independent preference profiles; dictionaries and learning remain shared. */
final class KeyboardSettingsProfile {
    static final String EXTRA_PROFILE = "keyboard_settings_profile";
    static final String VIRTUAL = "virtual";
    static final String PHYSICAL = "physical";
    static final String MIGRATED = "keyboard_profiles_migrated_v1";
    static final String APPEARANCE_MIGRATED = "keyboard_profiles_appearance_migrated_v1";
    private KeyboardSettingsProfile() {}
    static String key(boolean virtual, String name) {
        return "keyboard." + (virtual ? VIRTUAL : PHYSICAL) + "." + name;
    }
    static boolean belongsTo(String key, boolean virtual) {
        return key != null && key.startsWith(key(virtual, ""));
    }
    static SharedPreferences preferences(Context context) {
        migrate(context);
        return CandidateWindowSettings.preferences(context);
    }
    static synchronized void migrate(Context context) {
        SharedPreferences saved = CandidateWindowSettings.preferences(context);
        if (!saved.getBoolean(MIGRATED, false)) {
            writeMissing(saved, migrationValues(saved.getAll()), MIGRATED);
        }
        if (!saved.getBoolean(APPEARANCE_MIGRATED, false)) {
            writeMissing(saved, appearanceMigrationValues(saved.getAll()), APPEARANCE_MIGRATED);
        }
    }
    private static void writeMissing(SharedPreferences saved, Map<String, Object> values, String marker) {
        SharedPreferences.Editor edit = saved.edit();
        for (var entry : values.entrySet()) {
            if (saved.contains(entry.getKey())) continue;
            Object value = entry.getValue();
            if (value instanceof Boolean item) edit.putBoolean(entry.getKey(), item);
            else if (value instanceof Integer item) edit.putInt(entry.getKey(), item);
            else if (value instanceof String item) edit.putString(entry.getKey(), item);
        }
        edit.putBoolean(marker, true).apply();
    }
    /** Capture the former shared appearance once; later legacy edits cannot couple the profiles. */
    static Map<String, Object> appearanceMigrationValues(Map<String, ?> old) {
        Map<String, Object> result = new LinkedHashMap<>();
        Object color = old.get(CandidateColorSettings.KEY_COLOR);
        String colorValue = CandidateColorSettings.valueForColor(CandidateColorSettings.colorFromValue(
                color instanceof String item ? item : null));
        Object duration = old.get(HapticSettings.KEY_HAPTIC_DURATION_MS);
        Object level = old.get(HapticSettings.KEY_HAPTIC_LEVEL);
        int durationMs = duration instanceof Number item
                ? HapticSettings.durationMsForSelection(HapticSettings.selectionForDurationMs(item.intValue()))
                : HapticSettings.legacyDurationMsForLevel(level instanceof Number item ? item.intValue() : 0);
        for (boolean virtual : new boolean[]{true, false}) {
            result.put(key(virtual, CandidateColorSettings.KEY_COLOR), colorValue);
            result.put(key(virtual, HapticSettings.KEY_HAPTIC_DURATION_MS), durationMs);
        }
        return result;
    }
    /** Snapshot all old values once, before either new profile can change them. */
    static Map<String, Object> migrationValues(Map<String, ?> old) {
        Map<String, Object> result = new LinkedHashMap<>();
        Object method = old.get("chinese_input_method");
        if (!(method instanceof String) || ((String) method).isEmpty())
            method = "traditional".equals(old.get("bopomofo_composition_mode")) ? "TRADITIONAL" : "SMART";
        for (boolean virtual : new boolean[]{true, false}) {
            result.put(key(virtual, "chinese_input_method"), method);
            copy(result, old, virtual, "bopomofo_keyboard_layout", "Standard");
            copy(result, old, virtual, "simplified_chinese_output", false);
            copy(result, old, virtual, "smart_space_selects_candidates", false);
            copy(result, old, virtual, "smart_bigram_enabled", true);
            // The former setting was touch-only; never opt hardware into omission on upgrade.
            result.put(key(virtual, "smart_omit_tone"), virtual ? value(old, "smart_omit_tone", false) : false);
            for (String table : new String[]{"CANGJIE", "SIMPLEX"}) {
                String prefix = "table_options." + table + ".";
                boolean cangjie = table.equals("CANGJIE");
                boolean realtime = (Boolean) value(old, prefix + (cangjie && virtual ? "virtual.realtime" : "realtime"),
                        value(old, prefix + "realtime", cangjie && virtual));
                result.put(key(virtual, prefix + "realtime"), realtime);
                result.put(key(virtual, prefix + "prefix"), cangjie && (Boolean) value(old,
                        prefix + (virtual ? "virtual.prefix" : "physical.prefix"), virtual));
                result.put(key(virtual, prefix + "clear"), value(old,
                        prefix + (cangjie ? (virtual ? "virtual.clear" : "physical.clear") : "clear"),
                        value(old, prefix + "clear", cangjie)));
                copy(result, old, virtual, prefix + "maximum", !cangjie);
                copy(result, old, virtual, prefix + "learning", cangjie);
                copy(result, old, virtual, prefix + "punctuation", 0);
            }
        }
        return result;
    }
    private static Object value(Map<String, ?> old, String name, Object fallback) {
        Object value = old.get(name);
        return value == null ? fallback : value;
    }
    private static void copy(Map<String, Object> result, Map<String, ?> old, boolean virtual,
                             String name, Object fallback) {
        result.put(key(virtual, name), value(old, name, fallback));
    }
}
