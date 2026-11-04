package tw.chichi77.keykey.android;

import static org.junit.Assert.*;

import org.junit.Test;

public final class KeyboardTypographyTest {
    private static final float EPSILON = .0001f;

    @Test public void normalSizeIsUnchangedRegardlessOfTheAvailableLargeFit() {
        assertEquals(20, KeyboardTypography.keyTextSize(
                KeyboardLayoutProfile.FontSize.NORMAL, 20, 18), EPSILON);
        assertEquals(20, KeyboardTypography.keyTextSize(
                KeyboardLayoutProfile.FontSize.NORMAL, 20, 60), EPSILON);
    }

    @Test public void intermediateLevelsDivideTheIntervalAndExtraLargeKeepsTheOriginalMaximum() {
        assertSizes(12, 30, 12, 18, 24, 30);
        assertSizes(12, 60, 12, 28, 44, 60);
        assertSizes(16, 32, 16, 21.333334f, 26.666666f, 32);
    }

    @Test public void everyEnlargedLevelStaysWithinTheAvailableOriginalFit() {
        for (var font : KeyboardLayoutProfile.FontSize.values()) {
            if (font == KeyboardLayoutProfile.FontSize.NORMAL) continue;
            assertEquals(font.id, 18, KeyboardTypography.keyTextSize(font, 20, 18), EPSILON);
            assertEquals(font.id, 20, KeyboardTypography.keyTextSize(font, 20, 20), EPSILON);
        }
    }

    private static void assertSizes(float normal, float oldLargeFit,
            float expectedNormal, float expectedMedium, float expectedLarge, float expectedExtraLarge) {
        assertEquals(expectedNormal, KeyboardTypography.keyTextSize(
                KeyboardLayoutProfile.FontSize.NORMAL, normal, oldLargeFit), EPSILON);
        assertEquals(expectedMedium, KeyboardTypography.keyTextSize(
                KeyboardLayoutProfile.FontSize.MEDIUM, normal, oldLargeFit), EPSILON);
        assertEquals(expectedLarge, KeyboardTypography.keyTextSize(
                KeyboardLayoutProfile.FontSize.LARGE, normal, oldLargeFit), EPSILON);
        assertEquals(expectedExtraLarge, KeyboardTypography.keyTextSize(
                KeyboardLayoutProfile.FontSize.EXTRA_LARGE, normal, oldLargeFit), EPSILON);
    }
}
