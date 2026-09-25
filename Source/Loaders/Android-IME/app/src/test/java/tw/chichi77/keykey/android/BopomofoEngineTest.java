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
    public void englishShiftChangesLettersAndTrailingPunctuation() throws Exception {
        BopomofoEngine engine = engineWith("");
        engine.handleSoftKey("MODE");
        engine.handleSoftKey("SHIFT");

        assertEquals(BopomofoEngine.InputMode.ENGLISH, engine.inputMode());
        assertTrue(engine.isShifted());
        String[][] rows = BopomofoKeyboardView.shiftedEnglishRows();
        assertEquals(":", rows[2][9]);
        assertEquals("<", rows[3][7]);
        assertEquals(">", rows[3][8]);
        assertEquals("?", rows[3][9]);
        assertEquals(":", engine.handleSoftKey(rows[2][9]).committedText());
        assertEquals("<", engine.handleSoftKey(rows[3][7]).committedText());
        assertEquals(">", engine.handleSoftKey(rows[3][8]).committedText());
        assertEquals("?", engine.handleSoftKey(rows[3][9]).committedText());
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

    @Test
    public void smartModeComposesMultipleReadingsUntilEnter() throws Exception {
        BopomofoEngine engine = smartEngine();

        for (char key : "su3cl3".toCharArray()) {
            assertEquals("", engine.handleSoftKey(String.valueOf(key)).committedText());
        }

        assertEquals("你好", engine.composingText());
    }

    @Test
    public void smartModeEnterCommitsTheWholeCompositionAndSendsEnter() throws Exception {
        BopomofoEngine engine = smartEngine();
        type(engine, "su3cl3");
        TouchSmartHostTextState hostText = new TouchSmartHostTextState();
        hostText.update(engine.completedSmartText(), "");

        BopomofoEngine.Result result = engine.enter();

        assertEquals("你好", result.committedText());
        assertTrue(result.sendEnter());
        assertTrue(hostText.finish(result.committedText()).isEmpty());
        assertFalse(engine.hasComposition());
    }

    @Test
    public void touchSmartEnterKeepsUnfinishedReadingBeforeSendingEnter() throws Exception {
        BopomofoEngine engine = smartEngine();
        type(engine, "su3cl3s");

        BopomofoEngine.Result result = engine.handleSoftKey("ENTER");

        assertEquals("你好ㄋ", result.committedText());
        assertTrue(result.sendEnter());
        assertFalse(engine.hasComposition());
    }

    @Test
    public void touchSmartEnterKeepsPrefixEvictedWhileFinishingLastReading() throws Exception {
        BopomofoReading tonedReading = new BopomofoReading();
        for (char key : "su3".toCharArray()) tonedReading.combine(key);
        String toned = tonedReading.languageModelKey();
        BopomofoReading untunedReading = new BopomofoReading();
        for (char key : "su".toCharArray()) untunedReading.combine(key);
        String untuned = untunedReading.languageModelKey();
        SmartMandarinSource source = new SmartMandarinSource() {
            @Override
            public SmartMandarinComposition compose(List<String> readings,
                                                     Map<Integer, String> overrides) {
                java.util.ArrayList<SmartMandarinSegment> segments = new java.util.ArrayList<>();
                StringBuilder text = new StringBuilder();
                for (int index = 0; index < readings.size(); index++) {
                    String query = readings.get(index);
                    if (!query.equals(toned) && !query.equals(untuned)) return null;
                    String value = overrides.getOrDefault(index,
                            query.equals(toned) ? "你" : "尼");
                    segments.add(new SmartMandarinSegment(index, 1, query, value));
                    text.append(value);
                }
                return new SmartMandarinComposition(text.toString(), List.copyOf(segments));
            }

            @Override
            public List<String> candidates(List<String> readings, int index,
                                           SmartMandarinComposition composition) {
                return List.of();
            }
        };
        BopomofoEngine engine = new BopomofoEngine(CinDictionary.empty(), source,
                BopomofoCompositionMode.SMART);
        type(engine, "su3".repeat(9) + "su");

        BopomofoEngine.Result result = engine.enter();

        assertEquals("你".repeat(9) + "尼", result.committedText());
        assertTrue(result.sendEnter());
        assertFalse(engine.hasComposition());
    }

    @Test
    public void smartModeSwitchCommitsBeforeChangingKeys() throws Exception {
        for (String key : List.of("MODE", "SHIFT", "SYMBOL", "EMOJI")) {
            BopomofoEngine engine = smartEngine();
            type(engine, "su3cl3");
            BopomofoEngine.Result result = engine.handleSoftKey(key);
            assertEquals("你好", result.committedText());
            assertFalse(result.discardComposingText());
            assertFalse(engine.hasComposition());
        }
    }

    @Test
    public void smartModeSwitchPreservesUnfinishedReading() throws Exception {
        BopomofoEngine engine = smartEngine();
        type(engine, "su3cl3s");
        String visible = engine.composingText();
        assertTrue(visible.startsWith("你好"));

        BopomofoEngine.Result result = engine.handleSoftKey("MODE");
        assertEquals(visible, result.committedText());
        assertTrue(engine.isEnglishMode());
        assertFalse(engine.hasComposition());
    }

    @Test
    public void smartSymbolsAndPunctuationPreserveUnfinishedReading() throws Exception {
        BopomofoEngine symbols = smartEngine();
        type(symbols, "su3cl3s");
        String visible = symbols.composingText();
        assertEquals(visible, symbols.handleSoftKey("SYMBOL").committedText());
        assertFalse(symbols.displayedCandidates().isEmpty());

        BopomofoEngine punctuation = smartEngine();
        type(punctuation, "su3cl3s");
        String pending = punctuation.composingText();
        assertEquals(pending + "?", punctuation.handleSoftKey("?").committedText());
    }

    @Test
    public void smartHardwareLanguageAndPunctuationCommitComposition() throws Exception {
        BopomofoEngine engine = smartEngine();
        type(engine, "su3cl3");
        assertEquals("你好", engine.toggleHardwareLanguage().committedText());
        assertTrue(engine.isEnglishMode());

        engine.toggleHardwareLanguage();
        type(engine, "su3cl3");
        assertEquals("你好，", engine.commitHardwarePunctuation("，").committedText());
    }

    @Test
    public void smartOtherKeysCommitComposition() throws Exception {
        BopomofoEngine engine = smartEngine();
        type(engine, "su3cl3");
        assertEquals("你好?", engine.handleSoftKey("?").committedText());

        type(engine, "su3cl3");
        assertEquals("你好", engine.setCompositionMode(
                BopomofoCompositionMode.TRADITIONAL).committedText());
        assertFalse(engine.hasComposition());
    }

    @Test
    public void smartCandidateOverridesLastReadingWithoutCommitting() throws Exception {
        BopomofoEngine engine = smartEngine();
        type(engine, "su3");

        assertTrue(engine.displayedCandidates().isEmpty());
        assertTrue(engine.selectTouchSmartCell(0));

        BopomofoEngine.Result result = engine.selectDisplayedCandidate(1);

        assertEquals("", result.committedText());
        assertEquals("妳", engine.composingText());
        assertTrue(engine.displayedCandidates().isEmpty());
    }

    @Test
    public void touchSmartCorrectionPreservesInsertionPoint() throws Exception {
        BopomofoEngine engine = smartEngine();
        type(engine, "su3cl3su3cl3");
        assertEquals("你好你好", engine.composingText());
        assertTrue(engine.selectTouchSmartCell(2));
        engine.selectDisplayedCandidate(1);
        assertEquals("你好妳好", engine.composingText());
        type(engine, "su3");
        assertEquals("你好妳好你", engine.composingText());
    }

    @Test
    public void touchSmartKeepsNineEditableCellsAndEvictsOneOnTenth() throws Exception {
        BopomofoEngine engine = smartEngine();
        for (int index = 0; index < 9; index++) {
            type(engine, "su3");
        }
        assertEquals(9, engine.touchSmartEditableCount());
        assertEquals(9, engine.touchSmartCells().size());
        assertTrue(engine.displayedCandidates().isEmpty());

        engine.handleSoftKey("s");
        assertEquals("ㄋ", engine.touchSmartCells().get(9));
        assertTrue(engine.selectTouchSmartCell(2));
        assertEquals("", engine.selectDisplayedCandidate(1).committedText());
        assertEquals("妳", engine.touchSmartCells().get(2));
        assertTrue(engine.displayedCandidates().isEmpty());
        engine.backspace();

        BopomofoEngine.Result overflow = BopomofoEngine.Result.update();
        for (char key : "su3".toCharArray()) {
            overflow = engine.handleSoftKey(String.valueOf(key));
        }
        assertEquals("你", overflow.committedText());
        assertEquals(9, engine.touchSmartEditableCount());
        assertEquals("妳", engine.touchSmartCells().get(1));
    }

    @Test
    public void touchSmartKeepsQingJiaTogetherInLongSentence() throws Exception {
        String[] keys = {"fu/3", "ru84", "ul4", "fm4", "s83", "xu3",
                "j06", "sk7", "fm4", "c93", "1u0"};
        String sentence = "請假要去哪裡玩呢去海邊";
        java.util.HashMap<String, String> characters = new java.util.HashMap<>();
        java.util.ArrayList<String> queries = new java.util.ArrayList<>();
        for (int index = 0; index < keys.length; index++) {
            BopomofoReading reading = new BopomofoReading();
            for (char key : keys[index].toCharArray()) reading.combine(key);
            String query = reading.languageModelKey();
            queries.add(query);
            characters.put(query, sentence.substring(index, index + 1));
        }
        SmartMandarinSource source = new SmartMandarinSource() {
            @Override
            public SmartMandarinComposition compose(List<String> readings,
                                                     Map<Integer, String> overrides) {
                java.util.ArrayList<SmartMandarinSegment> segments = new java.util.ArrayList<>();
                int index = 0;
                if (readings.size() >= 2 && readings.get(0).equals(queries.get(0))
                        && readings.get(1).equals(queries.get(1))) {
                    segments.add(new SmartMandarinSegment(0, 2,
                            readings.get(0) + readings.get(1), "請假"));
                    index = 2;
                }
                for (; index < readings.size(); index++) {
                    String character = characters.get(readings.get(index));
                    if (character == null) return null;
                    segments.add(new SmartMandarinSegment(index, 1,
                            readings.get(index), character));
                }
                StringBuilder text = new StringBuilder();
                for (SmartMandarinSegment segment : segments) text.append(segment.text());
                return new SmartMandarinComposition(text.toString(), List.copyOf(segments));
            }

            @Override
            public List<String> candidates(List<String> readings, int index,
                                           SmartMandarinComposition composition) {
                return List.of();
            }
        };
        CinDictionary dictionary = CinDictionary.load(new ByteArrayInputStream(
                "%chardef begin\n%chardef end\n".getBytes(StandardCharsets.UTF_8)));
        BopomofoEngine engine = new BopomofoEngine(dictionary, source,
                BopomofoCompositionMode.SMART);

        StringBuilder committed = new StringBuilder();
        for (int index = 0; index < keys.length; index++) {
            BopomofoEngine.Result result = BopomofoEngine.Result.update();
            for (char key : keys[index].toCharArray()) {
                result = engine.handleSoftKey(String.valueOf(key));
                committed.append(result.committedText());
            }
            if (index == keys.length - 1) {
                result = engine.handleSoftKey("SPACE");
                committed.append(result.committedText());
            }
            if (index < 9) assertEquals("", committed.toString());
            assertEquals(sentence.substring(0, index + 1),
                    committed + engine.composingText());
            if (index == 9) {
                assertEquals("請假", committed.toString());
                assertEquals("要去哪裡玩呢去海", engine.composingText());
            }
        }
        assertEquals("請假要去哪裡玩呢去海邊", committed + engine.composingText());

        BopomofoEngine handoff = new BopomofoEngine(dictionary, source,
                BopomofoCompositionMode.SMART);
        StringBuilder alreadySent = new StringBuilder();
        for (int index = 0; index < 10; index++) {
            for (char key : keys[index].toCharArray()) {
                alreadySent.append(handoff.handleSoftKey(String.valueOf(key)).committedText());
            }
        }
        assertEquals("請假", alreadySent.toString());
        assertEquals("要去哪裡玩呢去海", handoff.composingText());
        String pending = handoff.finishCompositionForInputHandoff().committedText();
        assertEquals("請假要去哪裡玩呢去海", alreadySent + pending);
        assertEquals("", handoff.composingText());
        assertEquals("", handoff.finishCompositionForInputHandoff().committedText());
    }

    @Test
    public void touchSmartKeepsFollowingCharacterWhenContextLeaves() throws Exception {
        BopomofoReading headReading = new BopomofoReading();
        for (char key : "fu/3".toCharArray()) headReading.combine(key);
        BopomofoReading followingReading = new BopomofoReading();
        for (char key : "ru84".toCharArray()) followingReading.combine(key);
        BopomofoReading fillerReading = new BopomofoReading();
        for (char key : "su3".toCharArray()) fillerReading.combine(key);
        String head = headReading.languageModelKey();
        String following = followingReading.languageModelKey();
        String filler = fillerReading.languageModelKey();
        SmartMandarinSource source = new SmartMandarinSource() {
            @Override
            public SmartMandarinComposition compose(List<String> readings,
                                                     Map<Integer, String> overrides) {
                java.util.ArrayList<SmartMandarinSegment> segments = new java.util.ArrayList<>();
                for (int index = 0; index < readings.size(); index++) {
                    String query = readings.get(index);
                    String value;
                    if (query.equals(head)) value = "請";
                    else if (query.equals(following)) {
                        value = index > 0 && readings.get(index - 1).equals(head) ? "假" : "價";
                    } else if (query.equals(filler)) value = "你";
                    else return null;
                    segments.add(new SmartMandarinSegment(index, 1, query,
                            overrides.getOrDefault(index, value)));
                }
                StringBuilder text = new StringBuilder();
                for (SmartMandarinSegment segment : segments) text.append(segment.text());
                return new SmartMandarinComposition(text.toString(), List.copyOf(segments));
            }

            @Override
            public List<String> candidates(List<String> readings, int index,
                                           SmartMandarinComposition composition) {
                return List.of();
            }
        };
        CinDictionary dictionary = CinDictionary.load(new ByteArrayInputStream(
                "%chardef begin\n%chardef end\n".getBytes(StandardCharsets.UTF_8)));
        BopomofoEngine engine = new BopomofoEngine(dictionary, source,
                BopomofoCompositionMode.SMART);
        type(engine, "fu/3ru84");
        for (int index = 0; index < 7; index++) type(engine, "su3");
        assertEquals("請假" + "你".repeat(7), engine.composingText());
        BopomofoEngine.Result overflow = BopomofoEngine.Result.update();
        for (char key : "su3".toCharArray()) {
            overflow = engine.handleSoftKey(String.valueOf(key));
        }
        assertEquals("請", overflow.committedText());
        assertEquals("假" + "你".repeat(8), engine.composingText());
    }

    @Test
    public void smartBackspaceRemovesTheLastCompletedReading() throws Exception {
        BopomofoEngine engine = smartEngine();
        type(engine, "su3cl3");

        BopomofoEngine.Result result = engine.backspace();

        assertEquals("你", engine.composingText());
        assertFalse(result.deleteBeforeCursor());
    }

    @Test
    public void hardwareSmartTypingKeepsComposingUntilEnter() throws Exception {
        BopomofoEngine engine = smartEngine();
        typeHardware(engine, "su3");
        assertEquals("你", engine.composingText());
        assertTrue(engine.displayedCandidates().isEmpty());

        typeHardware(engine, "cl3");
        assertEquals("你好", engine.composingText());
        assertTrue(engine.displayedCandidates().isEmpty());
        assertEquals("你好", engine.enter().committedText());
    }

    @Test
    public void hardwareSmartCursorChangesAnEarlierCharacter() throws Exception {
        BopomofoEngine engine = smartEngine();
        typeHardware(engine, "su3cl3");
        assertEquals(2, engine.smartCompositionCursor());
        assertTrue(engine.moveSmartCompositionCursor(-2));
        assertEquals(0, engine.composingCaretUtf16Offset());
        engine.handleHardwareSpace();
        assertEquals(List.of("你", "妳"), engine.displayedCandidates());
        assertEquals("", engine.selectDisplayedCandidate(1).committedText());
        assertEquals("妳好", engine.composingText());
        assertEquals("妳好", engine.enter().committedText());
    }

    @Test
    public void hardwareSmartSpaceOpensCandidateOnlyWhenRequested() throws Exception {
        BopomofoEngine engine = smartEngine();
        typeHardware(engine, "su3");
        assertTrue(engine.displayedCandidates().isEmpty());
        engine.handleHardwareSpace();
        assertTrue(engine.isShowingSmartCandidates());
        engine.moveHighlight(1);
        assertEquals("", engine.enter().committedText());
        assertEquals("妳", engine.composingText());
        assertEquals("妳", engine.enter().committedText());
    }

    @Test
    public void hardwareSmartCursorCanChooseAWholePhrase() throws Exception {
        String cin = "%chardef begin\nsu3 你\ncl3 好\n%chardef end\n";
        CinDictionary dictionary = CinDictionary.load(new ByteArrayInputStream(
                cin.getBytes(StandardCharsets.UTF_8)));
        SmartMandarinSource source = new SmartMandarinSource() {
            @Override
            public SmartMandarinComposition compose(List<String> readings,
                                                     Map<Integer, String> overrides) {
                return composeSelections(readings, Map.of());
            }

            @Override
            public SmartMandarinComposition composeSelections(
                    List<String> readings, Map<Integer, SmartMandarinSelection> selections) {
                if (readings.size() == 2 && selections.containsKey(0)
                        && selections.get(0).length() == 2) {
                    String text = selections.get(0).text();
                    return new SmartMandarinComposition(text, List.of(
                            new SmartMandarinSegment(0, 2,
                                    readings.get(0) + readings.get(1), text)));
                }
                java.util.ArrayList<SmartMandarinSegment> segments = new java.util.ArrayList<>();
                for (int index = 0; index < readings.size(); index++) {
                    String text = selections.containsKey(index)
                            ? selections.get(index).text() : index == 0 ? "你" : "好";
                    segments.add(new SmartMandarinSegment(index, 1, readings.get(index), text));
                }
                StringBuilder text = new StringBuilder();
                for (SmartMandarinSegment segment : segments) text.append(segment.text());
                return new SmartMandarinComposition(text.toString(), List.copyOf(segments));
            }

            @Override
            public List<String> candidates(List<String> readings, int index,
                                           SmartMandarinComposition composition) {
                return index == 0 ? List.of("你") : List.of("好");
            }

            @Override
            public List<SmartMandarinCandidate> candidateOptions(
                    List<String> readings, int index, SmartMandarinComposition composition) {
                if (index == 0 && readings.size() == 2) {
                    return List.of(new SmartMandarinCandidate(1, "你"),
                            new SmartMandarinCandidate(2, "您好"));
                }
                return SmartMandarinSource.super.candidateOptions(readings, index, composition);
            }
        };
        BopomofoEngine engine = new BopomofoEngine(dictionary, source,
                BopomofoCompositionMode.SMART);
        typeHardware(engine, "su3cl3");
        assertTrue(engine.moveSmartCompositionCursor(-2));
        engine.handleHardwareSpace();
        assertEquals(List.of("你", "您好"), engine.displayedCandidates());
        engine.selectDisplayedCandidate(1);
        assertEquals("您好", engine.composingText());
        assertEquals(2, engine.composingCaretUtf16Offset());
        assertEquals("您好", engine.enter().committedText());
    }

    private BopomofoEngine smartEngine() throws Exception {
        String cin = "%chardef begin\nsu3 你\nsu3 妳\ncl3 好\n%chardef end\n";
        CinDictionary dictionary = CinDictionary.load(new ByteArrayInputStream(
                cin.getBytes(StandardCharsets.UTF_8)));
        BopomofoReading firstReading = new BopomofoReading();
        for (char key : "su3".toCharArray()) firstReading.combine(key);
        String firstQuery = firstReading.languageModelKey();
        BopomofoReading secondReading = new BopomofoReading();
        for (char key : "cl3".toCharArray()) secondReading.combine(key);
        String secondQuery = secondReading.languageModelKey();
        SmartMandarinSource source = new SmartMandarinSource() {
            @Override
            public SmartMandarinComposition compose(List<String> readings,
                                                     Map<Integer, String> overrides) {
                if (readings.stream().anyMatch(query -> !query.equals(firstQuery)
                        && !query.equals(secondQuery))) return null;
                StringBuilder text = new StringBuilder();
                java.util.ArrayList<SmartMandarinSegment> segments = new java.util.ArrayList<>();
                for (int index = 0; index < readings.size(); index++) {
                    String value = overrides.getOrDefault(index,
                            readings.get(index).equals(firstQuery) ? "你" : "好");
                    text.append(value);
                    segments.add(new SmartMandarinSegment(index, 1, readings.get(index), value));
                }
                return new SmartMandarinComposition(text.toString(), List.copyOf(segments));
            }

            @Override
            public List<String> candidates(List<String> readings, int index,
                                           SmartMandarinComposition composition) {
                return readings.get(index).equals(firstQuery)
                        ? List.of("你", "妳") : List.of("好");
            }
        };
        return new BopomofoEngine(dictionary, source, BopomofoCompositionMode.SMART);
    }

    private void type(BopomofoEngine engine, String keys) {
        for (int index = 0; index < keys.length(); index++) {
            engine.handleSoftKey(String.valueOf(keys.charAt(index)));
        }
    }

    private void typeHardware(BopomofoEngine engine, String keys) {
        for (int index = 0; index < keys.length(); index++) {
            engine.handleHardwareCharacter(keys.charAt(index));
        }
    }

    private BopomofoEngine engineWith(String definitions) throws Exception {
        String cin = "%chardef begin\n" + definitions + "%chardef end\n";
        CinDictionary dictionary = CinDictionary.load(new ByteArrayInputStream(
                cin.getBytes(StandardCharsets.UTF_8)));
        return new BopomofoEngine(dictionary);
    }
}
