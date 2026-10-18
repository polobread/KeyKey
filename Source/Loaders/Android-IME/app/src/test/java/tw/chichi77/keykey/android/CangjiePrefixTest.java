package tw.chichi77.keykey.android;

import static org.junit.Assert.*;
import org.junit.Test;
import java.nio.file.Path;
import java.util.*;

public final class CangjiePrefixTest {
    private BopomofoEngine engine() throws Exception {
        Path root = Path.of(System.getProperty("keykey.smart.database"));
        for (int i = 0; i < 5; i++) root = root.getParent();
        var engine = new BopomofoEngine(CinDictionary.empty());
        engine.setTableCandidateSource(new TableInputTest.Source(root.resolve("Source/DataTables/cj-ext.cin")));
        engine.setChineseInputMethod(ChineseInputMethod.CANGJIE);
        engine.tableOptions.prefixCandidates = true;
        engine.tableOptions.composeWhileTyping = true;
        return engine;
    }
    private List<String> all(BopomofoEngine engine) {
        var values = new ArrayList<String>();
        for (int i = 0; i < engine.pageCount(); i++) {
            values.addAll(engine.displayedCandidates());
            engine.changePage(1);
        }
        return values;
    }
    @Test public void qiaoEveryRootBackspaceAndExplicitCommit() throws Exception {
        var engine = engine();
        engine.tableOptions.queryAtMaximum = true;
        String[] roots = {"竹", "竹大", "竹大口", "竹大口月", "竹大口月口"};
        for (int i = 0; i < 5; i++) {
            assertEquals("", engine.handleSoftKey("hkrbr".substring(i, i + 1)).committedText());
            assertEquals(roots[i], engine.readingText());
            var values = all(engine);
            assertEquals(values.size(), new HashSet<>(values).size());
            if (i == 0) assertFalse(values.contains("喬"));
            else assertTrue(values.indexOf("喬") >= 0 && values.indexOf("喬") < 9);
        }
        assertEquals(List.of("喬"), all(engine));
        engine.backspace();
        assertEquals(List.of("喬", "䀉"), all(engine));
        assertEquals("喬", engine.enter().committedText());
        assertFalse(engine.hasComposition());
    }
    @Test public void physicalPreviewsHonorAllFourOptionCombinations() throws Exception {
        for (boolean realtime : new boolean[]{false, true}) {
            for (boolean prefix : new boolean[]{false, true}) {
                var engine = engine();
                engine.tableOptions.composeWhileTyping = realtime;
                engine.tableOptions.prefixCandidates = prefix;
                for (char key : "hk".toCharArray())
                    assertEquals("", engine.handleHardwareCharacter(key).committedText());
                assertEquals("竹大", engine.readingText());
                assertEquals(!realtime, engine.displayedCandidates().isEmpty());
                assertEquals(realtime && prefix, engine.displayedCandidates().contains("喬"));
                if (realtime && prefix) {
                    assertEquals("夭", engine.displayedCandidates().get(0));
                    assertEquals("喬", engine.selectDisplayedCandidate(
                            engine.displayedCandidates().indexOf("喬")).committedText());
                } else if (realtime) {
                    assertEquals("夭", engine.handleHardwareSpace().committedText());
                    assertEquals("", engine.readingText());
                } else {
                    assertEquals("", engine.handleHardwareSpace().committedText());
                    assertFalse(engine.displayedCandidates().isEmpty());
                    assertFalse(all(engine).contains("喬"));
                }
            }
        }
    }

    @Test public void physicalFifthRootDoesNotCommitAndBackspaceRefreshes() throws Exception {
        var engine = engine();
        engine.tableOptions.queryAtMaximum = true;
        for (int i = 0; i < 5; i++) {
            assertEquals("", engine.handleHardwareCharacter("hkrbr".charAt(i)).committedText());
            assertEquals(i > 0, engine.displayedCandidates().contains("喬"));
            if (i == 1) { engine.changePage(1); assertFalse(engine.displayedCandidates().contains("喬")); }
        }
        assertEquals("竹大口月口", engine.readingText());
        assertEquals(List.of("喬"), engine.displayedCandidates());
        engine.backspace();
        assertEquals(List.of("喬", "䀉"), engine.displayedCandidates());
        assertEquals("喬", engine.enter().committedText());
        assertFalse(engine.hasComposition());
    }

    @Test public void prefixDoesNotAffectWildcardOrSimplex() throws Exception {
        var engine = engine();
        for (char key : "hk?".toCharArray()) engine.handleSoftKey(String.valueOf(key));
        var wildcard = all(engine);
        assertTrue(wildcard.size() > 36);
        assertFalse(wildcard.contains("喬"));
        engine.escape();
        engine.tableOptions.prefixCandidates = false;
        engine.tableOptions.composeWhileTyping = true;
        for (char key : "hk?".toCharArray()) engine.handleSoftKey(String.valueOf(key));
        assertEquals(wildcard, all(engine));
    }
    @Test public void rankedValuesAfterRow100AndGlyphRefill() {
        var selection = new CangjiePrefixSelection(List.of("是"));
        for (int i = 0; i < 100; i++) selection.consider("候選" + i, s -> true);
        selection.consider("的", s -> true);
        selection.consider("是", s -> true);
        selection.consider("的", s -> true);
        assertEquals(36, selection.values().size());
        assertEquals("的", selection.values().get(0));
        assertEquals("候選34", selection.values().get(35));
        assertFalse(selection.values().contains("是"));
        var visible = new CangjiePrefixSelection(List.of());
        for (int i = 0; i < 40; i++) visible.consider("缺字" + i, s -> false);
        for (int i = 0; i < 40; i++) visible.consider("可見" + i, s -> true);
        assertEquals(36, visible.values().size());
        assertEquals("可見35", visible.values().get(35));
        var equivalent = new CangjiePrefixSelection(List.of());
        equivalent.consider("豈", s -> false);
        equivalent.consider("豈", s -> true);
        equivalent.consider("豈", s -> true);
        equivalent.consider("，", s -> true);
        equivalent.consider("★", s -> true);
        assertEquals(List.of("豈"), equivalent.values());
        assertEquals(1500, CangjieCommonRanking.RANKS.size());
        assertEquals(Integer.valueOf(1215), CangjieCommonRanking.RANKS.get("喬"));
        assertFalse(CangjiePrefixSelection.isPrefixCode("h?"));
        assertFalse(CangjiePrefixSelection.isPrefixCode("hkrbr"));
    }
}
