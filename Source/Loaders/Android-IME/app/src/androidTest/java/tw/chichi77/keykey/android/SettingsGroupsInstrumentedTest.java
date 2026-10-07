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
