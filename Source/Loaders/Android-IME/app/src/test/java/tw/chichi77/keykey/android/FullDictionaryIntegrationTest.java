package tw.chichi77.keykey.android;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

import org.junit.Test;

public final class FullDictionaryIntegrationTest {
    @Test
    public void sharedDictionaryContainsTraditionalCandidatesInDesktopOrder() throws Exception {
        Path dictionaryPath = Path.of(System.getProperty("keykey.bopomofo.cin"));
        try (InputStream input = Files.newInputStream(dictionaryPath)) {
            CinDictionary dictionary = CinDictionary.load(input);
            assertTrue(dictionary.entryCount() > 90_000);
            assertEquals(List.of("你", "妳", "擬"), dictionary.candidates("su3").subList(0, 3));
        }
    }
}
