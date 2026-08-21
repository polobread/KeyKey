package tw.chichi77.keykey.android;

import static org.junit.Assert.assertEquals;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;

import org.junit.Test;

public final class CinDictionaryTest {
    @Test
    public void parsesOnlyCharacterDefinitionsAndPreservesOrder() throws Exception {
        String cin = """
                %gen_inp
                %keyname begin
                s ㄋ
                %keyname end
                %chardef begin
                su3 你
                su3 擬
                %chardef end
                ignored value
                """;

        CinDictionary dictionary = CinDictionary.load(
                new ByteArrayInputStream(cin.getBytes(StandardCharsets.UTF_8)));

        assertEquals(List.of("你", "擬"), dictionary.candidates("su3"));
        assertEquals(2, dictionary.entryCount());
    }
}
