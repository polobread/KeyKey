package tw.chichi77.keykey.android;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;

import org.junit.Test;

public final class BopomofoEngineTest {
    @Test
    public void toneOpensCandidatesAndHardwareNumberSelects() throws Exception {
        BopomofoEngine engine = engineWith("su3 你\nsu3 擬\n");

        engine.handleSoftKey("s");
        engine.handleSoftKey("u");
        BopomofoEngine.Result result = engine.handleSoftKey("3");

        assertEquals("", result.committedText());
        assertEquals("ㄋㄧˇ", engine.readingText());
        assertEquals(List.of("你", "擬"), engine.displayedCandidates());

        result = engine.handleHardwareCharacter('2');
        assertEquals("擬", result.committedText());
        assertTrue(engine.readingText().isEmpty());
    }

    @Test
    public void softNumberKeysSelectOnlyWhileCandidatesAreVisible() throws Exception {
        BopomofoEngine engine = engineWith("su3 你\nsu3 擬\n");
        engine.handleSoftKey("s");
        engine.handleSoftKey("u");
        engine.handleSoftKey("3");

        BopomofoEngine.Result result = engine.handleSoftKey("2");

        assertEquals("擬", result.committedText());
        assertTrue(engine.readingText().isEmpty());

        result = engine.handleSoftKey("1");
        assertEquals("", result.committedText());
        assertEquals("ㄅ", engine.readingText());
    }

    @Test
    public void singleCandidateCommitsImmediately() throws Exception {
        BopomofoEngine engine = engineWith("su3 你\n");
        engine.handleSoftKey("s");
        engine.handleSoftKey("u");

        BopomofoEngine.Result result = engine.handleSoftKey("3");

        assertEquals("你", result.committedText());
        assertTrue(engine.readingText().isEmpty());
    }

    @Test
    public void languageKeySwitchesToDirectEnglishInput() throws Exception {
        BopomofoEngine engine = engineWith("");
        engine.handleSoftKey("MODE");
        engine.handleSoftKey("SHIFT");

        BopomofoEngine.Result result = engine.handleSoftKey("a");

        assertEquals("A", result.committedText());
        assertTrue(engine.isEnglishMode());
    }

    @Test
    public void symbolKeyOpensFullWidthPunctuationCandidates() throws Exception {
        BopomofoEngine engine = engineWith("");

        engine.handleSoftKey("SYMBOL");

        assertEquals(List.of("，", "。", "、", "？", "！", "：", "；", "「", "」"),
                engine.displayedCandidates());
        assertEquals(2, engine.pageCount());
        assertEquals("。", engine.selectDisplayedCandidate(1).committedText());
    }

    @Test
    public void emojiKeyOpensFivePagesOfCommonEmoji() throws Exception {
        BopomofoEngine engine = engineWith("");

        engine.handleSoftKey("EMOJI");

        assertEquals(5, engine.pageCount());
        assertEquals(9, engine.displayedCandidates().size());
        assertEquals("😀", engine.displayedCandidates().get(0));

        engine.changePage(-1);
        assertEquals(4, engine.page());
        assertEquals(List.of("❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "💯", "🎉"),
                engine.displayedCandidates());
        assertEquals("🎉", engine.handleSoftKey("9").committedText());
    }

    @Test
    public void spaceAndPageControlsCycleCandidatePages() throws Exception {
        StringBuilder definitions = new StringBuilder();
        for (int i = 1; i <= 21; i++) definitions.append("su3 候").append(i).append('\n');
        BopomofoEngine engine = engineWith(definitions.toString());
        engine.handleSoftKey("s");
        engine.handleSoftKey("u");
        engine.handleSoftKey("3");

        assertEquals(0, engine.page());
        assertEquals("候1", engine.displayedCandidates().get(0));
        assertEquals(9, engine.displayedCandidates().size());

        assertEquals("", engine.space().committedText());
        assertEquals(1, engine.page());
        assertEquals("候10", engine.displayedCandidates().get(0));

        engine.changePage(1);
        assertEquals(2, engine.page());
        assertEquals(List.of("候19", "候20", "候21"), engine.displayedCandidates());

        engine.space();
        assertEquals(0, engine.page());
        engine.changePage(-1);
        assertEquals(2, engine.page());
    }

    private BopomofoEngine engineWith(String definitions) throws Exception {
        String cin = "%chardef begin\n" + definitions + "%chardef end\n";
        CinDictionary dictionary = CinDictionary.load(new ByteArrayInputStream(
                cin.getBytes(StandardCharsets.UTF_8)));
        return new BopomofoEngine(dictionary);
    }
}
