package tw.chichi77.keykey.android;
import static org.junit.Assert.*;
import org.junit.Test;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;

public final class TableInputTest {
    private static final class Source implements TableCandidateSource {
        private final CinDictionary dictionary;
        private final Map<String, String> names = new HashMap<>();
        private String endKeys = "";
        Source(Path path) throws Exception {
            dictionary = CinDictionary.load(Files.newInputStream(path));
            boolean inNames = false;
            for (String line : Files.readAllLines(path)) {
                String row = line.trim();
                if (row.startsWith("%endkey ")) endKeys = row.substring(8).trim();
                if (row.equals("%keyname begin")) { inNames = true; continue; }
                if (row.equals("%keyname end")) { inNames = false; continue; }
                if (inNames) {
                    String[] fields = row.split("\\s+", 2);
                    if (fields.length == 2) names.put(fields[0], fields[1]);
                }
            }
        }
        public List<String> values(ChineseInputMethod method, String code, int punctuation) {
            if (method == ChineseInputMethod.CANGJIE && code.length() > 1 && (code.contains("?") || code.contains("*"))) {
                StringBuilder pattern = new StringBuilder();
                for (char c : code.toCharArray()) pattern.append(c == '?' ? "." : c == '*' ? ".*" : java.util.regex.Pattern.quote(String.valueOf(c)));
                List<String> result = new ArrayList<>();
                for (String key : dictionary.keys()) if (key.matches(pattern.toString())) result.addAll(dictionary.candidates(key));
                return result;
            }
            return dictionary.candidates(code);
        }
        public String keyName(ChineseInputMethod method, String key) { return names.get(key); }
        public String endKeys(ChineseInputMethod method) { return endKeys; }
    }
    @Test public void sharedMacOSGoldenCasesWithRealCinTables() throws Exception {
        Path root = Path.of(System.getProperty("keykey.smart.database"));
        for (int i = 0; i < 5; i++) root = root.getParent();
        Source cangjie = new Source(root.resolve("Source/DataTables/cj-ext.cin"));
        Source simplex = new Source(root.resolve("Source/DataTables/simplex-ext.cin"));
        runCases(Files.readString(root.resolve("tests/fixtures/mobile-table-input/cases.tsv")),
                method -> method == ChineseInputMethod.CANGJIE ? cangjie : simplex);
    }
    @Test public void defaultsAndRootCaptionsMatchMacOS() {
        var cangjie = new TableInputOptions(ChineseInputMethod.CANGJIE);
        assertTrue(cangjie.dynamicFrequency); assertTrue(cangjie.clearOnError); assertFalse(cangjie.queryAtMaximum);
        var simplex = new TableInputOptions(ChineseInputMethod.SIMPLEX);
        assertFalse(simplex.dynamicFrequency); assertFalse(simplex.clearOnError); assertTrue(simplex.queryAtMaximum);
        assertEquals("日", ChineseInputMethod.root("a")); assertEquals("重", ChineseInputMethod.root("z"));
    }
    private void runCases(String text, java.util.function.Function<ChineseInputMethod, TableCandidateSource> sources) {
        for (String line : text.split("\\n")) {
            if (line.startsWith("#") || line.isBlank()) continue;
            String[] f = line.split("\\t", -1);
            ChineseInputMethod method = ChineseInputMethod.valueOf(f[1].toUpperCase(java.util.Locale.ROOT));
            BopomofoEngine engine = new BopomofoEngine(CinDictionary.empty());
            engine.setTableCandidateSource(sources.apply(method));
            engine.setChineseInputMethod(method);
            StringBuilder committed = new StringBuilder();
            for (String token : f[2].split(" ")) {
                switch (token) {
                    case "SPACE" -> committed.append(engine.space().committedText());
                    case "ENTER" -> committed.append(engine.enter().committedText());
                    case "BACKSPACE" -> committed.append(engine.backspace().committedText());
                    case "ESCAPE" -> committed.append(engine.escape().committedText());
                    case "DOWN" -> engine.moveHighlight(1);
                    case "PAGE" -> engine.changePage(1);
                    case "ENGLISH" -> committed.append(engine.toggleHardwareLanguage().committedText());
                    case "HANDOFF" -> committed.append(engine.finishCompositionForInputHandoff().committedText());
                    case "SOFT_COMMA" -> committed.append(engine.handleSoftKey("，").committedText());
                    case "SYMBOL", "EMOJI" -> committed.append(engine.handleSoftKey(token).committedText());
                    case "REALTIME" -> engine.tableOptions.composeWhileTyping = true;
                    default -> {
                        for (char key : token.toCharArray()) committed.append(engine.handleHardwareCharacter(key).committedText());
                    }
                }
            }
            assertEquals(f[0] + ": committed", f[3].equals("-") ? "" : f[3], committed.toString());
            assertEquals(f[0] + ": reading", f[4].equals("-") ? "" : f[4], engine.readingText());
            assertEquals(f[0] + ": candidates", f[5].equals("-") ? null : f[5],
                    engine.displayedCandidates().isEmpty() ? null : engine.displayedCandidates().get(0));
        }
    }
}
