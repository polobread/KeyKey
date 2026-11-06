package tw.chichi77.keykey.android;

/** System requests outlive view creation and are independent of the opt-in preference. */
final class KeyboardBottomControlsPolicy {
    private boolean customSwitcherRequested;

    void onCustomSwitcherRequested(boolean visible) { customSwitcherRequested = visible; }

    boolean showGlobe(boolean modernSystem) { return modernSystem && customSwitcherRequested; }
}
