package tw.chichi77.keykey.android;

import static org.junit.Assert.*;

import android.os.Handler;
import android.os.Looper;
import android.view.inputmethod.InputConnection;
import android.view.inputmethod.InputConnectionWrapper;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.util.ArrayDeque;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Cursor requests may synchronously wait for an editor on the IME's own main looper. */
@RunWith(AndroidJUnit4.class)
public final class CursorAnchorRequestsInstrumentedTest {
    @Test public void sameProcessEditorRepliesWithoutBlockingMainForMonitorOrCancel() throws Exception {
        Handler main = new Handler(Looper.getMainLooper());
        ExecutorService worker = Executors.newSingleThreadExecutor();
        AtomicInteger hostReplies = new AtomicInteger();
        AtomicInteger callsOffMain = new AtomicInteger();
        AtomicInteger monitors = new AtomicInteger();
        AtomicInteger cancellations = new AtomicInteger();
        AtomicInteger completionsOnMain = new AtomicInteger();
        CountDownLatch completed = new CountDownLatch(2);
        AtomicBoolean hostTimedOut = new AtomicBoolean();
        InputConnection connection = new InputConnectionWrapper(null, false) {
            @Override public boolean requestCursorUpdates(int mode) {
                if (mode == 0) cancellations.incrementAndGet();
                if (mode == (InputConnection.CURSOR_UPDATE_IMMEDIATE
                        | InputConnection.CURSOR_UPDATE_MONITOR)) monitors.incrementAndGet();
                if (Looper.myLooper() != Looper.getMainLooper()) callsOffMain.incrementAndGet();
                CountDownLatch hostReply = new CountDownLatch(1);
                main.post(() -> { hostReplies.incrementAndGet(); hostReply.countDown(); });
                try {
                    if (!hostReply.await(1, TimeUnit.SECONDS)) hostTimedOut.set(true);
                } catch (InterruptedException error) {
                    Thread.currentThread().interrupt();
                    hostTimedOut.set(true);
                }
                return !hostTimedOut.get();
            }
            @Override public boolean requestCursorUpdates(int mode, int filter) {
                return requestCursorUpdates(mode);
            }
        };
        try {
            InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
                for (int mode : new int[]{InputConnection.CURSOR_UPDATE_IMMEDIATE
                        | InputConnection.CURSOR_UPDATE_MONITOR, 0}) {
                    BopomofoImeService.requestCursorUpdatesAsync(worker, main::post,
                            connection, mode, () -> true, () -> {
                                if (Looper.myLooper() == Looper.getMainLooper()) completionsOnMain.incrementAndGet();
                                completed.countDown();
                            });
                }
            });
            assertTrue("Both same-process host replies and completions must arrive", completed.await(3, TimeUnit.SECONDS));
            assertFalse("An editor reply must not wait on its own blocked main looper", hostTimedOut.get());
            assertEquals("Monitor and cancellation both run away from main", 2, callsOffMain.get());
            assertEquals(2, hostReplies.get());
            assertEquals("The monitor retains both immediate and monitor flags", 1, monitors.get());
            assertEquals("Cancellation must send mode zero", 1, cancellations.get());
            assertEquals("Only completion state runs on main", 2, completionsOnMain.get());
        } finally {
            worker.shutdownNow();
        }
    }

    @Test public void obsoleteQueuedRequestsAndLateCompletionsCannotAffectTheNextHost() {
        ArrayDeque<Runnable> worker = new ArrayDeque<>();
        ArrayDeque<Runnable> main = new ArrayDeque<>();
        AtomicLong host = new AtomicLong(1);
        AtomicLong request = new AtomicLong(1);
        AtomicInteger hostCalls = new AtomicInteger();
        AtomicInteger completions = new AtomicInteger();
        InputConnection connection = new InputConnectionWrapper(null, false) {
            @Override public boolean requestCursorUpdates(int mode) { hostCalls.incrementAndGet(); return true; }
            @Override public boolean requestCursorUpdates(int mode, int filter) { return requestCursorUpdates(mode); }
        };
        BopomofoImeService.requestCursorUpdatesAsync(worker::add, main::add, connection,
                InputConnection.CURSOR_UPDATE_MONITOR,
                () -> host.get() == 1 && request.get() == 1, completions::incrementAndGet);
        host.incrementAndGet();
        worker.remove().run();
        assertEquals("An old host's queued request never reaches its connection", 0, hostCalls.get());
        assertTrue(main.isEmpty());

        BopomofoImeService.requestCursorUpdatesAsync(worker::add, main::add, connection,
                InputConnection.CURSOR_UPDATE_MONITOR,
                () -> host.get() == 2 && request.get() == 1, completions::incrementAndGet);
        request.incrementAndGet();
        worker.remove().run();
        assertEquals("A superseded request on the same host is also skipped", 0, hostCalls.get());
        assertTrue(main.isEmpty());

        BopomofoImeService.requestCursorUpdatesAsync(worker::add, main::add, connection,
                InputConnection.CURSOR_UPDATE_MONITOR,
                () -> host.get() == 2 && request.get() == 2, completions::incrementAndGet);
        worker.remove().run();
        assertEquals(1, hostCalls.get());
        host.incrementAndGet();
        main.remove().run();
        assertEquals("A late old-host completion cannot schedule retry/failure for a new host", 0, completions.get());
    }
}
