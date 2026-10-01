package tw.chichi77.keykey.android;
import static org.junit.Assert.*;
import org.junit.Test;
import org.junit.runner.RunWith;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import android.content.Context;
import java.nio.charset.StandardCharsets;

@RunWith(AndroidJUnit4.class)
public final class TableInputInstrumentedTest {
    @Test public void sharedGoldenCasesUseBundledSQLiteDatabase() throws Exception {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        var learning = context.getSharedPreferences("table_input_test", Context.MODE_PRIVATE);
        learning.edit().clear().commit();
        try (SmartMandarinStore model = SmartMandarinStore.open(context, null);
             var input = instrumentation.getContext().getAssets().open("cases.tsv")) {
            var source = new TableCandidateStore(model.tableDatabase(), learning);
            // Each case gets isolated learning; production preferences are untouched.
            runCases(new String(input.readAllBytes(), StandardCharsets.UTF_8), method -> {
                learning.edit().clear().commit(); return source;
            });
        } finally { learning.edit().clear().commit(); }
    }
    @Test public void learningAndPunctuationPersistWithoutChangingBundledData() throws Exception {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        var learning = context.getSharedPreferences("table_input_test_learning", Context.MODE_PRIVATE);
        learning.edit().clear().commit();
        try (SmartMandarinStore model = SmartMandarinStore.open(context, null)) {
            var source = new TableCandidateStore(model.tableDatabase(), learning);
            var engine = new BopomofoEngine(CinDictionary.empty());
            engine.setTableCandidateSource(source); engine.setChineseInputMethod(ChineseInputMethod.CANGJIE);
            engine.handleHardwareCharacter('a'); engine.space();
            assertEquals("曰", engine.selectDisplayedCandidate(1).committedText());
            var reopened = new TableCandidateStore(model.tableDatabase(), learning);
            assertEquals("曰", reopened.ordered(reopened.values(ChineseInputMethod.CANGJIE, "a", 0), "a").get(0));
            assertEquals(",", reopened.values(ChineseInputMethod.CANGJIE, ",", 2).get(0));
            engine.tableOptions.composeWhileTyping = true;
            engine.handleSoftKey("a"); engine.handleSoftKey("b");
            assertEquals("日月", engine.readingText()); assertEquals("明", engine.displayedCandidates().get(0));
            engine.backspace(); assertEquals("日", engine.readingText());
        } finally { learning.edit().clear().commit(); }
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
