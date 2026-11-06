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
    enum DeletePosition {
        ABOVE_ENTER("above-enter"), LEFT_OF_ENTER("left-of-enter");
        final String id;
        DeletePosition(String id) { this.id = id; }
        static DeletePosition forId(String id) {
            return ABOVE_ENTER.id.equals(id) ? ABOVE_ENTER : LEFT_OF_ENTER;
        }
    }
    enum KeycapArea {
        SMALL("100", 1f), MEDIUM("90", .90f), LARGE("80", .80f);
        final String id;
        final float fraction;
        KeycapArea(String id, float fraction) { this.id = id; this.fraction = fraction; }
        static KeycapArea forId(String id) {
            for (var area : values()) if (area.id.equals(id)) return area;
            return SMALL;
        }
    }
    enum FontSize {
        NORMAL("normal", 1f), MEDIUM("medium", 1.15f), LARGE("large", 1.30f),
        EXTRA_LARGE("extra-large", 1.45f);
        final String id;
        final float stripScale;
        FontSize(String id, float stripScale) { this.id = id; this.stripScale = stripScale; }
        boolean showsHints() { return this == NORMAL; }
        static FontSize forId(String id) {
            for (var size : values()) if (size.id.equals(id)) return size;
            return NORMAL;
        }
    }
    record VisualOptions(KeyboardLayoutProfile layout, KeycapArea spacing,
            FontSize fontSize, DeletePosition deletePosition) {}

    static final class KeyPlane {
        private final List<List<String>> normalRows;
        private final List<List<String>> shiftedRows;
        private final List<Float> rowOffsets;

        KeyPlane(String[][] normalRows, String[][] shiftedRows) {
            this(normalRows, shiftedRows, Collections.nCopies(normalRows.length, 0f));
        }

        KeyPlane(String[][] normalRows, String[][] shiftedRows, List<Float> rowOffsets) {
            this.normalRows = immutableRows(normalRows);
            this.shiftedRows = immutableRows(shiftedRows);
            if (normalRows.length != shiftedRows.length || normalRows.length != rowOffsets.size()) {
                throw new IllegalArgumentException("Each key row needs an offset");
            }
            this.rowOffsets = List.copyOf(rowOffsets);
        }

        List<List<String>> rows(boolean shifted) { return shifted ? shiftedRows : normalRows; }
        float rowOffset(int row) { return rowOffsets.get(row); }
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
        List<List<String>> rows(Plane plane, boolean shifted, DeletePosition position) {
            return rows(plane, shifted).stream().map(row -> row.stream()
                    .map(key -> position == DeletePosition.ABOVE_ENTER && key.equals("SHIFT")
                            ? "BACKSPACE" : key).collect(Collectors.toList())).collect(Collectors.toList());
        }
        float rowOffset(Plane plane, int row) { return planes.get(plane).rowOffset(row); }
        List<String> functionKeys() { return functionKeys; }
        List<String> functionKeys(DeletePosition position) {
            return functionKeys.stream().map(key -> position == DeletePosition.ABOVE_ENTER
                    && key.equals("BACKSPACE") ? "SHIFT" : key).collect(Collectors.toList());
        }
        float functionWeight(String key) { return functionWeights.getOrDefault(key, 1f); }
        float functionWeight(String key, DeletePosition position) {
            return functionWeight(position == DeletePosition.ABOVE_ENTER && key.equals("SHIFT")
                    ? "BACKSPACE" : key);
        }
    }

    private static final String[][] BOPOMOFO_AND_ENGLISH_ROWS = {
            {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-"},
            {"q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "@"},
            {"a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "EMOJI"},
            {"z", "x", "c", "v", "b", "n", "m", ",", ".", "/", "SHIFT"}
    };
    private static final String[][] STANDARD_TABLE_ROWS = {
            BOPOMOFO_AND_ENGLISH_ROWS[0], BOPOMOFO_AND_ENGLISH_ROWS[1], BOPOMOFO_AND_ENGLISH_ROWS[2],
            {"z", "x", "c", "v", "b", "n", "m", ",", ".", "SHIFT"}
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

    static final KeyboardLayoutProfile ALIGNED = new KeyboardLayoutProfile("aligned", "對齊", Map.of(
            Orientation.PORTRAIT, fullLayout(330), Orientation.LANDSCAPE, fullLayout(230)));
    static final KeyboardLayoutProfile STANDARD = visualProfile("standard", "標準", true, false);
    static final KeyboardLayoutProfile ALIGNED_SPLIT = visualProfile("aligned-split", "對齊分離", false, true);
    private static final List<KeyboardLayoutProfile> PROFILES = List.of(STANDARD, ALIGNED, ALIGNED_SPLIT);

    final String id;
    final String displayName;
    final boolean staggered;
    final boolean split;
    private final Map<Orientation, Layout> orientations;

    KeyboardLayoutProfile(String id, String displayName, Map<Orientation, Layout> orientations) {
        this(id, displayName, orientations, false, false);
    }

    private KeyboardLayoutProfile(String id, String displayName, Map<Orientation, Layout> orientations,
            boolean staggered, boolean split) {
        this.id = id;
        this.displayName = displayName;
        this.orientations = Map.copyOf(orientations);
        this.staggered = staggered;
        this.split = split;
    }

    static List<KeyboardLayoutProfile> available() { return PROFILES; }

    static KeyboardLayoutProfile forId(String id) {
        for (KeyboardLayoutProfile profile : PROFILES) {
            if (profile.id.equals(id)) return profile;
        }
        return ALIGNED;
    }

    /** Read old style IDs only as migration input; all new options are independent. */
    static VisualOptions resolveOptions(String layoutId, String spacingId, String fontId,
            String deleteId, String legacyProfileId, String legacyAreaId, String legacyFontSizeId) {
        KeyboardLayoutProfile layout = ALIGNED;
        KeycapArea area = KeycapArea.SMALL;
        FontSize font = FontSize.NORMAL;
        if (legacyProfileId != null) {
            switch (legacyProfileId) {
                case "staggered" -> layout = STANDARD;
                case "large-full" -> font = FontSize.EXTRA_LARGE;
                case "large-staggered" -> { layout = STANDARD; font = FontSize.EXTRA_LARGE; }
                case "full-spaced" -> area = "85".equals(legacyAreaId) ? KeycapArea.LARGE : KeycapArea.MEDIUM;
                default -> { }
            }
        }
        if (layoutId != null) layout = forId(layoutId);
        if (spacingId != null) area = KeycapArea.forId(spacingId);
        if (legacyFontSizeId != null) font = "large".equals(legacyFontSizeId) ? FontSize.EXTRA_LARGE : FontSize.NORMAL;
        if (fontId != null) font = FontSize.forId(fontId);
        return new VisualOptions(layout, area, font, DeletePosition.forId(deleteId));
    }

    Layout layout(Orientation orientation) { return orientations.get(orientation); }

    private static KeyboardLayoutProfile visualProfile(String id, String name,
            boolean staggered, boolean split) {
        return new KeyboardLayoutProfile(id, name, Map.of(
                Orientation.PORTRAIT, fullLayout(ALIGNED.layout(Orientation.PORTRAIT).contentHeightDp, staggered),
                Orientation.LANDSCAPE, fullLayout(ALIGNED.layout(Orientation.LANDSCAPE).contentHeightDp, staggered)),
                staggered, split);
    }

    private static Layout fullLayout(int contentHeightDp) {
        return fullLayout(contentHeightDp, false);
    }

    private static Layout fullLayout(int contentHeightDp, boolean staggered) {
        List<Float> offsets = staggered ? List.of(0f, 1f / 3, 2f / 3, 0f) : List.of(0f, 0f, 0f, 0f);
        String[][] tableRows = staggered ? STANDARD_TABLE_ROWS : BOPOMOFO_AND_ENGLISH_ROWS;
        List<Float> tableOffsets = staggered ? List.of(0f, 1f / 3, 2f / 3, 1f) : offsets;
        // The five planes are declared independently for each orientation.
        // Shared immutable key actions keep the current glyph/mapping behavior.
        return new Layout(contentHeightDp, 11, Map.of(
                Plane.BOPOMOFO, new KeyPlane(BOPOMOFO_AND_ENGLISH_ROWS, BOPOMOFO_AND_ENGLISH_ROWS, offsets),
                Plane.CANGJIE, new KeyPlane(tableRows, tableRows, tableOffsets),
                Plane.SIMPLEX, new KeyPlane(tableRows, tableRows, tableOffsets),
                Plane.ENGLISH, new KeyPlane(BOPOMOFO_AND_ENGLISH_ROWS, SHIFTED_ENGLISH_ROWS, offsets),
                Plane.NUMBER_SYMBOLS, new KeyPlane(NUMBER_ROWS, SHIFTED_NUMBER_ROWS, offsets)),
                List.of("MODE", "SYMBOL", "SETTINGS", "，", "SPACE", "。", "BACKSPACE", "ENTER"),
                Map.of("SPACE", 3.8f, "BACKSPACE", 1.4f, "ENTER", 1.4f, "MODE", 1.65f));
    }

    private static List<List<String>> immutableRows(String[][] rows) {
        return Collections.unmodifiableList(Arrays.stream(rows)
                .map(row -> List.copyOf(Arrays.asList(row))).collect(Collectors.toList()));
    }
}
