package tw.chichi77.keykey.android;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/** Visual layout only; Standard/Hsu mappings and Rust input behavior stay separate. */
final class KeyboardLayoutProfile {
    enum Orientation { PORTRAIT, LANDSCAPE }
    enum Plane { BOPOMOFO, CANGJIE, SIMPLEX, ENGLISH, NUMBER_SYMBOLS }

    static final class KeyPlane {
        private final List<List<String>> normalRows;
        private final List<List<String>> shiftedRows;

        KeyPlane(String[][] normalRows, String[][] shiftedRows) {
            this.normalRows = immutableRows(normalRows);
            this.shiftedRows = immutableRows(shiftedRows);
        }

        List<List<String>> rows(boolean shifted) { return shifted ? shiftedRows : normalRows; }
    }

    static final class Layout {
        final int contentHeightDp;
        final int compositionCellCount;
        private final Map<Plane, KeyPlane> planes;
        private final List<String> functionKeys;
        private final Map<String, Float> functionWeights;

        Layout(int contentHeightDp, int compositionCellCount,
                Map<Plane, KeyPlane> planes, List<String> functionKeys,
                Map<String, Float> functionWeights) {
            this.contentHeightDp = contentHeightDp;
            this.compositionCellCount = compositionCellCount;
            this.planes = Map.copyOf(planes);
            this.functionKeys = List.copyOf(functionKeys);
            this.functionWeights = Map.copyOf(functionWeights);
        }

        List<List<String>> rows(Plane plane, boolean shifted) { return planes.get(plane).rows(shifted); }
        List<String> functionKeys() { return functionKeys; }
        float functionWeight(String key) { return functionWeights.getOrDefault(key, 1f); }
    }

    private static final String[][] BOPOMOFO_AND_ENGLISH_ROWS = {
            {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-"},
            {"q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "@"},
            {"a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "EMOJI"},
            {"z", "x", "c", "v", "b", "n", "m", ",", ".", "/", "SHIFT"}
    };
    private static final String[][] SHIFTED_ENGLISH_ROWS = {
            {"!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_"},
            {"Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "@"},
            {"A", "S", "D", "F", "G", "H", "J", "K", "L", ":", "EMOJI"},
            {"Z", "X", "C", "V", "B", "N", "M", "<", ">", "?", "SHIFT"}
    };
    private static final String[][] NUMBER_ROWS = {
            {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-"},
            {"!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_"},
            {"+", "=", "[", "]", "{", "}", "<", ">", "/", "\\", "|"},
            {"~", "`", "\"", "'", ":", ";", "?", ",", ".", "…", "SHIFT"}
    };
    private static final String[][] SHIFTED_NUMBER_ROWS = {
            {"$", "€", "£", "¥", "₩", "₹", "₽", "¢", "₫", "₱", "฿"},
            {"＋", "－", "×", "÷", "=", "≠", "≈", "±", "<", ">", "∞"},
            {"←", "→", "↑", "↓", "↔", "↕", "↖", "↗", "↘", "↙", "⇒"},
            {"★", "☆", "●", "○", "■", "□", "▲", "△", "▼", "▽", "SHIFT"}
    };

    static final KeyboardLayoutProfile FULL = new KeyboardLayoutProfile("full", "滿版", Map.of(
            Orientation.PORTRAIT, fullLayout(330), Orientation.LANDSCAPE, fullLayout(230)));
    private static final List<KeyboardLayoutProfile> PROFILES = List.of(FULL);

    final String id;
    final String displayName;
    private final Map<Orientation, Layout> orientations;

    KeyboardLayoutProfile(String id, String displayName, Map<Orientation, Layout> orientations) {
        this.id = id;
        this.displayName = displayName;
        this.orientations = Map.copyOf(orientations);
    }

    static List<KeyboardLayoutProfile> available() { return PROFILES; }

    static KeyboardLayoutProfile forId(String id) {
        for (KeyboardLayoutProfile profile : PROFILES) {
            if (profile.id.equals(id)) return profile;
        }
        return FULL;
    }

    Layout layout(Orientation orientation) { return orientations.get(orientation); }

    private static Layout fullLayout(int contentHeightDp) {
        // The five planes are declared independently for each orientation.
        // Shared immutable key actions keep the current glyph/mapping behavior.
        return new Layout(contentHeightDp, 11, Map.of(
                Plane.BOPOMOFO, new KeyPlane(BOPOMOFO_AND_ENGLISH_ROWS, BOPOMOFO_AND_ENGLISH_ROWS),
                Plane.CANGJIE, new KeyPlane(BOPOMOFO_AND_ENGLISH_ROWS, BOPOMOFO_AND_ENGLISH_ROWS),
                Plane.SIMPLEX, new KeyPlane(BOPOMOFO_AND_ENGLISH_ROWS, BOPOMOFO_AND_ENGLISH_ROWS),
                Plane.ENGLISH, new KeyPlane(BOPOMOFO_AND_ENGLISH_ROWS, SHIFTED_ENGLISH_ROWS),
                Plane.NUMBER_SYMBOLS, new KeyPlane(NUMBER_ROWS, SHIFTED_NUMBER_ROWS)),
                List.of("MODE", "SYMBOL", "SETTINGS", "，", "SPACE", "。", "BACKSPACE", "ENTER"),
                Map.of("SPACE", 3.8f, "BACKSPACE", 1.4f, "ENTER", 1.4f, "MODE", 1.65f));
    }

    private static List<List<String>> immutableRows(String[][] rows) {
        return Collections.unmodifiableList(Arrays.stream(rows)
                .map(row -> List.copyOf(Arrays.asList(row))).collect(Collectors.toList()));
    }
}
