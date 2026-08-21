package tw.chichi77.keykey.android;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

final class CinDictionary {
    private final Map<String, List<String>> entries;

    private CinDictionary(Map<String, List<String>> entries) {
        Map<String, List<String>> frozen = new LinkedHashMap<>();
        for (Map.Entry<String, List<String>> entry : entries.entrySet()) {
            frozen.put(entry.getKey(), List.copyOf(entry.getValue()));
        }
        this.entries = Collections.unmodifiableMap(frozen);
    }

    static CinDictionary empty() {
        return new CinDictionary(Map.of());
    }

    static CinDictionary load(InputStream... streams) throws IOException {
        Map<String, List<String>> values = new LinkedHashMap<>();
        for (InputStream stream : streams) parse(stream, values);
        return new CinDictionary(values);
    }

    List<String> candidates(String query) {
        return entries.getOrDefault(query, List.of());
    }

    int entryCount() {
        int count = 0;
        for (List<String> values : entries.values()) count += values.size();
        return count;
    }

    private static void parse(InputStream stream, Map<String, List<String>> output) throws IOException {
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(stream, StandardCharsets.UTF_8))) {
            boolean inDefinitions = false;
            String line;
            while ((line = reader.readLine()) != null) {
                String trimmed = line.trim();
                if (trimmed.regionMatches(true, 0, "%chardef", 0, 8)) {
                    inDefinitions = trimmed.toLowerCase(Locale.ROOT).contains("begin");
                    continue;
                }
                if (!inDefinitions || trimmed.isEmpty() || trimmed.startsWith("#")) continue;
                String[] fields = trimmed.split("\\s+", 2);
                if (fields.length != 2 || fields[0].isEmpty() || fields[1].isEmpty()) continue;
                output.computeIfAbsent(fields[0], ignored -> new ArrayList<>()).add(fields[1]);
            }
        }
    }
}
