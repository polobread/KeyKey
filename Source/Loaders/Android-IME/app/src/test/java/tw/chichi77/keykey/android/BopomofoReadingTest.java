package tw.chichi77.keykey.android;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class BopomofoReadingTest {
    @Test
    public void canonicalizesComponentsEnteredOutOfOrder() {
        BopomofoReading reading = new BopomofoReading();

        assertTrue(reading.combine('3'));
        assertTrue(reading.combine('u'));
        assertTrue(reading.combine('s'));

        assertEquals("su3", reading.queryKey());
        assertEquals("ㄋㄧˇ", reading.displayText());
        assertTrue(reading.hasTone());
    }

    @Test
    public void replacesComponentsOfTheSameKind() {
        BopomofoReading reading = new BopomofoReading();
        reading.combine('1');
        reading.combine('q');
        reading.combine('8');
        reading.combine('9');

        assertEquals("q9", reading.queryKey());
        assertEquals("ㄆㄞ", reading.displayText());
    }

    @Test
    public void backspaceUsesCanonicalComponentOrder() {
        BopomofoReading reading = new BopomofoReading();
        reading.combine('s');
        reading.combine('u');
        reading.combine('3');

        reading.backspace();
        assertEquals("su", reading.queryKey());
        reading.backspace();
        assertEquals("s", reading.queryKey());
        reading.backspace();
        assertTrue(reading.isEmpty());
        assertFalse(reading.hasTone());
    }
}
