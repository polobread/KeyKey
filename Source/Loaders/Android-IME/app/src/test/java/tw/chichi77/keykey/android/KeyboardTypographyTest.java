package tw.chichi77.keykey.android;

import static org.junit.Assert.*;
import org.junit.Test;

public final class KeyboardTypographyTest {
    private static final float EPSILON = .0001f;

    @Test public void endpointsUseTheAvailableStandardAndRadicalFit() {
        assertEquals(40, KeyboardTypography.keyTextSize(KeyboardLayoutProfile.FontSize.NORMAL, 40, 80), EPSILON);
        assertEquals(80, KeyboardTypography.keyTextSize(KeyboardLayoutProfile.FontSize.EXTRA_LARGE, 40, 80), EPSILON);
        assertEquals(120, KeyboardTypography.keyTextSize(KeyboardLayoutProfile.FontSize.EXTRA_LARGE, 60, 120), EPSILON);
    }

    @Test public void intermediateLevelsHaveEqualProportionalGrowth() {
        for (float full : new float[]{18, 36, 80, 120, 200}) {
            float standard = full * .6f;
            float previous = standard;
            float ratio = (float) Math.cbrt(full / standard);
            for (var level : KeyboardLayoutProfile.FontSize.values()) {
                float size = KeyboardTypography.keyTextSize(level, standard, full);
                if (level != KeyboardLayoutProfile.FontSize.NORMAL) {
                    assertTrue(level.id, size > previous);
                    assertEquals(level.id, ratio, size / previous, EPSILON);
                }
                assertTrue(size <= full + EPSILON);
                previous = size;
            }
        }
    }

    @Test public void everyLevelTracksTheActualAvailableSpace() {
        for (var level : KeyboardLayoutProfile.FontSize.values()) {
            assertEquals(KeyboardTypography.keyTextSize(level, 40, 80) * 1.5f,
                    KeyboardTypography.keyTextSize(level, 60, 120), EPSILON);
            assertEquals(KeyboardTypography.keyTextSize(level, 40, 80) / 2,
                    KeyboardTypography.keyTextSize(level, 20, 40), EPSILON);
        }
    }
}
