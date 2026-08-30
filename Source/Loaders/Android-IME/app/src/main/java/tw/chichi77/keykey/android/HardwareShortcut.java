package tw.chichi77.keykey.android;

import android.view.KeyEvent;

final class HardwareShortcut {
    private HardwareShortcut() {}

    static boolean isControlShortcut(int keyCode, int metaState) {
        if (!hasControl(metaState) || isShiftPressed(metaState)
                || hasAlt(metaState) || hasMeta(metaState)) {
            return false;
        }
        return keyCode == KeyEvent.KEYCODE_SPACE
                || keyCode == KeyEvent.KEYCODE_COMMA
                || keyCode == KeyEvent.KEYCODE_PERIOD
                || keyCode == KeyEvent.KEYCODE_0
                || keyCode == KeyEvent.KEYCODE_1;
    }

    static boolean isWidthToggle(int keyCode, int metaState) {
        return keyCode == KeyEvent.KEYCODE_SPACE && isShiftPressed(metaState)
                && !hasControl(metaState) && !hasAlt(metaState) && !hasMeta(metaState);
    }

    static boolean isShiftPressed(int state) {
        return (state & (KeyEvent.META_SHIFT_ON | KeyEvent.META_SHIFT_LEFT_ON
                | KeyEvent.META_SHIFT_RIGHT_ON)) != 0;
    }

    private static boolean hasControl(int state) {
        return (state & (KeyEvent.META_CTRL_ON | KeyEvent.META_CTRL_LEFT_ON
                | KeyEvent.META_CTRL_RIGHT_ON)) != 0;
    }

    private static boolean hasAlt(int state) {
        return (state & (KeyEvent.META_ALT_ON | KeyEvent.META_ALT_LEFT_ON
                | KeyEvent.META_ALT_RIGHT_ON)) != 0;
    }

    private static boolean hasMeta(int state) {
        return (state & (KeyEvent.META_META_ON | KeyEvent.META_META_LEFT_ON
                | KeyEvent.META_META_RIGHT_ON)) != 0;
    }
}
