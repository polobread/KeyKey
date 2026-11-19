package tw.chichi77.keykey.android;

import static org.junit.Assert.*;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.view.View;
import android.view.ViewGroup;
import android.widget.CheckBox;
import android.widget.TextView;
import android.widget.SeekBar;
import android.widget.Spinner;
import android.view.accessibility.AccessibilityNodeInfo;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import org.junit.Test;
import org.junit.runner.RunWith;
import java.util.Map;

@RunWith(AndroidJUnit4.class)
public final class KeyboardSettingsProfilesInstrumentedTest {
    private final android.app.Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
    private final Context context = instrumentation.getTargetContext();
    @Test public void profileValuesStayIndependentAndUpgradeRunsOnlyOnce() {
        var saved = CandidateWindowSettings.preferences(context);
        var before = saved.getAll();
        try {
            var edit = saved.edit();
            for (String key : saved.getAll().keySet())
                if (key.startsWith("keyboard.") || key.equals(KeyboardSettingsProfile.MIGRATED)) edit.remove(key);
            edit.putBoolean("smart_omit_tone", true).putBoolean("simplified_chinese_output", true)
                    .putBoolean("smart_space_selects_candidates", false).putBoolean("smart_bigram_enabled", true)
                    .putString("chinese_input_method", "SMART")
                    .putString("bopomofo_keyboard_layout", "ETen26")
                    .putBoolean("table_options.CANGJIE.realtime", false)
                    .putBoolean("table_options.CANGJIE.virtual.realtime", true).commit();
            KeyboardSettingsProfile.migrate(context);
            assertTrue(BopomofoCompositionModeSettings.omitTone(context, true));
            assertFalse(BopomofoCompositionModeSettings.omitTone(context, false));
            assertTrue(ChineseInputMethodSettings.simplifiedChineseOutput(context, false));
            assertTrue(ChineseInputMethodSettings.options(context, ChineseInputMethod.CANGJIE, true).composeWhileTyping);
            assertFalse(ChineseInputMethodSettings.options(context, ChineseInputMethod.CANGJIE, false).composeWhileTyping);
            ChineseInputMethodSettings.setSimplifiedChineseOutput(context, false, false);
            BopomofoKeyboardLayoutSettings.setLayout(context, BopomofoKeyboardLayout.HSU, false);
            BopomofoCompositionModeSettings.setSpaceSelectsCandidates(context, true, false);
            BopomofoCompositionModeSettings.setBigramEnabled(context, false, false);
            ChineseInputMethodSettings.setMethod(context, ChineseInputMethod.CANGJIE, false);
            assertTrue(ChineseInputMethodSettings.simplifiedChineseOutput(context, true));
            assertEquals(BopomofoKeyboardLayout.ETEN26, BopomofoKeyboardLayoutSettings.layout(context, true));
            assertFalse(BopomofoCompositionModeSettings.spaceSelectsCandidates(context, true));
            assertTrue(BopomofoCompositionModeSettings.bigramEnabled(context, true));
            assertNotEquals(ChineseInputMethod.CANGJIE, ChineseInputMethodSettings.method(context, true));
            KeyboardSettingsProfile.migrate(context);
            assertFalse(ChineseInputMethodSettings.simplifiedChineseOutput(context, false));
            assertEquals(BopomofoKeyboardLayout.HSU, BopomofoKeyboardLayoutSettings.layout(context, false));
        } finally { restore(saved, before); }
    }
    @Test public void appearanceUpgradePreservesChoicesAndNeverRecouplesTheProfiles() {
        var saved = CandidateWindowSettings.preferences(context);
        var before = saved.getAll();
        String virtualColor = KeyboardSettingsProfile.key(true, CandidateColorSettings.KEY_COLOR);
        String physicalColor = KeyboardSettingsProfile.key(false, CandidateColorSettings.KEY_COLOR);
        String virtualHaptic = KeyboardSettingsProfile.key(true, HapticSettings.KEY_HAPTIC_DURATION_MS);
        String physicalHaptic = KeyboardSettingsProfile.key(false, HapticSettings.KEY_HAPTIC_DURATION_MS);
        try {
            saved.edit().putBoolean(KeyboardSettingsProfile.MIGRATED, true)
                    .remove(KeyboardSettingsProfile.APPEARANCE_MIGRATED)
                    .remove(virtualColor).remove(virtualHaptic)
                    .putString(CandidateColorSettings.KEY_COLOR, "Green")
                    .putInt(HapticSettings.KEY_HAPTIC_DURATION_MS, 20)
                    .putString(physicalColor, "Red").putInt(physicalHaptic, 100).commit();
            KeyboardSettingsProfile.migrate(context);
            assertEquals(CandidateColorSettings.CandidateColor.GREEN, CandidateColorSettings.color(context, true));
            assertEquals(20, HapticSettings.durationMs(context, true));
            assertEquals(CandidateColorSettings.CandidateColor.RED, CandidateColorSettings.color(context, false));
            assertEquals(100, HapticSettings.durationMs(context, false));
            CandidateColorSettings.setColor(context, CandidateColorSettings.CandidateColor.YELLOW, true);
            HapticSettings.setDurationMs(context, 3, true);
            CandidateColorSettings.setColor(context, CandidateColorSettings.CandidateColor.PURPLE, false);
            HapticSettings.setDurationMs(context, 50, false);
            saved.edit().putString(CandidateColorSettings.KEY_COLOR, "Red")
                    .putInt(HapticSettings.KEY_HAPTIC_DURATION_MS, 100).commit();
            KeyboardSettingsProfile.migrate(context);
            assertEquals(CandidateColorSettings.CandidateColor.YELLOW, CandidateColorSettings.color(context, true));
            assertEquals(3, HapticSettings.durationMs(context, true));
            assertEquals(CandidateColorSettings.CandidateColor.PURPLE, CandidateColorSettings.color(context, false));
            assertEquals(50, HapticSettings.durationMs(context, false));
            saved.edit().remove(virtualColor).remove(virtualHaptic).commit();
            assertEquals(CandidateColorSettings.CandidateColor.PURPLE, CandidateColorSettings.color(context, true));
            assertEquals(0, HapticSettings.durationMs(context, true));
            assertEquals(50, HapticSettings.durationMs(context, false));
        } finally { restore(saved, before); }
    }

    @Test public void mergedHomeOpensBothProfilesAndReturnsWithoutAnOverviewPage() throws Exception {
        var saved = CandidateWindowSettings.preferences(context);
        var before = saved.getAll();
        Activity home = null;
        Activity page = null;
        try {
            CandidateWindowSettings.setFloatingEnabled(context, false);
            CandidateWindowSettings.setSmartTwoRowsEnabled(context, false);
            BopomofoCompositionModeSettings.setOmitTone(context, true, false);
            home = instrumentation.startActivitySync(new Intent(context, MainActivity.class)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
            Activity initial = home;
            instrumentation.runOnMainSync(() -> {
                View root = initial.findViewById(android.R.id.content);
                assertNotNull(find(root, context.getString(R.string.setup_title)));
                assertNotNull(find(root, context.getString(R.string.enable_ime)));
                assertNotNull(find(root, context.getString(R.string.choose_ime)));
                assertNotNull(find(root, context.getString(R.string.settings_title)));
                assertNotNull(find(root, context.getString(R.string.virtual_keyboard_settings)));
                assertNotNull(find(root, context.getString(R.string.physical_keyboard_settings)));
                assertNotNull(find(root, context.getString(R.string.keyboard_profiles_shared_data)));
                assertNotNull(find(root, "管理好打注音自訂詞"));
                assertNotNull(find(root, "重設好打注音學習紀錄"));
                assertNotNull(find(root, context.getString(R.string.privacy_note)));
                assertNotNull(find(root, context.getString(R.string.open_acknowledgements)));
                assertNull(find(root, context.getString(R.string.open_settings)));
                assertEquals(1, count(root, context.getString(R.string.phrase_collections_title)));
            });
            capture("settings-home.png");
            instrumentation.runOnMainSync(() -> {
                ViewGroup root = initial.findViewById(android.R.id.content);
                ((android.widget.ScrollView) root.getChildAt(0)).fullScroll(View.FOCUS_DOWN);
            });
            instrumentation.waitForIdleSync();
            capture("settings-home-bottom.png");
            for (boolean virtual : new boolean[]{true, false}) {
                var monitor = instrumentation.addMonitor(SettingsActivity.class.getName(), null, false);
                try {
                    instrumentation.runOnMainSync(() -> {
                        View button = find(initial.findViewById(android.R.id.content), context.getString(
                                virtual ? R.string.virtual_keyboard_settings : R.string.physical_keyboard_settings));
                        assertTrue(button.performClick());
                    });
                    page = instrumentation.waitForMonitorWithTimeout(monitor, 5000);
                    assertNotNull("Home must directly open the chosen profile page", page);
                } finally { instrumentation.removeMonitor(monitor); }
                Activity current = page;
                instrumentation.waitForIdleSync();
                instrumentation.runOnMainSync(() -> {
                    View root = current.findViewById(android.R.id.content);
                    assertNotNull(find(root, context.getString(virtual ? R.string.virtual_keyboard_settings : R.string.physical_keyboard_settings)));
                    assertNull(find(root, context.getString(R.string.settings_title)));
                    assertEquals(virtual, find(root, context.getString(R.string.keyboard_resize_title)) != null);
                    assertEquals(!virtual, find(root, context.getString(R.string.floating_candidates_enabled)) != null);
                    if (!virtual) {
                        CheckBox omission = (CheckBox) find(root, context.getString(R.string.smart_omit_tone));
                        CheckBox twoRows = (CheckBox) find(root, context.getString(R.string.hardware_smart_two_rows_enabled));
                        CheckBox floating = (CheckBox) find(root, context.getString(R.string.floating_candidates_enabled));
                        assertTrue(omission.isEnabled());
                        twoRows.setChecked(true);
                        assertFalse(omission.isEnabled());
                        assertTrue(omission.isChecked());
                        floating.setChecked(true);
                        assertTrue(omission.isEnabled());
                        assertFalse(twoRows.isEnabled());
                        floating.setChecked(false);
                        assertFalse(omission.isEnabled());
                        twoRows.setChecked(false);
                        assertTrue(omission.isEnabled());
                        assertTrue(omission.isChecked());
                    }
                    current.finish();
                });
                instrumentation.waitForIdleSync();
                IntegratedBottomControlsInstrumentedTest.await(initial::hasWindowFocus);
                page = null;
            }
            // A legacy unscoped settings entry redirects to this same home, with no intermediate page.
            var monitor = instrumentation.addMonitor(SettingsActivity.class.getName(), null, false);
            try {
                instrumentation.runOnMainSync(() -> initial.startActivity(new Intent(context, SettingsActivity.class)));
                Activity redirected = instrumentation.waitForMonitorWithTimeout(monitor, 5000);
                assertNotNull(redirected);
                instrumentation.waitForIdleSync();
                assertTrue(redirected.isFinishing());
                IntegratedBottomControlsInstrumentedTest.await(initial::hasWindowFocus);
            } finally { instrumentation.removeMonitor(monitor); }
        } finally {
            if (page != null) instrumentation.runOnMainSync(page::finish);
            if (home != null) instrumentation.runOnMainSync(home::finish);
            restore(saved, before);
        }
    }
    @Test public void profileAppearanceControlsAndHelpKeepTheirOwnScope() throws Exception {
        var saved = CandidateWindowSettings.preferences(context);
        var before = saved.getAll();
        Activity page = null;
        try {
            CandidateWindowSettings.setFloatingEnabled(context, false);
            CandidateWindowSettings.setSmartTwoRowsEnabled(context, false);
            BopomofoCompositionModeSettings.setOmitTone(context, true, false);
            BopomofoCompositionModeSettings.setOmitTone(context, false, true);
            CandidateColorSettings.setColor(context, CandidateColorSettings.CandidateColor.GREEN, true);
            CandidateColorSettings.setColor(context, CandidateColorSettings.CandidateColor.RED, false);
            HapticSettings.setDurationMs(context, 3, true);
            HapticSettings.setDurationMs(context, 50, false);
            for (boolean virtual : new boolean[]{true, false}) {
                page = instrumentation.startActivitySync(SettingsActivity.intent(context, virtual)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
                Activity current = page;
                instrumentation.waitForIdleSync();
                IntegratedBottomControlsInstrumentedTest.await(current::hasWindowFocus);
                showHelp(current, R.string.simplified_chinese_output,
                        context.getString(R.string.simplified_chinese_output_description),
                        virtual ? "virtual-output-help.png" : null);
                instrumentation.runOnMainSync(() -> {
                    View root = current.findViewById(android.R.id.content);
                    revealGroup(root, context.getString(R.string.settings_group_appearance));
                    Spinner color = (Spinner) described(root, context.getString(R.string.candidate_color_title));
                    SeekBar haptic = (SeekBar) described(root, context.getString(virtual
                            ? R.string.haptic_feedback_title : R.string.hardware_haptic_feedback_title));
                    assertNotNull(color);
                    assertNotNull(haptic);
                    assertEquals(virtual ? 1 : 3, color.getSelectedItemPosition());
                    assertEquals(HapticSettings.selectionForDurationMs(virtual ? 3 : 50), haptic.getProgress());
                    color.setSelection(virtual ? 2 : 0);
                    haptic.setProgress(HapticSettings.selectionForDurationMs(virtual ? 10 : 100));
                    assertNull(find(root, context.getString(R.string.candidate_color_description)));
                    assertNull(find(root, context.getString(R.string.simplified_chinese_output_description)));
                    assertEquals(virtual, find(root, "字體大小") != null);
                });
                instrumentation.waitForIdleSync();
                assertEquals(virtual ? CandidateColorSettings.CandidateColor.YELLOW
                        : CandidateColorSettings.CandidateColor.PURPLE, CandidateColorSettings.color(context, virtual));
                assertEquals(virtual ? 10 : 100, HapticSettings.durationMs(context, virtual));
                assertEquals(virtual ? CandidateColorSettings.CandidateColor.RED
                        : CandidateColorSettings.CandidateColor.YELLOW, CandidateColorSettings.color(context, !virtual));
                assertEquals(virtual ? 50 : 10, HapticSettings.durationMs(context, !virtual));
                if (virtual) {
                    showHelp(current, R.string.keyboard_font_size,
                            context.getString(R.string.keyboard_font_size_description), "virtual-font-help.png");
                } else {
                    showHelp(current, R.string.hardware_haptic_feedback_title,
                            context.getString(R.string.hardware_haptic_feedback_description), "physical-panel-haptic-help.png");
                    instrumentation.runOnMainSync(() -> {
                        View root = current.findViewById(android.R.id.content);
                        revealGroup(root, context.getString(R.string.settings_group_composition));
                        ((CheckBox) find(root, context.getString(R.string.hardware_smart_two_rows_enabled))).setChecked(true);
                        CheckBox omission = (CheckBox) find(root, context.getString(R.string.smart_omit_tone));
                        assertTrue(omission.isEnabled());
                        assertTrue(omission.isChecked());
                        omission.performClick();
                        assertFalse(omission.isChecked());
                        assertFalse(BopomofoCompositionModeSettings.omitTone(context, false));
                        BopomofoCompositionModeSettings.setOmitTone(context, true, true);
                        assertFalse(BopomofoCompositionModeSettings.omitTone(context, false));
                        omission.performClick();
                        assertTrue(omission.isChecked());
                        assertTrue(BopomofoCompositionModeSettings.omitTone(context, false));
                        BopomofoCompositionModeSettings.setOmitTone(context, false, true);
                        assertTrue(BopomofoCompositionModeSettings.omitTone(context, false));
                        assertFalse(BopomofoCompositionModeSettings.omitTone(context, true));
                        View info = described(root, context.getString(R.string.settings_show_help,
                                context.getString(R.string.smart_omit_tone)));
                        assertTrue("Enabled two-row omission keeps an accessible explanation", info.isEnabled());
                    });
                    showHelp(current, R.string.smart_omit_tone,
                            context.getString(R.string.hardware_omit_tone_description), "physical-double-row-omit-tone-help.png");
                    int[] titles = {R.string.hardware_candidate_before_cursor,
                            R.string.hardware_selection_returns_to_end, R.string.hardware_escape_clears_composition,
                            R.string.hardware_ignore_caps, R.string.hardware_shift_upper, R.string.hardware_max_syllables};
                    int[] details = {R.string.hardware_candidate_before_cursor_description,
                            R.string.hardware_selection_returns_to_end_description, R.string.hardware_escape_clears_composition_description,
                            R.string.hardware_ignore_caps_description, R.string.hardware_shift_upper_description,
                            R.string.hardware_max_syllables_description};
                    for (int i = 0; i < titles.length; i++) {
                        int title = titles[i];
                        instrumentation.runOnMainSync(() -> {
                            View root = current.findViewById(android.R.id.content);
                            View control = title == R.string.hardware_max_syllables
                                    ? described(root, context.getString(title)) : find(root, context.getString(title));
                            assertNotNull(control);
                            assertFalse("Other desktop options remain unavailable in two-row mode", control.isEnabled());
                        });
                        showHelp(current, title,
                                context.getString(details[i]) + "\n\n" + context.getString(R.string.hardware_advanced_description), null);
                    }
                    instrumentation.runOnMainSync(() -> {
                        View root = current.findViewById(android.R.id.content);
                        ((CheckBox) find(root, context.getString(R.string.hardware_smart_two_rows_enabled))).setChecked(false);
                        assertTrue(find(root, context.getString(R.string.smart_omit_tone)).isEnabled());
                    });
                }
                instrumentation.runOnMainSync(() -> {
                    ViewGroup root = current.findViewById(android.R.id.content);
                    android.widget.ScrollView scroll = (android.widget.ScrollView) root.getChildAt(0);
                    View header = described(root, "收合" + context.getString(R.string.settings_group_appearance));
                    android.graphics.Rect bounds = new android.graphics.Rect();
                    header.getDrawingRect(bounds);
                    scroll.offsetDescendantRectToMyCoords(header, bounds);
                    scroll.scrollTo(0, bounds.top + scroll.getScrollY());
                });
                capture(virtual ? "virtual-appearance-settings.png" : "physical-appearance-settings.png");
                instrumentation.runOnMainSync(current::finish);
                page = null;
            }
        } finally {
            if (page != null) instrumentation.runOnMainSync(page::finish);
            restore(saved, before);
        }
    }

    private static void revealGroup(View root, String title) {
        View header = described(root, "展開" + title);
        if (header != null) assertTrue(header.performClick());
        else assertNotNull(described(root, "收合" + title));
    }
    private static View described(View view, String description) {
        if (description.equals(view.getContentDescription())) return view;
        if (view instanceof ViewGroup group) for (int index = 0; index < group.getChildCount(); index++) {
            View result = described(group.getChildAt(index), description);
            if (result != null) return result;
        }
        return null;
    }
    private void showHelp(Activity page, int title, String message, String screenshot) throws Exception {
        instrumentation.runOnMainSync(() -> {
            View info = described(page.findViewById(android.R.id.content), context.getString(
                    R.string.settings_show_help, context.getString(title)));
            assertNotNull(info);
            assertTrue(info.isEnabled());
            assertTrue(info.performClick());
        });
        instrumentation.waitForIdleSync();
        AccessibilityNodeInfo dialog = null;
        long deadline = android.os.SystemClock.uptimeMillis() + 5000;
        while (android.os.SystemClock.uptimeMillis() < deadline) {
            dialog = instrumentation.getUiAutomation().getRootInActiveWindow();
            if (dialog != null && !dialog.findAccessibilityNodeInfosByText(message).isEmpty()) break;
            android.os.SystemClock.sleep(50);
        }
        assertNotNull("The explanation window must become accessible", dialog);
        assertFalse("The specific option explanation must be displayed", dialog.findAccessibilityNodeInfosByText(message).isEmpty());
        if (screenshot != null) capture(screenshot);
        boolean closed = false;
        for (AccessibilityNodeInfo button : dialog.findAccessibilityNodeInfosByText(context.getString(R.string.settings_close_help))) {
            if (context.getString(R.string.settings_close_help).contentEquals(button.getText()) && button.isClickable()) {
                closed = button.performAction(AccessibilityNodeInfo.ACTION_CLICK);
                break;
            }
        }
        assertTrue(closed);
        instrumentation.waitForIdleSync();
        long dismissedBy = android.os.SystemClock.uptimeMillis() + 5000;
        while (android.os.SystemClock.uptimeMillis() < dismissedBy) {
            var current = instrumentation.getUiAutomation().getRootInActiveWindow();
            if (current != null && current.findAccessibilityNodeInfosByText(message).isEmpty()) return;
            android.os.SystemClock.sleep(50);
        }
        fail("The help window must close before the next action or screenshot");
    }

    private void capture(String name) throws java.io.IOException {
        instrumentation.waitForIdleSync();
        // Accessibility may be ready before the dialog's enter/exit animation is painted.
        android.os.SystemClock.sleep(350);
        instrumentation.waitForIdleSync();
        var bitmap = instrumentation.getUiAutomation().takeScreenshot();
        assertNotNull(bitmap);
        try (var output = new java.io.FileOutputStream(new java.io.File(context.getExternalFilesDir(null), name))) {
            assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, output));
        } finally { bitmap.recycle(); }
    }
    private static int count(View view, String label) {
        int total = view instanceof TextView text && label.contentEquals(text.getText()) ? 1 : 0;
        if (view instanceof ViewGroup group) for (int index = 0; index < group.getChildCount(); index++)
            total += count(group.getChildAt(index), label);
        return total;
    }
    private static View find(View view, String label) {
        if (view instanceof TextView text && label.contentEquals(text.getText())) return view;
        if (view instanceof ViewGroup group) for (int index = 0; index < group.getChildCount(); index++) {
            View match = find(group.getChildAt(index), label);
            if (match != null) return match;
        }
        return null;
    }
    private static void restore(SharedPreferences saved, Map<String, ?> before) {
        var edit = saved.edit();
        for (String key : saved.getAll().keySet()) if (!before.containsKey(key)) edit.remove(key);
        for (var entry : before.entrySet()) {
            Object value = entry.getValue();
            if (value instanceof Boolean flag) edit.putBoolean(entry.getKey(), flag);
            else if (value instanceof String text) edit.putString(entry.getKey(), text);
            else if (value instanceof Integer number) edit.putInt(entry.getKey(), number);
            else if (value instanceof Float number) edit.putFloat(entry.getKey(), number);
            else if (value instanceof Long number) edit.putLong(entry.getKey(), number);
        }
        edit.commit();
    }
}
