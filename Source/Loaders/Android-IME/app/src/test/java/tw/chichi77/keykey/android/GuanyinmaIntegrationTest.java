package tw.chichi77.keykey.android;

import static org.junit.Assert.*;
import org.junit.Assume;
import org.junit.Before;
import org.junit.Test;
import org.json.JSONObject;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;
import java.util.function.Predicate;

/** A small real-JNI adapter suite. Full algorithm coverage belongs to core CI. */
public final class GuanyinmaIntegrationTest {
    @Before public void requireExplicitHostJNIHarness() {
        Assume.assumeTrue("Run through the Guanyinma host JNI integration harness",
                Boolean.getBoolean("keykey.guanyinma.integration"));
    }
    private static final class Fixture implements AutoCloseable {
        final Path directory = Files.createTempDirectory("KeyKey-Android-JNI-");
        final String model = System.getProperty("keykey.smart.database");
        final Path user = directory.resolve("Rust 使用者 資料.db");
        Fixture() throws Exception { assertNotNull(model); assertTrue(Files.isRegularFile(Path.of(model))); }
        GuanyinmaInputEngine engine(ChineseInputMethod method, Predicate<String> filter) {
            return new GuanyinmaInputEngine(model, user.toString(), method, BopomofoKeyboardLayout.STANDARD,
                    new TableInputOptions(method), false, true, false, filter);
        }
        HostInputEngine facade() {
            return new HostInputEngine(model, user.toString(), ChineseInputMethod.TRADITIONAL,
                    BopomofoKeyboardLayout.STANDARD, new TableInputOptions(ChineseInputMethod.TRADITIONAL),
                    false, true, text -> true);
        }
        @Override public void close() throws Exception {
            try (var paths = Files.walk(directory)) {
                for (Path path : paths.sorted(Comparator.reverseOrder()).toList()) Files.deleteIfExists(path);
            }
        }
    }
    private static void type(InputEngine engine, String text, boolean hardware) {
        for (char value : text.toCharArray()) {
            if (hardware) engine.handleHardwareCharacter(value); else engine.handleSoftKey(String.valueOf(value));
        }
    }
    @Test public void realJNIMapsTouchSnapshotAndOneShotHostEffects() throws Exception {
        try (Fixture fixture = new Fixture(); GuanyinmaInputEngine engine = fixture.engine(ChineseInputMethod.SMART, text -> true)) {
            type(engine, "su3cl3", false);
            assertNull(engine.lastError()); assertEquals("你好", engine.completedSmartText());
            assertEquals(List.of("你", "好"), engine.touchSmartCells());
            InputEngine.Result entered = engine.enter();
            assertEquals("你好", entered.committedText()); assertTrue(entered.sendEnter());
            assertFalse(engine.hasComposition()); assertEquals("", engine.finishCompositionForInputHandoff().committedText());
            assertTrue(engine.backspace().deleteBeforeCursor()); assertTrue(Files.isRegularFile(fixture.user));
        }
    }
    @Test public void fourMethodsShareOneJNIAdapter() throws Exception {
        try (Fixture fixture = new Fixture()) {
            for (ChineseInputMethod method : ChineseInputMethod.values()) {
                try (GuanyinmaInputEngine engine = fixture.engine(method, text -> true)) {
                    engine.setHardwareSmartEditing(true);
                    if (method == ChineseInputMethod.SMART) { type(engine, "su3cl3", true); assertEquals("你好", engine.completedSmartText()); }
                    else if (method == ChineseInputMethod.TRADITIONAL) { type(engine, "su3", true); assertFalse(engine.displayedCandidates().isEmpty()); }
                    else { type(engine, "a", true); engine.handleHardwareSpace(); assertTrue(!engine.displayedCandidates().isEmpty() || !engine.hasComposition()); }
                    assertNull(engine.lastError()); assertEquals(method, engine.chineseInputMethod());
                }
            }
        }
    }
    @Test public void hostEffectsBlockNewEventsUntilOriginalConnectionAcknowledges() throws Exception {
        try (Fixture fixture = new Fixture(); HostInputEngine engine = fixture.facade()) {
            type(engine, "su3", false);
            assertFalse(engine.displayedCandidates().isEmpty());
            String expected = engine.displayedCandidates().get(0);
            assertEquals(expected, engine.selectDisplayedCandidate(0).committedText());
            assertEquals("", engine.handleSoftKey("s").committedText());
            assertNotNull(engine.coreError()); assertFalse(engine.hasComposition());
            engine.acknowledgeHostEffects();
            assertEquals("", engine.handleSoftKey("s").committedText());
            assertEquals("ㄋ", engine.readingText()); assertNull(engine.coreError());
        }
    }
    @Test public void newHostAbandonsUnacknowledgedEffectsWithoutReplay() throws Exception {
        try (Fixture fixture = new Fixture(); HostInputEngine engine = fixture.facade()) {
            engine.handleSoftKey("SHIFT"); assertEquals("a", engine.handleSoftKey("a").committedText());
            engine.abandonHostEffects();
            assertFalse(engine.hasComposition());
            assertEquals("", engine.finishCompositionForInputHandoff().committedText());
            assertEquals("", engine.handleSoftKey("s").committedText()); assertEquals("ㄋ", engine.readingText());
            engine.close(); engine.close();
            assertThrows(IllegalStateException.class, () -> engine.handleSoftKey("a"));
        }
    }
    @Test public void modeAndWidthRemainFrontendStateAcrossHostChanges() throws Exception {
        try (Fixture fixture = new Fixture(); HostInputEngine engine = fixture.facade()) {
            engine.toggleHardwareWidth(); engine.handleSoftKey("SHIFT");
            assertTrue(engine.isTemporaryEnglish()); assertTrue(engine.isHardwareFullWidth());
            engine.abandonHostEffects();
            assertTrue(engine.isTemporaryEnglish()); assertTrue(engine.isHardwareFullWidth());
            assertEquals("a", engine.handleSoftKey("a").committedText());
            assertEquals(InputEngine.InputMode.BOPOMOFO, engine.inputMode());
            engine.acknowledgeHostEffects(); assertEquals("１", engine.commitHardwareLiteral('1').committedText());
        }
    }
    @Test public void temporaryEnglishModeKeyLocksEnglishAndProfilesMapExplicitly() throws Exception {
        try (Fixture fixture = new Fixture(); GuanyinmaInputEngine engine = fixture.engine(ChineseInputMethod.SMART, text -> true)) {
            engine.handleSoftKey("SHIFT"); engine.handleSoftKey("MODE");
            assertEquals(InputEngine.InputMode.ENGLISH, engine.inputMode()); assertFalse(engine.isTemporaryEnglish());
            assertEquals("a", engine.handleSoftKey("a").committedText()); assertEquals(InputEngine.InputMode.ENGLISH, engine.inputMode());
            engine.toggleHardwareLanguage(); engine.setHardwareSmartEditing(false); type(engine, "su3cl3", false);
            assertTrue(engine.isTouchSmartComposition()); assertEquals(-1, engine.smartCompositionCursor());
            engine.setHardwareTouchSmartEditing(false); engine.prepareForHardwareInput();
            assertFalse(engine.isTouchSmartComposition()); assertTrue(engine.smartCompositionCursor() >= 0);
            engine.setHardwareTouchSmartEditing(true); engine.prepareForHardwareInput();
            assertTrue(engine.isTouchSmartComposition()); assertEquals("你好", engine.completedSmartText());
            engine.setUseBigrams(false);
            JSONObject state = new JSONObject(engine.snapshotJSON());
            assertEquals("touch", state.getString("profile"));
            assertFalse(state.getJSONObject("smart_options").getBoolean("use_bigrams"));
            assertFalse(state.getJSONObject("learning").getBoolean("bigrams"));
            assertTrue(state.getJSONObject("smart_options").getBoolean("shift_at_limit"));
        }
    }
    @Test public void nativeGlyphFilteringKeepsDisplayedSelectionIndices() throws Exception {
        try (Fixture fixture = new Fixture(); GuanyinmaInputEngine engine = fixture.engine(ChineseInputMethod.CANGJIE, text -> !text.equals("夭"))) {
            TableInputOptions options = new TableInputOptions(ChineseInputMethod.CANGJIE);
            options.composeWhileTyping = true; options.prefixCandidates = true;
            engine.setTableOptions(options); type(engine, "hk", false);
            assertNull(engine.lastError()); assertFalse(engine.displayedCandidates().isEmpty()); assertFalse(engine.displayedCandidates().contains("夭"));
            String selected = engine.displayedCandidates().get(0); assertEquals(selected, engine.selectDisplayedCandidate(0).committedText());
        }
    }
    @Test public void independentRustStoreAndResetNeverImportOrOverwriteJavaData() throws Exception {
        try (Fixture fixture = new Fixture()) {
            Path legacy = fixture.directory.resolve("UserPhrase.db"); byte[] original = "Java source remains untouched".getBytes(StandardCharsets.UTF_8); Files.write(legacy, original);
            try (GuanyinmaNative session = GuanyinmaNative.open(fixture.model,
                    new JSONObject().put("user_database", fixture.user.toString()).toString(), text -> true)) {
                session.apply(new JSONObject().put("type", "add_user_phrase").put("qstring", "0_0_").put("text", "士事").toString());
                assertEquals(1, new JSONObject(session.userData()).getJSONObject("data").getJSONArray("phrases").length());
                GuanyinmaInputEngine.resetLearning(fixture.model, fixture.user.toString());
                assertEquals(1, new JSONObject(session.userData()).getJSONObject("data").getJSONArray("phrases").length());
            }
            assertArrayEquals(original, Files.readAllBytes(legacy));
        }
    }
    @Test public void missingRustModelFailsWithoutCreatingAnotherEngineOrUserData() throws Exception {
        try (Fixture fixture = new Fixture()) {
            assertThrows(RuntimeException.class, () -> new HostInputEngine(
                    fixture.directory.resolve("missing.db").toString(), fixture.user.toString(),
                    ChineseInputMethod.SMART, BopomofoKeyboardLayout.STANDARD,
                    new TableInputOptions(ChineseInputMethod.SMART), false, true, text -> true));
            assertFalse(Files.exists(fixture.user));
        }
    }
    @Test public void fatalNativeFailureCannotReplayStateAtNewHostBoundary() throws Exception {
        try (Fixture fixture = new Fixture()) {
            boolean[] fail = {false};
            try (HostInputEngine engine = new HostInputEngine(fixture.model, fixture.user.toString(),
                    ChineseInputMethod.SMART, BopomofoKeyboardLayout.STANDARD,
                    new TableInputOptions(ChineseInputMethod.SMART), false, true, text -> {
                        if (fail[0]) throw new IllegalStateException("font service failed");
                        return true;
                    })) {
                type(engine, "su", false); assertEquals("ㄋㄧ", engine.readingText());
                fail[0] = true;
                assertEquals("", engine.handleSoftKey("3").committedText());
                assertNotNull(engine.coreError());
                // The service closes a session when this boundary cannot reset;
                // it must never receive a successful result carrying old text.
                assertThrows(IllegalStateException.class, engine::abandonHostEffects);
            }
        }
    }
    @Test public void sqliteWriterFailurePreservesReadingCandidatesAndErrorUntilSuccessfulRetry() throws Exception {
        String python = System.getProperty("keykey.guanyinma.python"); Assume.assumeNotNull(python);
        try (Fixture fixture = new Fixture(); GuanyinmaInputEngine engine = fixture.engine(ChineseInputMethod.CANGJIE, text -> true)) {
            type(engine, "hk", true); engine.handleHardwareSpace(); assertTrue(engine.displayedCandidates().size() > 1); engine.moveHighlight(1);
            String reading = engine.readingText(), expected = engine.displayedCandidates().get(engine.highlightedIndex()); List<String> candidates = List.copyOf(engine.displayedCandidates());
            String script = "import sqlite3,sys\nc=sqlite3.connect(sys.argv[1],timeout=1)\nc.execute('BEGIN IMMEDIATE')\nprint('LOCKED',flush=True)\nsys.stdin.buffer.read(1)\nc.rollback()\nc.close()\n";
            Process locker = new ProcessBuilder(python, "-u", "-c", script, fixture.user.toString()).redirectErrorStream(true).start();
            try (BufferedReader output = new BufferedReader(new InputStreamReader(locker.getInputStream(), StandardCharsets.UTF_8))) {
                String ready = CompletableFuture.supplyAsync(() -> { try { return output.readLine(); } catch (Exception error) { throw new IllegalStateException(error); } }).get(10, TimeUnit.SECONDS);
                assertEquals("LOCKED", ready);
                assertEquals("", engine.finishCompositionForInputHandoff().committedText()); assertNotNull(engine.lastError());
                assertEquals(reading, engine.readingText()); assertEquals(candidates, engine.displayedCandidates());
                assertEquals("", engine.handleSoftKey("SYMBOL").committedText()); assertNotNull(engine.lastError()); assertEquals(candidates, engine.displayedCandidates());
                locker.getOutputStream().write('x'); locker.getOutputStream().flush(); assertTrue(locker.waitFor(10, TimeUnit.SECONDS)); assertEquals(0, locker.exitValue());
                assertEquals(expected, engine.finishCompositionForInputHandoff().committedText()); assertNull(engine.lastError());
                assertFalse(engine.hasComposition()); assertEquals("", engine.finishCompositionForInputHandoff().committedText());
            } finally { if (locker.isAlive()) { locker.destroyForcibly(); locker.waitFor(10, TimeUnit.SECONDS); } }
        }
    }
}
