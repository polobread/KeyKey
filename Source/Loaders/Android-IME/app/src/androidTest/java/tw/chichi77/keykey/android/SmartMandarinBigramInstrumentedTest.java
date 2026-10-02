package tw.chichi77.keykey.android;

import static org.junit.Assert.*;

import android.content.Context;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.util.List;
import java.util.Map;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Runs against Android SQLite, including API 26, rather than a substitute language model. */
@RunWith(AndroidJUnit4.class)
public final class SmartMandarinBigramInstrumentedTest {
    private static final String NI = BopomofoReading.languageModelKeyForReading("ㄋㄧˇ");
    private static final String HAO = BopomofoReading.languageModelKeyForReading("ㄏㄠˇ");
    private static final List<String> READINGS = List.of(NI, HAO);
    private SQLiteDatabase model;
    private SQLiteDatabase learning;
    private SmartMandarinUserData userData;
    private SmartMandarinStore store;

    @Before public void setUp() {
        model = SQLiteDatabase.create(null);
        model.execSQL("CREATE TABLE unigrams (qstring, current, probability, backoff)");
        model.execSQL("CREATE TABLE bigrams (qstring, previous, current, probability)");
        unigram(NI, "你", -1, -30);
        unigram(NI, "妳", -2, 0);
        unigram(HAO, "好", -1, -20);
        unigram(HAO, "郝", -2, 0);
        unigram(NI + HAO, "你好", -5, 0);
        bigram("! " + NI, "", "妳", 0);
        bigram(NI + " " + HAO, "妳", "郝", 0);
        bigram(HAO + " $", "郝", "", 0);
        learning = SQLiteDatabase.create(null);
        userData = new SmartMandarinUserData(learning);
        store = new SmartMandarinStore(model, userData);
    }

    @After public void tearDown() {
        store.close();
        userData.close();
    }

    @Test public void defaultsToContextAndCanToggleBothWays() {
        assertEquals("妳郝", compose().text());
        store.setBigramEnabled(false);
        assertEquals("你好", compose().text());
        assertEquals(2, compose().segments().size()); // No backoff or end marker scoring.
        store.setBigramEnabled(true);
        assertEquals("妳郝", compose().text());
    }

    @Test public void disabledCanComposeAndListCandidatesWithoutBigramTable() {
        store.setBigramEnabled(false);
        model.execSQL("DROP TABLE bigrams"); // Any bundled Bigram SELECT now fails the test.
        assertEquals("你", store.composeSelections(List.of(NI), Map.of()).text());
        SmartMandarinComposition sentence = compose();
        assertEquals("你好", sentence.text());
        assertEquals(List.of("你", "妳", "你好"), store.candidates(READINGS, 0, sentence));
        assertEquals(List.of("好", "郝"), store.candidates(READINGS, 1, sentence));
        assertEquals("妳好", store.composeSelections(READINGS,
                Map.of(0, new SmartMandarinSelection(1, "妳"))).text());
    }

    @Test public void disabledIgnoresLearnedContextAndPreservesItForReenabling() {
        model.execSQL("DELETE FROM bigrams");
        // Without learned context, either mode chooses 你 for an isolated syllable.
        learning.execSQL("INSERT INTO user_bigram_cache VALUES (?, ?, ?, ?)",
                new Object[]{"! " + NI, "", "妳", 0});
        assertEquals("妳", store.composeSelections(List.of(NI), Map.of()).text());
        store.setBigramEnabled(false);
        assertEquals("你", store.composeSelections(List.of(NI), Map.of()).text());
        store.setBigramEnabled(true);
        assertEquals("妳", store.composeSelections(List.of(NI), Map.of()).text());
    }

    @Test public void disabledKeepsCustomPhrasesAndCandidateLearningWithoutBigramWrites() {
        store.setBigramEnabled(false);
        learning.execSQL("INSERT INTO user_bigram_cache VALUES (?, ?, ?, ?)",
                new Object[]{"sentinel", "舊", "詞", -3});
        // Fail immediately if a disabled learning path attempts any context writes.
        learning.execSQL("CREATE TRIGGER no_context_insert BEFORE INSERT ON user_bigram_cache "
                + "BEGIN SELECT RAISE(ABORT, 'unexpected context insert'); END");
        learning.execSQL("CREATE TRIGGER no_context_delete BEFORE DELETE ON user_bigram_cache "
                + "BEGIN SELECT RAISE(ABORT, 'unexpected context delete'); END");
        SmartMandarinComposition sentence = compose();
        store.learnSelection(READINGS, 1, new SmartMandarinCandidate(1, "郝"), sentence);
        assertEquals("郝", userData.learnedCandidate(HAO));
        assertEquals("你郝", compose().text());
        store.learnConfirmedComposition(compose());
        try (Cursor rows = learning.rawQuery(
                "SELECT qstring, probability FROM user_bigram_cache", null)) {
            assertEquals(1, rows.getCount());
            assertTrue(rows.moveToFirst());
            assertEquals("sentinel", rows.getString(0));
            assertEquals(-3, rows.getDouble(1), 0);
        }
        learning.execSQL("DELETE FROM user_candidate_override_cache");
        userData.savePhrase(null, "擬好", "ㄋㄧˇ ㄏㄠˇ");
        assertEquals("擬好", compose().text());
        assertTrue(store.candidates(READINGS, 0, compose()).contains("擬好"));
    }

    @Test public void confirmationDoesNotLearnButExplicitSelectionStillDoes() {
        store.setBigramEnabled(false);
        store.learnConfirmedComposition(compose());
        assertNull(userData.learnedBigram(NI, HAO, "你", "好"));
        store.setBigramEnabled(true);
        SmartMandarinComposition sentence = compose();
        store.learnConfirmedComposition(sentence);
        assertNull(userData.learnedBigram(NI, HAO, "妳", "郝"));
        store.learnSelection(READINGS, 1, new SmartMandarinCandidate(1, "郝"), sentence);
        assertEquals(Double.valueOf(0), userData.learnedBigram(NI, HAO, "妳", "郝"));
    }

    @Test public void learnedSingleCharacterKeepsStrongerCookedPhrase() throws Exception {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String ke = BopomofoReading.languageModelKeyForReading("ㄎㄜˇ");
        String yi = BopomofoReading.languageModelKeyForReading("ㄧˇ");
        List<String> phrase = List.of(ke, yi);
        try (SmartMandarinStore real = SmartMandarinStore.open(context, userData)) {
            String de = BopomofoReading.languageModelKeyForReading("ㄉㄜ˙");
            assertEquals("舊的", real.composeSelections(List.of(
                    BopomofoReading.languageModelKeyForReading("ㄐㄧㄡˋ"), de), Map.of()).text());
            assertEquals("新的", real.composeSelections(List.of(
                    BopomofoReading.languageModelKeyForReading("ㄒㄧㄣ"), de), Map.of()).text());
            assertEquals("可以", real.composeSelections(phrase, Map.of()).text());
            userData.learnCandidate(yi, "已", null, null);
            assertEquals("已", real.candidates(List.of(yi), 0, null).get(0));
            assertEquals("可以", real.composeSelections(phrase, Map.of()).text());
            assertEquals("可已", real.composeSelections(phrase,
                    Map.of(1, new SmartMandarinSelection(1, "已"))).text());
            userData.resetLearning();
            assertEquals("可以", real.composeSelections(phrase, Map.of()).text());
        }
    }

    @Test public void collectionWordsAndChineseAliasesAreSelectable() throws Exception {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String[][] rows = {{"神經網路", "ㄕㄣˊ", "ㄐㄧㄥ", "ㄨㄤˇ", "ㄌㄨˋ"},
                {"蒙其迪魯夫", "ㄇㄥˊ", "ㄑㄧˊ", "ㄉㄧˊ", "ㄌㄨˇ", "ㄈㄨ"}};
        try (SmartMandarinStore real = SmartMandarinStore.open(context, userData)) {
            for (String[] row : rows) {
                java.util.ArrayList<String> readings = new java.util.ArrayList<>();
                for (int i = 1; i < row.length; i++) readings.add(BopomofoReading.languageModelKeyForReading(row[i]));
                assertTrue(real.candidates(readings, 0, null).contains(row[0]));
                assertEquals(row[0], real.composeSelections(readings,
                        Map.of(0, new SmartMandarinSelection(readings.size(), row[0]))).text());
            }
        }
    }

    @Test public void preferenceDefaultsOnAndPersistsIndependentlyOfCompositionMode() {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        SharedPreferences prefs = BopomofoCompositionModeSettings.preferences(context);
        String key = BopomofoCompositionModeSettings.KEY_BIGRAM_ENABLED;
        boolean hadValue = prefs.contains(key);
        boolean oldValue = BopomofoCompositionModeSettings.bigramEnabled(context);
        BopomofoCompositionMode oldMode = BopomofoCompositionModeSettings.mode(context);
        try {
            prefs.edit().remove(key).commit();
            assertTrue(BopomofoCompositionModeSettings.bigramEnabled(context));
            BopomofoCompositionModeSettings.setBigramEnabled(context, false);
            assertFalse(BopomofoCompositionModeSettings.bigramEnabled(context));
            BopomofoCompositionModeSettings.setMode(context, BopomofoCompositionMode.TRADITIONAL);
            BopomofoCompositionModeSettings.setMode(context, BopomofoCompositionMode.SMART);
            assertFalse(BopomofoCompositionModeSettings.bigramEnabled(context));
        } finally {
            BopomofoCompositionModeSettings.setMode(context, oldMode);
            if (hadValue) prefs.edit().putBoolean(key, oldValue).commit();
            else prefs.edit().remove(key).commit();
        }
    }

    @Test public void switchingPreservesVisibleSentenceAndUnfinishedReading() {
        BopomofoEngine engine = new BopomofoEngine(CinDictionary.empty(), store,
                BopomofoCompositionMode.SMART);
        for (char key : "su3c".toCharArray()) engine.handleHardwareCharacter(key);
        String visible = engine.composingText();
        assertEquals("妳ㄏ", visible);
        store.setBigramEnabled(false);
        assertEquals(visible, engine.finishCompositionForModeSwitch().committedText());
        assertFalse(engine.hasComposition());
        for (char key : "su3".toCharArray()) engine.handleHardwareCharacter(key);
        assertEquals("你", engine.composingText());
    }

    @Test public void bundledModelKeepsTouchAndHardwareBoundariesWithEitherSetting()
            throws Exception {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String[] keys = {"fu/3", "ru84", "ul4", "fm4", "s83", "xu3", "j06", "sk7",
                "fm4", "c93", "1u0 ", "up ", "jo4", "s84", "xu3", "u.3", "1u3", "ru ", "su6"};
        for (boolean contextEnabled : new boolean[]{true, false}) {
            for (boolean hardware : new boolean[]{true, false}) {
                try (SmartMandarinStore actual = SmartMandarinStore.open(context, null)) {
                    actual.setBigramEnabled(contextEnabled);
                    BopomofoEngine engine = new BopomofoEngine(CinDictionary.empty(), actual,
                            BopomofoCompositionMode.SMART);
                    StringBuilder committed = new StringBuilder();
                    int limit = hardware ? 10 : 9;
                    for (int index = 0; index < keys.length; index++) {
                        for (char key : keys[index].toCharArray()) {
                            BopomofoEngine.Result result = hardware
                                    ? (key == ' ' ? engine.handleHardwareSpace()
                                            : engine.handleHardwareCharacter(key))
                                    : engine.handleSoftKey(key == ' ' ? "SPACE" : String.valueOf(key));
                            committed.append(result.committedText());
                        }
                        String whole = committed + engine.composingText();
                        assertEquals("context=" + contextEnabled + ", hardware=" + hardware
                                + ", syllable=" + (index + 1),
                                index + 1, whole.codePointCount(0, whole.length()));
                        if (index + 1 == limit) assertEquals("", committed.toString());
                        if (index + 1 == limit + 1) assertEquals("請假", committed.toString());
                    }
                    String visible = committed + engine.composingText();
                    committed.append(engine.enter().committedText());
                    assertEquals(visible, committed.toString());
                    assertFalse(engine.hasComposition());
                }
            }
        }
    }

    private SmartMandarinComposition compose() {
        return store.composeSelections(READINGS, Map.of());
    }

    private void unigram(String query, String text, double probability, double backoff) {
        model.execSQL("INSERT INTO unigrams VALUES (?, ?, ?, ?)",
                new Object[]{query, text, probability, backoff});
    }

    private void bigram(String query, String previous, String current, double probability) {
        model.execSQL("INSERT INTO bigrams VALUES (?, ?, ?, ?)",
                new Object[]{query, previous, current, probability});
    }
}
