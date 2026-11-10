package tw.chichi77.keykey.android;

/** Screen-space endpoints measured upward from the keyboard's fixed bottom area. */
record KeyboardEdgeGeometry(int top, int bottom) {
    int contentHeight() {
        return top - bottom;
    }

    KeyboardEdgeGeometry drag(boolean topEdge, int delta, int minContent, int maxContent,
            int maxExtent, int maxBottom) {
        if (topEdge) {
            int minTop = bottom + minContent;
            int maxTop = Math.min(maxExtent, bottom + maxContent);
            return new KeyboardEdgeGeometry(Math.max(minTop, Math.min(maxTop, top + delta)), bottom);
        }
        int minBottom = Math.max(0, top - maxContent);
        int maxGap = Math.min(maxBottom, top - minContent);
        return new KeyboardEdgeGeometry(top, Math.max(minBottom, Math.min(maxGap, bottom + delta)));
    }
}
