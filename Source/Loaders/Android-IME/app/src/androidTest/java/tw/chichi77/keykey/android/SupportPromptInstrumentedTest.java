package tw.chichi77.keykey.android;

import static org.junit.Assert.*;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.view.MotionEvent;
import android.view.View;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import java.util.ArrayList;
import java.util.List;

import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public final class SupportPromptInstrumentedTest {
    private static final List<String> SUPPORT_WORDS = List.of("歡迎", "付費", "支持");
    private static final List<String> NINE_CANDIDATES =
            List.of("好", "豪", "號", "浩", "毫", "郝", "皓", "耗", "壕");

    @Test
    public void idleTouchPromptUsesLastThreeCellsAndHasNoSelectionAction() {
        onMain(() -> {
            for (BopomofoKeyboardView.Mode mode : List.of(
                    BopomofoKeyboardView.Mode.PORTRAIT, BopomofoKeyboardView.Mode.LANDSCAPE)) {
                Fixture fixture = new Fixture(mode);
                fixture.state(List.of(), "", List.of(), true, true,
                        BopomofoEngine.InputMode.BOPOMOFO, false);
                RecordingCanvas canvas = fixture.draw();
                for (int index = 0; index < SUPPORT_WORDS.size(); index++) {
                    DrawnText word = canvas.single(SUPPORT_WORDS.get(index));
                    assertEquals(fixture.view.getWidth() * (8.5f + index) / 11f, word.x, 1f);
                    fixture.tap(word.x, word.y);
                }
                assertTrue(fixture.events.isEmpty());
                assertTrue(canvas.has("@"));
                assertTrue(canvas.has("0"));
                assertTrue(canvas.has("-"));
            }
        });
    }

    @Test
    public void touchPromptHidesForEveryCompositionStateAndKeepsCandidateSelection() {
        onMain(() -> {
            Fixture fixture = new Fixture(BopomofoKeyboardView.Mode.PORTRAIT);
            fixture.state(List.of(), "ㄏ", List.of(), true, true,
                    BopomofoEngine.InputMode.BOPOMOFO, false);
            fixture.assertNoSupportWords();
            fixture.state(List.of(), "", List.of("好"), true, true,
                    BopomofoEngine.InputMode.BOPOMOFO, false);
            fixture.assertNoSupportWords();
            fixture.state(NINE_CANDIDATES, "", List.of(), true, true,
                    BopomofoEngine.InputMode.BOPOMOFO, false);
            RecordingCanvas candidates = fixture.draw();
            assertFalse(candidates.has("歡迎"));
            DrawnText firstCandidate = candidates.single("好");
            fixture.tap(firstCandidate.x, firstCandidate.y);
            assertEquals(List.of("candidate:0"), fixture.events);
            fixture.state(List.of(), "", List.of(), true, true,
                    BopomofoEngine.InputMode.BOPOMOFO, true);
            fixture.assertNoSupportWords();
            for (BopomofoEngine.InputMode mode : List.of(
                    BopomofoEngine.InputMode.ENGLISH, BopomofoEngine.InputMode.NUMBER)) {
                fixture.state(List.of(), "", List.of(), true, true, mode, false);
                fixture.assertNoSupportWords();
            }
            fixture.view.setChineseInputMethod(ChineseInputMethod.CANGJIE);
            fixture.state(List.of(), "", List.of(), true, true,
                    BopomofoEngine.InputMode.BOPOMOFO, false);
            fixture.assertNoSupportWords();
            fixture.view.setChineseInputMethod(ChineseInputMethod.TRADITIONAL);
            fixture.state(List.of(), "", List.of(), false, true,
                    BopomofoEngine.InputMode.BOPOMOFO, false);
            RecordingCanvas traditional = fixture.draw();
            assertTrue(traditional.has("歡迎付費支持"));
            assertFalse(traditional.has("歡迎"));
        });
    }

    @Test
    public void hardwarePromptUsesCandidateCellsSevenToNineAndEligibilityChangeHidesItImmediately() {
        onMain(() -> {
            Fixture fixture = new Fixture(BopomofoKeyboardView.Mode.HARDWARE);
            fixture.state(List.of(), "ㄏ", List.of(), true, true,
                    BopomofoEngine.InputMode.BOPOMOFO, false);
            RecordingCanvas canvas = fixture.draw();
            for (int index = 0; index < SUPPORT_WORDS.size(); index++) {
                DrawnText word = canvas.single(SUPPORT_WORDS.get(index));
                assertEquals(fixture.view.getWidth() * (6.5f + index) / 12f, word.x, 1f);
                fixture.tap(word.x, word.y);
            }
            assertTrue(fixture.events.isEmpty());
            assertTrue(canvas.has("☺"));
            assertTrue(canvas.has("ㄅ"));
            assertTrue(canvas.has("半"));
            fixture.state(NINE_CANDIDATES, "ㄏㄠˇ", List.of(), true, true,
                    BopomofoEngine.InputMode.BOPOMOFO, false);
            RecordingCanvas candidates = fixture.draw();
            assertFalse(candidates.has("歡迎"));
            DrawnText lastCandidate = candidates.single("壕");
            fixture.tap(lastCandidate.x, lastCandidate.y);
            assertEquals(List.of("candidate:8"), fixture.events);
            fixture.state(List.of(), "", List.of(), true, false,
                    BopomofoEngine.InputMode.BOPOMOFO, false);
            fixture.assertNoSupportWords();
            fixture.view.setMode(BopomofoKeyboardView.Mode.PORTRAIT);
            fixture.assertNoSupportWords();
        });
    }

    private static void onMain(Runnable test) {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(test);
    }

    private static final class Fixture implements BopomofoKeyboardView.Listener {
        final BopomofoKeyboardView view;
        final List<String> events = new ArrayList<>();

        Fixture(BopomofoKeyboardView.Mode mode) {
            Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
            view = new BopomofoKeyboardView(context);
            view.setMode(mode);
            view.setListener(this);
            view.setKeyPreviewEnabled(false);
        }

        void state(List<String> candidates, String reading, List<String> cells,
                   boolean smartMode, boolean eligible, BopomofoEngine.InputMode inputMode,
                   boolean associated) {
            view.setAssociatedPhrasesVisible(associated);
            view.setState(candidates, reading, smartMode, cells, cells.size(), inputMode,
                    false, false, false, eligible, 0, candidates.isEmpty() ? 0 : 1,
                    candidates.isEmpty() ? -1 : 0, InputFieldPolicy.DEFAULT);
        }

        RecordingCanvas draw() {
            view.measure(View.MeasureSpec.makeMeasureSpec(1320, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED));
            view.layout(0, 0, view.getMeasuredWidth(), view.getMeasuredHeight());
            RecordingCanvas canvas = new RecordingCanvas();
            view.draw(canvas);
            return canvas;
        }

        void assertNoSupportWords() {
            RecordingCanvas canvas = draw();
            for (String word : SUPPORT_WORDS) assertFalse(canvas.has(word));
        }

        void tap(float x, float y) {
            MotionEvent down = MotionEvent.obtain(0, 0, MotionEvent.ACTION_DOWN, x, y, 0);
            MotionEvent up = MotionEvent.obtain(0, 1, MotionEvent.ACTION_UP, x, y, 0);
            view.onTouchEvent(down);
            view.onTouchEvent(up);
            down.recycle();
            up.recycle();
        }

        @Override public void onPress() {}
        @Override public void onKey(String key) { events.add("key:" + key); }
        @Override public void onCandidate(int index) { events.add("candidate:" + index); }
        @Override public void onSmartCell(int index) { events.add("smart:" + index); }
        @Override public void onPage(int delta) { events.add("page:" + delta); }
    }

    private static final class DrawnText {
        final String text;
        final float x;
        final float y;
        DrawnText(String text, float x, float y) {
            this.text = text;
            this.x = x;
            this.y = y;
        }
    }

    private static final class RecordingCanvas extends Canvas {
        final List<DrawnText> text = new ArrayList<>();
        @Override public void drawText(String value, float x, float y, Paint paint) {
            text.add(new DrawnText(value, x, y));
        }
        boolean has(String value) {
            for (DrawnText drawn : text) if (drawn.text.equals(value)) return true;
            return false;
        }
        DrawnText single(String value) {
            List<DrawnText> matches = new ArrayList<>();
            for (DrawnText drawn : text) if (drawn.text.equals(value)) matches.add(drawn);
            assertEquals("draw count for " + value, 1, matches.size());
            return matches.get(0);
        }
    }
}
