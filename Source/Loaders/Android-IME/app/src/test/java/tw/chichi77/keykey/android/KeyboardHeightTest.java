package tw.chichi77.keykey.android;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class KeyboardHeightTest {
    @Test
    public void touchUsesOrientationSizeAndTransientPreview() {
        for (var profile : KeyboardLayoutProfile.available()) {
            int portraitBase = profile.layout(KeyboardLayoutProfile.Orientation.PORTRAIT).contentHeightDp;
            int landscapeBase = profile.layout(KeyboardLayoutProfile.Orientation.LANDSCAPE).contentHeightDp;
            var portrait = KeyboardHeight.touch(portraitBase, 1f,
                    new KeyboardSizeSettings.Size(0.5f, 0f), null, 24);
            var landscape = KeyboardHeight.touch(landscapeBase, 1f,
                    new KeyboardSizeSettings.Size(2f, 12f), null, 0);

            assertEquals(profile.id, new KeyboardEdgeGeometry(165, 0), portrait.desiredEdges());
            assertEquals(profile.id, 165, portrait.minimumContentHeight());
            assertEquals(profile.id, 189, portrait.requestedWindowHeight());
            assertEquals(profile.id, new KeyboardEdgeGeometry(472, 12), landscape.desiredEdges());
            assertEquals(profile.id, 115, landscape.minimumContentHeight());
            assertEquals(profile.id, 472, landscape.requestedWindowHeight());
        }
        var preview = new KeyboardEdgeGeometry(391, 27);
        var editing = KeyboardHeight.touch(330, 1f,
                KeyboardSizeSettings.DEFAULT_SIZE, preview, 24);
        assertEquals(preview, editing.desiredEdges());
        assertEquals(415, editing.requestedWindowHeight());
    }

    @Test
    public void overlappingSystemBarsReserveOnlyTheLargerVisibleArea() {
        int displayBottom = 2424;
        int navigation = 63;
        int caption = 126;
        int simple = KeyboardHeight.systemBottomOverlap(1432, 2424,
                displayBottom, navigation, 2424, caption);
        int integrated = KeyboardHeight.systemBottomOverlap(1495, 2424,
                displayBottom, navigation, 2424, 0);
        assertEquals(126, simple);
        assertEquals(63, integrated);

        var classic = KeyboardHeight.touch(866, 2.625f,
                KeyboardSizeSettings.DEFAULT_SIZE, null, simple);
        var withIntegratedControls = KeyboardHeight.touch(866, 2.625f,
                KeyboardSizeSettings.DEFAULT_SIZE, null, integrated);
        assertEquals(992, classic.requestedWindowHeight());
        assertEquals(929, withIntegratedControls.requestedWindowHeight());
        assertEquals(classic.visibleEdges(992), withIntegratedControls.visibleEdges(929));
        assertEquals(new KeyboardEdgeGeometry(866, 0), classic.visibleEdges(992));
    }

    @Test
    public void systemOverlapUsesTheDisplayForNavigationAndWindowForCaption() {
        int displayBottom = 2424;
        assertEquals("A side or hidden system bar has no bottom inset", 0,
                KeyboardHeight.systemBottomOverlap(1450, 2424, displayBottom, 0, 2424, 0));
        assertEquals("The child ends above the independent system bars", 0,
                KeyboardHeight.systemBottomOverlap(1450, 2200, displayBottom, 63, 2424, 126));
        assertEquals("Navigation only overlaps the bottom 39 px of this child", 39,
                KeyboardHeight.systemBottomOverlap(1450, 2400, displayBottom, 63, 2400, 0));
        assertEquals("Caption is docked to the window, independent of the display",
                121, KeyboardHeight.systemBottomOverlap(1450, 2395, displayBottom, 0, 2400, 126));
        assertEquals("A control strip can cover a child shorter than the strip", 40,
                KeyboardHeight.systemBottomOverlap(2370, 2410, displayBottom, 0, 2424, 126));
    }

    @Test
    public void touchShrinksOptionalGapBeforeKeysFallBelowTheirMinimum() {
        var keyboard = KeyboardHeight.touch(330, 1f,
                new KeyboardSizeSettings.Size(1f, 48f), null, 24);

        assertEquals(402, keyboard.requestedWindowHeight());
        assertEquals(new KeyboardEdgeGeometry(258, 48), keyboard.visibleEdges(282));
        assertEquals(new KeyboardEdgeGeometry(195, 30), keyboard.visibleEdges(219));
        assertEquals(new KeyboardEdgeGeometry(140, 0), keyboard.visibleEdges(164));
        assertEquals(new KeyboardEdgeGeometry(0, 0), keyboard.visibleEdges(15));

        var constrained = keyboard.measuredEdges(219);
        assertEquals(new KeyboardEdgeGeometry(195, 30), constrained);
        assertEquals(219, keyboard.measuredWindowHeight(219, constrained));
    }

    @Test
    public void aShorterMeasureProbeDoesNotSetTheVisibleEdge() {
        for (float customGapDp : new float[]{0f, 16f}) {
            String sample = "Custom bottom gap " + customGapDp + " dp";
            int gap = customGapDp == 0f ? 0 : 42;
            var keyboard = KeyboardHeight.touch(866, 2.625f,
                    new KeyboardSizeSettings.Size(1f, customGapDp), null, 126);
            int actualHeight = 992 + gap;
            int probeHeight = actualHeight - 63;
            var full = new KeyboardEdgeGeometry(866 + gap, gap);
            var shortFrame = new KeyboardEdgeGeometry(803 + gap, gap);

            assertEquals(sample, full, keyboard.visibleEdges(actualHeight));
            var measured = keyboard.measuredEdges(probeHeight);
            assertEquals(sample, shortFrame, measured);
            assertEquals(sample, probeHeight, keyboard.measuredWindowHeight(probeHeight, measured));
            assertEquals(sample, full, keyboard.visibleEdges(actualHeight));
            assertEquals(sample, shortFrame, keyboard.visibleEdges(probeHeight));
        }
    }

    @Test
    public void hardwareBottomSpaceChangesWindowHeightWithTheSameContentBudget() {
        assertHardwareBottomSpace(false, 40);
        assertHardwareBottomSpace(true, 35);
    }

    private static void assertHardwareBottomSpace(boolean landscape, int reserve) {
        var withSpace = KeyboardHeight.hardware(1f, landscape, true, true, false);
        var withoutSpace = KeyboardHeight.hardware(1f, landscape, false, true, false);
        assertEquals(154 + reserve, withSpace.requestedWindowHeight());
        assertEquals(154 + reserve, withoutSpace.requestedWindowHeight());
        assertEquals(reserve, withSpace.visibleBottomSpace());
        assertEquals(0, withoutSpace.visibleBottomSpace());
        assertEquals(reserve, withSpace.reservedBottomSpace());
        assertEquals(reserve, withoutSpace.reservedBottomSpace());

        int cappedHeight = 100 + reserve;
        var capped = new KeyboardEdgeGeometry(100, 0);
        assertEquals(capped, withSpace.measuredEdges(cappedHeight));
        assertEquals(capped, withoutSpace.measuredEdges(cappedHeight));
        assertEquals(cappedHeight, withSpace.measuredWindowHeight(cappedHeight, capped));
        assertEquals(100, withoutSpace.measuredWindowHeight(cappedHeight, capped));
    }

    @Test
    public void hardwareSmartAndNumberRowsHaveStableHeights() {
        assertEquals(58, hardwareContent(false, false));
        assertEquals(106, hardwareContent(false, true));
        assertEquals(154, hardwareContent(true, false));
        assertEquals(154, hardwareContent(true, true));
    }

    private static int hardwareContent(boolean numberRows, boolean smartTwoRows) {
        return KeyboardHeight.hardware(1f, false, false, numberRows, smartTwoRows)
                .desiredEdges().contentHeight();
    }

    @Test
    public void floatingKeyboardNeedsOnlyTheGlobeWhenRequested() {
        var hidden = KeyboardHeight.floating(1f, false);
        var globe = KeyboardHeight.floating(1f, true);
        assertEquals(1, hidden.requestedWindowHeight());
        assertEquals(58, globe.requestedWindowHeight());
        assertEquals(0, globe.visibleBottomSpace());
        assertEquals(0, globe.reservedBottomSpace());
        assertEquals(new KeyboardEdgeGeometry(58, 0), globe.visibleEdges(58));
    }

    @Test
    public void draggingKeepsTheOppositeEdgeFixedAndClampsAtItsLimits() {
        var edges = new KeyboardEdgeGeometry(360, 30);
        assertEquals(new KeyboardEdgeGeometry(425, 30), edges.drag(true, 200, 165, 660, 425, 72));
        assertEquals(new KeyboardEdgeGeometry(195, 30), edges.drag(true, -500, 165, 660, 425, 72));
        assertEquals(new KeyboardEdgeGeometry(360, 72), edges.drag(false, 60, 165, 660, 425, 72));
        var flush = new KeyboardEdgeGeometry(360, 0);
        assertEquals(flush, edges.drag(false, -60, 165, 660, 425, 72));
        assertEquals(flush, flush.drag(false, -20, 165, 660, 425, 72));
        assertEquals(edges, flush.drag(false, 30, 165, 660, 425, 72));
        assertEquals(new KeyboardEdgeGeometry(690, 30), edges.drag(true, 500, 165, 660, 900, 72));
        var compact = new KeyboardEdgeGeometry(190, 20);
        assertEquals(new KeyboardEdgeGeometry(190, 25), compact.drag(false, 60, 165, 660, 425, 72));
        var tall = new KeyboardEdgeGeometry(690, 40);
        assertEquals(new KeyboardEdgeGeometry(690, 30), tall.drag(false, -60, 165, 660, 900, 72));
    }
}
