package tw.chichi77.keykey.android;
import java.util.List;

interface TableCandidateSource {
    List<String> values(ChineseInputMethod method, String code, int punctuation);
    default void forEachPrefixValue(String code, java.util.function.Consumer<String> action) {}
    String keyName(ChineseInputMethod method, String key);
    String endKeys(ChineseInputMethod method);
    default void learn(String code, String text) {}
    default List<String> ordered(List<String> values, String code) { return values; }
}
