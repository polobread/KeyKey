package tw.chichi77.keykey.android;

/** Height requested by the keyboard and the parts that fit in its window, in pixels. */
record KeyboardHeight(KeyboardEdgeGeometry desiredEdges, int minimumContentHeight,
                      int visibleBottomSpace, int reservedBottomSpace) {
    static final int HARDWARE_CONTENT_HEIGHT_DP = 58;
    static final int HARDWARE_NUMBER_ROW_HEIGHT_DP = 48;

    static KeyboardHeight touch(int defaultHeightPx, float density, KeyboardSizeSettings.Size size,
            KeyboardEdgeGeometry preview, int systemBottomInset) {
        int minimum = minimumTouchContentHeight(defaultHeightPx);
        if (preview != null) return new KeyboardHeight(preview, minimum, systemBottomInset, systemBottomInset);

        int height = Math.round(defaultHeightPx * size.heightScale());
        int gap = Math.round(size.bottomGapDp() * density);
        return new KeyboardHeight(new KeyboardEdgeGeometry(height + gap, gap), minimum,
                systemBottomInset, systemBottomInset);
    }

    static int minimumTouchContentHeight(int defaultHeightPx) {
        return Math.round(defaultHeightPx * (KeyboardSizeSettings.MIN_PERCENT / 100f));
    }

    static KeyboardHeight hardware(float density, boolean landscape, boolean bottomSpaceEnabled,
            boolean numberRowsEnabled, boolean smartTwoRowsEnabled) {
        int rows = hardwareNumberRowCount(numberRowsEnabled, smartTwoRowsEnabled);
        int content = Math.round((HARDWARE_CONTENT_HEIGHT_DP + rows * HARDWARE_NUMBER_ROW_HEIGHT_DP) * density);
        // Keep the same content budget whether the optional space is shown or hidden.
        int reservedSpace = Math.round((landscape ? 35 : 40) * density);
        return new KeyboardHeight(new KeyboardEdgeGeometry(content, 0), 0,
                bottomSpaceEnabled ? reservedSpace : 0, reservedSpace);
    }

    static int hardwareNumberRowCount(boolean numberRowsEnabled, boolean smartTwoRowsEnabled) {
        return numberRowsEnabled ? 2 : smartTwoRowsEnabled ? 1 : 0;
    }

    static KeyboardHeight floating(float density, boolean showGlobe) {
        int content = Math.round((showGlobe ? HARDWARE_CONTENT_HEIGHT_DP : 1) * density);
        return new KeyboardHeight(new KeyboardEdgeGeometry(content, 0), 0, 0, 0);
    }

    int requestedWindowHeight() {
        return desiredEdges.top() + reservedBottomSpace;
    }

    KeyboardEdgeGeometry measuredEdges(int heightBudget) {
        return fitEdges(heightBudget, reservedBottomSpace);
    }

    int measuredWindowHeight(int heightBudget, KeyboardEdgeGeometry measuredEdges) {
        return Math.min(heightBudget, measuredEdges.top() + visibleBottomSpace);
    }

    KeyboardEdgeGeometry visibleEdges(int actualWindowHeight) {
        return fitEdges(actualWindowHeight, visibleBottomSpace);
    }

    private KeyboardEdgeGeometry fitEdges(int windowHeight, int bottomSpace) {
        return KeyboardEdgeGeometry.fromNative(GuanyinmaNative.nativeFitKeyboardHeight(
                desiredEdges.contentHeight(), desiredEdges.bottom(), windowHeight,
                bottomSpace, minimumContentHeight));
    }

    static int systemBottomOverlap(int top, int bottom, int displayBottom, int navigation,
            int windowBottom, int caption) {
        return Math.max(bottomOverlap(top, bottom, displayBottom, navigation),
                bottomOverlap(top, bottom, windowBottom, caption));
    }

    private static int bottomOverlap(int top, int bottom, int barBottom, int barHeight) {
        return Math.max(0, Math.min(bottom, barBottom) - Math.max(top, barBottom - barHeight));
    }
}
