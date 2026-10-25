// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
package tw.chichi77.keykey.android;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;
import org.junit.Test;

public final class UserPhraseArchiveTest {
    @Test public void importsOnlyExplicitPhraseSectionAndKeepsFiniteScores() {
        UserPhraseArchive.Parsed parsed = UserPhraseArchive.parse("MJSR version 1.0.0\n"
                + "你好\tsu3,cl3\t-2.5\t0.2\n"
                + "你好\tsu3 cl3\t1\t0\n"
                + "妳\tsu3\tNaN\tInfinity\n"
                + "bad row\n"
                + "<database>encrypted learning\n"
                + "好\tcl3\t1\t0\n");
        assertEquals(2, parsed.rows().size());
        assertEquals(2, parsed.skipped());
        assertEquals(-2.5, parsed.rows().get(0).probability(), 0);
        assertEquals(-1, parsed.rows().get(1).probability(), 0);
        assertEquals(0, parsed.rows().get(1).backoff(), 0);
        UserPhraseArchive.Parsed roundTrip = UserPhraseArchive.parse(UserPhraseArchive.export(parsed.rows()));
        assertEquals(parsed.rows(), roundTrip.rows());
    }
    @Test public void invalidFormatAndReadingCannotBecomeAnImport() {
        assertThrows(IllegalArgumentException.class, () -> UserPhraseArchive.parse("not a phrase archive"));
        UserPhraseArchive.Parsed parsed = UserPhraseArchive.parse("MJSR version 1.0.0\n"
                + "你好\tsu3\n" + "你 好\tsu3 cl3\n" + "你\t???\n");
        assertEquals(0, parsed.rows().size());
        assertEquals(3, parsed.skipped());
    }
}
