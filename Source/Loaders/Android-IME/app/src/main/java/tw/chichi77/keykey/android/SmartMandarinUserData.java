package tw.chichi77.keykey.android;

import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;

import java.io.File;
import java.util.ArrayList;
import java.util.List;

/** The macOS-compatible user phrase and learning tables, kept separate from the cooked model. */
final class SmartMandarinUserData implements AutoCloseable {
    record Phrase(long id, String text, String reading) {}
    record Unigram(String text, double probability, double backoff) {}
    record ImportResult(int imported, int skipped) {}

    private final SQLiteDatabase database;

    static SmartMandarinUserData open(Context context) {
        File file = new File(context.getFilesDir(), "UserPhrase.db");
        return new SmartMandarinUserData(SQLiteDatabase.openOrCreateDatabase(file, null));
    }

    SmartMandarinUserData(SQLiteDatabase database) {
        this.database = database;
        database.execSQL("CREATE TABLE IF NOT EXISTS user_unigrams ("
                + "qstring TEXT NOT NULL, current TEXT NOT NULL, "
                + "probability REAL NOT NULL, backoff REAL NOT NULL)");
        database.execSQL("CREATE INDEX IF NOT EXISTS user_unigrams_index "
                + "ON user_unigrams(qstring)");
        database.execSQL("CREATE TABLE IF NOT EXISTS user_bigram_cache ("
                + "qstring TEXT NOT NULL, previous TEXT NOT NULL, "
                + "current TEXT NOT NULL, probability REAL NOT NULL)");
        database.execSQL("CREATE INDEX IF NOT EXISTS user_bigram_cache_index "
                + "ON user_bigram_cache(qstring)");
        database.execSQL("CREATE TABLE IF NOT EXISTS user_candidate_override_cache ("
                + "qstring TEXT NOT NULL, current TEXT NOT NULL)");
        database.execSQL("CREATE INDEX IF NOT EXISTS user_candidate_override_cache_index "
                + "ON user_candidate_override_cache(qstring)");
    }

    List<Unigram> unigrams(String query) {
        ArrayList<Unigram> result = new ArrayList<>();
        try (Cursor cursor = database.rawQuery(
                "SELECT current, probability, backoff FROM user_unigrams "
                        + "WHERE qstring = ? ORDER BY probability DESC, rowid",
                new String[]{query})) {
            while (cursor.moveToNext()) {
                result.add(new Unigram(cursor.getString(0), cursor.getDouble(1),
                        cursor.getDouble(2)));
            }
        }
        return result;
    }

    String learnedCandidate(String query) {
        try (Cursor cursor = database.rawQuery(
                "SELECT current FROM user_candidate_override_cache WHERE qstring = ? "
                        + "ORDER BY rowid DESC LIMIT 1", new String[]{query})) {
            return cursor.moveToFirst() ? cursor.getString(0) : null;
        }
    }

    Double learnedBigram(String previousQuery, String query,
                         String previous, String current) {
        try (Cursor cursor = database.rawQuery(
                "SELECT probability FROM user_bigram_cache WHERE "
                        + "qstring = ? AND previous = ? AND current = ? "
                        + "ORDER BY rowid DESC LIMIT 1",
                new String[]{previousQuery + " " + query, previous, current})) {
            return cursor.moveToFirst() ? cursor.getDouble(0) : null;
        }
    }

    void learnCandidate(String query, String current,
                        String previousQuery, String previous) {
        if (query.isEmpty() || current.isEmpty()) return;
        database.beginTransaction();
        try {
            database.execSQL("DELETE FROM user_candidate_override_cache WHERE qstring = ?",
                    new Object[]{query});
            database.execSQL("INSERT INTO user_candidate_override_cache VALUES (?, ?)",
                    new Object[]{query, current});
            if (previousQuery != null && previous != null && !previousQuery.isEmpty()) {
                learnBigramInTransaction(previousQuery, query, previous, current);
            }
            database.setTransactionSuccessful();
        } finally {
            database.endTransaction();
        }
    }

    void learnComposition(SmartMandarinComposition composition) {
        List<SmartMandarinSegment> segments = composition.segments();
        if (segments.size() < 2) return;
        database.beginTransaction();
        try {
            for (int index = 1; index < segments.size(); index++) {
                SmartMandarinSegment previous = segments.get(index - 1);
                SmartMandarinSegment current = segments.get(index);
                learnBigramInTransaction(previous.query(), current.query(),
                        previous.text(), current.text());
            }
            database.setTransactionSuccessful();
        } finally {
            database.endTransaction();
        }
    }

    private void learnBigramInTransaction(String previousQuery, String query,
                                          String previous, String current) {
        String combined = previousQuery + " " + query;
        database.execSQL("DELETE FROM user_bigram_cache WHERE qstring = ?",
                new Object[]{combined});
        database.execSQL("INSERT INTO user_bigram_cache VALUES (?, ?, ?, 0)",
                new Object[]{combined, previous, current});
    }

    void resetLearning() {
        database.beginTransaction();
        try {
            database.execSQL("DELETE FROM user_bigram_cache");
            database.execSQL("DELETE FROM user_candidate_override_cache");
            database.setTransactionSuccessful();
        } finally {
            database.endTransaction();
        }
    }

    List<Phrase> phrases() {
        ArrayList<Phrase> result = new ArrayList<>();
        try (Cursor cursor = database.rawQuery(
                "SELECT rowid, current, qstring FROM user_unigrams ORDER BY rowid", null)) {
            while (cursor.moveToNext()) {
                String reading = readingForQuery(cursor.getString(2));
                if (reading != null) {
                    result.add(new Phrase(cursor.getLong(0), cursor.getString(1), reading));
                }
            }
        }
        return result;
    }

    void savePhrase(Long id, String text, String reading) {
        text = text.trim();
        String query = queryForReading(reading);
        if (query == null || text.isEmpty() || text.codePointCount(0, text.length()) > 8
                || text.codePoints().anyMatch(Character::isWhitespace)
                || text.codePointCount(0, text.length()) != query.length() / 2) {
            throw new IllegalArgumentException("詞句須為 1 至 8 字，且每個字都要有一組有效注音。");
        }
        try (Cursor cursor = database.rawQuery(
                "SELECT rowid FROM user_unigrams WHERE qstring = ? AND current = ? LIMIT 1",
                new String[]{query, text})) {
            if (cursor.moveToFirst() && (id == null || cursor.getLong(0) != id)) {
                throw new IllegalArgumentException("這個自訂詞與注音已存在。");
            }
        }
        if (id == null) {
            database.execSQL("INSERT INTO user_unigrams VALUES (?, ?, -1.0, 0.0)",
                    new Object[]{query, text});
        } else {
            database.execSQL("UPDATE user_unigrams SET qstring = ?, current = ? WHERE rowid = ?",
                    new Object[]{query, text, id});
        }
    }

    void deletePhrase(long id) {
        database.execSQL("DELETE FROM user_unigrams WHERE rowid = ?", new Object[]{id});
    }

    /** The unencrypted phrase section of macOS's MJSR 1.0.0 export. */
    String exportPhrases() {
        StringBuilder result = new StringBuilder("MJSR version 1.0.0\n");
        try (Cursor cursor = database.rawQuery(
                "SELECT qstring, current, probability, backoff FROM user_unigrams ORDER BY rowid",
                null)) {
            while (cursor.moveToNext()) {
                String reading = readingForQuery(cursor.getString(0));
                if (reading == null) continue;
                result.append(cursor.getString(1)).append('\t')
                        .append(reading.replace(' ', ',')).append('\t')
                        .append(cursor.getDouble(2)).append('\t')
                        .append(cursor.getDouble(3)).append('\n');
            }
        }
        return result.toString();
    }

    ImportResult importPhrases(String contents) {
        String[] lines = contents.split("\\r?\\n", -1);
        if (lines.length == 0 || !lines[0].contains("MJSR version 1.0.0")) {
            throw new IllegalArgumentException("不是 macOS MJSR 1.0.0 詞庫檔案");
        }
        int imported = 0, skipped = 0;
        database.beginTransaction();
        try {
            for (int lineIndex = 1; lineIndex < lines.length; lineIndex++) {
                String line = lines[lineIndex];
                if (line.contains("<database>")) break;
                if (line.isEmpty() || line.startsWith("#")) continue;
                String[] fields = line.split("\\t", -1);
                if (fields.length < 2) { skipped++; continue; }
                String text = fields[0];
                String query = queryForReading(fields[1]);
                if (query == null || text.isEmpty() || text.codePointCount(0, text.length()) > 8
                        || text.codePoints().anyMatch(Character::isWhitespace)
                        || text.codePointCount(0, text.length()) != query.length() / 2) {
                    skipped++;
                    continue;
                }
                try (Cursor existing = database.rawQuery(
                        "SELECT 1 FROM user_unigrams WHERE qstring = ? AND current = ? LIMIT 1",
                        new String[]{query, text})) {
                    if (existing.moveToFirst()) { skipped++; continue; }
                }
                double probability = parseFinite(fields, 2, -1);
                double backoff = parseFinite(fields, 3, 0);
                database.execSQL("INSERT INTO user_unigrams VALUES (?, ?, ?, ?)",
                        new Object[]{query, text, probability, backoff});
                imported++;
            }
            database.setTransactionSuccessful();
        } finally {
            database.endTransaction();
        }
        return new ImportResult(imported, skipped);
    }

    private static double parseFinite(String[] fields, int index, double fallback) {
        if (index >= fields.length) return fallback;
        try {
            double value = Double.parseDouble(fields[index]);
            return Double.isFinite(value) ? value : fallback;
        } catch (NumberFormatException error) {
            return fallback;
        }
    }

    static String queryForReading(String reading) {
        ArrayList<String> syllables = new ArrayList<>();
        for (String part : reading.trim().split("[\\s,，]+")) {
            StringBuilder current = new StringBuilder();
            for (int offset = 0; offset < part.length();) {
                int point = part.codePointAt(offset);
                offset += Character.charCount(point);
                current.appendCodePoint(point);
                if (("6347ˊˇˋ˙".indexOf(point) >= 0) && current.codePointCount(0,
                        current.length()) > 1) {
                    syllables.add(current.toString());
                    current.setLength(0);
                }
            }
            if (current.length() > 0) syllables.add(current.toString());
        }
        if (syllables.size() < 1 || syllables.size() > 8) return null;
        StringBuilder result = new StringBuilder();
        for (String syllable : syllables) {
            String key = BopomofoReading.languageModelKeyForReading(syllable);
            if (key == null) return null;
            result.append(key);
        }
        return result.toString();
    }

    static String readingForQuery(String query) {
        if (query == null || query.isEmpty() || query.length() % 2 != 0) return null;
        ArrayList<String> syllables = new ArrayList<>();
        for (int index = 0; index < query.length(); index += 2) {
            String reading = BopomofoReading.readingForLanguageModelKey(
                    query.substring(index, index + 2));
            if (reading == null) return null;
            syllables.add(reading);
        }
        return String.join(" ", syllables);
    }

    @Override public void close() {
        database.close();
    }
}
