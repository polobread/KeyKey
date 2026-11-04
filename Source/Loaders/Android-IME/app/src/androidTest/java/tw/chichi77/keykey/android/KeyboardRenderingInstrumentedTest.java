package tw.chichi77.keykey.android;

import static org.junit.Assert.*;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RectF;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.View;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.util.ArrayList;
import java.util.List;
import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public final class KeyboardRenderingInstrumentedTest {
    private record PlacementCase(KeyboardLayoutProfile.Plane plane,
            ChineseInputMethod method, InputEngine.InputMode inputMode) {}

    private static final List<PlacementCase> PLACEMENTS = List.of(
            new PlacementCase(KeyboardLayoutProfile.Plane.BOPOMOFO,
                    ChineseInputMethod.SMART, InputEngine.InputMode.BOPOMOFO),
            new PlacementCase(KeyboardLayoutProfile.Plane.CANGJIE,
                    ChineseInputMethod.CANGJIE, InputEngine.InputMode.BOPOMOFO),
            new PlacementCase(KeyboardLayoutProfile.Plane.SIMPLEX,
                    ChineseInputMethod.SIMPLEX, InputEngine.InputMode.BOPOMOFO),
            new PlacementCase(KeyboardLayoutProfile.Plane.ENGLISH,
                    ChineseInputMethod.SMART, InputEngine.InputMode.ENGLISH),
            new PlacementCase(KeyboardLayoutProfile.Plane.NUMBER_SYMBOLS,
                    ChineseInputMethod.SMART, InputEngine.InputMode.NUMBER));

    @Test public void spacingShrinksOnlyPaintAndRetainsEdgeTouchesAndCaptionPositions() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        instrumentation.runOnMainSync(() -> {
          for (var profile : KeyboardLayoutProfile.available()) {
            for (var orientation : KeyboardLayoutProfile.Orientation.values()) {
              for (var font : KeyboardLayoutProfile.FontSize.values()) {
                var view = new BopomofoKeyboardView(instrumentation.getTargetContext());
                view.setMode(orientation == KeyboardLayoutProfile.Orientation.PORTRAIT
                        ? BopomofoKeyboardView.Mode.PORTRAIT : BopomofoKeyboardView.Mode.LANDSCAPE);
                view.setKeyPreviewEnabled(false);
                view.setState(List.of(), "", false, List.of(), 0, InputEngine.InputMode.BOPOMOFO,
                        false, false, false, false, 0, 1, -1, InputFieldPolicy.DEFAULT);
                var events = new ArrayList<String>();
                view.setListener(keyListener(events));
                view.setLayoutProfile(profile);
                view.setLayoutOptions(KeyboardLayoutProfile.KeycapArea.SMALL, font,
                        KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER);
                KeyCanvas original = draw(view);
                for (var area : KeyboardLayoutProfile.KeycapArea.values()) {
                    view.setLayoutOptions(area, font, KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER);
                    KeyCanvas spaced = draw(view);
                    assertEquals(original.keys.size(), spaced.keys.size());
                    for (int index = 0; index < original.keys.size(); index++) {
                        RectF before = original.keys.get(index); RectF after = spaced.keys.get(index);
                        assertEquals(before.centerX(), after.centerX(), .01f);
                        assertEquals(before.centerY(), after.centerY(), .01f);
                        assertEquals(area.fraction, after.width() * after.height() / (before.width() * before.height()), .001f);
                    }
                    assertEquals("Caption size and position must not follow the smaller cap", original.texts, spaced.texts);
                    RectF first = original.keys.get(0);
                    if (area != KeyboardLayoutProfile.KeycapArea.SMALL) {
                        assertTrue(first.right - 1 > spaced.keys.get(0).right);
                    }
                    events.clear();
                    tap(view, first.right - 1, first.centerY());
                    assertEquals(List.of("1"), events);
                }
              }
            }
          }
        });
    }

    @Test public void largeTextUsesTheSameKeysWithoutHintsAndFitsInsideEachCap() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        instrumentation.runOnMainSync(() -> {
            for (var profile : KeyboardLayoutProfile.available()) {
                for (var orientation : KeyboardLayoutProfile.Orientation.values()) {
                    var view = new BopomofoKeyboardView(instrumentation.getTargetContext());
                    view.setMode(orientation == KeyboardLayoutProfile.Orientation.PORTRAIT
                            ? BopomofoKeyboardView.Mode.PORTRAIT : BopomofoKeyboardView.Mode.LANDSCAPE);
                    view.setState(List.of(), "", false, List.of(), 0, InputEngine.InputMode.BOPOMOFO,
                            false, false, false, false, 0, 1, -1, InputFieldPolicy.DEFAULT);
                    view.setLayoutProfile(profile);
                    view.setLayoutOptions(KeyboardLayoutProfile.KeycapArea.SMALL, KeyboardLayoutProfile.FontSize.NORMAL,
                            KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER);
                    KeyCanvas normal = draw(view);
                    view.setLayoutOptions(KeyboardLayoutProfile.KeycapArea.SMALL, KeyboardLayoutProfile.FontSize.LARGE,
                            KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER);
                    KeyCanvas large = draw(view);
                    assertEquals(normal.keys, large.keys);
                    if (profile.split) {
                        for (var text : normal.texts) {
                            if (!text.value.contains("/") && !text.value.equals("空白")) continue;
                            RectF key = normal.keys.get(text.keyIndex);
                            assertTrue("Split control caption must fit: " + text.value,
                                    text.ink.left >= key.left - 1 && text.ink.right <= key.right + 1);
                        }
                    }
                    assertTrue(normal.texts.stream().anyMatch(text -> text.value.equals("1")));
                    assertFalse(large.texts.stream().anyMatch(text -> List.of("1", "q", "a").contains(text.value)));
                    for (var text : large.texts) {
                        if (text.keyIndex < 0) continue;
                        RectF key = large.keys.get(text.keyIndex);
                        assertTrue("Large glyph outside cap: " + text.value,
                                text.ink.left >= key.left - 1 && text.ink.right <= key.right + 1
                                && text.ink.top >= key.top - 1 && text.ink.bottom <= key.bottom + 1);
                    }
                    float regular = normal.texts.stream().filter(text -> text.value.equals("ㄅ")).findFirst().orElseThrow().size;
                    float enlarged = large.texts.stream().filter(text -> text.value.equals("ㄅ")).findFirst().orElseThrow().size;
                    assertTrue(enlarged > regular);
                }
            }
        });
    }

    @Test public void switchingEveryVisualOptionRetainsCompositionAndCandidateLabels() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        instrumentation.runOnMainSync(() -> {
            var view = new BopomofoKeyboardView(instrumentation.getTargetContext());
            view.setState(List.of("你好", "你"), "你好ㄋㄧ", true, List.of("你", "好", "ㄋ", "ㄧ"), 2,
                    InputEngine.InputMode.BOPOMOFO, false, false, false, false, 0, 2, 0, InputFieldPolicy.DEFAULT);
            for (var profile : KeyboardLayoutProfile.available()) {
                view.setLayoutProfile(profile);
                for (var position : KeyboardLayoutProfile.DeletePosition.values()) {
                    view.setLayoutOptions(KeyboardLayoutProfile.KeycapArea.LARGE, KeyboardLayoutProfile.FontSize.LARGE, position);
                    KeyCanvas canvas = draw(view);
                    assertTrue(canvas.texts.stream().anyMatch(text -> text.value.contains("你好")));
                    assertTrue(canvas.texts.stream().anyMatch(text -> text.value.equals("ㄋ")));
                    assertTrue(canvas.texts.stream().anyMatch(text -> text.value.equals("ㄧ")));
                }
            }
        });
    }

    @Test public void standardTableBottomRowMovesOnePitchWithoutMovingTheLastControl() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        instrumentation.runOnMainSync(() -> {
            var profile = KeyboardLayoutProfile.STANDARD;
            for (var orientation : KeyboardLayoutProfile.Orientation.values()) {
                var view = new BopomofoKeyboardView(instrumentation.getTargetContext());
                view.setLayoutProfile(profile);
                view.setMode(orientation == KeyboardLayoutProfile.Orientation.PORTRAIT
                        ? BopomofoKeyboardView.Mode.PORTRAIT : BopomofoKeyboardView.Mode.LANDSCAPE);
                view.setKeyPreviewEnabled(false);
                var events = new ArrayList<String>();
                view.setListener(keyListener(events));
                for (boolean shifted : new boolean[] {false, true}) {
                    for (var position : KeyboardLayoutProfile.DeletePosition.values()) {
                        for (var spacing : KeyboardLayoutProfile.KeycapArea.values()) {
                            for (var font : KeyboardLayoutProfile.FontSize.values()) {
                                view.setLayoutOptions(spacing, font, position);
                                view.setChineseInputMethod(ChineseInputMethod.SMART);
                                view.setState(List.of(), "", false, List.of(), 0, InputEngine.InputMode.BOPOMOFO,
                                        shifted, false, false, false, 0, 1, -1, InputFieldPolicy.DEFAULT);
                                var original = draw(view);
                                var oldActions = keyActions(profile, orientation, KeyboardLayoutProfile.Plane.BOPOMOFO,
                                        shifted, position);
                                RectF oldZ = original.keys.get(oldActions.indexOf("z"));
                                RectF oldX = original.keys.get(oldActions.indexOf("x"));
                                String control = position == KeyboardLayoutProfile.DeletePosition.ABOVE_ENTER
                                        ? "BACKSPACE" : "SHIFT";
                                RectF oldControl = original.keys.get(oldActions.indexOf(control));
                                for (var method : List.of(ChineseInputMethod.CANGJIE, ChineseInputMethod.SIMPLEX)) {
                                    view.setChineseInputMethod(method);
                                    var rendered = draw(view);
                                    var plane = method == ChineseInputMethod.CANGJIE
                                            ? KeyboardLayoutProfile.Plane.CANGJIE : KeyboardLayoutProfile.Plane.SIMPLEX;
                                    var actions = keyActions(profile, orientation, plane, shifted, position);
                                    assertFalse(actions.contains("/"));
                                    assertEquals(oldX, rendered.keys.get(actions.indexOf("z")));
                                    assertEquals(oldControl, rendered.keys.get(actions.indexOf(control)));
                                    assertEquals(original.keys.get(0), rendered.keys.get(0));
                                    assertTrue(rendered.texts.stream().anyMatch(text -> text.value.equals("重")));
                                    events.clear();
                                    tap(view, oldX.centerX(), oldX.centerY());
                                    assertEquals(List.of("z"), events);
                                    events.clear();
                                    tap(view, oldZ.centerX(), oldZ.centerY());
                                    assertTrue("The new leading space must not send a key", events.isEmpty());
                                    tap(view, oldControl.centerX(), oldControl.centerY());
                                    assertEquals(List.of(control), events);
                                }
                            }
                        }
                    }
                }
            }
        });
    }

    private static List<String> keyActions(KeyboardLayoutProfile profile,
            KeyboardLayoutProfile.Orientation orientation, KeyboardLayoutProfile.Plane plane,
            boolean shifted, KeyboardLayoutProfile.DeletePosition position) {
        var result = new ArrayList<String>();
        profile.layout(orientation).rows(plane, shifted, position).forEach(result::addAll);
        result.addAll(profile.layout(orientation).functionKeys(position));
        return result;
    }

    private static BopomofoKeyboardView.Listener keyListener(List<String> events) {
        return new BopomofoKeyboardView.Listener() {
            @Override public void onPress() {}
            @Override public void onKey(String key) { events.add(key); }
            @Override public void onCandidate(int index) { fail("Unexpected candidate"); }
            @Override public void onSmartCell(int index) { fail("Unexpected composition selection"); }
            @Override public void onPage(int delta) { fail("Unexpected page"); }
        };
    }

    private static KeyCanvas draw(BopomofoKeyboardView view) {
        int width = view.getResources().getDisplayMetrics().widthPixels;
        view.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED));
        view.layout(0, 0, view.getMeasuredWidth(), view.getMeasuredHeight());
        KeyCanvas canvas = new KeyCanvas(); view.draw(canvas); return canvas;
    }

    @Test public void touchProfilesRenderReachableActionsAcrossDirectionsAndPlacements() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        instrumentation.runOnMainSync(() -> {
            var context = instrumentation.getTargetContext();
            // Pairwise width samples keep this a frontend smoke, not a full UI matrix.
            int[] sampleWidthsDp = {320, 414, 768};
            int sample = 0;
            for (var profile : KeyboardLayoutProfile.available()) {
                for (var orientation : KeyboardLayoutProfile.Orientation.values()) {
                    var view = new BopomofoKeyboardView(context);
                    view.setLayoutProfile(profile);
                    view.setMode(orientation == KeyboardLayoutProfile.Orientation.PORTRAIT
                            ? BopomofoKeyboardView.Mode.PORTRAIT : BopomofoKeyboardView.Mode.LANDSCAPE);
                    view.setKeyPreviewEnabled(false);
                    var dispatched = new ArrayList<String>();
                    view.setListener(new BopomofoKeyboardView.Listener() {
                        @Override public void onPress() {}
                        @Override public void onKey(String key) { dispatched.add(key); }
                        @Override public void onCandidate(int index) { fail("Unexpected candidate action"); }
                        @Override public void onSmartCell(int index) { fail("Unexpected composition action"); }
                        @Override public void onPage(int delta) { fail("Unexpected page action"); }
                    });
                    for (var mapping : BopomofoKeyboardLayout.values()) {
                        view.setKeyboardLayout(mapping);
                        for (var placement : PLACEMENTS) {
                            view.setChineseInputMethod(placement.method());
                            for (boolean shifted : new boolean[] {false, true}) {
                              for (var deletePosition : KeyboardLayoutProfile.DeletePosition.values()) {
                                view.setLayoutOptions(KeyboardLayoutProfile.KeycapArea.SMALL, KeyboardLayoutProfile.FontSize.NORMAL, deletePosition);
                                // Keep candidates and editable cells empty to isolate key hit testing.
                                view.setState(List.of(), "", false, List.of(), 0, placement.inputMode(),
                                        shifted, false, false, false, 0, 1, -1, InputFieldPolicy.DEFAULT);
                                int width = Math.round(sampleWidthsDp[sample++ % sampleWidthsDp.length]
                                        * context.getResources().getDisplayMetrics().density);
                                view.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                                        View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED));
                                view.layout(0, 0, view.getMeasuredWidth(), view.getMeasuredHeight());
                                var canvas = new KeyCanvas();
                                view.draw(canvas);
                                var expected = new ArrayList<String>();
                                float widthDp = width / context.getResources().getDisplayMetrics().density;
                                KeyboardLayoutGeometry.resolvedRows(profile, orientation, placement.plane(), shifted,
                                        deletePosition, widthDp).forEach(expected::addAll);
                                expected.addAll(KeyboardLayoutGeometry.resolvedFunctionKeys(profile, orientation,
                                        deletePosition, widthDp));
                                assertEquals("Each declared action must have one painted key", expected.size(), canvas.keys.size());
                                dispatched.clear();
                                for (int index = 0; index < canvas.keys.size(); index++) {
                                    RectF bounds = canvas.keys.get(index);
                                    assertTrue("Key must have usable width", bounds.width() > 0);
                                    assertTrue("Key must have usable height", bounds.height() > 0);
                                    assertTrue("Key must remain inside the view", bounds.left >= 0 && bounds.top >= 0
                                            && bounds.right <= view.getWidth() && bounds.bottom <= view.getHeight());
                                    for (int previous = 0; previous < index; previous++) {
                                        assertFalse("Painted keys must not overlap", RectF.intersects(bounds, canvas.keys.get(previous)));
                                    }
                                    tap(view, bounds.centerX(), bounds.centerY());
                                }
                                assertEquals("Painting and hit testing must use the same profile actions", expected, dispatched);
                                if (profile.split) {
                                    dispatched.clear();
                                    for (RectF key : canvas.keys) tap(view, width / 2f, key.centerY());
                                    assertTrue("The centre gap must never dispatch a key", dispatched.isEmpty());
                                }
                              }
                            }
                        }
                    }
                }
            }
        });
    }

    private static void tap(View view, float x, float y) {
        long time = SystemClock.uptimeMillis();
        MotionEvent down = MotionEvent.obtain(time, time, MotionEvent.ACTION_DOWN, x, y, 0);
        MotionEvent up = MotionEvent.obtain(time, time + 1, MotionEvent.ACTION_UP, x, y, 0);
        try {
            view.onTouchEvent(down);
            view.onTouchEvent(up);
        } finally {
            down.recycle();
            up.recycle();
        }
    }

    private static final class KeyCanvas extends Canvas {
        final List<RectF> keys = new ArrayList<>();
        final List<PaintedText> texts = new ArrayList<>();
        @Override public void drawRoundRect(RectF bounds, float rx, float ry, Paint paint) {
            keys.add(new RectF(bounds));
        }
        @Override public void drawText(String value, float x, float y, Paint paint) {
            android.graphics.Rect ink = new android.graphics.Rect();
            paint.getTextBounds(value, 0, value.length(), ink);
            float left = x - paint.measureText(value) / 2;
            texts.add(new PaintedText(value, x, y, paint.getTextSize(), keys.size() - 1,
                    new RectF(left + ink.left, y + ink.top, left + ink.right, y + ink.bottom)));
        }
    }
    private record PaintedText(String value, float x, float y, float size, int keyIndex, RectF ink) {}
}
