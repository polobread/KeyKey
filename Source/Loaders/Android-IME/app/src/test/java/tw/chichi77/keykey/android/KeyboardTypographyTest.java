package tw.chichi77.keykey.android;

import static org.junit.Assert.*;
import org.junit.Test;

public final class KeyboardTypographyTest {
    private static final float EPSILON = .0001f;

    @Test public void ampleSpaceDoesNotStretchGlyphsToFillKeys() {
        assertEquals(20, KeyboardTypography.keyTextSize(KeyboardLayoutProfile.FontSize.NORMAL, 20, 200), EPSILON);
        assertEquals(23, KeyboardTypography.keyTextSize(KeyboardLayoutProfile.FontSize.MEDIUM, 20, 200), EPSILON);
        assertEquals(26, KeyboardTypography.keyTextSize(KeyboardLayoutProfile.FontSize.LARGE, 20, 200), EPSILON);
        assertEquals(29, KeyboardTypography.keyTextSize(KeyboardLayoutProfile.FontSize.EXTRA_LARGE, 20, 200), EPSILON);
    }

    @Test public void constrainedRowsRetainAllFourProportionalLevels() {
        for (float fit : new float[]{12, 18, 20, 25, 40, 200}) {
            float standard = KeyboardTypography.keyTextSize(KeyboardLayoutProfile.FontSize.NORMAL, 20, fit);
            float previous = 0;
            for (var level : KeyboardLayoutProfile.FontSize.values()) {
                float size = KeyboardTypography.keyTextSize(level, 20, fit);
                assertEquals(level.id, level.stripScale, size / standard, EPSILON);
                assertTrue("Every level must visibly grow", size > previous);
                assertTrue("The whole family stays within the shared fit", size <= fit + EPSILON);
                previous = size;
            }
        }
    }

    @Test public void sharedFitScalesTheFamilyWithoutChangingItsRatios() {
        float spacious = KeyboardTypography.keyTextSize(KeyboardLayoutProfile.FontSize.NORMAL, 20, 29);
        float narrow = KeyboardTypography.keyTextSize(KeyboardLayoutProfile.FontSize.NORMAL, 20, 14.5f);
        assertEquals(spacious / 2, narrow, EPSILON);
        for (var level : KeyboardLayoutProfile.FontSize.values()) {
            assertEquals(KeyboardTypography.keyTextSize(level, 20, 29) / 2,
                    KeyboardTypography.keyTextSize(level, 20, 14.5f), EPSILON);
        }
    }
}
