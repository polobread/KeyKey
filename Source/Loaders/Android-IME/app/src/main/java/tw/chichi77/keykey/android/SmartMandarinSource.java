package tw.chichi77.keykey.android;

import java.util.List;
import java.util.Map;

interface SmartMandarinSource {
    SmartMandarinComposition compose(List<String> readings, Map<Integer, String> overrides);

    List<String> candidates(List<String> readings, int index,
                            SmartMandarinComposition composition);

    default void learnSelection(List<String> readings, int index, String selected,
                                SmartMandarinComposition composition) {}

    default void learnConfirmedComposition(SmartMandarinComposition composition) {}
}

record SmartMandarinSegment(int start, int length, String query, String text) {}

record SmartMandarinComposition(String text, List<SmartMandarinSegment> segments) {}
