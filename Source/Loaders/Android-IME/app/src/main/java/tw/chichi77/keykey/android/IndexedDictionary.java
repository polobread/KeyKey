package tw.chichi77.keykey.android;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.BufferUnderflowException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

final class IndexedDictionary {
    static final int MAGIC = 0x4b4b4931; // KKI1
    static final int VERSION = 1;

    private static final class Entry {
        private final int valuesOffset;
        private final int valueCount;

        Entry(int valuesOffset, int valueCount) {
            this.valuesOffset = valuesOffset;
            this.valueCount = valueCount;
        }
    }

    private final byte[] data;
    private final Map<String, Entry> entries;
    private final Map<String, List<String>> cache = new HashMap<>();
    private final int valueCount;

    private IndexedDictionary(byte[] data, Map<String, Entry> entries, int valueCount) {
        this.data = data;
        this.entries = entries;
        this.valueCount = valueCount;
    }

    static IndexedDictionary load(InputStream stream) throws IOException {
        byte[] data;
        try (stream; ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[16 * 1024];
            int count;
            while ((count = stream.read(buffer)) != -1) output.write(buffer, 0, count);
            data = output.toByteArray();
        }

        try {
            ByteBuffer input = ByteBuffer.wrap(data).order(ByteOrder.BIG_ENDIAN);
            if (input.getInt() != MAGIC) throw new IOException("Invalid dictionary magic");
            if (input.getInt() != VERSION) throw new IOException("Unsupported dictionary version");
            int groupCount = nonnegative(input.getInt(), "group count");
            LinkedHashMap<String, Entry> entries = new LinkedHashMap<>();
            int totalValueCount = 0;
            for (int group = 0; group < groupCount; group++) {
                String key = readString(input);
                int candidateCount = nonnegative(input.getInt(), "candidate count");
                int valuesOffset = input.position();
                for (int candidate = 0; candidate < candidateCount; candidate++) {
                    skipString(input);
                }
                entries.put(key, new Entry(valuesOffset, candidateCount));
                totalValueCount = Math.addExact(totalValueCount, candidateCount);
            }
            if (input.hasRemaining()) throw new IOException("Trailing dictionary data");
            return new IndexedDictionary(data, Map.copyOf(entries), totalValueCount);
        } catch (BufferUnderflowException | ArithmeticException | IllegalArgumentException error) {
            throw new IOException("Malformed indexed dictionary", error);
        }
    }

    List<String> candidates(String key) {
        List<String> cached = cache.get(key);
        if (cached != null) return cached;
        Entry entry = entries.get(key);
        if (entry == null) return List.of();

        ByteBuffer input = ByteBuffer.wrap(data).order(ByteOrder.BIG_ENDIAN);
        input.position(entry.valuesOffset);
        String[] values = new String[entry.valueCount];
        try {
            for (int index = 0; index < values.length; index++) values[index] = readString(input);
        } catch (IOException error) {
            return List.of();
        }
        List<String> result = List.of(values);
        cache.put(key, result);
        return result;
    }

    int valueCount() {
        return valueCount;
    }

    Set<String> keys() {
        return entries.keySet();
    }

    private static String readString(ByteBuffer input) throws IOException {
        int length = nonnegative(input.getInt(), "string length");
        if (length > input.remaining()) throw new IOException("Truncated dictionary string");
        byte[] value = new byte[length];
        input.get(value);
        return new String(value, StandardCharsets.UTF_8);
    }

    private static void skipString(ByteBuffer input) throws IOException {
        int length = nonnegative(input.getInt(), "string length");
        if (length > input.remaining()) throw new IOException("Truncated dictionary string");
        input.position(input.position() + length);
    }

    private static int nonnegative(int value, String label) throws IOException {
        if (value < 0) throw new IOException("Negative " + label);
        return value;
    }
}
