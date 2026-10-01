package tw.chichi77.keykey.android;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

import org.junit.Test;

public final class FullDictionaryIntegrationTest {
    @Test
    public void modelCacheNameTracksBundledContentAndRetiresPreviousVersion() throws Exception {
        var digest = java.security.MessageDigest.getInstance("SHA-256");
        try (InputStream input = Files.newInputStream(
                Path.of(System.getProperty("keykey.smart.database")))) {
            byte[] buffer = new byte[64 * 1024];
            int count;
            while ((count = input.read(buffer)) != -1) digest.update(buffer, 0, count);
        }
        String fingerprint = java.util.HexFormat.of().formatHex(digest.digest()).substring(0, 16);
        var installed = SmartMandarinStore.class.getDeclaredField("INSTALLED_NAME");
        installed.setAccessible(true);
        assertEquals("KeyKey-smart-" + fingerprint + ".db", installed.get(null));
        var previous = SmartMandarinStore.class.getDeclaredField("PREVIOUS_INSTALLED_NAMES");
        previous.setAccessible(true);
        assertTrue(List.of((String[]) previous.get(null)).contains("KeyKey-smart-reading-v3.db"));
    }

    @Test
    public void sharedDictionaryContainsTraditionalCandidatesInDesktopOrder() throws Exception {
        Path dictionaryPath = Path.of(System.getProperty("keykey.bopomofo.cin"));
        try (InputStream input = Files.newInputStream(dictionaryPath)) {
            CinDictionary dictionary = CinDictionary.load(input);
            assertTrue(dictionary.entryCount() > 90_000);
            assertEquals(List.of("你", "妳", "擬"), dictionary.candidates("su3").subList(0, 3));
        }
    }

    @Test
    public void generatedIndexContainsTraditionalCandidatesInDesktopOrder() throws Exception {
        Path dictionaryPath = Path.of(System.getProperty("keykey.bopomofo.cin"));
        Path punctuationPath = Path.of(System.getProperty("keykey.bopomofo.punctuation"));
        CinDictionary source;
        try (InputStream dictionary = Files.newInputStream(dictionaryPath);
             InputStream punctuation = Files.newInputStream(punctuationPath)) {
            source = CinDictionary.load(dictionary, punctuation);
        }

        File index = new File(System.getProperty("keykey.bopomofo.index"));
        try (InputStream input = new FileInputStream(index)) {
            CinDictionary dictionary = CinDictionary.loadIndexed(input);
            assertTrue(dictionary.entryCount() > 90_000);
            assertEquals(List.of("你", "妳", "擬"),
                    dictionary.candidates("su3").subList(0, 3));
            assertEquals(source.entryCount(), dictionary.entryCount());
            assertEquals(source.keys(), dictionary.keys());
            for (String key : source.keys()) {
                assertEquals(key, source.candidates(key), dictionary.candidates(key));
            }
        }
    }
}
