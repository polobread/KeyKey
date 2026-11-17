package tw.chichi77.keykey.android;

/** Screen-space endpoints measured upward from the keyboard's fixed bottom area. */
record KeyboardEdgeGeometry(int top, int bottom) {
    int contentHeight() {
        return top - bottom;
    }

    KeyboardEdgeGeometry drag(boolean topEdge, int delta, int minContent, int maxContent,
            int maxExtent, int maxBottom) {
        return fromNative(GuanyinmaNative.nativeDragKeyboardEdge(top, bottom, topEdge ? 0 : 1,
                delta, minContent, maxContent, maxExtent, maxBottom));
    }

    static KeyboardEdgeGeometry fromNative(long packed) {
        return new KeyboardEdgeGeometry((int) (packed >>> 32), (int) packed);
    }
}
