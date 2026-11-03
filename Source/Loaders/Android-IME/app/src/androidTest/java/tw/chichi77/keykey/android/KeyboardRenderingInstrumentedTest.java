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
                                profile.layout(orientation).rows(placement.plane(), shifted).forEach(expected::addAll);
                                expected.addAll(profile.layout(orientation).functionKeys());
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
        @Override public void drawRoundRect(RectF bounds, float rx, float ry, Paint paint) {
            keys.add(new RectF(bounds));
        }
    }
}
