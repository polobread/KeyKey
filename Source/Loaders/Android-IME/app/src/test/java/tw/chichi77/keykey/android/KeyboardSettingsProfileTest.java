package tw.chichi77.keykey.android;

import static org.junit.Assert.*;
import java.util.Map;
import org.junit.Test;

public final class KeyboardSettingsProfileTest {
    @Test public void upgradePreservesTheEffectiveVirtualAndPhysicalTableChoices() {
        var migrated = KeyboardSettingsProfile.migrationValues(Map.of(
                "bopomofo_composition_mode", "traditional", "bopomofo_keyboard_layout", "ETen26",
                "simplified_chinese_output", true, "smart_space_selects_candidates", true,
                "smart_bigram_enabled", false, "table_options.CANGJIE.realtime", false,
                "table_options.CANGJIE.virtual.realtime", true,
                "table_options.CANGJIE.physical.clear", true,
                "table_options.CANGJIE.virtual.clear", false));
        for (boolean virtual : new boolean[]{true, false}) {
            assertEquals("TRADITIONAL", migrated.get(KeyboardSettingsProfile.key(virtual, "chinese_input_method")));
            assertEquals("ETen26", migrated.get(KeyboardSettingsProfile.key(virtual, "bopomofo_keyboard_layout")));
            assertEquals(true, migrated.get(KeyboardSettingsProfile.key(virtual, "simplified_chinese_output")));
            assertEquals(true, migrated.get(KeyboardSettingsProfile.key(virtual, "smart_space_selects_candidates")));
            assertEquals(false, migrated.get(KeyboardSettingsProfile.key(virtual, "smart_bigram_enabled")));
            assertEquals(virtual, migrated.get(KeyboardSettingsProfile.key(virtual, "table_options.CANGJIE.realtime")));
            assertEquals(!virtual, migrated.get(KeyboardSettingsProfile.key(virtual, "table_options.CANGJIE.clear")));
        }
    }
    @Test public void touchToneOmissionNeverOptsHardwareInDuringUpgrade() {
        var values = new java.util.HashMap<>(KeyboardSettingsProfile.migrationValues(Map.of("smart_omit_tone", true)));
        String virtual = KeyboardSettingsProfile.key(true, "smart_omit_tone");
        String physical = KeyboardSettingsProfile.key(false, "smart_omit_tone");
        assertEquals(true, values.get(virtual));
        assertEquals(false, values.get(physical));
        values.put(physical, true);
        values.put(virtual, false);
        assertEquals(true, values.get(physical));
        assertEquals(false, values.get(virtual));
    }
    @Test public void defaultsPreserveTouchPrefixAndPhysicalCursorBehavior() {
        var values = KeyboardSettingsProfile.migrationValues(Map.of());
        assertEquals(true, values.get(KeyboardSettingsProfile.key(true, "table_options.CANGJIE.realtime")));
        assertEquals(false, values.get(KeyboardSettingsProfile.key(false, "table_options.CANGJIE.realtime")));
        assertEquals(true, values.get(KeyboardSettingsProfile.key(true, "table_options.CANGJIE.prefix")));
        assertEquals(false, values.get(KeyboardSettingsProfile.key(false, "table_options.CANGJIE.prefix")));
        var options = HardwareSmartSettings.Options.defaults();
        assertFalse(options.omitTone());
        assertFalse(options.returnsToEnd());
        assertFalse(options.ignoreCaps());
        assertEquals(10, options.maxSyllables());
        assertFalse(KeyboardSettingsProfile.belongsTo(KeyboardSettingsProfile.key(false, "chinese_input_method"), true));
    }
    @Test public void appearanceUpgradeCopiesEffectiveLegacyChoicesForBothProfiles() {
        var legacy = KeyboardSettingsProfile.appearanceMigrationValues(Map.of(
                CandidateColorSettings.KEY_COLOR, "Green", HapticSettings.KEY_HAPTIC_LEVEL, 4));
        var explicit = KeyboardSettingsProfile.appearanceMigrationValues(Map.of(
                CandidateColorSettings.KEY_COLOR, "Red", HapticSettings.KEY_HAPTIC_LEVEL, 8,
                HapticSettings.KEY_HAPTIC_DURATION_MS, 10));
        for (boolean virtual : new boolean[]{true, false}) {
            assertEquals("Green", legacy.get(KeyboardSettingsProfile.key(virtual, CandidateColorSettings.KEY_COLOR)));
            assertEquals(50, legacy.get(KeyboardSettingsProfile.key(virtual, HapticSettings.KEY_HAPTIC_DURATION_MS)));
            assertEquals("Red", explicit.get(KeyboardSettingsProfile.key(virtual, CandidateColorSettings.KEY_COLOR)));
            assertEquals(10, explicit.get(KeyboardSettingsProfile.key(virtual, HapticSettings.KEY_HAPTIC_DURATION_MS)));
        }
    }

}
