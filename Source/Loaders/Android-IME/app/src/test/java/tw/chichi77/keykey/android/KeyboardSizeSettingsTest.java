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

    @Test
    public void keyboardHeightUsesNineSelectedRatiosAndSnapsPreviousValues() {
        int[] percents = {50, 75, 90, 100, 110, 125, 150, 175, 200};
        assertEquals(percents.length - 1, KeyboardSizeSettings.maxSelectionIndex());
        for (int index = 0; index < percents.length; index++) {
            assertEquals(percents[index], KeyboardSizeSettings.percentForSelection(index));
            assertEquals(index, KeyboardSizeSettings.selectionForPercent(percents[index]));
        }
        assertEquals(50, KeyboardSizeSettings.percentForSelection(-1));
        assertEquals(200, KeyboardSizeSettings.percentForSelection(9));
        assertEquals(0, KeyboardSizeSettings.selectionForPercent(10));
        assertEquals(5, KeyboardSizeSettings.selectionForPercent(137));
        assertEquals(5, KeyboardSizeSettings.selectionForPercent(125));
        assertEquals(8, KeyboardSizeSettings.selectionForPercent(250));
    }
}
