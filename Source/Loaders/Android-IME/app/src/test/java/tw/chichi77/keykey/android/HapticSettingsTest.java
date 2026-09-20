package tw.chichi77.keykey.android;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class HapticSettingsTest {
    @Test
    public void durationUsesTenSelectedStepsAndSnapsPreviousValues() {
        int[] durations = {0, 1, 2, 3, 5, 10, 20, 30, 50, 100};
        assertEquals(durations.length - 1, HapticSettings.maxSelectionIndex());
        for (int index = 0; index < durations.length; index++) {
            assertEquals(durations[index], HapticSettings.durationMsForSelection(index));
            assertEquals(index, HapticSettings.selectionForDurationMs(durations[index]));
        }
        assertEquals(0, HapticSettings.durationMsForSelection(-1));
        assertEquals(100, HapticSettings.durationMsForSelection(10));
        assertEquals(0, HapticSettings.selectionForDurationMs(-1));
        assertEquals(4, HapticSettings.selectionForDurationMs(7));
        assertEquals(8, HapticSettings.selectionForDurationMs(75));
        assertEquals(9, HapticSettings.selectionForDurationMs(76));
        assertEquals(9, HapticSettings.selectionForDurationMs(200));
        assertEquals(10, HapticSettings.legacyDurationMsForLevel(1));
        assertEquals(100, HapticSettings.legacyDurationMsForLevel(5));
        assertEquals(100, HapticSettings.legacyDurationMsForLevel(8));
    }
}
