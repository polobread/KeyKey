package tw.chichi77.keykey.android;

import static org.junit.Assert.*;

import android.content.Context;
import android.content.ContextWrapper;
import android.graphics.Rect;
import android.graphics.PixelFormat;
import android.hardware.display.DisplayManager;
import android.hardware.display.VirtualDisplay;
import android.media.ImageReader;
import android.os.Build;
import android.os.Binder;
import android.os.IBinder;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowManager;
import android.view.WindowMetrics;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import java.lang.reflect.Proxy;
import java.util.ArrayList;
import java.util.List;

import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public final class FloatingCandidateWindowInstrumentedTest {
    @Test
    public void persistentAttachFailureStopsAndReportsOnce() {
        onMain(() -> {
            Fixture fixture = new Fixture();
            fixture.failuresRemaining = 100;
            fixture.show();
            fixture.drain();
            assertEquals(List.of(CandidateWindowSettings.Failure.ATTACH), fixture.failures);
            assertTrue(fixture.token.pending.isEmpty());
            int attempts = fixture.attempts;
            fixture.drain();
            assertEquals(attempts, fixture.attempts);
        });
    }

    @Test
    public void hideCancelsBothTokenAndAttachRetries() {
        onMain(() -> {
            for (boolean hasToken : new boolean[] {false, true}) {
                Fixture fixture = new Fixture();
                fixture.token.hasToken = hasToken;
                fixture.failuresRemaining = 100;
                fixture.show();
                assertFalse(fixture.token.pending.isEmpty());
                fixture.window.hide();
                int attempts = fixture.attempts;
                fixture.drain();
                assertTrue(fixture.token.pending.isEmpty());
                assertTrue(fixture.failures.isEmpty());
                assertEquals(attempts, fixture.attempts);
            }
        });
    }

    @Test
    public void successfulAttachResetsConsecutiveFailures() {
        onMain(() -> {
            Fixture fixture = new Fixture();
            fixture.failuresRemaining = 10;
            fixture.show();
            fixture.drain();
            assertTrue(fixture.failures.isEmpty());
            assertEquals(11, fixture.attempts);

            // A second transient outage must get its own bounded recovery period.
            fixture.failuresRemaining = 10;
            fixture.show();
            fixture.drain();
            assertTrue(fixture.failures.isEmpty());
            assertEquals(22, fixture.attempts);
            fixture.window.hide();
        });
    }

    @Test
    public void supportFooterUsesApprovedTypographyAndNeverSelectsCandidates() {
        onMain(() -> {
            for (CandidateWindowSettings.Layout layout : CandidateWindowSettings.Layout.values()) {
                Fixture fixture = new Fixture();
                fixture.window.update(List.of("好", "豪"), 0, layout, null, true);
                assertEquals(LinearLayout.VERTICAL, fixture.content.getOrientation());
                LinearLayout candidates = (LinearLayout) fixture.content.getChildAt(0);
                assertEquals(2, candidates.getChildCount());
                TextView footer = (TextView) fixture.content.getChildAt(2);
                assertEquals("歡迎付費支持", footer.getText().toString());
                boolean horizontal = layout == CandidateWindowSettings.Layout.HORIZONTAL;
                float density = fixture.content.getResources().getDisplayMetrics().density;
                assertEquals(horizontal ? 15 : 13, footer.getTextSize() / density, 0.01f);
                assertEquals(horizontal ? Gravity.END : Gravity.CENTER_HORIZONTAL,
                        footer.getGravity() & Gravity.RELATIVE_HORIZONTAL_GRAVITY_MASK);
                assertFalse(footer.isClickable());
                assertFalse(footer.performClick());
                assertTrue(fixture.selected.isEmpty());
                assertTrue(candidates.getChildAt(1).performClick());
                assertEquals(List.of(1), fixture.selected);
                int heightWithFooter = fixture.parameters.height;

                fixture.window.update(List.of("好", "豪"), 0, layout, null, false);
                assertEquals(1, fixture.content.getChildCount());
                assertTrue(fixture.parameters.height < heightWithFooter);
                candidates = (LinearLayout) fixture.content.getChildAt(0);
                assertEquals(2, candidates.getChildCount());
                int attempts = fixture.attempts;
                fixture.window.update(List.of(), -1, layout, null, true);
                assertEquals(attempts, fixture.attempts);
                assertEquals(1, fixture.removals);
            }
        });
    }

    @Test
    public void footerHeightIsReservedBeforeFittingCandidatesToSafeBounds() {
        onMain(() -> {
            for (CandidateWindowSettings.Layout layout : CandidateWindowSettings.Layout.values()) {
                try (Fixture fixture = new Fixture()) {
                    float density = fixture.token.getResources().getDisplayMetrics().density;
                    fixture.safeHeight = Math.round(55 * density);
                    fixture.window.update(List.of("一", "二", "三", "四", "五", "六", "七", "八", "九"),
                            0, layout, null, true);
                    assertTrue(fixture.parameters.height <= fixture.safeHeight);
                    assertTrue(fixture.parameters.y >= 0);
                    assertTrue(fixture.parameters.y + fixture.parameters.height <= fixture.safeHeight);
                    LinearLayout candidates = (LinearLayout) fixture.content.getChildAt(0);
                    assertTrue(candidates.getChildAt(0).getLayoutParams().height < Math.round(40 * density));
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                        assertTrue("legacy safe bounds must query the owned display",
                                fixture.legacyBoundsQueries > 0);
                        Log.i("KeyKeyFloatingTest", "legacy footer bounds: sdk="
                                + Build.VERSION.SDK_INT + " layout=" + layout
                                + " safeHeight=" + fixture.safeHeight
                                + " windowHeight=" + fixture.parameters.height
                                + " displayQueries=" + fixture.legacyBoundsQueries);
                    }
                }
            }
        });
    }

    private static void onMain(Runnable test) {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(test);
    }

    private static final class TokenView extends View {
        final ArrayList<Runnable> pending = new ArrayList<>();
        final IBinder token = new Binder();
        boolean hasToken = true;

        TokenView(Context context) { super(context); }

        @Override public IBinder getWindowToken() { return hasToken ? token : null; }
        @Override public boolean postDelayed(Runnable action, long delay) {
            pending.add(action);
            return true;
        }
        @Override public boolean removeCallbacks(Runnable action) {
            pending.removeIf(item -> item == action);
            return true;
        }
    }

    private static final class Fixture implements FloatingCandidateWindow.Listener, AutoCloseable {
        final ArrayList<CandidateWindowSettings.Failure> failures = new ArrayList<>();
        final TokenView token;
        final FloatingCandidateWindow window;
        int failuresRemaining;
        int attempts;
        int removals;
        Integer safeHeight;
        VirtualDisplay legacyDisplay;
        ImageReader legacySurface;
        int legacyBoundsQueries;
        LinearLayout content;
        WindowManager.LayoutParams parameters;
        final ArrayList<Integer> selected = new ArrayList<>();

        Fixture() {
            Context base = InstrumentationRegistry.getInstrumentation().getTargetContext();
            WindowManager real = base.getSystemService(WindowManager.class);
            WindowManager fake = (WindowManager) Proxy.newProxyInstance(
                    WindowManager.class.getClassLoader(), new Class<?>[] {WindowManager.class},
                    (proxy, method, args) -> {
                        if (method.getName().equals("addView")
                                || method.getName().equals("updateViewLayout")) {
                            attempts++;
                            content = (LinearLayout) args[0];
                            parameters = (WindowManager.LayoutParams) args[1];
                            if (failuresRemaining-- > 0) {
                                throw new WindowManager.BadTokenException("test failure");
                            }
                            return null;
                        }
                        if (method.getName().equals("removeViewImmediate")) {
                            removals++;
                            return null;
                        }
                        if (method.getName().equals("getCurrentWindowMetrics") && safeHeight != null) {
                            return new WindowMetrics(new Rect(0, 0, 600, safeHeight),
                                    new WindowInsets.Builder().build());
                        }
                        if (method.getName().equals("getDefaultDisplay") && safeHeight != null) {
                            if (legacyDisplay == null) {
                                // Exercise the pre-30 Display.getRealMetrics path with public APIs.
                                // OWN_CONTENT_ONLY keeps this private display from capturing the screen.
                                legacySurface = ImageReader.newInstance(600, safeHeight,
                                        PixelFormat.RGBA_8888, 2);
                                legacyDisplay = base.getSystemService(DisplayManager.class)
                                        .createVirtualDisplay("KeyKey footer bounds", 600, safeHeight,
                                                base.getResources().getDisplayMetrics().densityDpi,
                                                legacySurface.getSurface(),
                                                DisplayManager.VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY);
                                assertNotNull("could not create owned legacy bounds display", legacyDisplay);
                            }
                            legacyBoundsQueries++;
                            return legacyDisplay.getDisplay();
                        }
                        return method.invoke(real, args);
                    });
            Context context = new ContextWrapper(base) {
                @Override public Object getSystemService(String name) {
                    return WINDOW_SERVICE.equals(name) ? fake : super.getSystemService(name);
                }
            };
            token = new TokenView(context);
            window = new FloatingCandidateWindow(context, token, this);
        }

        void show() {
            window.update(List.of("請"), 0, CandidateWindowSettings.Layout.VERTICAL, null);
        }

        void drain() {
            // Bound the harness too: the old counter-reset bug never exhausted retries.
            for (int i = 0; i < 30 && !token.pending.isEmpty(); i++) {
                token.pending.remove(0).run();
            }
            assertTrue("window retry did not stop", token.pending.isEmpty());
        }

        @Override public void close() {
            try {
                window.hide();
            } finally {
                try {
                    if (legacyDisplay != null) legacyDisplay.release();
                } finally {
                    if (legacySurface != null) legacySurface.close();
                }
            }
        }

        @Override public void onPress() {}
        @Override public void onCandidate(int index) { selected.add(index); }
        @Override public void onWindowUnavailable(CandidateWindowSettings.Failure failure) {
            failures.add(failure);
        }
    }
}
