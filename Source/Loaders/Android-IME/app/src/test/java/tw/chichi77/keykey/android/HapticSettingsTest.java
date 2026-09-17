package tw.chichi77.keykey.android;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class HapticSettingsTest {
    @Test
    public void durationUsesOneMillisecondStepsThroughOneTenthSecond() {
        assertEquals(0, HapticSettings.clampDurationMs(-1));
        assertEquals(1, HapticSettings.clampDurationMs(1));
        assertEquals(7, HapticSettings.clampDurationMs(7));
        assertEquals(99, HapticSettings.clampDurationMs(99));
        assertEquals(100, HapticSettings.clampDurationMs(100));
        assertEquals(100, HapticSettings.clampDurationMs(101));
        assertEquals(10, HapticSettings.legacyDurationMsForLevel(1));
        assertEquals(100, HapticSettings.legacyDurationMsForLevel(8));
    }
}
