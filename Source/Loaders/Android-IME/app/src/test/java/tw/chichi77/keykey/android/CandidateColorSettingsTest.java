package tw.chichi77.keykey.android;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class CandidateColorSettingsTest {
    @Test
    public void unknownAndMissingValuesUsePurple() {
        assertEquals(CandidateColorSettings.CandidateColor.PURPLE,
                CandidateColorSettings.colorFromValue(null));
        assertEquals(CandidateColorSettings.CandidateColor.PURPLE,
                CandidateColorSettings.colorFromValue("unknown"));
    }

    @Test
    public void colorsRoundTripThroughStoredValuesAndSelectionIndexes() {
        for (CandidateColorSettings.CandidateColor color
                : CandidateColorSettings.CandidateColor.values()) {
            assertEquals(color, CandidateColorSettings.colorFromValue(
                    CandidateColorSettings.valueForColor(color)));
            assertEquals(color, CandidateColorSettings.colorAtSelectionIndex(
                    CandidateColorSettings.selectionIndex(color)));
        }
    }

    @Test
    public void colorsMatchTheDesktopPalette() {
        assertEquals(0xFF800080, CandidateColorSettings.backgroundColor(
                CandidateColorSettings.CandidateColor.PURPLE));
        assertEquals(0xFF3BAD1F, CandidateColorSettings.backgroundColor(
                CandidateColorSettings.CandidateColor.GREEN));
        assertEquals(0xFFEBB500, CandidateColorSettings.backgroundColor(
                CandidateColorSettings.CandidateColor.YELLOW));
        assertEquals(0xFFBF0029, CandidateColorSettings.backgroundColor(
                CandidateColorSettings.CandidateColor.RED));
        assertEquals(0xFF000000, CandidateColorSettings.textColor(
                CandidateColorSettings.CandidateColor.YELLOW));
        assertEquals(0xFFFFFFFF, CandidateColorSettings.textColor(
                CandidateColorSettings.CandidateColor.PURPLE));
    }
}
