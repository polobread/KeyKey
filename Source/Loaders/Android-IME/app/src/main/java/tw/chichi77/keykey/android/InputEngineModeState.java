package tw.chichi77.keykey.android;

/** Transferred as data at idle boundaries; never replayed as Shift/key events. */
final class InputEngineModeState {
    final BopomofoEngine.InputMode mode;
    final boolean shifted;
    final boolean temporaryEnglish;
    final boolean hardwareFullWidth;
    InputEngineModeState(BopomofoEngine.InputMode mode, boolean shifted, boolean temporaryEnglish, boolean hardwareFullWidth) {
        this.mode = mode; this.shifted = shifted; this.temporaryEnglish = temporaryEnglish; this.hardwareFullWidth = hardwareFullWidth;
    }
}
