// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
package tw.chichi77.keykey.android;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/** FE decoding of the unencrypted MJSR phrase section; never imports learning. */
final class UserPhraseArchive {
    record Row(String query, String text, double probability, double backoff) {}
    record Parsed(List<Row> rows, int skipped) {}
    private UserPhraseArchive() {}

    static String checkedQuery(String text, String reading) {
        String query = SmartMandarinUserData.queryForReading(reading);
        if (query == null || text.isEmpty() || text.indexOf('\0') >= 0
                || text.codePointCount(0, text.length()) > 8
                || text.codePoints().anyMatch(Character::isWhitespace)
                || text.codePointCount(0, text.length()) != query.length() / 2) {
            throw new IllegalArgumentException("詞句須為 1 至 8 字，且每個字都要有一組有效注音。");
        }
        return query;
    }

    static Parsed parse(String contents) {
        String[] lines = contents.split("\\r?\\n", -1);
        if (lines.length == 0 || !lines[0].contains("MJSR version 1.0.0")) {
            throw new IllegalArgumentException("不是 macOS MJSR 1.0.0 詞庫檔案");
        }
        ArrayList<Row> rows = new ArrayList<>();
        Set<List<String>> seen = new HashSet<>();
        int skipped = 0;
        for (int index = 1; index < lines.length; index++) {
            String line = lines[index];
            if (line.contains("<database>")) break;
            if (line.isEmpty() || line.startsWith("#")) continue;
            String[] fields = line.split("\\t", -1);
            if (fields.length < 2) { skipped++; continue; }
            final String query;
            try { query = checkedQuery(fields[0], fields[1]); }
            catch (IllegalArgumentException error) { skipped++; continue; }
            if (!seen.add(List.of(query, fields[0]))) { skipped++; continue; }
            rows.add(new Row(query, fields[0], finite(fields, 2, -1), finite(fields, 3, 0)));
        }
        return new Parsed(List.copyOf(rows), skipped);
    }

    static String export(List<Row> rows) {
        StringBuilder result = new StringBuilder("MJSR version 1.0.0\n");
        for (Row row : rows) {
            String reading = SmartMandarinUserData.readingForQuery(row.query());
            if (reading == null) continue;
            result.append(row.text()).append('\t').append(reading.replace(' ', ','))
                    .append('\t').append(row.probability()).append('\t').append(row.backoff()).append('\n');
        }
        return result.toString();
    }
    private static double finite(String[] fields, int index, double fallback) {
        if (index >= fields.length) return fallback;
        try {
            double value = Double.parseDouble(fields[index]);
            return Double.isFinite(value) ? value : fallback;
        } catch (NumberFormatException error) { return fallback; }
    }
}
