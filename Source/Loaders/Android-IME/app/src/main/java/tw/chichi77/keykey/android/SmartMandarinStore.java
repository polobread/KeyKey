package tw.chichi77.keykey.android;

import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** Lazy, read-only Viterbi walker over the same language model used by macOS and iOS. */
final class SmartMandarinStore implements SmartMandarinSource, AutoCloseable {
    private static final String ASSET_NAME = "KeyKey.db";
    private static final String INSTALLED_NAME = "KeyKey-smart-reading-v2.db";
    private static final String[] PREVIOUS_INSTALLED_NAMES = {
            "KeyKey-smart-885614.db", "KeyKey-smart-1.2.10.db"
    };
    private static final long EXPECTED_BIGRAM_ROWS = 885_614;
    private static final int MAXIMUM_SPAN = 8;

    private record Unigram(String text, double probability, double backoff) {}
    private record BigramKey(String previous, String current) {}
    private record Path(double score, double lastBackoff,
                        List<SmartMandarinSegment> segments) {}

    private final SQLiteDatabase database;
    private final SmartMandarinUserData userData;
    private final Map<String, List<Unigram>> unigramCache = new HashMap<>();
    private final Map<String, Map<BigramKey, Double>> bigramCache = new HashMap<>();

    static SmartMandarinStore open(Context context, SmartMandarinUserData userData)
            throws IOException {
        File databaseFile = new File(context.getNoBackupFilesDir(), INSTALLED_NAME);
        if (!databaseFile.isFile() || databaseFile.length() == 0) {
            File temporary = new File(databaseFile.getParentFile(), INSTALLED_NAME + ".tmp");
            try (InputStream input = context.getAssets().open(ASSET_NAME);
                 FileOutputStream output = new FileOutputStream(temporary)) {
                byte[] buffer = new byte[64 * 1024];
                int count;
                while ((count = input.read(buffer)) >= 0) output.write(buffer, 0, count);
                output.getFD().sync();
            } catch (IOException error) {
                temporary.delete();
                throw error;
            }
            if (!temporary.renameTo(databaseFile)) {
                temporary.delete();
                throw new IOException("Unable to install " + ASSET_NAME);
            }
        }
        SQLiteDatabase database = SQLiteDatabase.openDatabase(
                databaseFile.getAbsolutePath(), null, SQLiteDatabase.OPEN_READONLY);
        try (Cursor cursor = database.rawQuery("SELECT COUNT(*) FROM bigrams", null)) {
            if (!cursor.moveToFirst() || cursor.getLong(0) != EXPECTED_BIGRAM_ROWS) {
                throw new IOException("The bundled Smart Mandarin database must have 885614 bigrams");
            }
        } catch (IOException | RuntimeException error) {
            database.close();
            throw error;
        }
        for (String previousName : PREVIOUS_INSTALLED_NAMES) {
            new File(databaseFile.getParentFile(), previousName).delete();
        }
        return new SmartMandarinStore(database, userData);
    }

    SmartMandarinStore(SQLiteDatabase database) {
        this(database, null);
    }

    SmartMandarinStore(SQLiteDatabase database, SmartMandarinUserData userData) {
        this.database = database;
        this.userData = userData;
    }

    @Override
    public SmartMandarinComposition compose(List<String> readings,
                                             Map<Integer, String> overrides) {
        if (readings.isEmpty()) return new SmartMandarinComposition("", List.of());

        List<Map<String, Path>> paths = new ArrayList<>(readings.size() + 1);
        for (int index = 0; index <= readings.size(); index++) paths.add(new HashMap<>());
        paths.get(0).put("", new Path(0, 0, List.of()));

        for (int start = 0; start < readings.size(); start++) {
            if (paths.get(start).isEmpty()) continue;
            int largestSpan = Math.min(MAXIMUM_SPAN, readings.size() - start);
            for (int length = 1; length <= largestSpan; length++) {
                int end = start + length;
                String query = String.join("", readings.subList(start, end));
                Set<Integer> protectedIndices = new HashSet<>();
                for (int index : overrides.keySet()) {
                    if (start <= index && index < end) protectedIndices.add(index);
                }
                if (!protectedIndices.isEmpty()
                        && !(length == 1 && protectedIndices.size() == 1
                        && protectedIndices.contains(start))) continue;

                List<Unigram> entries = unigrams(query);
                String learned = learnedCandidate(query);
                String required = overrides.get(start);
                if (required != null) {
                    ArrayList<Unigram> matching = new ArrayList<>();
                    for (Unigram row : entries) {
                        if (row.text().equals(required)) matching.add(row);
                    }
                    entries = matching;
                }
                if (entries.isEmpty()) continue;

                for (Unigram entry : entries) {
                    SmartMandarinSegment segment = new SmartMandarinSegment(
                            start, length, query, entry.text());
                    for (Path previousPath : paths.get(start).values()) {
                        Double bigram;
                        if (previousPath.segments().isEmpty()) {
                            bigram = bigramProbability("!", query, "", entry.text());
                        } else {
                            SmartMandarinSegment previous = previousPath.segments()
                                    .get(previousPath.segments().size() - 1);
                            bigram = bigramProbability(previous.query(), query,
                                    previous.text(), entry.text());
                        }
                        double fallback = previousPath.lastBackoff() + entry.probability();
                        double transition = bigram == null
                                ? fallback : Math.max(bigram, fallback);
                        ArrayList<SmartMandarinSegment> segments =
                                new ArrayList<>(previousPath.segments());
                        segments.add(segment);
                        if (entry.text().equals(learned)) {
                            transition = Math.max(transition, 0);
                        }
                        Path path = new Path(previousPath.score() + transition,
                                entry.backoff(), List.copyOf(segments));
                        String stateKey = query + '\u001f' + entry.text();
                        Path existing = paths.get(end).get(stateKey);
                        if (existing == null || path.score() > existing.score()) {
                            paths.get(end).put(stateKey, path);
                        }
                    }
                }
            }
        }

        Path best = null;
        double bestScore = Double.NEGATIVE_INFINITY;
        for (Path path : paths.get(readings.size()).values()) {
            double score = finalScore(path);
            if (score > bestScore) {
                best = path;
                bestScore = score;
            }
        }
        if (best == null) return null;
        StringBuilder text = new StringBuilder();
        for (SmartMandarinSegment segment : best.segments()) text.append(segment.text());
        return new SmartMandarinComposition(text.toString(), best.segments());
    }

    @Override
    public List<String> candidates(List<String> readings, int index,
                                   SmartMandarinComposition composition) {
        if (index < 0 || index >= readings.size()) return List.of();
        String query = readings.get(index);
        String learned = learnedCandidate(query);
        SmartMandarinSegment previous = null;
        if (composition != null) {
            for (SmartMandarinSegment segment : composition.segments()) {
                if (segment.start() + segment.length() == index) previous = segment;
            }
        }

        record Ranked(String text, double score) {}
        ArrayList<Ranked> ranked = new ArrayList<>();
        double previousBackoff = 0;
        if (previous != null) {
            for (Unigram item : unigrams(previous.query())) {
                if (item.text().equals(previous.text())) {
                    previousBackoff = item.backoff();
                    break;
                }
            }
        }
        for (Unigram entry : unigrams(query)) {
            Double bigram = previous == null
                    ? bigramProbability("!", query, "", entry.text())
                    : bigramProbability(previous.query(), query,
                            previous.text(), entry.text());
            double fallback = previousBackoff + entry.probability();
            ranked.add(new Ranked(entry.text(), entry.text().equals(learned) ? 0
                    : bigram == null ? fallback : Math.max(bigram, fallback)));
        }
        ranked.sort((left, right) -> Double.compare(right.score(), left.score()));
        LinkedHashSet<String> unique = new LinkedHashSet<>();
        for (Ranked item : ranked) unique.add(item.text());
        return List.copyOf(unique);
    }

    @Override
    public void learnSelection(List<String> readings, int index, String selected,
                               SmartMandarinComposition composition) {
        if (userData == null || index < 0 || index >= readings.size()) return;
        SmartMandarinSegment previous = null;
        if (composition != null) {
            for (SmartMandarinSegment segment : composition.segments()) {
                if (segment.start() + segment.length() == index) previous = segment;
            }
        }
        try {
            userData.learnCandidate(readings.get(index), selected,
                    previous == null ? null : previous.query(),
                    previous == null ? null : previous.text());
        } catch (RuntimeException ignored) {
            // A temporarily unavailable user database must not stop text input.
        }
    }

    @Override
    public void learnConfirmedComposition(SmartMandarinComposition composition) {
        if (userData == null) return;
        try {
            userData.learnComposition(composition);
        } catch (RuntimeException ignored) {
            // The cooked model can still commit the completed text.
        }
    }

    private double finalScore(Path path) {
        if (path.segments().isEmpty()) return path.score();
        SmartMandarinSegment last = path.segments().get(path.segments().size() - 1);
        Double ending = bigramProbability(last.query(), "$", last.text(), "");
        return path.score() + (ending == null
                ? path.lastBackoff() : Math.max(ending, path.lastBackoff()));
    }

    private List<Unigram> unigrams(String query) {
        List<Unigram> cached = unigramCache.get(query);
        if (cached == null) {
            ArrayList<Unigram> rows = new ArrayList<>();
            try (Cursor cursor = database.rawQuery(
                "SELECT current, probability, backoff FROM unigrams "
                        + "WHERE qstring = ? ORDER BY probability DESC LIMIT 64",
                new String[]{query})) {
                while (cursor.moveToNext()) {
                    String text = cursor.getString(0);
                    if (text != null && !text.isEmpty()) {
                        rows.add(new Unigram(text, cursor.getDouble(1), cursor.getDouble(2)));
                    }
                }
            }
            cached = List.copyOf(rows);
            unigramCache.put(query, cached);
        }
        if (userData == null) return cached;
        HashMap<String, Unigram> merged = new HashMap<>();
        for (Unigram item : cached) merged.put(item.text(), item);
        try {
            for (SmartMandarinUserData.Unigram item : userData.unigrams(query)) {
                merged.put(item.text(), new Unigram(item.text(), item.probability(), item.backoff()));
            }
        } catch (RuntimeException ignored) {
            // Keep the cooked model available if the user database is busy.
        }
        String learned = learnedCandidate(query);
        if (learned != null && merged.containsKey(learned)) {
            Unigram item = merged.get(learned);
            merged.put(learned, new Unigram(learned, 0, item.backoff()));
        }
        ArrayList<Unigram> result = new ArrayList<>(merged.values());
        result.sort((left, right) -> Double.compare(right.probability(), left.probability()));
        return result;
    }

    private Double bigramProbability(String previousQuery, String currentQuery,
                                     String previousText, String currentText) {
        if (userData != null) {
            try {
                Double learned = userData.learnedBigram(previousQuery, currentQuery,
                        previousText, currentText);
                if (learned != null) return learned;
            } catch (RuntimeException ignored) {
                // Use the cooked bigram when the user database is busy.
            }
        }
        String query = previousQuery + " " + currentQuery;
        Map<BigramKey, Double> rows = bigramCache.get(query);
        if (rows == null) {
            rows = new HashMap<>();
            try (Cursor cursor = database.rawQuery(
                    "SELECT previous, current, probability FROM bigrams WHERE qstring = ?",
                    new String[]{query})) {
                while (cursor.moveToNext()) {
                    rows.put(new BigramKey(cursor.getString(0), cursor.getString(1)),
                            cursor.getDouble(2));
                }
            }
            bigramCache.put(query, rows);
        }
        return rows.get(new BigramKey(previousText, currentText));
    }

    @Override
    public void close() {
        database.close();
    }

    private String learnedCandidate(String query) {
        if (userData == null) return null;
        try {
            return userData.learnedCandidate(query);
        } catch (RuntimeException ignored) {
            return null;
        }
    }
}
