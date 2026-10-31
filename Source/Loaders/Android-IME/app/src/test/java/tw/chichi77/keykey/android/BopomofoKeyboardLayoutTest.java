package tw.chichi77.keykey.android;

import static org.junit.Assert.*;
import org.junit.Test;

public final class BopomofoKeyboardLayoutTest {
    @Test public void literalAtKeyHasNoPhoneticLabel() {
        assertEquals("", BopomofoKeyboardLayout.symbolForKey('@'));
    }

    @Test public void everyPrintableKeyHasANonNullDisplayLabel() {
        for (char key = ' '; key <= '~'; key++) {
            assertNotNull("Display label for " + key, BopomofoKeyboardLayout.symbolForKey(key));
        }
    }

    @Test public void phoneticKeysAndCaseFoldingKeepTheirPrintedLabels() {
        assertEquals("ㄏ", BopomofoKeyboardLayout.symbolForKey('c'));
        assertEquals("ㄏ", BopomofoKeyboardLayout.symbolForKey('C'));
        assertEquals("ㄨ", BopomofoKeyboardLayout.symbolForKey('j'));
        assertEquals("ˇ", BopomofoKeyboardLayout.symbolForKey('3'));
    }
}
