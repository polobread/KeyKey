// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
package tw.chichi77.keykey.android;

import android.content.Context;
import java.util.List;

/** User phrases are edited only through the required Guanyinma C ABI. */
interface UserPhraseRepository extends AutoCloseable {
    record Phrase(long id, String text, String reading) {}
    record ImportResult(int imported, int skipped) {}
    List<Phrase> phrases();
    void savePhrase(Long id, String text, String reading);
    void deletePhrase(long id);
    String exportPhrases();
    ImportResult importPhrases(String contents);
    void resetSmartLearning();
    @Override void close();
    static UserPhraseRepository open(Context context) { return new GuanyinmaUserData(context); }
}
