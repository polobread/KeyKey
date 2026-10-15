package tw.chichi77.keykey.android;

import static org.junit.Assert.*;
import java.util.ArrayList;
import java.util.List;
import org.junit.Test;

public final class CandidateGlyphSupportTest {
    @Test public void cachesGraphemesAndResetRechecksPreviouslyMissingCharacters() {
        List<String> probes = new ArrayList<>();
        boolean[] supported = {false};
        CandidateGlyphSupport cache = new CandidateGlyphSupport(text -> {
            probes.add(text); return !text.equals("缺") || supported[0];
        });
        assertTrue(cache.canDisplay("你好𠮷e\u0301👩‍💻"));
        assertEquals(List.of("你", "好", "𠮷", "e\u0301", "👩‍💻"), probes);
        assertTrue(cache.canDisplay("你好𠮷e\u0301👩‍💻"));
        assertEquals(5, probes.size());
        assertFalse(cache.canDisplay("缺"));
        supported[0] = true;
        assertFalse(cache.canDisplay("缺"));
        cache.reset();
        assertTrue(cache.canDisplay("缺"));
        assertEquals(7, probes.size());
        assertTrue(new CandidateGlyphSupport(text -> true).canDisplay("缺"));
    }

    @Test public void cacheIsBoundedAndEvictsOldestEntries() {
        int[] probes = {0};
        CandidateGlyphSupport cache = new CandidateGlyphSupport(text -> { probes[0]++; return true; });
        for (int index = 0; index <= 4096; index++) cache.canDisplay(new String(Character.toChars(0x4E00 + index)));
        assertEquals(4097, probes[0]);
        cache.canDisplay("一");
        assertEquals(4098, probes[0]);
    }
}
