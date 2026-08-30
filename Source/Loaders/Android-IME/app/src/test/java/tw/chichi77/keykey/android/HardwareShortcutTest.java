package tw.chichi77.keykey.android;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.view.KeyEvent;

import org.junit.Test;

public final class HardwareShortcutTest {
    @Test
    public void widthToggleAcceptsEitherShiftSideAndNoOtherModifier() {
        assertTrue(HardwareShortcut.isWidthToggle(KeyEvent.KEYCODE_SPACE,
                KeyEvent.META_SHIFT_LEFT_ON));
        assertTrue(HardwareShortcut.isWidthToggle(KeyEvent.KEYCODE_SPACE,
                KeyEvent.META_SHIFT_RIGHT_ON));
        assertFalse(HardwareShortcut.isWidthToggle(KeyEvent.KEYCODE_SPACE,
                KeyEvent.META_SHIFT_LEFT_ON | KeyEvent.META_CTRL_LEFT_ON));
        assertFalse(HardwareShortcut.isWidthToggle(KeyEvent.KEYCODE_A,
                KeyEvent.META_SHIFT_LEFT_ON));
    }

    @Test
    public void controlShortcutsAcceptEitherControlSideButRejectShift() {
        assertTrue(HardwareShortcut.isControlShortcut(KeyEvent.KEYCODE_SPACE,
                KeyEvent.META_CTRL_LEFT_ON));
        assertTrue(HardwareShortcut.isControlShortcut(KeyEvent.KEYCODE_PERIOD,
                KeyEvent.META_CTRL_RIGHT_ON));
        assertFalse(HardwareShortcut.isControlShortcut(KeyEvent.KEYCODE_SPACE,
                KeyEvent.META_CTRL_LEFT_ON | KeyEvent.META_SHIFT_LEFT_ON));
        assertFalse(HardwareShortcut.isControlShortcut(KeyEvent.KEYCODE_A,
                KeyEvent.META_CTRL_LEFT_ON));
    }
}
