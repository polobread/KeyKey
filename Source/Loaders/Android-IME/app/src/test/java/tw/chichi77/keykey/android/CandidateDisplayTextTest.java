package tw.chichi77.keykey.android;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class CandidateDisplayTextTest {
    @Test
    public void keepsUpToThreeVisibleCharacters() {
        assertEquals("你", CandidateDisplayText.elide("你"));
        assertEquals("你們好", CandidateDisplayText.elide("你們好"));
        assertEquals("你們好…", CandidateDisplayText.elide("你們好嗎"));
    }

    @Test
    public void treatsEmojiSequencesAsSingleVisibleCharacters() {
        assertEquals("👨‍👩❤️🇹🇼", CandidateDisplayText.elide("👨‍👩❤️🇹🇼"));
        assertEquals("👨‍👩❤️🇹🇼…", CandidateDisplayText.elide("👨‍👩❤️🇹🇼好"));
        assertEquals("👍🏻好", CandidateDisplayText.elide("👍🏻好"));
    }

    @Test
    public void handlesNullAndEmptyText() {
        assertEquals("", CandidateDisplayText.elide(null));
        assertEquals("", CandidateDisplayText.elide(""));
    }
}
