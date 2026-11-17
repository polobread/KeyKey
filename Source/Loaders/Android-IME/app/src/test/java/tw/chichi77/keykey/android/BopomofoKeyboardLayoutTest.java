package tw.chichi77.keykey.android;

import static org.junit.Assert.*;
import org.junit.Test;

public final class BopomofoKeyboardLayoutTest {
    @Test public void literalAtKeyHasNoPhoneticLabel() {
        assertEquals("", BopomofoKeyboardLayout.STANDARD.symbolForKey('@'));
    }

    @Test public void everyPrintableKeyHasANonNullDisplayLabel() {
        for (char key = ' '; key <= '~'; key++) {
            assertNotNull("Display label for " + key, BopomofoKeyboardLayout.STANDARD.symbolForKey(key));
        }
    }

    @Test public void etenPhysicalActionsAndVisibleLabelsStayAligned() {
        var eten = BopomofoKeyboardLayout.ETEN;
        assertEquals("ㄘ", eten.symbolForKey('\''));
        assertEquals("ㄦ", eten.symbolForKey('='));
        assertEquals("ˇ", eten.symbolForKey('3'));
        assertEquals("ㄈ", eten.symbolForKey('F'));
        assertEquals("", eten.symbolForKey('@'));
        assertTrue("倚天 apostrophe is an input key", eten.isPhoneticKey('\''));
        assertTrue("倚天 equals is an input key", eten.isPhoneticKey('='));
        assertFalse(eten.isPhoneticKey('5'));

        var eten26 = BopomofoKeyboardLayout.ETEN26;
        assertEquals("", eten26.symbolForKey('j'));
        assertTrue("倚天 26 鍵 uses a contextual letter for third tone", eten26.isPhoneticKey('j'));
        assertFalse(eten26.isPhoneticKey('3'));
        assertSame(eten, BopomofoKeyboardLayout.fromValue("ETen"));
        assertSame(eten26, BopomofoKeyboardLayout.fromValue("ETen26"));
    }

    @Test public void phoneticKeysAndCaseFoldingKeepTheirPrintedLabels() {
        assertEquals("ㄏ", BopomofoKeyboardLayout.STANDARD.symbolForKey('c'));
        assertEquals("ㄏ", BopomofoKeyboardLayout.STANDARD.symbolForKey('C'));
        assertEquals("ㄨ", BopomofoKeyboardLayout.STANDARD.symbolForKey('j'));
        assertEquals("ˇ", BopomofoKeyboardLayout.STANDARD.symbolForKey('3'));
    }
}
