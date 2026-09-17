package tw.chichi77.keykey.android;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class KeyboardSizeSettingsTest {
    @Test
    public void keyboardHeightAllowsHalfThroughDoubleSize() {
        assertEquals(50, KeyboardSizeSettings.clampPercent(10));
        assertEquals(50, KeyboardSizeSettings.clampPercent(50));
        assertEquals(100, KeyboardSizeSettings.clampPercent(100));
        assertEquals(137, KeyboardSizeSettings.clampPercent(137));
        assertEquals(200, KeyboardSizeSettings.clampPercent(200));
        assertEquals(200, KeyboardSizeSettings.clampPercent(250));
    }
}
