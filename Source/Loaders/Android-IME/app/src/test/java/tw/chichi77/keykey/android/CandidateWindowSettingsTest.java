package tw.chichi77.keykey.android;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class CandidateWindowSettingsTest {
    @Test
    public void unknownAndMissingValuesUseVerticalLayout() {
        assertEquals(CandidateWindowSettings.Layout.VERTICAL,
                CandidateWindowSettings.layoutFromValue(null));
        assertEquals(CandidateWindowSettings.Layout.VERTICAL,
                CandidateWindowSettings.layoutFromValue("unknown"));
    }

    @Test
    public void layoutsRoundTripThroughStoredValues() {
        for (CandidateWindowSettings.Layout layout : CandidateWindowSettings.Layout.values()) {
            assertEquals(layout, CandidateWindowSettings.layoutFromValue(
                    CandidateWindowSettings.valueForLayout(layout)));
        }
    }
}
