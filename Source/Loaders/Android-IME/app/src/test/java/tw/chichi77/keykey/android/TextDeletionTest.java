package tw.chichi77.keykey.android;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class TextDeletionTest {
    @Test
    public void deletesOneAsciiCharacter() {
        assertEquals(1, TextDeletion.previousGraphemeLength("abc"));
    }

    @Test
    public void deletesSupplementaryEmojiInOneOperation() {
        assertEquals("😀".length(), TextDeletion.previousGraphemeLength("文字😀"));
    }

    @Test
    public void deletesEmojiVariationAndSkinToneSequences() {
        assertEquals("❤️".length(), TextDeletion.previousGraphemeLength("文字❤️"));
        assertEquals("👍🏻".length(), TextDeletion.previousGraphemeLength("文字👍🏻"));
    }

    @Test
    public void deletesJoinedEmojiAndFlagSequences() {
        assertEquals("👨‍👩".length(), TextDeletion.previousGraphemeLength("文字👨‍👩"));
        assertEquals("🇹🇼".length(), TextDeletion.previousGraphemeLength("文字🇹🇼"));
    }
}
