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
                assertEquals(6, page.getChildCount()); // title + four groups + supporter

                View supporter = page.getChildAt(1);
                assertTrue(containsText(supporter, "支持開發"));
                for (int index = 2; index < page.getChildCount(); index++) {
                    LinearLayout group = (LinearLayout) page.getChildAt(index);
                    assertEquals(View.GONE, group.getChildAt(1).getVisibility());
                }

                // Simulate the billing result while the same settings screen remains open.
                settings.onStateChanged(true, true, null);
                assertSame(supporter, page.getChildAt(page.getChildCount() - 1));
                assertTrue(containsText(supporter, "感謝你支持琦琦注音"));
                assertFalse(containsText(supporter, "歡迎一次付費支持"));
                assertTrue(containsText(page.getChildAt(page.getChildCount() - 2),
                        "關聯詞詞庫"));
                settings.onStateChanged(true, false, null);
                assertSame(supporter, page.getChildAt(1));
                LinearLayout appearance = (LinearLayout) page.getChildAt(3);
                assertTrue(containsText(appearance.getChildAt(0), "外觀與操作"));
                appearance.getChildAt(0).performClick();
                View appearanceBody = appearance.getChildAt(1);
                assertEquals(View.VISIBLE, appearanceBody.getVisibility());
                assertTrue(containsText(appearanceBody, "虛擬鍵盤高度"));
                assertTrue(containsText(appearanceBody, "直式虛擬鍵盤"));
                assertTrue(containsText(appearanceBody, "橫式虛擬鍵盤"));
                appearance.getChildAt(0).performClick();

                LinearLayout phrases = (LinearLayout) page.getChildAt(5);
                phrases.getChildAt(0).performClick();
                assertEquals(View.VISIBLE, phrases.getChildAt(1).getVisibility());
                assertEquals(30, countCollectionChecks(phrases.getChildAt(1)));

                LinearLayout composition = (LinearLayout) page.getChildAt(2);
                View header = composition.getChildAt(0);
                View body = composition.getChildAt(1);
                header.performClick();
                assertEquals(View.VISIBLE, body.getVisibility());
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
