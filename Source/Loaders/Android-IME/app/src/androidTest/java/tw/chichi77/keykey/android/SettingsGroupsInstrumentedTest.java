package tw.chichi77.keykey.android;

import static org.junit.Assert.*;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Spinner;
import android.widget.TextView;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public final class SettingsGroupsInstrumentedTest {
    @Test
    public void supporterMovesFromTopToBottomAndGroupsExpand() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        boolean oldSupporter = SupporterState.isSupporter(context);
        boolean oldBigram = BopomofoCompositionModeSettings.bigramEnabled(context);
        SupporterState.setSupporter(context, false);
        Activity activity = null;
        try {
            activity = instrumentation.startActivitySync(new Intent(context,
                    SettingsActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            SettingsActivity settings = (SettingsActivity) activity;
            instrumentation.runOnMainSync(() -> {
                ViewGroup root = settings.findViewById(android.R.id.content);
                ScrollView scroll = (ScrollView) root.getChildAt(0);
                LinearLayout page = (LinearLayout) scroll.getChildAt(0);
                assertEquals(7, page.getChildCount()); // title + method picker + four groups + supporter

                View supporter = page.getChildAt(1);
                assertTrue(containsText(supporter, "支持開發"));
                for (String title : new String[]{"注音與選字", "倉頡與簡易", "外觀與操作", "實體鍵盤"}) {
                    LinearLayout group = findGroup(page, title);
                    assertEquals(View.GONE, group.getChildAt(1).getVisibility());
                }
                LinearLayout table = findGroup(page, "倉頡與簡易");
                table.getChildAt(0).performClick();
                assertEquals(View.VISIBLE, table.getChildAt(1).getVisibility());
                assertTrue(containsText(table.getChildAt(1), "倉頡設定"));
                assertTrue(containsText(table.getChildAt(1), "簡易設定"));
                table.getChildAt(0).performClick();

                // Simulate the billing result while the same settings screen remains open.
                settings.onStateChanged(true, true, null);
                assertSame(supporter, page.getChildAt(page.getChildCount() - 1));
                assertTrue(containsText(supporter, "感謝你支持琦琦輸入法"));
                assertFalse(containsText(supporter, "歡迎一次付費支持"));
                assertTrue(containsText(page.getChildAt(page.getChildCount() - 2), "實體鍵盤"));
                settings.onStateChanged(true, false, null);
                assertSame(supporter, page.getChildAt(1));
                LinearLayout appearance = findGroup(page, "外觀與操作");
                assertTrue(containsText(appearance.getChildAt(0), "外觀與操作"));
                appearance.getChildAt(0).performClick();
                View appearanceBody = appearance.getChildAt(1);
                assertEquals(View.VISIBLE, appearanceBody.getVisibility());
                assertTrue(containsText(appearanceBody, "調整鍵盤高度"));
                assertFalse(containsText(appearanceBody, "直式虛擬鍵盤"));
                assertFalse(containsText(appearanceBody, "橫式虛擬鍵盤"));
                appearance.getChildAt(0).performClick();

                assertFalse(containsText(page, "關聯詞詞庫"));
                assertEquals(0, countCollectionChecks(page));

                LinearLayout composition = findGroup(page, "注音與選字");
                View header = composition.getChildAt(0);
                View body = composition.getChildAt(1);
                header.performClick();
                assertEquals(View.VISIBLE, body.getVisibility());
                assertFalse(containsText(body, "倉頡"));
                assertFalse(containsText(body, "簡易"));
                CheckBox bigram = findBigram(body);
                assertNotNull(bigram);
                bigram.setChecked(false);
                assertTrue(containsText(header, "上下文：關閉"));
                header.performClick();
                assertEquals(View.GONE, body.getVisibility());
            });
        } finally {
            if (activity != null) {
                Activity current = activity;
                instrumentation.runOnMainSync(current::finish);
            }
            SupporterState.setSupporter(context, oldSupporter);
            BopomofoCompositionModeSettings.setBigramEnabled(context, oldBigram);
        }
    }

    @Test
    public void homeOpensPhraseCollectionsAndKeepsTheirPreferences() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        var preferences = CandidateWindowSettings.preferences(context);
        boolean previouslyStored = preferences.contains(PhraseSettings.KEY_ENABLED_COLLECTIONS);
        var previous = PhraseSettings.enabledCollections(context);
        var monitor = instrumentation.addMonitor(PhraseCollectionsActivity.class.getName(), null, false);
        Activity home = null;
        Activity collections = null;
        try {
            PhraseSettings.setEnabledCollections(context, PhraseSettings.baseCollectionOnly());
            home = instrumentation.startActivitySync(new Intent(context, MainActivity.class)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            Activity main = home;
            instrumentation.runOnMainSync(() ->
                    clickButton(main.findViewById(android.R.id.content), R.string.phrase_collections_title));
            collections = instrumentation.waitForMonitorWithTimeout(monitor, 5000);
            assertNotNull("Home must open the dedicated phrase collection page", collections);
            Activity page = collections;
            instrumentation.runOnMainSync(() -> {
                View root = page.findViewById(android.R.id.content);
                assertEquals(30, countCollectionChecks(root));
                CheckBox base = root.findViewWithTag("McBopomofo");
                assertNotNull(base);
                assertTrue(base.isChecked());
                assertTrue(containsText(root, "已啟用 1／30 個詞庫"));

                clickButton(root, R.string.phrase_select_all);
                assertEquals(30, PhraseSettings.enabledCollections(context).size());
                clickButton(root, R.string.phrase_select_none);
                assertTrue(PhraseSettings.enabledCollections(context).isEmpty());
                clickButton(root, R.string.phrase_base_only);
                assertEquals(PhraseSettings.baseCollectionOnly(), PhraseSettings.enabledCollections(context));
                base.performClick();
                assertTrue(PhraseSettings.enabledCollections(context).isEmpty());
            });
        } finally {
            instrumentation.removeMonitor(monitor);
            if (collections != null) instrumentation.runOnMainSync(collections::finish);
            if (home != null) instrumentation.runOnMainSync(home::finish);
            if (previouslyStored) PhraseSettings.setEnabledCollections(context, previous);
            else preferences.edit().remove(PhraseSettings.KEY_ENABLED_COLLECTIONS).apply();
        }
    }

    @Test
    public void allThreeBopomofoLayoutsKeepTheSharedToneOmissionSetting() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        var preferences = CandidateWindowSettings.preferences(context);
        String layoutKey = BopomofoKeyboardLayoutSettings.KEY_LAYOUT;
        String omitKey = BopomofoCompositionModeSettings.KEY_OMIT_TONE;
        var previous = preferences.getAll();
        Activity activity = null;
        CheckBox[] option = {null};
        Spinner[] selector = {null};
        try {
            BopomofoKeyboardLayoutSettings.setLayout(context, BopomofoKeyboardLayout.STANDARD);
            BopomofoCompositionModeSettings.setOmitTone(context, true);
            activity = instrumentation.startActivitySync(new Intent(context, SettingsActivity.class)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            Activity initial = activity;
            instrumentation.runOnMainSync(() -> {
                View body = revealComposition(initial, context);
                option[0] = findOmitTone(body, context);
                assertTrue(option[0].isEnabled());
                assertTrue(option[0].isChecked());
                selector[0] = findProfileSelector(body, context.getString(R.string.bopomofo_keyboard_layout));
                assertNotNull(selector[0]);
                selector[0].setSelection(BopomofoKeyboardLayout.HSU.ordinal());
            });
            instrumentation.waitForIdleSync();
            instrumentation.runOnMainSync(() -> {
                assertTrue(option[0].isEnabled());
                assertTrue(option[0].isChecked());
                initial.finish();
            });
            assertSame(BopomofoKeyboardLayout.HSU, BopomofoKeyboardLayoutSettings.layout(context));
            assertTrue(preferences.getBoolean(omitKey, false));

            activity = instrumentation.startActivitySync(new Intent(context, SettingsActivity.class)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            Activity reopened = activity;
            instrumentation.runOnMainSync(() -> {
                View body = revealComposition(reopened, context);
                option[0] = findOmitTone(body, context);
                assertTrue(option[0].isEnabled());
                assertTrue(option[0].isChecked());
                selector[0] = findProfileSelector(body, context.getString(R.string.bopomofo_keyboard_layout));
                assertNotNull(selector[0]);
                selector[0].setSelection(BopomofoKeyboardLayout.HANYU_PINYIN.ordinal());
            });
            instrumentation.waitForIdleSync();
            instrumentation.runOnMainSync(() -> {
                assertTrue(option[0].isEnabled());
                assertTrue(option[0].isChecked());
                assertTrue(preferences.getBoolean(omitKey, false));
                option[0].performClick();
                assertFalse(option[0].isChecked());
                selector[0].setSelection(BopomofoKeyboardLayout.STANDARD.ordinal());
            });
            instrumentation.waitForIdleSync();
            instrumentation.runOnMainSync(() -> {
                assertTrue(option[0].isEnabled());
                assertFalse(option[0].isChecked());
            });
            assertSame(BopomofoKeyboardLayout.STANDARD, BopomofoKeyboardLayoutSettings.layout(context));
            assertFalse(preferences.getBoolean(omitKey, true));
        } finally {
            if (activity != null) instrumentation.runOnMainSync(activity::finish);
            var edit = preferences.edit().remove(layoutKey).remove(omitKey);
            if (previous.get(layoutKey) instanceof String layout) edit.putString(layoutKey, layout);
            if (previous.get(omitKey) instanceof Boolean omit) edit.putBoolean(omitKey, omit);
            edit.commit();
        }
    }

    @Test
    public void keyboardProfileSelectorUsesRegisteredProfilesAndRestoresTheSavedChoice() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        var preferences = CandidateWindowSettings.preferences(context);
        var previous = savedLayoutPreferences(context);
        var mapping = BopomofoKeyboardLayoutSettings.layout(context);
        Activity activity = null;
        try {
            var profiles = KeyboardLayoutProfile.available();
            for (int index = 0; index < profiles.size(); index++) {
                activity = instrumentation.startActivitySync(new Intent(context,
                        SettingsActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
                Activity current = activity;
                int selected = index;
                instrumentation.runOnMainSync(() -> {
                    Spinner selector = revealProfileSelector(current, context);
                    assertNotNull("Settings must expose the profile selector", selector);
                    assertEquals(profiles.size(), selector.getAdapter().getCount());
                    for (int item = 0; item < profiles.size(); item++) {
                        assertEquals(profiles.get(item).displayName, selector.getAdapter().getItem(item));
                    }
                    selector.setSelection(selected);
                });
                instrumentation.waitForIdleSync();
                assertEquals(profiles.get(index).id,
                        preferences.getString(KeyboardLayoutProfileSettings.KEY_LAYOUT, null));
                assertEquals("Visual profiles must not change Standard/Hsu input mapping",
                        mapping, BopomofoKeyboardLayoutSettings.layout(context));
                instrumentation.runOnMainSync(current::finish);
                activity = instrumentation.startActivitySync(new Intent(context,
                        SettingsActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
                Activity reopened = activity;
                instrumentation.runOnMainSync(() -> {
                    Spinner selector = revealProfileSelector(reopened, context);
                    assertNotNull(selector);
                    assertEquals(selected, selector.getSelectedItemPosition());
                    reopened.finish();
                });
                activity = null;
            }
        } finally {
            if (activity != null) {
                Activity current = activity;
                instrumentation.runOnMainSync(current::finish);
            }
            instrumentation.waitForIdleSync();
            restoreLayoutPreferences(context, previous);
        }
    }

    @Test public void layoutOptionsFollowCandidateColorAndPersistByStableIdentifier() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        var preferences = CandidateWindowSettings.preferences(context);
        var previous = savedLayoutPreferences(context);
        var fonts = java.util.Arrays.asList(KeyboardLayoutProfile.FontSize.values());
        var fontLabels = java.util.Map.of(KeyboardLayoutProfile.FontSize.NORMAL, "標準",
                KeyboardLayoutProfile.FontSize.MEDIUM, "中", KeyboardLayoutProfile.FontSize.LARGE, "大",
                KeyboardLayoutProfile.FontSize.EXTRA_LARGE, "特大");
        Activity activity = null;
        try {
            // The previous largest font is now named extra large without reducing its size.
            restoreLayoutPreferences(context, java.util.Map.of(KeyboardLayoutProfileSettings.KEY_FONT_SIZE, "large"));
            activity = instrumentation.startActivitySync(new Intent(context,
                    SettingsActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            Activity initial = activity;
            instrumentation.runOnMainSync(() -> {
                Spinner profile = revealProfileSelector(initial, context);
                LinearLayout body = (LinearLayout) profile.getParent();
                int colorIndex = labelIndex(body, context.getString(R.string.candidate_color_title));
                int profileIndex = labelIndex(body, context.getString(R.string.keyboard_layout_profile));
                int areaIndex = labelIndex(body, context.getString(R.string.keyboard_keycap_area));
                int fontIndex = labelIndex(body, context.getString(R.string.keyboard_font_size));
                int deleteIndex = labelIndex(body, context.getString(R.string.keyboard_delete_position));
                int integratedIndex = labelIndex(body, context.getString(R.string.integrated_bottom_controls_enabled));
                assertTrue(colorIndex >= 0 && profileIndex > colorIndex && areaIndex > profileIndex
                        && fontIndex > areaIndex && deleteIndex > fontIndex && integratedIndex > deleteIndex);
                assertTrue(body.getChildAt(integratedIndex) instanceof CheckBox);
                Spinner font = findProfileSelector(body, context.getString(R.string.keyboard_font_size));
                assertEquals(fonts.size(), font.getAdapter().getCount());
                for (int index = 0; index < fonts.size(); index++) {
                    assertEquals(fontLabels.get(fonts.get(index)), font.getAdapter().getItem(index));
                }
                assertEquals(fonts.indexOf(KeyboardLayoutProfile.FontSize.EXTRA_LARGE), font.getSelectedItemPosition());
                assertEquals("特大", font.getSelectedItem());
                profile.setSelection(KeyboardLayoutProfile.available().indexOf(KeyboardLayoutProfile.ALIGNED_SPLIT));
            });
            instrumentation.waitForIdleSync();
            instrumentation.runOnMainSync(() -> {
                var body = (View) revealProfileSelector(initial, context).getParent();
                Spinner area = findProfileSelector(body, context.getString(R.string.keyboard_keycap_area));
                Spinner position = findProfileSelector(body, context.getString(R.string.keyboard_delete_position));
                assertTrue(area.isEnabled());
                area.setSelection(java.util.Arrays.asList(KeyboardLayoutProfile.KeycapArea.values())
                        .indexOf(KeyboardLayoutProfile.KeycapArea.LARGE));
                position.setSelection(java.util.Arrays.asList(KeyboardLayoutProfile.DeletePosition.values())
                        .indexOf(KeyboardLayoutProfile.DeletePosition.ABOVE_ENTER));
            });
            instrumentation.waitForIdleSync();
            assertSame(KeyboardLayoutProfile.FontSize.EXTRA_LARGE, KeyboardLayoutProfileSettings.fontSize(context));
            for (var font : fonts) {
                Activity current = activity;
                instrumentation.runOnMainSync(() -> {
                    var body = (View) revealProfileSelector(current, context).getParent();
                    findProfileSelector(body, context.getString(R.string.keyboard_font_size))
                            .setSelection(fonts.indexOf(font));
                });
                instrumentation.waitForIdleSync();
                assertSavedFontAndIndependentOptions(context, font);
                for (var profile : KeyboardLayoutProfile.available()) {
                    instrumentation.runOnMainSync(() -> revealProfileSelector(current, context)
                            .setSelection(KeyboardLayoutProfile.available().indexOf(profile)));
                    instrumentation.waitForIdleSync();
                    assertSame(profile, KeyboardLayoutProfileSettings.profile(context));
                    assertSavedFontAndIndependentOptions(context, font);
                }
                instrumentation.runOnMainSync(current::finish);
                instrumentation.waitForIdleSync();
                activity = instrumentation.startActivitySync(new Intent(context,
                        SettingsActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
                Activity reopened = activity;
                instrumentation.runOnMainSync(() -> {
                    var body = (View) revealProfileSelector(reopened, context).getParent();
                    assertEquals(fonts.indexOf(font),
                            findProfileSelector(body, context.getString(R.string.keyboard_font_size)).getSelectedItemPosition());
                    assertEquals(fontLabels.get(font),
                            findProfileSelector(body, context.getString(R.string.keyboard_font_size)).getSelectedItem());
                    assertEquals(java.util.Arrays.asList(KeyboardLayoutProfile.KeycapArea.values())
                                    .indexOf(KeyboardLayoutProfile.KeycapArea.LARGE),
                            findProfileSelector(body, context.getString(R.string.keyboard_keycap_area)).getSelectedItemPosition());
                    assertEquals(java.util.Arrays.asList(KeyboardLayoutProfile.DeletePosition.values())
                                    .indexOf(KeyboardLayoutProfile.DeletePosition.ABOVE_ENTER),
                            findProfileSelector(body, context.getString(R.string.keyboard_delete_position)).getSelectedItemPosition());
                });
                instrumentation.waitForIdleSync();
                assertSavedFontAndIndependentOptions(context, font);
            }
            Activity last = activity;
            instrumentation.runOnMainSync(last::finish);
            activity = null;
            // Finish draining the closed Activity before changing stored values.
            instrumentation.waitForIdleSync();
            var unavailable = preferences.edit();
            unavailable.remove(KeyboardLayoutProfileSettings.KEY_PROFILE).remove(KeyboardLayoutProfileSettings.KEY_KEYCAP_AREA);
            for (String key : new String[] {KeyboardLayoutProfileSettings.KEY_LAYOUT, KeyboardLayoutProfileSettings.KEY_SPACING,
                    KeyboardLayoutProfileSettings.KEY_FONT_LEVEL, KeyboardLayoutProfileSettings.KEY_DELETE_POSITION}) {
                unavailable.putString(key, "unavailable");
            }
            unavailable.commit();
            assertSame(KeyboardLayoutProfile.ALIGNED, KeyboardLayoutProfileSettings.profile(context));
            assertSame(KeyboardLayoutProfile.KeycapArea.SMALL, KeyboardLayoutProfileSettings.keycapArea(context));
            assertSame(KeyboardLayoutProfile.FontSize.NORMAL, KeyboardLayoutProfileSettings.fontSize(context));
            assertSame(KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER, KeyboardLayoutProfileSettings.deletePosition(context));
        } finally {
            if (activity != null) {
                Activity current = activity; instrumentation.runOnMainSync(current::finish);
            }
            instrumentation.waitForIdleSync();
            restoreLayoutPreferences(context, previous);
        }
    }

    private static void assertSavedFontAndIndependentOptions(Context context, KeyboardLayoutProfile.FontSize font) {
        var preferences = CandidateWindowSettings.preferences(context);
        assertEquals(font.id, preferences.getString(KeyboardLayoutProfileSettings.KEY_FONT_LEVEL, null));
        assertEquals("Old font preferences are read only", "large",
                preferences.getString(KeyboardLayoutProfileSettings.KEY_FONT_SIZE, null));
        assertSame(font, KeyboardLayoutProfileSettings.fontSize(context));
        assertEquals("80", preferences.getString(KeyboardLayoutProfileSettings.KEY_SPACING, null));
        assertSame(KeyboardLayoutProfile.KeycapArea.LARGE, KeyboardLayoutProfileSettings.keycapArea(context));
        assertEquals("above-enter", preferences.getString(KeyboardLayoutProfileSettings.KEY_DELETE_POSITION, null));
        assertSame(KeyboardLayoutProfile.DeletePosition.ABOVE_ENTER, KeyboardLayoutProfileSettings.deletePosition(context));
    }

    @Test public void editingOneOptionMaterializesTheWholeLegacyChoice() {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        var preferences = CandidateWindowSettings.preferences(context);
        var previous = savedLayoutPreferences(context);
        try {
            for (String legacy : new String[] {"large-full", "large-staggered", "full-spaced"}) {
                restoreLayoutPreferences(context, java.util.Map.of());
                preferences.edit().putString(KeyboardLayoutProfileSettings.KEY_PROFILE, legacy)
                        .putString(KeyboardLayoutProfileSettings.KEY_KEYCAP_AREA, "85")
                        .putString(KeyboardLayoutProfileSettings.KEY_DELETE_POSITION, "above-enter").commit();
                KeyboardLayoutProfileSettings.setProfile(context, KeyboardLayoutProfile.STANDARD);
                assertSame(KeyboardLayoutProfile.STANDARD, KeyboardLayoutProfileSettings.profile(context));
                assertEquals(legacy.equals("full-spaced") ? "normal" : "extra-large",
                        preferences.getString(KeyboardLayoutProfileSettings.KEY_FONT_LEVEL, null));
                assertSame(legacy.equals("full-spaced") ? KeyboardLayoutProfile.FontSize.NORMAL
                        : KeyboardLayoutProfile.FontSize.EXTRA_LARGE, KeyboardLayoutProfileSettings.fontSize(context));
                assertFalse("Setters must not create the old font preference",
                        preferences.contains(KeyboardLayoutProfileSettings.KEY_FONT_SIZE));
                assertEquals(legacy.equals("full-spaced") ? "80" : "100",
                        preferences.getString(KeyboardLayoutProfileSettings.KEY_SPACING, null));
                assertEquals("above-enter", preferences.getString(KeyboardLayoutProfileSettings.KEY_DELETE_POSITION, null));
            }
        } finally { restoreLayoutPreferences(context, previous); }
    }

    private static final java.util.List<String> LAYOUT_KEYS = java.util.List.of(
            KeyboardLayoutProfileSettings.KEY_LAYOUT, KeyboardLayoutProfileSettings.KEY_SPACING,
            KeyboardLayoutProfileSettings.KEY_FONT_LEVEL, KeyboardLayoutProfileSettings.KEY_DELETE_POSITION,
            KeyboardLayoutProfileSettings.KEY_FONT_SIZE, KeyboardLayoutProfileSettings.KEY_PROFILE, KeyboardLayoutProfileSettings.KEY_KEYCAP_AREA);

    private static java.util.Map<String, String> savedLayoutPreferences(Context context) {
        var preferences = CandidateWindowSettings.preferences(context);
        var result = new java.util.HashMap<String, String>();
        for (String key : LAYOUT_KEYS) result.put(key, preferences.getString(key, null));
        return result;
    }

    private static void restoreLayoutPreferences(Context context, java.util.Map<String, String> previous) {
        var editor = CandidateWindowSettings.preferences(context).edit();
        for (String key : LAYOUT_KEYS) {
            if (previous.get(key) == null) editor.remove(key); else editor.putString(key, previous.get(key));
        }
        editor.commit();
    }

    private static int labelIndex(LinearLayout body, String label) {
        for (int index = 0; index < body.getChildCount(); index++) {
            if (body.getChildAt(index) instanceof TextView text && label.contentEquals(text.getText())) return index;
        }
        return -1;
    }

    private static View revealComposition(Activity activity, Context context) {
        ViewGroup root = activity.findViewById(android.R.id.content);
        LinearLayout page = (LinearLayout) ((ScrollView) root.getChildAt(0)).getChildAt(0);
        LinearLayout composition = findGroup(page, context.getString(R.string.settings_group_composition));
        View body = composition.getChildAt(1);
        if (body.getVisibility() != View.VISIBLE) composition.getChildAt(0).performClick();
        return body;
    }

    private static CheckBox findOmitTone(View root, Context context) {
        var matches = new java.util.ArrayList<View>();
        root.findViewsWithText(matches, context.getString(R.string.smart_omit_tone), View.FIND_VIEWS_WITH_TEXT);
        for (View view : matches) if (view instanceof CheckBox check) return check;
        throw new AssertionError("Missing Smart tone omission check box");
    }

    private static Spinner revealProfileSelector(Activity activity, Context context) {
        ViewGroup root = activity.findViewById(android.R.id.content);
        LinearLayout page = (LinearLayout) ((ScrollView) root.getChildAt(0)).getChildAt(0);
        LinearLayout appearance = findGroup(page, context.getString(R.string.settings_group_appearance));
        if (appearance.getChildAt(1).getVisibility() != View.VISIBLE) {
            appearance.getChildAt(0).performClick();
        }
        return findProfileSelector(appearance.getChildAt(1), context.getString(R.string.keyboard_layout_profile));
    }

    private static Spinner findProfileSelector(View root, String description) {
        if (root instanceof Spinner spinner && description.equals(String.valueOf(spinner.getContentDescription()))) {
            return spinner;
        }
        if (root instanceof ViewGroup group) {
            for (int index = 0; index < group.getChildCount(); index++) {
                Spinner result = findProfileSelector(group.getChildAt(index), description);
                if (result != null) return result;
            }
        }
        return null;
    }

    private static LinearLayout findGroup(LinearLayout page, String title) {
        for (int i = 0; i < page.getChildCount(); i++) {
            if (page.getChildAt(i) instanceof LinearLayout section && section.getChildCount() == 2) {
                CharSequence description = section.getChildAt(0).getContentDescription();
                if (description != null && description.toString().contains(title)) return section;
            }
        }
        throw new AssertionError("Missing settings group: " + title);
    }

    private static void clickButton(View root, int label) {
        Button button = findButton(root, root.getResources().getString(label));
        assertNotNull(button);
        assertTrue(button.performClick());
    }

    private static Button findButton(View root, String label) {
        if (root instanceof Button button && label.contentEquals(button.getText())) return button;
        if (root instanceof ViewGroup group) {
            for (int i = 0; i < group.getChildCount(); i++) {
                Button button = findButton(group.getChildAt(i), label);
                if (button != null) return button;
            }
        }
        return null;
    }

    private static int countCollectionChecks(View root) {
        if (root instanceof CheckBox check && check.getTag() instanceof String) return 1;
        if (root instanceof ViewGroup group) {
            int count = 0;
            for (int i = 0; i < group.getChildCount(); i++) {
                count += countCollectionChecks(group.getChildAt(i));
            }
            return count;
        }
        return 0;
    }

    private static CheckBox findBigram(View root) {
        if (root instanceof CheckBox check
                && check.getText().toString().contains("Bigram")) return check;
        if (root instanceof ViewGroup group) {
            for (int i = 0; i < group.getChildCount(); i++) {
                CheckBox result = findBigram(group.getChildAt(i));
                if (result != null) return result;
            }
        }
        return null;
    }

    private static boolean containsText(View root, String expected) {
        if (root instanceof TextView text
                && text.getText().toString().contains(expected)) return true;
        if (root instanceof ViewGroup group) {
            for (int i = 0; i < group.getChildCount(); i++) {
                if (containsText(group.getChildAt(i), expected)) return true;
            }
        }
        return false;
    }
}
