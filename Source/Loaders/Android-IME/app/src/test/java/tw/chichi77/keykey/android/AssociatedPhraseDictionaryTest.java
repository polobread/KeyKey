package tw.chichi77.keykey.android;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.List;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;

import org.junit.Test;

public final class AssociatedPhraseDictionaryTest {
    @Test
    public void generatedDisplayNameMappingContainsProductLabels() throws Exception {
        File directory = new File(System.getProperty("keykey.associated.collections"));
        File mapping = new File(directory, "display-names.tsv");
        assertTrue(mapping.isFile());

        Map<String, String> names;
        try (FileInputStream stream = new FileInputStream(mapping)) {
            names = AssociatedPhraseDictionary.parseDisplayNames(stream);
        }
        assertEquals("小麥注音", names.get("McBopomofo"));
        assertEquals("中文文學", names.get("chinese"));
        assertEquals("一般生活", names.get("general"));
    }

    @Test
    public void parserFiltersRareRowsAndSortsByFrequency() throws Exception {
        String source = "詞\t詞頻\t注音\t分類\n"
                + "甲乙\t2000000\t-\t測試\n"
                + "甲丁\t3000000\t-\t測試\n"
                + "甲丙\t1\t-\t測試\n"
                + "乙甲\t500000\t-\t測試\n";
        Map<String, List<String>> parsed = AssociatedPhraseDictionary.parseCollection(
                new ByteArrayInputStream(source.getBytes(StandardCharsets.UTF_8)));

        assertEquals(List.of("丁", "乙"), parsed.get("甲"));
        assertEquals(List.of("甲"), parsed.get("乙"));
        assertFalse(parsed.get("甲").contains("丙"));
    }

    @Test
    public void parserKeepsHighestFrequencyForDuplicateWords() throws Exception {
        String source = "甲乙 2\n甲乙 20\n甲丙 10\n";
        Map<String, List<String>> parsed = AssociatedPhraseDictionary.parseCollection(
                new ByteArrayInputStream(source.getBytes(StandardCharsets.UTF_8)));

        assertEquals(List.of("乙", "丙"), parsed.get("甲"));
    }

    @Test
    public void parserRemovesWordsOwnedByPeopleCollectionsFromBase() throws Exception {
        String source = "王小明 20\n王小華 10\n";
        Map<String, List<String>> parsed = AssociatedPhraseDictionary.parseCollection(
                new ByteArrayInputStream(source.getBytes(StandardCharsets.UTF_8)),
                Set.of("王小明"));

        assertEquals(List.of("小華"), parsed.get("王"));
    }

    @Test
    public void generatedAssetsContainAllPublicCollections() throws Exception {
        File directory = new File(System.getProperty("keykey.associated.collections"));
        File base = new File(directory, "McBopomofo.occ");
        assertTrue(base.isFile());

        File[] files = directory.listFiles(file ->
                file.getName().equals("McBopomofo.occ")
                        || file.getName().matches("phrase\\..+\\.tsv"));
        assertEquals(30, files == null ? 0 : files.length);
        assertTrue(new File(directory, "phrase.software.tsv").isFile());

        Map<String, List<String>> parsed;
        try (FileInputStream stream = new FileInputStream(base)) {
            parsed = AssociatedPhraseDictionary.parseCollection(stream);
        }
        assertFalse(parsed.isEmpty());
    }

    @Test
    public void generatedIndexesContainAllCollectionsAndBaseCandidates() throws Exception {
        File sourceDirectory = new File(System.getProperty("keykey.associated.collections"));
        File indexDirectory = new File(System.getProperty("keykey.associated.indexes"));
        File[] files = indexDirectory.listFiles(file -> file.getName().endsWith(".kki"));
        assertEquals(30, files == null ? 0 : files.length);

        Set<String> baseExclusions = peopleCollectionWords(sourceDirectory);
        assertIndexMatchesSource(
                new File(sourceDirectory, "McBopomofo.occ"),
                new File(indexDirectory, "McBopomofo.occ.kki"),
                baseExclusions);

        File[] collections = sourceDirectory.listFiles(file ->
                file.getName().startsWith("phrase.") && file.getName().endsWith(".tsv"));
        assertEquals(29, collections == null ? 0 : collections.length);
        for (File collection : collections) {
            assertIndexMatchesSource(collection,
                    new File(indexDirectory, collection.getName() + ".kki"), Set.of());
        }
    }

    private static Set<String> peopleCollectionWords(File directory) throws IOException {
        LinkedHashSet<String> result = new LinkedHashSet<>();
        File[] collections = directory.listFiles(file ->
                file.getName().startsWith("phrase.people-")
                        && file.getName().endsWith(".tsv"));
        if (collections == null) return result;
        for (File collection : collections) {
            for (String line : Files.readAllLines(collection.toPath(), StandardCharsets.UTF_8)) {
                int tab = line.indexOf('\t');
                String word = (tab < 0 ? line : line.substring(0, tab)).trim();
                if (!word.isEmpty() && !"詞".equals(word)) result.add(word);
            }
        }
        return result;
    }

    private static void assertIndexMatchesSource(File source, File index,
                                                  Set<String> exclusions) throws Exception {
        Map<String, List<String>> expected;
        try (FileInputStream stream = new FileInputStream(source)) {
            expected = AssociatedPhraseDictionary.parseCollection(stream, exclusions);
        }
        try (FileInputStream stream = new FileInputStream(index)) {
            IndexedDictionary actual = IndexedDictionary.load(stream);
            assertEquals(source.getName(), expected.keySet(), actual.keys());
            int valueCount = 0;
            for (Map.Entry<String, List<String>> entry : expected.entrySet()) {
                assertEquals(source.getName() + ":" + entry.getKey(),
                        entry.getValue(), actual.candidates(entry.getKey()));
                valueCount += entry.getValue().size();
            }
            assertEquals(source.getName(), valueCount, actual.valueCount());
        }
    }
}
