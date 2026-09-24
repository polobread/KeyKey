package tw.chichi77.keykey.android;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class BopomofoCompositionModeSettingsTest {
    @Test
    public void unknownAndMissingValuesDefaultToSmart() {
        assertEquals(BopomofoCompositionMode.SMART,
                BopomofoCompositionModeSettings.modeFromValue(null));
        assertEquals(BopomofoCompositionMode.SMART,
                BopomofoCompositionModeSettings.modeFromValue("unknown"));
    }

    @Test
    public void traditionalValueRoundTrips() {
        assertEquals(BopomofoCompositionMode.TRADITIONAL,
                BopomofoCompositionModeSettings.modeFromValue("traditional"));
        assertEquals("traditional", BopomofoCompositionModeSettings.valueForMode(
                BopomofoCompositionMode.TRADITIONAL));
    }
}
