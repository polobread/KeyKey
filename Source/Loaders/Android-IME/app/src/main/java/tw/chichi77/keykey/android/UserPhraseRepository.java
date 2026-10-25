// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
package tw.chichi77.keykey.android;

import android.content.Context;
import java.util.ArrayList;
import java.util.List;

/** A repository is permanently bound to the core captured by its editor. */
interface UserPhraseRepository extends AutoCloseable {
    record Phrase(long id, String text, String reading) {}
    record ImportResult(int imported, int skipped) {}
    InputCore core();
    List<Phrase> phrases();
    void savePhrase(Long id, String text, String reading);
    void deletePhrase(long id);
    String exportPhrases();
    ImportResult importPhrases(String contents);
    void resetSmartLearning();
    @Override void close();

    static UserPhraseRepository open(Context context, InputCore core) {
        return core == InputCore.GUANYINMA ? new GuanyinmaUserData(context) : new Legacy(context);
    }

    final class Legacy implements UserPhraseRepository {
        private final Context context;
        private final SmartMandarinUserData data;
        Legacy(Context context) {
            this.context = context.getApplicationContext();
            data = SmartMandarinUserData.open(context);
        }
        @Override public InputCore core() { return InputCore.JAVA; }
        @Override public List<Phrase> phrases() {
            ArrayList<Phrase> result = new ArrayList<>();
            for (SmartMandarinUserData.Phrase row : data.phrases()) {
                result.add(new Phrase(row.id(), row.text(), row.reading()));
            }
            return result;
        }
        @Override public void savePhrase(Long id, String text, String reading) {
            data.savePhrase(id, text, reading);
            changed();
        }
        @Override public void deletePhrase(long id) { data.deletePhrase(id); changed(); }
        @Override public String exportPhrases() { return data.exportPhrases(); }
        @Override public ImportResult importPhrases(String contents) {
            SmartMandarinUserData.ImportResult result = data.importPhrases(contents);
            if (result.imported() > 0) changed();
            return new ImportResult(result.imported(), result.skipped());
        }
        @Override public void resetSmartLearning() { data.resetLearning(); changed(); }
        private void changed() { InputCoreSettings.notifyUserDataChanged(context, core()); }
        @Override public void close() { data.close(); }
    }
}
