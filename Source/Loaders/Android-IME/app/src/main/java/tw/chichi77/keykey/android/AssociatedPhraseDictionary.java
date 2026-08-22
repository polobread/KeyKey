package tw.chichi77.keykey.android;

import android.content.res.AssetManager;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

final class AssociatedPhraseDictionary {
    static final class CollectionInfo {
        private final String source;
        private final String displayName;
        private final String assetName;

        CollectionInfo(String source, String displayName, String assetName) {
            this.source = source;
            this.displayName = displayName;
            this.assetName = assetName;
        }

        String source() { return source; }
        String displayName() { return displayName; }
        String assetName() { return assetName; }
    }

    private static final class PhraseRow {
        private final String word;
        private long count;
        private final int firstCharacterLength;

        PhraseRow(String word, long count, int firstCharacterLength) {
            this.word = word;
            this.count = count;
            this.firstCharacterLength = firstCharacterLength;
        }
    }

    private static final String ASSET_DIRECTORY = "collections";
    private static final String BASE_ASSET = "McBopomofo.occ";
    private static final String BASE_SOURCE = "McBopomofo";
    private static final String BASE_DISPLAY_NAME = "小麥";

    private final Map<String, List<String>> entries;

    private AssociatedPhraseDictionary(Map<String, List<String>> entries) {
        LinkedHashMap<String, List<String>> frozen = new LinkedHashMap<>();
        for (Map.Entry<String, List<String>> entry : entries.entrySet()) {
            frozen.put(entry.getKey(), List.copyOf(entry.getValue()));
        }
        this.entries = Collections.unmodifiableMap(frozen);
    }

    static AssociatedPhraseDictionary empty() {
        return new AssociatedPhraseDictionary(Map.of());
    }

    static AssociatedPhraseDictionary fromEntries(Map<String, List<String>> entries) {
        return new AssociatedPhraseDictionary(entries);
    }

    static AssociatedPhraseDictionary load(AssetManager assets, Set<String> enabled)
            throws IOException {
        if (enabled.isEmpty()) return empty();

        List<CollectionInfo> collections = availableCollections(assets);
        Set<String> baseExclusions = loadBaseExclusions(assets, collections);
        LinkedHashMap<String, List<String>> merged = new LinkedHashMap<>();
        LinkedHashMap<String, Set<String>> seen = new LinkedHashMap<>();
        for (CollectionInfo collection : collections) {
            if (!enabled.contains(collection.source())) continue;
            Map<String, List<String>> parsed;
            try (InputStream stream = assets.open(
                    ASSET_DIRECTORY + "/" + collection.assetName())) {
                parsed = parseCollection(stream,
                        BASE_SOURCE.equals(collection.source()) ? baseExclusions : Set.of());
            }
            for (Map.Entry<String, List<String>> entry : parsed.entrySet()) {
                List<String> values = merged.computeIfAbsent(
                        entry.getKey(), ignored -> new ArrayList<>());
                Set<String> unique = seen.computeIfAbsent(
                        entry.getKey(), ignored -> new LinkedHashSet<>());
                for (String suffix : entry.getValue()) {
                    if (unique.add(suffix)) values.add(suffix);
                }
            }
        }
        return new AssociatedPhraseDictionary(merged);
    }

    static List<CollectionInfo> availableCollections(AssetManager assets) throws IOException {
        String[] names = assets.list(ASSET_DIRECTORY);
        if (names == null) return List.of();

        ArrayList<CollectionInfo> result = new ArrayList<>();
        for (String name : names) {
            if (BASE_ASSET.equals(name)) {
                result.add(new CollectionInfo(BASE_SOURCE, BASE_DISPLAY_NAME, name));
            } else if (name.startsWith("phrase.") && name.endsWith(".tsv")) {
                String source = name.substring("phrase.".length(), name.length() - ".tsv".length());
                try (InputStream stream = assets.open(ASSET_DIRECTORY + "/" + name)) {
                    result.add(new CollectionInfo(source, readDisplayName(stream), name));
                }
            }
        }
        result.sort(Comparator
                .comparing((CollectionInfo value) -> !BASE_SOURCE.equals(value.source()))
                .thenComparing(CollectionInfo::source));
        return List.copyOf(result);
    }

    List<String> candidates(String headCharacter) {
        return entries.getOrDefault(headCharacter, List.of());
    }

    int entryCount() {
        int count = 0;
        for (List<String> values : entries.values()) count += values.size();
        return count;
    }

    static Map<String, List<String>> parseCollection(InputStream stream) throws IOException {
        return parseCollection(stream, Set.of());
    }

    static Map<String, List<String>> parseCollection(InputStream stream, Set<String> exclusions)
            throws IOException {
        LinkedHashMap<String, PhraseRow> uniqueRows = new LinkedHashMap<>();
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(stream, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                String[] fields = line.indexOf('\t') >= 0
                        ? line.split("\\t") : line.trim().split("\\s+");
                if (fields.length < 2) continue;
                String word = fields[0].trim();
                long count = parseCount(fields[1]);
                if (count == 0 || !startsWithHan(word) || exclusions.contains(word)) continue;
                int codePointCount = word.codePointCount(0, word.length());
                if (codePointCount < 2 || codePointCount > 20) continue;
                if (word.contains("媽的")) continue;

                int firstCharacterLength = Character.charCount(word.codePointAt(0));
                PhraseRow previous = uniqueRows.get(word);
                if (previous == null) {
                    uniqueRows.put(word, new PhraseRow(word, count, firstCharacterLength));
                } else {
                    previous.count = Math.max(previous.count, count);
                }
            }
        }

        long total = 0;
        for (PhraseRow row : uniqueRows.values()) total += row.count;
        LinkedHashMap<String, List<PhraseRow>> grouped = new LinkedHashMap<>();
        for (PhraseRow row : uniqueRows.values()) {
            if ((double) row.count * 1_000_000d <= total) continue;
            String head = row.word.substring(0, row.firstCharacterLength);
            grouped.computeIfAbsent(head, ignored -> new ArrayList<>()).add(row);
        }

        LinkedHashMap<String, List<String>> result = new LinkedHashMap<>();
        for (Map.Entry<String, List<PhraseRow>> entry : grouped.entrySet()) {
            entry.getValue().sort(Comparator.comparingLong((PhraseRow row) -> row.count).reversed());
            ArrayList<String> suffixes = new ArrayList<>();
            for (PhraseRow row : entry.getValue()) {
                suffixes.add(row.word.substring(row.firstCharacterLength));
            }
            result.put(entry.getKey(), List.copyOf(suffixes));
        }
        return Collections.unmodifiableMap(result);
    }

    private static Set<String> loadBaseExclusions(
            AssetManager assets, List<CollectionInfo> collections) throws IOException {
        LinkedHashSet<String> exclusions = new LinkedHashSet<>();
        for (CollectionInfo collection : collections) {
            if (!collection.assetName().startsWith("phrase.people-")) continue;
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(
                    assets.open(ASSET_DIRECTORY + "/" + collection.assetName()),
                    StandardCharsets.UTF_8))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    String[] fields = line.split("\\t", 2);
                    if (fields.length == 0) continue;
                    String word = fields[0].trim();
                    if (!word.isEmpty() && !"詞".equals(word)) exclusions.add(word);
                }
            }
        }
        return exclusions;
    }

    private static String readDisplayName(InputStream stream) throws IOException {
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(stream, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                String[] fields = line.split("\\t");
                if (fields.length >= 4 && !fields[3].trim().isEmpty()
                        && !"分類".equals(fields[3].trim())) {
                    return fields[3].trim();
                }
            }
        }
        return "詞庫";
    }

    private static long parseCount(String value) {
        try {
            long count = Long.parseLong(value.trim());
            return Math.max(0, count);
        } catch (NumberFormatException ignored) {
            return 0;
        }
    }

    private static boolean startsWithHan(String value) {
        if (value.isEmpty()) return false;
        return Character.UnicodeScript.of(value.codePointAt(0)) == Character.UnicodeScript.HAN;
    }
}
