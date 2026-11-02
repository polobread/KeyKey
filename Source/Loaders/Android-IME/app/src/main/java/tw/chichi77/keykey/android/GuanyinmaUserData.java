// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
package tw.chichi77.keykey.android;

import android.content.Context;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** Rust's independent user store, edited only through the shared C ABI. */
final class GuanyinmaUserData implements UserPhraseRepository {
    static final String FILE_NAME = "GuanyinmaUser.db";
    private final Runnable changeListener;
    private final GuanyinmaNative session;
    private final Map<Long, UserPhraseArchive.Row> tokens = new HashMap<>();
    private long nextToken = 1;

    GuanyinmaUserData(Context context) {
        this(installModel(context), new File(context.getFilesDir(), FILE_NAME),
                () -> UserDataNotifications.changed(context));
    }
    // The same repository is usable by a headless JNI smoke with temporary files.
    GuanyinmaUserData(File model, File user, Runnable changeListener) {
        this.changeListener = changeListener;
        try {
            session = GuanyinmaNative.open(model.getAbsolutePath(), object(
                    "method", "smart", "user_database", user.getAbsolutePath(),
                    "learning", object("user_phrases", true, "candidate_overrides", false,
                            "bigrams", false, "table_learning", false)).toString(), text -> true);
        } catch (LinkageError error) { throw new IllegalStateException("無法載入 Guanyinma 核心", error); }
    }
    private static File installModel(Context context) {
        try { return SharedModelDatabase.install(context); }
        catch (IOException error) { throw new IllegalStateException("無法準備共用字庫", error); }
    }

    @Override public List<Phrase> phrases() {
        List<UserPhraseArchive.Row> rows = rows();
        tokens.clear();
        ArrayList<Phrase> result = new ArrayList<>();
        for (UserPhraseArchive.Row row : rows) {
            String reading = PhraseReadingCodec.readingForQuery(row.query());
            if (reading == null) continue;
            long token = nextToken++;
            tokens.put(token, row);
            result.add(new Phrase(token, row.text(), reading));
        }
        return result;
    }
    @Override public void savePhrase(Long id, String text, String reading) {
        text = text.trim();
        String query = UserPhraseArchive.checkedQuery(text, reading);
        if (id == null) {
            if (contains(rows(), query, text)) throw duplicatePhrase();
            session.apply(object("type", "add_user_phrase", "qstring", query, "text", text).toString());
            // The core deliberately ignores a phrase already in its model.
            // A successful C call alone does not mean a custom row was added.
            if (!contains(rows(), query, text)) throw duplicatePhrase();
        } else {
            UserPhraseArchive.Row previous = existing(id);
            session.apply(object("type", "update_user_phrase", "qstring", previous.query(),
                    "text", previous.text(), "new_qstring", query, "new_text", text).toString());
        }
        changed();
    }
    private static boolean contains(List<UserPhraseArchive.Row> rows, String query, String text) {
        for (UserPhraseArchive.Row row : rows) {
            if (row.query().equals(query) && row.text().equals(text)) return true;
        }
        return false;
    }
    private static IllegalArgumentException duplicatePhrase() {
        return new IllegalArgumentException("這個注音與詞句已存在於內建或自訂詞庫。");
    }
    @Override public void deletePhrase(long id) {
        UserPhraseArchive.Row previous = existing(id);
        session.apply(object("type", "remove_user_phrase", "qstring", previous.query(),
                "text", previous.text()).toString());
        changed();
    }
    private UserPhraseArchive.Row existing(long token) {
        UserPhraseArchive.Row row = tokens.get(token);
        if (row == null || rows().stream().noneMatch(value ->
                value.query().equals(row.query()) && value.text().equals(row.text()))) {
            throw new IllegalStateException("這筆詞條已變更，請重新開啟詞庫再編輯。");
        }
        return row;
    }
    @Override public String exportPhrases() { return UserPhraseArchive.export(rows()); }
    @Override public ImportResult importPhrases(String contents) {
        UserPhraseArchive.Parsed parsed = UserPhraseArchive.parse(contents);
        Set<List<String>> present = new HashSet<>();
        for (UserPhraseArchive.Row row : rows()) present.add(List.of(row.query(), row.text()));
        JSONArray phrases = new JSONArray();
        int skipped = parsed.skipped();
        for (UserPhraseArchive.Row row : parsed.rows()) {
            if (!present.add(List.of(row.query(), row.text()))) { skipped++; continue; }
            phrases.put(object("qstring", row.query(), "current", row.text(),
                    "probability", row.probability(), "backoff", row.backoff()));
        }
        if (phrases.length() > 0) {
            // Missing smart/table scopes preserve both forms of local learning.
            JSONObject archive = object("format", "guanyinma_user_data", "schema_version", 1,
                    "phrases", phrases);
            session.apply(object("type", "import_user_data", "archive", archive).toString());
            changed();
        }
        return new ImportResult(phrases.length(), skipped);
    }
    @Override public void resetSmartLearning() {
        session.apply(object("type", "reset_method_learning", "method", "smart").toString());
        changed();
    }
    private List<UserPhraseArchive.Row> rows() {
        try {
            JSONObject result = new JSONObject(session.userData());
            if (result.getInt("schema_version") != 1 || !"user_data".equals(result.getString("kind"))) {
                throw new IllegalStateException("不支援的 Guanyinma 詞庫快照");
            }
            JSONArray rows = result.getJSONObject("data").getJSONArray("phrases");
            ArrayList<UserPhraseArchive.Row> values = new ArrayList<>();
            for (int index = 0; index < rows.length(); index++) {
                JSONObject row = rows.getJSONObject(index);
                values.add(new UserPhraseArchive.Row(row.getString("qstring"), row.getString("current"),
                        row.getDouble("probability"), row.getDouble("backoff")));
            }
            return values;
        } catch (JSONException error) { throw new IllegalStateException("無法讀取 Guanyinma 詞庫快照", error); }
    }
    private static JSONObject object(Object... pairs) {
        JSONObject result = new JSONObject();
        try {
            for (int index = 0; index < pairs.length; index += 2) result.put((String) pairs[index], pairs[index + 1]);
        } catch (JSONException error) { throw new IllegalArgumentException("無法編碼 Guanyinma 操作", error); }
        return result;
    }
    private void changed() {
        tokens.clear();
        changeListener.run();
    }
    @Override public void close() { tokens.clear(); session.close(); }
}
