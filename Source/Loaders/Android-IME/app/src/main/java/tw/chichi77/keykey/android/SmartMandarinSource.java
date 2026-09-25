package tw.chichi77.keykey.android;

import java.util.List;
import java.util.Map;

interface SmartMandarinSource {
    SmartMandarinComposition compose(List<String> readings, Map<Integer, String> overrides);

    default SmartMandarinComposition composeSelections(
            List<String> readings, Map<Integer, SmartMandarinSelection> selections) {
        Map<Integer, String> singleReadings = new java.util.HashMap<>();
        for (Map.Entry<Integer, SmartMandarinSelection> entry : selections.entrySet()) {
            if (entry.getValue().length() != 1) return null;
            singleReadings.put(entry.getKey(), entry.getValue().text());
        }
        return compose(readings, singleReadings);
    }

    List<String> candidates(List<String> readings, int index,
                            SmartMandarinComposition composition);

    default List<SmartMandarinCandidate> candidateOptions(
            List<String> readings, int index, SmartMandarinComposition composition) {
        java.util.ArrayList<SmartMandarinCandidate> options = new java.util.ArrayList<>();
        for (String text : candidates(readings, index, composition)) {
            options.add(new SmartMandarinCandidate(1, text));
        }
        return List.copyOf(options);
    }

    default void learnSelection(List<String> readings, int index, String selected,
                                SmartMandarinComposition composition) {}

    default void learnSelection(List<String> readings, int index,
                                SmartMandarinCandidate candidate,
                                SmartMandarinComposition composition) {
        if (candidate.length() == 1) {
            learnSelection(readings, index, candidate.text(), composition);
        }
    }

    default void learnConfirmedComposition(SmartMandarinComposition composition) {}

    default int evictionLength(List<String> readings, SmartMandarinComposition composition) {
        return composition.segments().isEmpty() ? 0 : composition.segments().get(0).length();
    }
}

record SmartMandarinSegment(int start, int length, String query, String text) {}

record SmartMandarinComposition(String text, List<SmartMandarinSegment> segments) {}

record SmartMandarinSelection(int length, String text) {}

record SmartMandarinCandidate(int length, String text) {}
