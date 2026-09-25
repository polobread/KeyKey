package tw.chichi77.keykey.android;

import android.os.Handler;

/** One immediate delete is handled by the caller; this schedules the held-key repeats. */
final class BackspaceRepeater {
    static final int INITIAL_DELAY_MS = 450;

    static int intervalMs(int repeatCount) {
        if (repeatCount <= 8) return 115;
        if (repeatCount <= 24) return 90;
        return 70;
    }

    private final Handler handler;
    private Runnable action;
    private int repeatCount;
    private final Runnable tick = new Runnable() {
        @Override
        public void run() {
            Runnable current = action;
            if (current == null) return;
            current.run();
            if (action != current) return;
            repeatCount++;
            handler.postDelayed(this, intervalMs(repeatCount));
        }
    };

    BackspaceRepeater(Handler handler) {
        this.handler = handler;
    }

    void start(Runnable action) {
        stop();
        this.action = action;
        handler.postDelayed(tick, INITIAL_DELAY_MS);
    }

    void stop() {
        handler.removeCallbacks(tick);
        action = null;
        repeatCount = 0;
    }
}
