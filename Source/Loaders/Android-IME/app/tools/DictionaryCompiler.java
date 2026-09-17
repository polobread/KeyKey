import java.io.BufferedReader;
import java.io.DataOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.stream.Stream;

public final class DictionaryCompiler {
    private static final int MAGIC = 0x4b4b4931; // KKI1
    private static final int VERSION = 1;

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

    private DictionaryCompiler() {}

    public static void main(String[] arguments) throws Exception {
        if (arguments.length != 5) {
            throw new IllegalArgumentException(
                    "Expected: output-directory bpmf.cin punctuations.cin phrase.occ "
                            + "categorized-directory");
        }
        Path outputDirectory = Path.of(arguments[0]);
        Path bpmf = Path.of(arguments[1]);
        Path punctuations = Path.of(arguments[2]);
        Path basePhrases = Path.of(arguments[3]);
        Path categorizedDirectory = Path.of(arguments[4]);

        Files.createDirectories(outputDirectory);
        compileCin(outputDirectory.resolve("bpmf-index.kki"), List.of(bpmf, punctuations));
        compilePhraseCollections(outputDirectory.resolve("collections"), basePhrases,
                categorizedDirectory);
    }

    private static void compileCin(Path output, List<Path> sources) throws IOException {
        LinkedHashMap<String, List<String>> entries = new LinkedHashMap<>();
        for (Path source : sources) {
            try (BufferedReader reader = Files.newBufferedReader(source, StandardCharsets.UTF_8)) {
                boolean inDefinitions = false;
                String line;
                while ((line = reader.readLine()) != null) {
                    String trimmed = line.trim();
                    if (trimmed.regionMatches(true, 0, "%chardef", 0, 8)) {
                        inDefinitions = trimmed.toLowerCase(Locale.ROOT).contains("begin");
                        continue;
                    }
                    if (!inDefinitions || trimmed.isEmpty() || trimmed.startsWith("#")) continue;
                    int separator = firstWhitespace(trimmed);
                    if (separator <= 0) continue;
                    int valueStart = separator;
                    while (valueStart < trimmed.length()
                            && Character.isWhitespace(trimmed.charAt(valueStart))) valueStart++;
                    if (valueStart >= trimmed.length()) continue;
                    entries.computeIfAbsent(trimmed.substring(0, separator), ignored ->
                            new ArrayList<>()).add(trimmed.substring(valueStart));
                }
            }
        }
        writeDictionary(output, entries);
    }

    private static void compilePhraseCollections(Path outputDirectory, Path basePhrases,
                                                  Path categorizedDirectory) throws IOException {
        Files.createDirectories(outputDirectory);
        Files.deleteIfExists(outputDirectory.resolve("display-names.tsv"));
        try (Stream<Path> oldOutputs = Files.list(outputDirectory)) {
            for (Path output : oldOutputs.filter(path ->
                    path.getFileName().toString().endsWith(".kki")).toList()) {
                Files.delete(output);
            }
        }

        List<Path> categorized;
        try (Stream<Path> files = Files.list(categorizedDirectory)) {
            categorized = files.filter(path -> {
                String name = path.getFileName().toString();
                return name.startsWith("phrase.") && name.endsWith(".tsv");
            }).sorted(Comparator.comparing(path -> path.getFileName().toString())).toList();
        }

        LinkedHashSet<String> baseExclusions = new LinkedHashSet<>();
        for (Path source : categorized) {
            if (!source.getFileName().toString().startsWith("phrase.people-")) continue;
            try (BufferedReader reader = Files.newBufferedReader(source, StandardCharsets.UTF_8)) {
                String line;
                while ((line = reader.readLine()) != null) {
                    int tab = line.indexOf('\t');
                    String word = (tab < 0 ? line : line.substring(0, tab)).trim();
                    if (!word.isEmpty() && !"詞".equals(word)) baseExclusions.add(word);
                }
            }
        }

        writeDictionary(outputDirectory.resolve("McBopomofo.occ.kki"),
                parsePhraseCollection(basePhrases, baseExclusions));
        for (Path source : categorized) {
            writeDictionary(outputDirectory.resolve(source.getFileName() + ".kki"),
                    parsePhraseCollection(source, Set.of()));
        }
    }

    private static Map<String, List<String>> parsePhraseCollection(Path source,
                                                                    Set<String> exclusions)
            throws IOException {
        LinkedHashMap<String, PhraseRow> uniqueRows = new LinkedHashMap<>();
        try (BufferedReader reader = Files.newBufferedReader(source, StandardCharsets.UTF_8)) {
            String line;
            while ((line = reader.readLine()) != null) {
                String[] fields = line.indexOf('\t') >= 0
                        ? line.split("\\t") : line.trim().split("\\s+");
                if (fields.length < 2) continue;
                String word = fields[0].trim();
                long count = parseCount(fields[1]);
                if (count == 0 || !startsWithHan(word) || exclusions.contains(word)) continue;
                int codePointCount = word.codePointCount(0, word.length());
                if (codePointCount < 2 || codePointCount > 20 || word.contains("媽的")) continue;

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
            result.put(entry.getKey(), suffixes);
        }
        return result;
    }

    private static void writeDictionary(Path output, Map<String, List<String>> entries)
            throws IOException {
        Files.createDirectories(output.getParent());
        try (DataOutputStream writer = new DataOutputStream(Files.newOutputStream(output,
                StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING))) {
            writer.writeInt(MAGIC);
            writer.writeInt(VERSION);
            writer.writeInt(entries.size());
            for (Map.Entry<String, List<String>> entry : entries.entrySet()) {
                writeString(writer, entry.getKey());
                writer.writeInt(entry.getValue().size());
                for (String value : entry.getValue()) writeString(writer, value);
            }
        }
    }

    private static void writeString(DataOutputStream writer, String value) throws IOException {
        byte[] encoded = value.getBytes(StandardCharsets.UTF_8);
        writer.writeInt(encoded.length);
        writer.write(encoded);
    }

    private static int firstWhitespace(String value) {
        for (int index = 0; index < value.length(); index++) {
            if (Character.isWhitespace(value.charAt(index))) return index;
        }
        return -1;
    }

    private static long parseCount(String value) {
        try {
            return Math.max(0, Long.parseLong(value.trim()));
        } catch (NumberFormatException ignored) {
            return 0;
        }
    }

    private static boolean startsWithHan(String value) {
        return !value.isEmpty()
                && Character.UnicodeScript.of(value.codePointAt(0)) == Character.UnicodeScript.HAN;
    }
}
