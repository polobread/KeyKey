package tw.chichi77.keykey.android;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;
import static org.junit.Assume.assumeTrue;

import android.content.Context;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.HashMap;
import java.util.Map;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Explicit Rust-migration baseline recorder. Ordinary instrumentation runs skip it. */
@RunWith(AndroidJUnit4.class)
public final class CoreFunctionalInstrumentedTest {
    @Test public void migrationBaseline() throws Exception {
        var arguments = InstrumentationRegistry.getArguments();
        assumeTrue("Enable explicitly with -e migrationBaseline true",
                "true".equals(arguments.getString("migrationBaseline")));
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        String contents;
        try (var input = instrumentation.getContext().getAssets().open("migration-scenarios.tsv");
             var reader = new BufferedReader(new InputStreamReader(input, StandardCharsets.UTF_8))) {
            StringBuilder text = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) text.append(line).append("\n");
            contents = text.toString();
        }
        File scratch = new File(context.getCacheDir(), "rust-migration-" + UUID.randomUUID());
        assertTrue("Cannot create isolated migration scratch", scratch.mkdirs());
        File modelFile = new File(scratch, "model.db");
        File trace = new File(arguments.getString("migrationTrace",
                new File(context.getCacheDir(), "core-migration-trace.jsonl").getAbsolutePath()));
        CinDictionary dictionary;
        try (var cin = context.getAssets().open("bpmf-ext.cin");
             var punctuation = context.getAssets().open("bpmf-punctuations.cin")) {
            dictionary = CinDictionary.load(cin, punctuation);
        }
        MigrationSession session = null;
        String activeCase = "", activeProfile = "", initialMethod = "";
        Set<String> seenCases = new HashSet<>(), methods = new HashSet<>(), profiles = new HashSet<>();
        int caseIndex = 0, step = 0;
        try {
            try (var input = context.getAssets().open("KeyKey.db");
                 var output = new FileOutputStream(modelFile)) {
                byte[] buffer = new byte[64 * 1024];
                int count;
                while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
            }
            File parent = trace.getParentFile();
            assertTrue("Cannot create trace directory", parent.isDirectory() || parent.mkdirs());
            try (Writer output = new OutputStreamWriter(new FileOutputStream(trace), StandardCharsets.UTF_8)) {
                String[] lines = contents.split("\r?\n", -1);
                for (int line = 0; line < lines.length; line++) {
                    if (lines[line].isEmpty() || lines[line].startsWith("#")) continue;
                    String[] fields = lines[line].split("\t", -1);
                    String location = "migration-scenarios.tsv:" + (line + 1);
                    assertEquals(location + ": expected five TSV columns", 5, fields.length);
                    String name = fields[0], profile = fields[1], method = fields[2];
                    String label = location + " [" + name + ", " + fields[3] + "]";
                    assertFalse(label + ": empty case", name.isEmpty());
                    assertTrue(label + ": unknown profile", profile.equals("hardware") || profile.equals("touch"));
                    ChineseInputMethod parsedMethod = method(method, label);
                    if (!name.equals(activeCase)) {
                        assertTrue(label + ": noncontiguous case", seenCases.add(name));
                        if (session != null) session.close();
                        session = new MigrationSession(context, modelFile,
                                new File(scratch, Integer.toString(++caseIndex)), dictionary,
                                profile, parsedMethod);
                        activeCase = name;
                        activeProfile = profile;
                        initialMethod = method;
                        step = 0;
                    } else {
                        assertEquals(label + ": profile changed within case", activeProfile, profile);
                        assertEquals(label + ": initial method changed within case", initialMethod, method);
                    }
                    List<String> unsupported = session.apply(fields[3], fields[4], label);
                    JSONObject snapshot = session.snapshot();
                    snapshot.put("case", name).put("step", ++step).put("profile", profile)
                            .put("operation", fields[3]).put("argument", fields[4]);
                    if (!unsupported.isEmpty()) snapshot.put("unsupported", new JSONArray(unsupported));
                    output.write(snapshot.toString());
                    output.write("\n");
                    output.flush();
                    methods.add(method);
                    profiles.add(profile);
                }
            }
        } finally {
            if (session != null) session.close();
            deleteOwned(scratch);
        }
        assertFalse("Migration fixture is empty", seenCases.isEmpty());
        assertEquals("Migration fixture must cover all four methods",
                Set.of("smart", "traditional", "cangjie", "simplex"), methods);
        assertEquals("Migration fixture must cover both profiles", Set.of("hardware", "touch"), profiles);
    }

    private static ChineseInputMethod method(String value, String label) {
        assertTrue(label + ": unknown method " + value,
                Set.of("smart", "traditional", "cangjie", "simplex").contains(value));
        return ChineseInputMethod.valueOf(value.toUpperCase(Locale.ROOT));
    }

    private static void deleteOwned(File file) {
        File[] children = file.listFiles();
        if (children != null) for (File child : children) deleteOwned(child);
        assertTrue("Could not remove owned migration scratch", !file.exists() || file.delete());
    }

    private static final class MigrationConfiguration {
        final BopomofoKeyboardLayout layout;
        final boolean spaceSelects;
        final TableInputOptions table;
        MigrationConfiguration(ChineseInputMethod method) {
            layout = BopomofoKeyboardLayout.STANDARD;
            spaceSelects = false;
            table = new TableInputOptions(method);
        }
        MigrationConfiguration(BopomofoEngine engine, boolean spaceSelects) {
            layout = engine.keyboardLayout();
            this.spaceSelects = spaceSelects;
            table = new TableInputOptions(engine.chineseInputMethod());
            table.queryAtMaximum = engine.tableOptions.queryAtMaximum;
            table.clearOnError = engine.tableOptions.clearOnError;
            table.composeWhileTyping = engine.tableOptions.composeWhileTyping;
            table.prefixCandidates = engine.tableOptions.prefixCandidates;
            table.dynamicFrequency = engine.tableOptions.dynamicFrequency;
            table.punctuation = engine.tableOptions.punctuation;
        }
    }

    private static final class MigrationSession implements AutoCloseable {
        private final Context context;
        private final File modelFile, userFile;
        private final CinDictionary dictionary;
        private final String profile, preferencesName;
        private SharedPreferences preferences;
        private SmartMandarinStore model;
        private SmartMandarinUserData userData;
        private SQLiteDatabase learningDatabase;
        private BopomofoEngine engine;
        private final StringBuilder committed = new StringBuilder();
        private final Map<ChineseInputMethod, MigrationConfiguration> configurations = new HashMap<>();

        MigrationSession(Context context, File modelFile, File scratch, CinDictionary dictionary,
                String profile, ChineseInputMethod method) {
            this.context = context;
            this.modelFile = modelFile;
            this.dictionary = dictionary;
            this.profile = profile;
            preferencesName = "RustMigration." + UUID.randomUUID();
            assertTrue("Cannot create case scratch", scratch.mkdirs());
            userFile = new File(scratch, "user.db");
            preferences = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE);
            assertTrue("Cannot initialize learning preferences", preferences.edit().clear().commit());
            open(method, BopomofoKeyboardLayout.STANDARD, false, null);
        }

        private void open(ChineseInputMethod method, BopomofoKeyboardLayout layout,
                boolean spaceSelects, TableInputOptions options) {
            learningDatabase = SQLiteDatabase.openOrCreateDatabase(userFile, null);
            userData = new SmartMandarinUserData(learningDatabase);
            model = new SmartMandarinStore(SQLiteDatabase.openDatabase(modelFile.getAbsolutePath(),
                    null, SQLiteDatabase.OPEN_READONLY), userData);
            engine = new BopomofoEngine(dictionary, model,
                    method == ChineseInputMethod.SMART ? BopomofoCompositionMode.SMART
                            : BopomofoCompositionMode.TRADITIONAL);
            engine.setTableCandidateSource(new TableCandidateStore(model.tableDatabase(), preferences));
            engine.setChineseInputMethod(method);
            engine.setKeyboardLayout(layout);
            engine.setSpaceSelectsCandidates(spaceSelects);
            this.spaceSelects = spaceSelects;
            if (options != null) engine.tableOptions = options;
        }

        private void closeEngine() {
            engine = null;
            if (model != null) { model.close(); model = null; }
            if (userData != null) { userData.close(); userData = null; }
            learningDatabase = null;
        }

        private void reopen(boolean reset, String label) {
            assertFalse(label + ": reopen/reset requires empty composition", engine.hasComposition());
            ChineseInputMethod method = engine.chineseInputMethod();
            BopomofoKeyboardLayout layout = engine.keyboardLayout();
            TableInputOptions options = engine.tableOptions;
            configurations.put(method, new MigrationConfiguration(engine, spaceSelects));
            if (reset) {
                userData.resetLearning();
                assertTrue(label + ": cannot clear table learning", preferences.edit().clear().commit());
            } else {
                // Wait for the real TableCandidateStore's apply() writes before closing the engine.
                assertTrue(label + ": cannot flush table learning",
                        preferences.edit().putBoolean("_migration_flush", true).commit());
            }
            boolean space = spaceSelects;
            closeEngine();
            preferences = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE);
            open(method, layout, space, options);
        }

        private boolean spaceSelects;
        private boolean closed;

        List<String> apply(String operation, String argument, String label) {
            if (operation.equals("REOPEN") || operation.equals("RESET_LEARNING")) {
                assertTrue(label + ": unexpected argument", argument.isEmpty());
                reopen(operation.equals("RESET_LEARNING"), label);
                return List.of();
            }
            switch (operation) {
                case "TYPE":
                    for (char key : argument.toCharArray()) {
                        assertTrue(label + ": TYPE requires ASCII keys", key < 128);
                        if (key == ' ') committed.append((profile.equals("hardware")
                                ? engine.handleHardwareSpace() : engine.space()).committedText());
                        else committed.append((profile.equals("hardware")
                                ? engine.handleHardwareCharacter(key)
                                : engine.handleSoftKey(String.valueOf(key))).committedText());
                    }
                    break;
                case "KEY":
                    switch (argument) {
                        case "RETURN": committed.append(engine.enter().committedText()); break;
                        case "BACKSPACE": committed.append(engine.backspace().committedText()); break;
                        case "ESCAPE": committed.append(engine.escape().committedText()); break;
                        case "SPACE": committed.append((profile.equals("hardware")
                                ? engine.handleHardwareSpace() : engine.space()).committedText()); break;
                        case "DOWN":
                            if (engine.chineseInputMethod() == ChineseInputMethod.SMART && !engine.isShowingSmartCandidates())
                                committed.append(engine.openSmartCandidates().committedText());
                            else engine.moveHighlight(1);
                            break;
                        case "PAGE_DOWN": engine.changePage(1); break;
                        case "PAGE_UP": engine.changePage(-1); break;
                        case "LEFT":
                        case "RIGHT":
                        case "END":
                            if (!profile.equals("hardware") || engine.chineseInputMethod() != ChineseInputMethod.SMART)
                                return List.of("KEY:" + argument);
                            engine.moveSmartCompositionCursor(argument.equals("LEFT") ? -1
                                    : argument.equals("RIGHT") ? 1 : Integer.MAX_VALUE / 2);
                            break;
                        default: fail(label + ": unknown key " + argument);
                    }
                    break;
                case "OPEN": {
                    int index;
                    try { index = Integer.parseInt(argument); }
                    catch (NumberFormatException error) { throw new AssertionError(label + ": invalid reading index", error); }
                    assertTrue(label + ": negative reading index", index >= 0);
                    if (engine.chineseInputMethod() != ChineseInputMethod.SMART) return List.of("OPEN");
                    if (profile.equals("hardware")) {
                        assertTrue(label + ": no composition cursor", engine.smartCompositionCursor() >= 0);
                        assertTrue(label + ": could not inspect reading end",
                                engine.moveSmartCompositionCursor(Integer.MAX_VALUE / 2));
                        int count = engine.smartCompositionCursor();
                        assertTrue(label + ": reading index outside composition", index < count);
                        assertTrue(label + ": could not move to reading",
                                engine.moveSmartCompositionCursor(index - count));
                        committed.append(engine.openSmartCandidates().committedText());
                    } else assertTrue(label + ": could not open touch cell", engine.selectTouchSmartCell(index));
                    break;
                }
                case "SELECT": {
                    assertFalse(label + ": empty selection", argument.isEmpty());
                    int pages = engine.pageCount();
                    for (int page = 0; page < pages; page++) {
                        int index = engine.displayedCandidates().indexOf(argument);
                        if (index >= 0) {
                            committed.append(engine.selectDisplayedCandidate(index).committedText());
                            return List.of();
                        }
                        engine.changePage(1);
                    }
                    fail(label + ": candidate " + argument + " not found");
                    break;
                }
                case "METHOD": {
                    configurations.put(engine.chineseInputMethod(), new MigrationConfiguration(engine, spaceSelects));
                    ChineseInputMethod target = method(argument, label);
                    committed.append(engine.setChineseInputMethod(target).committedText());
                    MigrationConfiguration config = configurations.getOrDefault(target, new MigrationConfiguration(target));
                    committed.append(engine.setKeyboardLayout(config.layout).committedText());
                    engine.setSpaceSelectsCandidates(config.spaceSelects);
                    spaceSelects = config.spaceSelects;
                    engine.tableOptions = config.table;
                    break;
                }
                case "OPTION": {
                    String[] fields = argument.split("=", -1);
                    assertEquals(label + ": OPTION requires key=value", 2, fields.length);
                    String key = fields[0], value = fields[1];
                    if (key.equals("layout")) {
                        assertTrue(label + ": unknown layout", value.equals("standard") || value.equals("hsu"));
                        committed.append(engine.setKeyboardLayout(value.equals("hsu")
                                ? BopomofoKeyboardLayout.HSU : BopomofoKeyboardLayout.STANDARD).committedText());
                    } else if (key.equals("punctuation")) {
                        assertTrue(label + ": invalid punctuation mode", Set.of("0", "1", "2").contains(value));
                        engine.tableOptions.punctuation = Integer.parseInt(value);
                    } else {
                        assertTrue(label + ": unknown option " + key,
                                Set.of("realtime", "prefix", "dynamic", "clear_on_error", "space_selects").contains(key));
                        assertTrue(label + ": invalid boolean", value.equals("true") || value.equals("false"));
                        boolean enabled = value.equals("true");
                        switch (key) {
                            case "realtime": engine.tableOptions.composeWhileTyping = enabled; break;
                            case "prefix": engine.tableOptions.prefixCandidates = enabled; break;
                            case "dynamic": engine.tableOptions.dynamicFrequency = enabled; break;
                            case "clear_on_error": engine.tableOptions.clearOnError = enabled; break;
                            case "space_selects":
                                spaceSelects = enabled;
                                engine.setSpaceSelectsCandidates(enabled);
                                break;
                            default: break;
                        }
                    }
                    break;
                }
                default: fail(label + ": unknown operation " + operation);
            }
            return List.of();
        }

        private List<String> allCandidates() {
            int page = engine.page(), highlight = engine.highlightedIndex(), count = engine.pageCount();
            if (count == 0) return List.of();
            engine.changePage(-page);
            List<String> result = new ArrayList<>();
            for (int index = 0; index < count; index++) {
                result.addAll(engine.displayedCandidates());
                if (index + 1 < count) engine.changePage(1);
            }
            engine.changePage(page - engine.page());
            if (highlight > 0) engine.moveHighlight(highlight);
            return result;
        }

        private List<List<String>> rows(String sql, int count, int numericFrom) {
            List<List<String>> result = new ArrayList<>();
            try (Cursor cursor = learningDatabase.rawQuery(sql, null)) {
                while (cursor.moveToNext()) {
                    List<String> row = new ArrayList<>();
                    for (int index = 0; index < count; index++) row.add(index < numericFrom
                            ? cursor.getString(index) : Double.toString(cursor.getDouble(index)));
                    result.add(row);
                }
            }
            return result;
        }

        private JSONObject learningSnapshot() throws Exception {
            List<List<String>> table = new ArrayList<>();
            String prefix = "cangjie_order.";
            for (var entry : preferences.getAll().entrySet()) {
                if (!entry.getKey().startsWith(prefix)) continue;
                String suffix = entry.getKey().substring(prefix.length());
                int separator = suffix.indexOf('.');
                assertTrue("Invalid table learning key", separator > 0 && separator + 1 < suffix.length());
                table.add(List.of(suffix.substring(0, separator), suffix.substring(separator + 1),
                        Integer.toString(((Number) entry.getValue()).intValue())));
            }
            table.sort(Comparator.comparing((List<String> row) -> row.get(0)).thenComparing(row -> row.get(1)));
            return new JSONObject()
                    .put("overrides", new JSONArray(rows("SELECT qstring, current FROM user_candidate_override_cache ORDER BY qstring, current", 2, 2)))
                    .put("bigrams", new JSONArray(rows("SELECT qstring, previous, current, probability FROM user_bigram_cache ORDER BY qstring, previous, current", 4, 3)))
                    .put("unigrams", new JSONArray(rows("SELECT qstring, current, probability, backoff FROM user_unigrams ORDER BY qstring, current", 4, 2)))
                    .put("table", new JSONArray(table));
        }

        JSONObject snapshot() throws Exception {
            return new JSONObject()
                    .put("method", engine.chineseInputMethod().name().toLowerCase(Locale.ROOT))
                    .put("committed", committed.toString()).put("composition", engine.composingText())
                    .put("reading", engine.readingText()).put("cursor", engine.composingCaretUtf16Offset())
                    .put("cursor_unit", "utf16").put("candidates", new JSONArray(allCandidates()))
                    .put("page", engine.page()).put("page_size", BopomofoEngine.CANDIDATES_PER_PAGE)
                    .put("highlight", engine.highlightedIndex()).put("learning", learningSnapshot());
        }

        @Override public void close() {
            if (closed) return;
            closed = true;
            closeEngine();
            assertTrue("Could not remove owned learning preferences", context.deleteSharedPreferences(preferencesName));
        }
    }
}
