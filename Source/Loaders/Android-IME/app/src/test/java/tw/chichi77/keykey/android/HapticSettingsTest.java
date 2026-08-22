package tw.chichi77.keykey.android;

import static org.junit.Assert.assertArrayEquals;

import org.junit.Test;

public final class HapticSettingsTest {
    @Test
    public void nineLevelsUseTheRequestedDurations() {
        int[] durations = new int[HapticSettings.LEVEL_COUNT];
        for (int level = 0; level < durations.length; level++) {
            durations[level] = HapticSettings.durationMsForLevel(level);
        }
        assertArrayEquals(new int[]{0, 10, 20, 30, 50, 80, 100, 150, 200}, durations);
    }
}
