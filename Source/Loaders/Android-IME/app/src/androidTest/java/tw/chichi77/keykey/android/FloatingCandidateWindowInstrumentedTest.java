package tw.chichi77.keykey.android;

import static org.junit.Assert.*;

import android.content.Context;
import android.content.ContextWrapper;
import android.os.Binder;
import android.os.IBinder;
import android.view.View;
import android.view.WindowManager;

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

    private static final class Fixture implements FloatingCandidateWindow.Listener {
        final ArrayList<CandidateWindowSettings.Failure> failures = new ArrayList<>();
        final TokenView token;
        final FloatingCandidateWindow window;
        int failuresRemaining;
        int attempts;

        Fixture() {
            Context base = InstrumentationRegistry.getInstrumentation().getTargetContext();
            WindowManager real = base.getSystemService(WindowManager.class);
            WindowManager fake = (WindowManager) Proxy.newProxyInstance(
                    WindowManager.class.getClassLoader(), new Class<?>[] {WindowManager.class},
                    (proxy, method, args) -> {
                        if (method.getName().equals("addView")
                                || method.getName().equals("updateViewLayout")) {
                            attempts++;
                            if (failuresRemaining-- > 0) {
                                throw new WindowManager.BadTokenException("test failure");
                            }
                            return null;
                        }
                        if (method.getName().equals("removeViewImmediate")) return null;
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

        @Override public void onPress() {}
        @Override public void onCandidate(int index) {}
        @Override public void onWindowUnavailable(CandidateWindowSettings.Failure failure) {
            failures.add(failure);
        }
    }
}
