package tw.chichi77.keykey.android;

import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.content.SharedPreferences;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Lazy lookups over the same cooked table used by macOS/iOS; bounded raw cache. */
final class TableCandidateStore implements TableCandidateSource {
    private final SQLiteDatabase database;
    private final SharedPreferences learning;
    private final Map<String, List<String>> cache = new HashMap<>();
    TableCandidateStore(SQLiteDatabase database, SharedPreferences learning) {
        this.database = database; this.learning = learning;
    }
    private List<String> rows(String table, String code, boolean wildcard) {
        String cacheKey = table + ":" + code;
        if (!wildcard && cache.containsKey(cacheKey)) return cache.get(cacheKey);
        ArrayList<String> values = new ArrayList<>();
        // table comes only from fixed enum/override names; code is always bound.
        try (Cursor cursor = database.rawQuery("SELECT value FROM '" + table + "' WHERE key "
                + (wildcard ? "GLOB" : "=") + " ? ORDER BY rowid", new String[]{wildcard ? code.replace("[", "[[]") : code})) {
            while (cursor.moveToNext()) values.add(cursor.getString(0));
        }
        if (cache.size() >= 128) cache.clear();
        List<String> result = List.copyOf(values);
        if (!wildcard && result.size() <= 256) cache.put(cacheKey, result);
        return result;
    }
    public List<String> values(ChineseInputMethod method, String code, int punctuation) {
        boolean wildcard = method == ChineseInputMethod.CANGJIE && code.length() > 1
                && (code.contains("?") || code.contains("*"));
        if (method == ChineseInputMethod.CANGJIE && punctuation > 0 && !wildcard) {
            List<String> override = rows(punctuation == 1 ? "Punctuations-cj-mixedwidth-cin"
                    : "Punctuations-cj-halfwidth-cin", code, false);
            if (!override.isEmpty()) return override;
        }
        return rows(method.tableName(), code, wildcard);
    }
    public String keyName(ChineseInputMethod method, String key) {
        List<String> names = rows(method.tableName(), "__property_keyname-" + key, false);
        return names.isEmpty() ? null : names.get(0);
    }
    public String endKeys(ChineseInputMethod method) {
        List<String> names = rows(method.tableName(), "__property_endkey", false);
        return names.isEmpty() ? "" : names.get(0);
    }
    private String countKey(String code, String text) { return "cangjie_order." + code + "." + text; }
    public void learn(String code, String text) {
        String key = countKey(code, text);
        learning.edit().putInt(key, Math.min(learning.getInt(key, 0) + 1, 1_000_000)).apply();
    }
    public List<String> ordered(List<String> values, String code) {
        ArrayList<String> result = new ArrayList<>(values);
        result.sort((a, b) -> Integer.compare(learning.getInt(countKey(code, b), 0),
                learning.getInt(countKey(code, a), 0)));
        return List.copyOf(result);
    }
}
