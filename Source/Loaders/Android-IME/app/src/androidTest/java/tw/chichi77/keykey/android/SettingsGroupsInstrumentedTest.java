package tw.chichi77.keykey.android;

import static org.junit.Assert.*;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.view.View;
import android.view.ViewGroup;
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
    public void supporterMovesFromTopToAfterPhraseGroupAndGroupsExpand() {
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
                assertEquals(8, page.getChildCount()); // title + method picker + five groups + supporter

                View supporter = page.getChildAt(1);
                assertTrue(containsText(supporter, "支持開發"));
                for (String title : new String[]{"注音與選字", "倉頡與簡易", "外觀與操作", "實體鍵盤", "關聯詞詞庫"}) {
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
                assertTrue(containsText(page.getChildAt(page.getChildCount() - 2),
                        "關聯詞詞庫"));
                settings.onStateChanged(true, false, null);
                assertSame(supporter, page.getChildAt(1));
                LinearLayout appearance = findGroup(page, "外觀與操作");
                assertTrue(containsText(appearance.getChildAt(0), "外觀與操作"));
                appearance.getChildAt(0).performClick();
                View appearanceBody = appearance.getChildAt(1);
                assertEquals(View.VISIBLE, appearanceBody.getVisibility());
                assertTrue(containsText(appearanceBody, "虛擬鍵盤高度"));
                assertTrue(containsText(appearanceBody, "直式虛擬鍵盤"));
                assertTrue(containsText(appearanceBody, "橫式虛擬鍵盤"));
                appearance.getChildAt(0).performClick();

                LinearLayout phrases = findGroup(page, "關聯詞詞庫");
                phrases.getChildAt(0).performClick();
                assertEquals(View.VISIBLE, phrases.getChildAt(1).getVisibility());
                assertEquals(30, countCollectionChecks(phrases.getChildAt(1)));

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
        Activity activity = null;
        try {
            activity = instrumentation.startActivitySync(new Intent(context,
                    SettingsActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            Activity current = activity;
            instrumentation.runOnMainSync(() -> {
                Spinner profile = revealProfileSelector(current, context);
                LinearLayout body = (LinearLayout) profile.getParent();
                int colorIndex = labelIndex(body, context.getString(R.string.candidate_color_title));
                int profileIndex = labelIndex(body, context.getString(R.string.keyboard_layout_profile));
                int areaIndex = labelIndex(body, context.getString(R.string.keyboard_keycap_area));
                int fontIndex = labelIndex(body, context.getString(R.string.keyboard_font_size));
                int deleteIndex = labelIndex(body, context.getString(R.string.keyboard_delete_position));
                assertTrue(colorIndex >= 0 && profileIndex > colorIndex && areaIndex > profileIndex
                        && fontIndex > areaIndex && deleteIndex > fontIndex);
                profile.setSelection(KeyboardLayoutProfile.available().indexOf(KeyboardLayoutProfile.ALIGNED_SPLIT));
            });
            instrumentation.waitForIdleSync();
            instrumentation.runOnMainSync(() -> {
                var body = (View) revealProfileSelector(current, context).getParent();
                Spinner area = findProfileSelector(body, context.getString(R.string.keyboard_keycap_area));
                Spinner font = findProfileSelector(body, context.getString(R.string.keyboard_font_size));
                Spinner position = findProfileSelector(body, context.getString(R.string.keyboard_delete_position));
                assertTrue(area.isEnabled());
                area.setSelection(java.util.Arrays.asList(KeyboardLayoutProfile.KeycapArea.values())
                        .indexOf(KeyboardLayoutProfile.KeycapArea.LARGE));
                font.setSelection(java.util.Arrays.asList(KeyboardLayoutProfile.FontSize.values())
                        .indexOf(KeyboardLayoutProfile.FontSize.LARGE));
                position.setSelection(java.util.Arrays.asList(KeyboardLayoutProfile.DeletePosition.values())
                        .indexOf(KeyboardLayoutProfile.DeletePosition.ABOVE_ENTER));
            });
            instrumentation.waitForIdleSync();
            assertEquals("80", preferences.getString(KeyboardLayoutProfileSettings.KEY_SPACING, null));
            assertEquals("large", preferences.getString(KeyboardLayoutProfileSettings.KEY_FONT_SIZE, null));
            assertEquals("above-enter", preferences.getString(KeyboardLayoutProfileSettings.KEY_DELETE_POSITION, null));
            instrumentation.runOnMainSync(current::finish);
            activity = instrumentation.startActivitySync(new Intent(context,
                    SettingsActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            Activity reopened = activity;
            instrumentation.runOnMainSync(() -> {
                var body = (View) revealProfileSelector(reopened, context).getParent();
                assertEquals(java.util.Arrays.asList(KeyboardLayoutProfile.KeycapArea.values()).indexOf(KeyboardLayoutProfile.KeycapArea.LARGE),
                        findProfileSelector(body, context.getString(R.string.keyboard_keycap_area)).getSelectedItemPosition());
                assertEquals(java.util.Arrays.asList(KeyboardLayoutProfile.FontSize.values()).indexOf(KeyboardLayoutProfile.FontSize.LARGE),
                        findProfileSelector(body, context.getString(R.string.keyboard_font_size)).getSelectedItemPosition());
                assertEquals(java.util.Arrays.asList(KeyboardLayoutProfile.DeletePosition.values()).indexOf(KeyboardLayoutProfile.DeletePosition.ABOVE_ENTER),
                        findProfileSelector(body, context.getString(R.string.keyboard_delete_position)).getSelectedItemPosition());
                reopened.finish();
            });
            activity = null;
            // Spinner selection callbacks are posted during layout; finish
            // draining the closed Activity before changing stored values.
            instrumentation.waitForIdleSync();
            var unavailable = preferences.edit();
            unavailable.remove(KeyboardLayoutProfileSettings.KEY_PROFILE).remove(KeyboardLayoutProfileSettings.KEY_KEYCAP_AREA);
            for (String key : new String[] {KeyboardLayoutProfileSettings.KEY_LAYOUT, KeyboardLayoutProfileSettings.KEY_SPACING,
                    KeyboardLayoutProfileSettings.KEY_FONT_SIZE, KeyboardLayoutProfileSettings.KEY_DELETE_POSITION}) {
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

    @Test public void editingOneOptionMaterializesTheWholeLegacyChoice() {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        var preferences = CandidateWindowSettings.preferences(context);
        var previous = savedLayoutPreferences(context);
        try {
            for (String legacy : new String[] {"large-full", "full-spaced"}) {
                restoreLayoutPreferences(context, java.util.Map.of());
                preferences.edit().putString(KeyboardLayoutProfileSettings.KEY_PROFILE, legacy)
                        .putString(KeyboardLayoutProfileSettings.KEY_KEYCAP_AREA, "85")
                        .putString(KeyboardLayoutProfileSettings.KEY_DELETE_POSITION, "above-enter").commit();
                KeyboardLayoutProfileSettings.setProfile(context, KeyboardLayoutProfile.STANDARD);
                assertSame(KeyboardLayoutProfile.STANDARD, KeyboardLayoutProfileSettings.profile(context));
                assertEquals(legacy.equals("large-full") ? "large" : "normal",
                        preferences.getString(KeyboardLayoutProfileSettings.KEY_FONT_SIZE, null));
                assertEquals(legacy.equals("full-spaced") ? "80" : "100",
                        preferences.getString(KeyboardLayoutProfileSettings.KEY_SPACING, null));
                assertEquals("above-enter", preferences.getString(KeyboardLayoutProfileSettings.KEY_DELETE_POSITION, null));
            }
        } finally { restoreLayoutPreferences(context, previous); }
    }

    private static final java.util.List<String> LAYOUT_KEYS = java.util.List.of(
            KeyboardLayoutProfileSettings.KEY_LAYOUT, KeyboardLayoutProfileSettings.KEY_SPACING,
            KeyboardLayoutProfileSettings.KEY_FONT_SIZE, KeyboardLayoutProfileSettings.KEY_DELETE_POSITION,
            KeyboardLayoutProfileSettings.KEY_PROFILE, KeyboardLayoutProfileSettings.KEY_KEYCAP_AREA);

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
