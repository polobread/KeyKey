// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
package tw.chichi77.keykey.android;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Stream;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.After;
import org.junit.Assume;
import org.junit.Before;
import org.junit.Test;

/** Small repository/JNI contracts; the Rust behavior matrix belongs to core CI. */
public final class GuanyinmaUserDataTest {
    private Path directory;
    private File model;
    private File user;
    private GuanyinmaUserData repository;
    private final AtomicInteger notifications = new AtomicInteger();

    @Before public void openIndependentRepository() throws Exception {
        String library = System.getProperty("keykey.guanyinma.library");
        // Ordinary Java-only unit runs do not load a different-ABI Android SO.
        // The dedicated host-JNI task requires this property before launching tests.
        Assume.assumeTrue("Host JNI library was not supplied", library != null && !library.isBlank());
        assertTrue("Supplied host JNI library must exist", new File(library).isFile());
        String modelPath = System.getProperty("keykey.smart.database");
        assertTrue("Host JNI tests require the explicit shared model", modelPath != null && !modelPath.isBlank());
        model = new File(modelPath);
        assertTrue("Shared model must exist", model.isFile());
        directory = Files.createTempDirectory("KeyKey Guanyinma 詞庫 ");
        user = directory.resolve("Rust 使用者.db").toFile();
        repository = new GuanyinmaUserData(model, user, notifications::incrementAndGet);
    }

    @After public void closeOnlyOwnedTemporaryFiles() throws Exception {
        if (repository != null) repository.close();
        if (directory != null) {
            try (Stream<Path> paths = Files.walk(directory)) {
                for (Path path : paths.sorted(Comparator.reverseOrder()).toList()) Files.delete(path);
            }
        }
    }

    @Test public void realRepositoryCrudKeepsUnicodeAndRejectsStaleRowTokens() {
        repository.savePhrase(null, "𠮷", "ㄐㄧˊ");
        UserPhraseRepository.Phrase stale = repository.phrases().get(0);
        assertEquals("𠮷", stale.text());
        repository.savePhrase(null, "𠮷𠮷", "ㄐㄧˊ ㄐㄧˊ");
        int beforeRejectedEdit = notifications.get();
        assertThrows(IllegalStateException.class,
                () -> repository.savePhrase(stale.id(), "妳", "su3"));
        assertEquals(beforeRejectedEdit, notifications.get());
        assertEquals(List.of("𠮷", "𠮷𠮷"), repository.phrases().stream().map(UserPhraseRepository.Phrase::text).toList());

        UserPhraseRepository.Phrase unicode = repository.phrases().stream()
                .filter(row -> row.text().equals("𠮷")).findFirst().orElseThrow();
        repository.savePhrase(unicode.id(), "𠮷𠮷𠮷", "ㄐㄧˊ ㄐㄧˊ ㄐㄧˊ");
        UserPhraseRepository.Phrase replacement = repository.phrases().stream()
                .filter(row -> row.text().equals("𠮷𠮷𠮷")).findFirst().orElseThrow();
        repository.deletePhrase(replacement.id());
        assertEquals(List.of("𠮷𠮷"), repository.phrases().stream().map(UserPhraseRepository.Phrase::text).toList());
        assertTrue(repository.exportPhrases().startsWith("MJSR version 1.0.0\n"));
        assertTrue(user.isFile());
        assertFalse(new File(user.getParentFile(), "UserPhrase.db").exists());
    }

    @Test public void phraseImportPreservesLearningAndInvalidArchiveCommitsNothing() throws Exception {
        try (GuanyinmaNative admin = openAdmin()) {
            seedIndependentLearning(admin);
            String before = admin.userData();
            assertThrows(IllegalArgumentException.class,
                    () -> repository.importPhrases("unsupported archive\n你好\tsu3 cl3\n"));
            assertEquals(before, admin.userData());

            JSONArray invalidRows = new JSONArray()
                    .put(phrase("你好", "su3 cl3"))
                    .put(json("qstring", "", "current", "無效", "probability", -1, "backoff", 0));
            JSONObject archive = json("format", "guanyinma_user_data", "schema_version", 1,
                    "phrases", invalidRows);
            assertThrows(RuntimeException.class,
                    () -> admin.apply(json("type", "import_user_data", "archive", archive).toString()));
            assertEquals("The valid first row cannot survive a rejected archive", before, admin.userData());

            UserPhraseRepository.ImportResult result = repository.importPhrases(
                    "MJSR version 1.0.0\n你好\tsu3,cl3\t-2.5\t0\n"
                    + "你好\tsu3 cl3\t1\t0\n<database>encrypted learning\n");
            assertEquals(1, result.imported());
            assertEquals(1, result.skipped());
            JSONObject data = data(admin);
            assertEquals(1, data.getJSONArray("phrases").length());
            assertEquals(1, data.getJSONArray("overrides").length());
            assertEquals(1, data.getJSONArray("table").length());
            assertEquals("妳", data.getJSONArray("overrides").getJSONObject(0).getString("current"));
        }
    }

    @Test public void smartResetPreservesCustomPhrasesTableLearningAndLegacyFile() throws Exception {
        Path legacy = directory.resolve("UserPhrase.db");
        byte[] legacyBytes = "the other core's untouched data".getBytes(StandardCharsets.UTF_8);
        Files.write(legacy, legacyBytes);
        try (GuanyinmaNative admin = openAdmin()) {
            seedIndependentLearning(admin);
            repository.savePhrase(null, "𠮷𠮷", "ㄐㄧˊ ㄐㄧˊ");
            repository.resetSmartLearning();
            JSONObject data = data(admin);
            assertEquals(0, data.getJSONArray("overrides").length());
            assertEquals(0, data.getJSONArray("bigrams").length());
            assertEquals(1, data.getJSONArray("phrases").length());
            JSONArray table = data.getJSONArray("table");
            assertEquals(1, table.length());
            assertEquals("cangjie", table.getJSONObject(0).getString("method"));
            assertEquals(3, table.getJSONObject(0).getInt("count"));
            assertEquals(new String(legacyBytes, StandardCharsets.UTF_8), Files.readString(legacy));
        }
    }

    @Test public void existingBuiltInOrCustomPhraseIsNotReportedAsANewSave() {
        IllegalArgumentException builtIn = assertThrows(IllegalArgumentException.class,
                () -> repository.savePhrase(null, "你好", "su3 cl3"));
        assertTrue(builtIn.getMessage().contains("已存在"));
        assertTrue(repository.phrases().isEmpty());
        assertEquals(0, notifications.get());

        repository.savePhrase(null, "𠮷𠮷", "ㄐㄧˊ ㄐㄧˊ");
        int savedNotifications = notifications.get();
        assertThrows(IllegalArgumentException.class,
                () -> repository.savePhrase(null, "𠮷𠮷", "ㄐㄧˊ ㄐㄧˊ"));
        assertEquals(savedNotifications, notifications.get());
        assertEquals(List.of("𠮷𠮷"), repository.phrases().stream().map(UserPhraseRepository.Phrase::text).toList());
    }

    private GuanyinmaNative openAdmin() {
        return GuanyinmaNative.open(model.getAbsolutePath(),
                json("method", "smart", "user_database", user.getAbsolutePath()).toString(), text -> true);
    }
    private static JSONObject data(GuanyinmaNative admin) throws Exception {
        JSONObject result = new JSONObject(admin.userData());
        assertEquals("user_data", result.getString("kind"));
        return result.getJSONObject("data");
    }
    private static JSONObject phrase(String text, String reading) {
        return json("qstring", UserPhraseArchive.checkedQuery(text, reading), "current", text,
                "probability", -1, "backoff", 0);
    }
    private static void seedIndependentLearning(GuanyinmaNative admin) {
        JSONObject smart = json("overrides", new JSONArray().put(json(
                "qstring", UserPhraseArchive.checkedQuery("妳", "su3"), "current", "妳")),
                "bigrams", new JSONArray());
        JSONArray table = new JSONArray().put(json("method", "cangjie", "code", "a", "current", "日", "count", 3));
        JSONObject archive = json("format", "guanyinma_user_data", "schema_version", 1,
                "phrases", new JSONArray(), "smart", smart, "table", table);
        admin.apply(json("type", "import_user_data", "archive", archive).toString());
    }
    private static JSONObject json(Object... pairs) {
        try {
            JSONObject value = new JSONObject();
            for (int index = 0; index < pairs.length; index += 2) value.put((String) pairs[index], pairs[index + 1]);
            return value;
        } catch (Exception error) { throw new IllegalArgumentException(error); }
    }
}
