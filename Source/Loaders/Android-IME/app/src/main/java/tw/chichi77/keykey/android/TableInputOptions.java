package tw.chichi77.keykey.android;

/** macOS OVIMGeneric/TakaoCangjie/TakaoSimplex defaults. */
final class TableInputOptions {
    boolean queryAtMaximum;
    boolean clearOnError;
    boolean composeWhileTyping;
    boolean dynamicFrequency;
    int punctuation;
    TableInputOptions(ChineseInputMethod method) {
        queryAtMaximum = method == ChineseInputMethod.SIMPLEX;
        clearOnError = method == ChineseInputMethod.CANGJIE;
        dynamicFrequency = method == ChineseInputMethod.CANGJIE;
    }
}
