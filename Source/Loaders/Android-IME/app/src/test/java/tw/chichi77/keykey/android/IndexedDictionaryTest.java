package tw.chichi77.keykey.android;

import static org.junit.Assert.assertEquals;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;

import org.junit.Test;

public final class IndexedDictionaryTest {
    @Test
    public void loadsIndexWithoutChangingCandidateOrder() throws Exception {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (DataOutputStream output = new DataOutputStream(bytes)) {
            output.writeInt(IndexedDictionary.MAGIC);
            output.writeInt(IndexedDictionary.VERSION);
            output.writeInt(2);
            writeString(output, "su3");
            output.writeInt(2);
            writeString(output, "你");
            writeString(output, "擬");
            writeString(output, "5j/");
            output.writeInt(1);
            writeString(output, "中");
        }

        IndexedDictionary dictionary = IndexedDictionary.load(
                new ByteArrayInputStream(bytes.toByteArray()));
        assertEquals(3, dictionary.valueCount());
        assertEquals(List.of("你", "擬"), dictionary.candidates("su3"));
        assertEquals(List.of("中"), dictionary.candidates("5j/"));
        assertEquals(List.of(), dictionary.candidates("missing"));
    }

    private static void writeString(DataOutputStream output, String value) throws Exception {
        byte[] encoded = value.getBytes(StandardCharsets.UTF_8);
        output.writeInt(encoded.length);
        output.write(encoded);
    }
}
