package tw.chichi77.keykey.android;

import static org.junit.Assert.*;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Paint;
import android.os.SystemClock;
import android.view.View;
import android.view.ViewGroup;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.TextView;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public final class CandidateGlyphSupportInstrumentedTest {
    @Test public void nativeFontFallbackAcceptsWordsAndEmojiAndRejectsMissingCharacters() {
        CandidateGlyphSupport glyphs = CandidateGlyphSupport.shared();
        glyphs.reset();
        for (String text : new String[]{"你好", "妳", "A", "e\u0301", "✌️", "🇹🇼", "👩‍💻", "你󠄀", " "}) {
            assertTrue("unexpected missing glyph: " + text, glyphs.canDisplay(text));
        }
        String unassigned = new String(Character.toChars(0x10FFFF));
        assertFalse(glyphs.canDisplay(unassigned));
        assertFalse(glyphs.canDisplay("你" + unassigned));
        String supplementary = new String(Character.toChars(0x20BB7));
        assertEquals(new Paint().hasGlyph(supplementary), glyphs.canDisplay(supplementary));
    }

    @Test public void nativeFilterAndHardwareSelectionAgree() throws Exception {
        String missing = new String(Character.toChars(0x10FFFF));
        String cin = "%chardef begin\nsu3 " + missing + "\nsu3 你\nsu3 妳\n%chardef end\n";
        BopomofoEngine engine = new BopomofoEngine(CinDictionary.load(new ByteArrayInputStream(
                cin.getBytes(StandardCharsets.UTF_8))));
        engine.setCandidateFilter(CandidateGlyphSupport.shared()::canDisplay);
        for (char key : "su3".toCharArray()) engine.handleHardwareCharacter(key);
        assertEquals(java.util.List.of("你", "妳"), engine.displayedCandidates());
        assertEquals("妳", engine.handleHardwareCharacter('2').committedText());
    }

    @Test public void settingsLearningResetAlsoClearsGlyphCache() throws Exception {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        CandidateGlyphSupport glyphs = CandidateGlyphSupport.shared();
        glyphs.canDisplay("你");
        var field = CandidateGlyphSupport.class.getDeclaredField("cache");
        field.setAccessible(true);
        Map<?, ?> cache = (Map<?, ?>) field.get(glyphs);
        assertFalse(cache.isEmpty());
        Activity activity = instrumentation.startActivitySync(new Intent(context,
                SettingsActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        try {
            instrumentation.runOnMainSync(() -> findReset(activity.findViewById(android.R.id.content)).performClick());
            instrumentation.waitForIdleSync();
            boolean clicked = false;
            long deadline = SystemClock.uptimeMillis() + 5000;
            while (!clicked && SystemClock.uptimeMillis() < deadline) {
                AccessibilityNodeInfo root = instrumentation.getUiAutomation().getRootInActiveWindow();
                if (root != null) {
                    for (AccessibilityNodeInfo node : root.findAccessibilityNodeInfosByText("重設")) {
                        if ("重設".contentEquals(node.getText()) && node.isClickable()) {
                            clicked = node.performAction(AccessibilityNodeInfo.ACTION_CLICK); break;
                        }
                    }
                }
                if (!clicked) SystemClock.sleep(50);
            }
            assertTrue("reset confirmation button", clicked);
            instrumentation.waitForIdleSync();
            assertTrue(cache.isEmpty());
        } finally { instrumentation.runOnMainSync(activity::finish); }
    }

    private static View findReset(View view) {
        if (view instanceof TextView label && "重設好打注音學習紀錄".contentEquals(label.getText())) return view;
        if (view instanceof ViewGroup group) {
            for (int index = 0; index < group.getChildCount(); index++) {
                View found = findReset(group.getChildAt(index));
                if (found != null) return found;
            }
        }
        return null;
    }
}
