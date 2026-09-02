package tw.chichi77.keykey.android;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.EnumSet;

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
    public void softBopomofoKeysNeverSelectVisibleCandidates() throws Exception {
        BopomofoEngine engine = engineWith("su3 你\nsu3 擬\n");
        engine.handleSoftKey("s");
        engine.handleSoftKey("u");
        engine.handleSoftKey("3");

        BopomofoEngine.Result result = engine.handleSoftKey("2");

        assertEquals("你", result.committedText());
        assertEquals("ㄉ", engine.readingText());
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
        assertTrue(engine.isShifted());
    }

    @Test
    public void touchShiftInBopomofoOpensLowercaseEnglishLayout() throws Exception {
        BopomofoEngine engine = engineWith("");

        engine.handleSoftKey("SHIFT");

        assertTrue(engine.isEnglishMode());
        assertTrue(engine.isTemporaryEnglish());
        assertTrue(!engine.isShifted());
        assertEquals("q", engine.handleSoftKey("q").committedText());
        assertEquals(BopomofoEngine.InputMode.BOPOMOFO, engine.inputMode());
        assertTrue(!engine.isTemporaryEnglish());
    }

    @Test
    public void backspaceRemovesToneAndKeepsTheRestOfTheReading() throws Exception {
        BopomofoEngine engine = engineWith("su3 你\nsu3 擬\n");
        engine.handleSoftKey("s");
        engine.handleSoftKey("u");
        engine.handleSoftKey("3");

        BopomofoEngine.Result result = engine.backspace();

        assertEquals("ㄋㄧ", engine.readingText());
        assertTrue(engine.displayedCandidates().isEmpty());
        assertTrue(!result.deleteBeforeCursor());
        assertTrue(!result.discardComposingText());
        assertEquals("", result.committedText());
    }

    @Test
    public void backspaceDiscardsTheLastComposingComponent() throws Exception {
        BopomofoEngine engine = engineWith("");
        engine.handleSoftKey("1");

        BopomofoEngine.Result result = engine.backspace();

        assertTrue(engine.readingText().isEmpty());
        assertTrue(result.discardComposingText());
        assertTrue(!result.deleteBeforeCursor());
        assertEquals("", result.committedText());
    }

    @Test
    public void modeKeyCyclesBopomofoEnglishAndNumberLayouts() throws Exception {
        BopomofoEngine engine = engineWith("");

        engine.handleSoftKey("MODE");
        assertEquals(BopomofoEngine.InputMode.ENGLISH, engine.inputMode());
        engine.handleSoftKey("MODE");
        assertEquals(BopomofoEngine.InputMode.NUMBER, engine.inputMode());
        assertEquals("@", engine.handleSoftKey("@").committedText());
        engine.handleSoftKey("MODE");
        assertEquals(BopomofoEngine.InputMode.BOPOMOFO, engine.inputMode());
    }

    @Test
    public void restrictedModeCycleSkipsBopomofo() throws Exception {
        BopomofoEngine engine = engineWith("");
        engine.setAllowedInputModes(
                EnumSet.of(BopomofoEngine.InputMode.ENGLISH, BopomofoEngine.InputMode.NUMBER),
                BopomofoEngine.InputMode.ENGLISH, true);

        assertEquals(BopomofoEngine.InputMode.ENGLISH, engine.inputMode());
        engine.handleSoftKey("MODE");
        assertEquals(BopomofoEngine.InputMode.NUMBER, engine.inputMode());
        engine.handleSoftKey("MODE");
        assertEquals(BopomofoEngine.InputMode.ENGLISH, engine.inputMode());
    }

    @Test
    public void hardwareLanguageShortcutTogglesOnlyBopomofoAndEnglish() throws Exception {
        BopomofoEngine engine = engineWith("");

        engine.toggleHardwareLanguage();
        assertEquals(BopomofoEngine.InputMode.ENGLISH, engine.inputMode());
        assertEquals("a", engine.handleHardwareCharacter('a').committedText());

        engine.toggleHardwareLanguage();
        assertEquals(BopomofoEngine.InputMode.BOPOMOFO, engine.inputMode());

        engine.setAllowedInputModes(EnumSet.of(BopomofoEngine.InputMode.NUMBER),
                BopomofoEngine.InputMode.NUMBER, true);
        engine.toggleHardwareLanguage();
        assertEquals(BopomofoEngine.InputMode.BOPOMOFO, engine.inputMode());
        engine.toggleHardwareLanguage();
        assertEquals(BopomofoEngine.InputMode.ENGLISH, engine.inputMode());
    }

    @Test
    public void hardwareFullWidthConvertsAsciiLikeWindows() throws Exception {
        BopomofoEngine engine = engineWith("");
        engine.toggleHardwareLanguage();
        engine.toggleHardwareWidth();

        assertTrue(engine.isHardwareFullWidth());
        assertEquals("ａ", engine.handleHardwareCharacter('a').committedText());
        assertEquals("Ａ", engine.handleHardwareCharacter('A').committedText());
        assertEquals("！", engine.handleHardwareCharacter('!').committedText());
        assertEquals("　", engine.handleHardwareSpace().committedText());
        assertEquals("é", engine.handleHardwareCharacter('é').committedText());

        engine.toggleHardwareWidth();
        assertEquals("a", engine.handleHardwareCharacter('a').committedText());
    }

    @Test
    public void widthTogglePreservesAnActiveBopomofoReading() throws Exception {
        BopomofoEngine engine = engineWith("");
        engine.handleHardwareCharacter('s');

        engine.toggleHardwareWidth();

        assertTrue(engine.isHardwareFullWidth());
        assertEquals("ㄋ", engine.readingText());
    }

    @Test
    public void fullWidthConverterOnlyChangesPrintableAsciiAndSpace() {
        assertEquals("Ａｚ０９！～　中文é",
                BopomofoEngine.toFullWidth("Az09!~ 中文é"));
    }

    @Test
    public void hardwarePunctuationShortcutsCommitFullWidthMarks() throws Exception {
        BopomofoEngine engine = engineWith("");

        assertEquals("，", engine.commitHardwarePunctuation("，").committedText());
        assertEquals("。", engine.commitHardwarePunctuation("。").committedText());
    }

    @Test
    public void hardwareSymbolShortcutOpensTheTouchSymbolCandidates() throws Exception {
        BopomofoEngine engine = engineWith("");

        engine.showHardwareSymbols();

        assertEquals(List.of("，", "。", "、", "？", "！", "：", "；", "「", "」"),
                engine.displayedCandidates());
        assertEquals(10, engine.pageCount());
    }

    @Test
    public void hardwarePunctuationShortcutPreservesAnActiveReading() throws Exception {
        BopomofoEngine engine = engineWith("");
        engine.handleHardwareCharacter('s');

        BopomofoEngine.Result result = engine.commitHardwarePunctuation("，");

        assertEquals("", result.committedText());
        assertEquals("ㄋ", engine.readingText());
    }

    @Test
    public void symbolKeyOpensFullWidthPunctuationCandidates() throws Exception {
        BopomofoEngine engine = engineWith("");

        engine.handleSoftKey("SYMBOL");

        assertEquals(List.of("，", "。", "、", "？", "！", "：", "；", "「", "」"),
                engine.displayedCandidates());
        assertEquals(10, engine.pageCount());
        engine.changePage(-1);
        assertEquals(List.of("●", "○", "■", "□", "▲", "△", "▼", "▽", "◆"),
                engine.displayedCandidates());
        engine.changePage(1);
        assertEquals("。", engine.selectDisplayedCandidate(1).committedText());
    }

    @Test
    public void numberShiftTogglesASecondDirectSymbolLayout() throws Exception {
        BopomofoEngine engine = engineWith("");
        engine.handleSoftKey("MODE");
        engine.handleSoftKey("MODE");

        engine.handleSoftKey("SHIFT");

        assertEquals(BopomofoEngine.InputMode.NUMBER, engine.inputMode());
        assertTrue(engine.isShifted());
        assertEquals("€", engine.handleSoftKey("€").committedText());
        engine.handleSoftKey("SHIFT");
        assertTrue(!engine.isShifted());
    }

    @Test
    public void emojiKeyOpensTenPagesOfCommonEmoji() throws Exception {
        BopomofoEngine engine = engineWith("");

        engine.handleSoftKey("EMOJI");

        assertEquals(10, engine.pageCount());
        assertEquals(9, engine.displayedCandidates().size());
        assertEquals("😀", engine.displayedCandidates().get(0));

        engine.changePage(-1);
        assertEquals(9, engine.page());
        assertEquals(List.of("🚗", "🚌", "🚆", "✈️", "🚀", "🏠", "🎁", "🎈", "🔔"),
                engine.displayedCandidates());
        assertEquals("🔔", engine.selectDisplayedCandidate(8).committedText());
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

    @Test
    public void highlightedCandidateMovesAcrossPagesAndWraps() throws Exception {
        StringBuilder definitions = new StringBuilder();
        for (int i = 1; i <= 12; i++) definitions.append("su3 候").append(i).append('\n');
        BopomofoEngine engine = engineWith(definitions.toString());
        engine.handleSoftKey("s");
        engine.handleSoftKey("u");
        engine.handleSoftKey("3");

        assertEquals(0, engine.highlightedIndex());
        engine.moveHighlight(-1);
        assertEquals(1, engine.page());
        assertEquals(2, engine.highlightedIndex());
        assertEquals("候12", engine.selectHighlightedCandidate().committedText());
    }

    @Test
    public void pageChangeResetsHighlightToFirstCandidate() throws Exception {
        StringBuilder definitions = new StringBuilder();
        for (int i = 1; i <= 12; i++) definitions.append("su3 候").append(i).append('\n');
        BopomofoEngine engine = engineWith(definitions.toString());
        engine.handleSoftKey("s");
        engine.handleSoftKey("u");
        engine.handleSoftKey("3");

        engine.moveHighlight(3);
        engine.changePage(1);

        assertEquals(1, engine.page());
        assertEquals(0, engine.highlightedIndex());
        assertEquals("候10", engine.enter().committedText());
    }

    @Test
    public void escapeClosesCandidatesAndClearsReading() throws Exception {
        BopomofoEngine engine = engineWith("su3 你\nsu3 擬\n");
        engine.handleSoftKey("s");
        engine.handleSoftKey("u");
        engine.handleSoftKey("3");

        BopomofoEngine.Result result = engine.escape();

        assertTrue(engine.readingText().isEmpty());
        assertTrue(engine.displayedCandidates().isEmpty());
        assertEquals(-1, engine.highlightedIndex());
        assertTrue(result.discardComposingText());
    }

    @Test
    public void selectingCharacterOpensAssociatedPhrasesAndTouchCommitsSuffix() throws Exception {
        BopomofoEngine engine = engineWith("su3 你\nsu3 擬\n");
        engine.setAssociatedPhraseDictionary(AssociatedPhraseDictionary.fromEntries(
                Map.of("你", List.of("好", "們"))));
        engine.handleSoftKey("s");
        engine.handleSoftKey("u");
        engine.handleSoftKey("3");

        BopomofoEngine.Result head = engine.selectDisplayedCandidate(0);

        assertEquals("你", head.committedText());
        assertEquals(List.of("好", "們"), engine.displayedCandidates());
        assertTrue(engine.isShowingAssociatedPhrases());
        assertEquals("們", engine.selectDisplayedCandidate(1).committedText());
        assertTrue(engine.displayedCandidates().isEmpty());
    }

    @Test
    public void enterDismissesAssociatedPhrasesAndRequestsEnter() throws Exception {
        BopomofoEngine engine = engineWith("su3 你\nsu3 擬\n");
        engine.setAssociatedPhraseDictionary(AssociatedPhraseDictionary.fromEntries(
                Map.of("你", List.of("好", "們"))));
        engine.handleSoftKey("s");
        engine.handleSoftKey("u");
        engine.handleSoftKey("3");
        engine.selectDisplayedCandidate(0);

        engine.moveHighlight(1);

        BopomofoEngine.Result result = engine.enter();

        assertEquals("", result.committedText());
        assertTrue(result.sendEnter());
        assertTrue(engine.displayedCandidates().isEmpty());
        assertFalse(engine.isShowingAssociatedPhrases());
    }

    @Test
    public void unshiftedHardwareNumberStartsReadingInsteadOfSelectingAssociatedPhrase()
            throws Exception {
        BopomofoEngine engine = engineWith("su3 你\nsu3 擬\n");
        engine.setAssociatedPhraseDictionary(AssociatedPhraseDictionary.fromEntries(
                Map.of("你", List.of("好", "們"))));
        engine.handleSoftKey("s");
        engine.handleSoftKey("u");
        engine.handleSoftKey("3");
        engine.selectDisplayedCandidate(0);

        BopomofoEngine.Result result = engine.handleHardwareCharacter('2');

        assertEquals("", result.committedText());
        assertEquals("ㄉ", engine.readingText());
        assertTrue(engine.displayedCandidates().isEmpty());
    }

    @Test
    public void newReadingDismissesAssociatedPhrasesWithoutCommittingOne() throws Exception {
        BopomofoEngine engine = engineWith("su3 你\nsu3 擬\n");
        engine.setAssociatedPhraseDictionary(AssociatedPhraseDictionary.fromEntries(
                Map.of("你", List.of("好", "們"))));
        engine.handleSoftKey("s");
        engine.handleSoftKey("u");
        engine.handleSoftKey("3");
        engine.selectDisplayedCandidate(0);

        BopomofoEngine.Result nextReading = engine.handleSoftKey("s");

        assertEquals("", nextReading.committedText());
        assertEquals("ㄋ", engine.readingText());
        assertTrue(engine.displayedCandidates().isEmpty());
    }

    private BopomofoEngine engineWith(String definitions) throws Exception {
        String cin = "%chardef begin\n" + definitions + "%chardef end\n";
        CinDictionary dictionary = CinDictionary.load(new ByteArrayInputStream(
                cin.getBytes(StandardCharsets.UTF_8)));
        return new BopomofoEngine(dictionary);
    }
}
