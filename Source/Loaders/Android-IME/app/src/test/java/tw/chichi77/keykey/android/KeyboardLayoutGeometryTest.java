package tw.chichi77.keykey.android;

import static org.junit.Assert.*;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import org.junit.Test;

public final class KeyboardLayoutGeometryTest {
    private static final float EPSILON = .000001f;
    private static final int PUNCTUATION_INSERT_INDEX = 5;
    private static final List<Float> ORIGINAL_STANDARD_OFFSETS = List.of(0f, 1f / 3, 2f / 3, 0f);
    private static final List<String> SPLIT_PUNCTUATION = List.of("，", "。", "、", "？");
    private static final List<String> ORIGINAL_FUNCTIONS = List.of(
            "MODE", "SYMBOL", "SETTINGS", "，", "SPACE", "。", "BACKSPACE", "ENTER");
    private static final List<List<String>> ORIGINAL_ROWS = List.of(
            List.of("1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-"),
            List.of("q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "@"),
            List.of("a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "EMOJI"),
            List.of("z", "x", "c", "v", "b", "n", "m", ",", ".", "/", "SHIFT"));
    private static final List<List<String>> SHIFTED_ENGLISH_ROWS = List.of(
            List.of("!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_"),
            List.of("Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "@"),
            List.of("A", "S", "D", "F", "G", "H", "J", "K", "L", ":", "EMOJI"),
            List.of("Z", "X", "C", "V", "B", "N", "M", "<", ">", "?", "SHIFT"));
    private static final List<List<String>> NUMBER_ROWS = List.of(
            List.of("1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-"),
            List.of("!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_"),
            List.of("+", "=", "[", "]", "{", "}", "<", ">", "/", "\\", "|"),
            List.of("~", "`", "\"", "'", ":", ";", "?", ",", ".", "…", "SHIFT"));
    private static final List<List<String>> SHIFTED_NUMBER_ROWS = List.of(
            List.of("$", "€", "£", "¥", "₩", "₹", "₽", "¢", "₫", "₱", "฿"),
            List.of("＋", "－", "×", "÷", "=", "≠", "≈", "±", "<", ">", "∞"),
            List.of("←", "→", "↑", "↓", "↔", "↕", "↖", "↗", "↘", "↙", "⇒"),
            List.of("★", "☆", "●", "○", "■", "□", "▲", "△", "▼", "▽", "SHIFT"));

    @Test public void independentOptionsPreserveOriginalActionsAndUsableSlots() {
        for (var profile : KeyboardLayoutProfile.available()) {
            for (var spacing : KeyboardLayoutProfile.KeycapArea.values()) {
                for (var font : KeyboardLayoutProfile.FontSize.values()) {
                    for (var position : KeyboardLayoutProfile.DeletePosition.values()) {
                        var options = KeyboardLayoutProfile.resolveOptions(profile.id, spacing.id,
                                font.id, position.id, null, null, null);
                        assertSame(profile, options.layout());
                        assertSame(spacing, options.spacing());
                        assertSame(font, options.fontSize());
                        assertSame(position, options.deletePosition());
                        for (var orientation : KeyboardLayoutProfile.Orientation.values()) {
                            assertEquals(KeyboardLayoutProfile.ALIGNED.layout(orientation).contentHeightDp,
                                    options.layout().layout(orientation).contentHeightDp);
                            for (var plane : KeyboardLayoutProfile.Plane.values()) {
                                for (boolean shifted : new boolean[] {false, true}) {
                                    for (float width : new float[] {390, 844}) {
                                        String context = profile.id + "/" + spacing + "/" + font + "/"
                                                + position + "/" + orientation + "/" + plane + "/" + shifted + "/" + width;
                                        var keys = KeyboardLayoutGeometry.keys(options.layout(), orientation,
                                                plane, shifted, options.deletePosition(), width);
                                        var rows = expectedRows(profile, plane, shifted, position);
                                        var functions = expectedFunctions(profile, position);
                                        var expectedActions = flatten(rows);
                                        expectedActions.addAll(functions);
                                        assertEquals(context, expectedActions, actions(keys));
                                        assertEquals(context, rows, KeyboardLayoutGeometry.resolvedRows(
                                                profile, orientation, plane, shifted, position));
                                        assertEquals(context, functions, KeyboardLayoutGeometry.resolvedFunctionKeys(
                                                profile, orientation, position));
                                        var originalActions = flatten(originalRows(plane, shifted));
                                        originalActions.addAll(ORIGINAL_FUNCTIONS);
                                        if (standardTablePlane(profile, plane)) assertTrue(originalActions.remove("/"));
                                        if (profile.split) originalActions.add("SPACE");
                                        if (profile.split) originalActions.addAll(List.of("、", "？"));
                                        assertEquals(context, counts(originalActions), counts(actions(keys)));
                                        assertRowBands(context, keys, rows);
                                        assertValidSlots(context, keys);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @Test public void alignedRowsKeepEqualWidthSlotsAcrossTheWholeKeyboard() {
        var profile = KeyboardLayoutProfile.ALIGNED;
        for (var orientation : KeyboardLayoutProfile.Orientation.values()) {
            for (var plane : KeyboardLayoutProfile.Plane.values()) {
                for (boolean shifted : new boolean[] {false, true}) {
                    var rows = profile.layout(orientation).rows(plane, shifted);
                    var keys = KeyboardLayoutGeometry.keys(profile, orientation, plane, shifted,
                            KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER, 390);
                    int index = 0;
                    for (var row : rows) {
                        for (int column = 0; column < row.size(); column++) {
                            var key = keys.get(index++);
                            assertEquals((float) column / row.size(), key.left(), EPSILON);
                            assertEquals((float) (column + 1) / row.size(), key.right(), EPSILON);
                        }
                    }
                }
            }
        }
    }

    @Test public void standardRowsUseThirdKeyOffsetsAndTheLastControlFillsTheRightEdge() {
        var profile = KeyboardLayoutProfile.STANDARD;
        for (var orientation : KeyboardLayoutProfile.Orientation.values()) {
            for (var plane : KeyboardLayoutProfile.Plane.values()) {
                var offsets = List.of(0f, 1f / 3, 2f / 3, standardTablePlane(profile, plane) ? 1f : 0f);
                var layout = profile.layout(orientation);
                for (boolean shifted : new boolean[] {false, true}) {
                    var rows = layout.rows(plane, shifted);
                    assertEquals(offsets, java.util.stream.IntStream.range(0, rows.size())
                            .mapToObj(row -> layout.rowOffset(plane, row)).collect(Collectors.toList()));
                    var keys = KeyboardLayoutGeometry.keys(profile, orientation, plane, shifted,
                            KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER, 390);
                    // Keep the original common pitch even when the table bottom row loses one key.
                    var original = originalRows(plane, shifted);
                    float effectiveColumns = 0;
                    for (int row = 0; row < original.size(); row++) {
                        effectiveColumns = Math.max(effectiveColumns,
                                original.get(row).size() + ORIGINAL_STANDARD_OFFSETS.get(row));
                    }
                    int index = 0;
                    for (int row = 0; row < rows.size(); row++) {
                        for (int column = 0; column < rows.get(row).size(); column++) {
                            var key = keys.get(index++);
                            assertEquals((offsets.get(row) + column) / effectiveColumns, key.left(), EPSILON);
                            float expectedRight = row == rows.size() - 1 && column == rows.get(row).size() - 1
                                    ? 1 : (offsets.get(row) + column + 1) / effectiveColumns;
                            assertEquals(expectedRight, key.right(), EPSILON);
                        }
                    }
                    assertEquals(1, keys.get(index - 1).right(), EPSILON);
                }
            }
        }
    }

    @Test public void standardTableBottomRowStartsAtTheFormerXSlotAndKeepsTheFinalControl() {
        var profile = KeyboardLayoutProfile.STANDARD;
        for (var orientation : KeyboardLayoutProfile.Orientation.values()) {
            for (var plane : List.of(KeyboardLayoutProfile.Plane.CANGJIE, KeyboardLayoutProfile.Plane.SIMPLEX)) {
                for (boolean shifted : new boolean[] {false, true}) {
                    for (var position : KeyboardLayoutProfile.DeletePosition.values()) {
                        for (float width : new float[] {390, 844}) {
                            String context = plane + "/" + orientation + "/" + shifted + "/" + position + "/" + width;
                            // Bopomofo preserves the original standard row and is the old slot reference.
                            var original = KeyboardLayoutGeometry.keys(profile, orientation,
                                    KeyboardLayoutProfile.Plane.BOPOMOFO, shifted, position, width);
                            var table = KeyboardLayoutGeometry.keys(profile, orientation, plane, shifted, position, width);
                            var oldX = keyWithAction(original, "x");
                            var newZ = keyWithAction(table, "z");
                            assertSameSlot(context, oldX, newZ);
                            assertTrue(context, newZ.left() > 0);
                            String controlAction = position == KeyboardLayoutProfile.DeletePosition.ABOVE_ENTER
                                    ? "BACKSPACE" : "SHIFT";
                            var oldControl = keyWithAction(original, controlAction);
                            var newControl = keyWithAction(table, controlAction);
                            assertSameSlot(context, oldControl, newControl);
                            assertEquals(context, 1, newControl.right(), EPSILON);
                            assertTrue(context, actions(original).contains("/"));
                            assertFalse(context, actions(table).contains("/"));
                            for (var key : table) {
                                boolean overlapsLeadingGap = key.left() < newZ.left() - EPSILON
                                        && key.right() > EPSILON && key.top() < newZ.bottom() - EPSILON
                                        && key.bottom() > newZ.top() + EPSILON;
                                assertFalse(context + ": leading gap contains " + key.action(), overlapsLeadingGap);
                            }
                        }
                    }
                }
            }
        }
    }

    @Test public void splitRowsKeepSixEqualKeysPerHalfAtEveryWidth() {
        var profile = KeyboardLayoutProfile.ALIGNED_SPLIT;
        for (float width : new float[] {320, 390, 599, 600, 800, 1200}) {
            float gap = Math.min(80, width * .1f) / width;
            float halfWidth = (1 - gap) / 2;
            assertEquals(gap * width, KeyboardLayoutGeometry.centreGapDp(width), .0001f);
            for (var orientation : KeyboardLayoutProfile.Orientation.values()) {
                for (var plane : KeyboardLayoutProfile.Plane.values()) {
                    for (boolean shifted : new boolean[] {false, true}) {
                        for (var position : KeyboardLayoutProfile.DeletePosition.values()) {
                            var rows = expectedRows(profile, plane, shifted, position);
                            var keys = KeyboardLayoutGeometry.keys(profile, orientation, plane, shifted, position, width);
                            int index = 0;
                            for (var row : rows) {
                                assertEquals("Split design must keep all twelve actions on small and large screens", 12, row.size());
                                int leftCount = row.size() / 2;
                                int rightCount = row.size() - leftCount;
                                for (int column = 0; column < row.size(); column++) {
                                    var key = keys.get(index++);
                                    boolean left = column < leftCount;
                                    int localColumn = left ? column : column - leftCount;
                                    int count = left ? leftCount : rightCount;
                                    float origin = left ? 0 : halfWidth + gap;
                                    assertEquals(origin + halfWidth * localColumn / count, key.left(), EPSILON);
                                    assertEquals(origin + halfWidth * (localColumn + 1) / count, key.right(), EPSILON);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @Test public void splitStripSlotsAlignWithTheSameMainRowColumnsAtEveryWidth() {
        for (var profile : KeyboardLayoutProfile.available()) {
            if (!profile.split) continue;
            for (var orientation : KeyboardLayoutProfile.Orientation.values()) {
                int cellCount = profile.layout(orientation).compositionCellCount + 1;
                for (float width : new float[] {320, 390, 600, 768, 1200}) {
                    var slots = KeyboardLayoutGeometry.splitStripSlots(cellCount, width);
                    assertEquals(cellCount, slots.size());
                    for (var plane : KeyboardLayoutProfile.Plane.values()) {
                        var rows = KeyboardLayoutGeometry.resolvedRows(profile, orientation, plane,
                                false, KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER);
                        var keys = KeyboardLayoutGeometry.keys(profile, orientation, plane,
                                false, KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER, width);
                        assertEquals(rows.get(0).size(), slots.size());
                        for (int index = 0; index < slots.size(); index++) {
                            assertEquals(keys.get(index).left(), slots.get(index).left(), EPSILON);
                            assertEquals(keys.get(index).right(), slots.get(index).right(), EPSILON);
                            assertTrue(slots.get(index).right() <= .5f || slots.get(index).left() >= .5f);
                        }
                    }
                }
            }
        }
        assertThrows(IllegalArgumentException.class, () -> KeyboardLayoutGeometry.splitStripSlots(0, 320));
        assertThrows(IllegalArgumentException.class, () -> KeyboardLayoutGeometry.splitStripSlots(11, 320));
    }

    @Test public void splitFunctionRowsDuplicateSpaceAndRespectTheSameCentralGap() {
        var profile = KeyboardLayoutProfile.ALIGNED_SPLIT;
        var splitWeights = Map.of("MODE", 1.5f, "SYMBOL", 1f, "SETTINGS", 1f,
                "BACKSPACE", 2f, "SHIFT", 1f, "ENTER", 2f);
        for (float width : new float[] {390, 600, 1200}) {
            float gap = Math.min(80, width * .1f) / width;
            float halfWidth = (1 - gap) / 2;
            for (var orientation : KeyboardLayoutProfile.Orientation.values()) {
                for (var position : KeyboardLayoutProfile.DeletePosition.values()) {
                    var functions = expectedFunctions(profile, position);
                    int split = functions.indexOf("SPACE") + 1;
                    assertEquals("SPACE", functions.get(split));
                    for (var plane : KeyboardLayoutProfile.Plane.values()) {
                        for (boolean shifted : new boolean[] {false, true}) {
                            var keys = KeyboardLayoutGeometry.keys(profile, orientation, plane, shifted, position, width);
                            var functionSlots = keys.subList(keys.size() - functions.size(), keys.size());
                            for (int group = 0; group < 2; group++) {
                                int start = group == 0 ? 0 : split;
                                int end = group == 0 ? split : functions.size();
                                int columnsPerSide = KeyboardLayoutGeometry.resolvedRows(profile, orientation,
                                        plane, shifted, position).get(0).size() / 2;
                                float fixed = 0;
                                for (String action : functions.subList(start, end)) {
                                    if (!action.equals("SPACE")) fixed += splitWeights.get(action);
                                }
                                float cursor = group == 0 ? 0 : halfWidth + gap;
                                for (int index = start; index < end; index++) {
                                    var slot = functionSlots.get(index);
                                    String action = functions.get(index);
                                    float weight = action.equals("SPACE") ? columnsPerSide - fixed : splitWeights.get(action);
                                    assertEquals(cursor, slot.left(), EPSILON);
                                    cursor += halfWidth * weight / columnsPerSide;
                                    assertEquals(cursor, slot.right(), EPSILON);
                                }
                            }
                            assertEquals(halfWidth, functionSlots.get(split - 1).right(), EPSILON);
                            assertEquals(halfWidth + gap, functionSlots.get(split).left(), EPSILON);
                        }
                    }
                }
            }
        }
    }

    @Test public void deleteAndShiftSwapActionsWithoutMovingMainKeySlots() {
        for (var profile : KeyboardLayoutProfile.available()) {
            for (var orientation : KeyboardLayoutProfile.Orientation.values()) {
                for (var plane : KeyboardLayoutProfile.Plane.values()) {
                    for (boolean shifted : new boolean[] {false, true}) {
                        for (float width : new float[] {390, 844}) {
                            var left = KeyboardLayoutGeometry.keys(profile, orientation, plane, shifted,
                                    KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER, width);
                            var above = KeyboardLayoutGeometry.keys(profile, orientation, plane, shifted,
                                    KeyboardLayoutProfile.DeletePosition.ABOVE_ENTER, width);
                            assertEquals(left.size(), above.size());
                            int mainCount = KeyboardLayoutGeometry.resolvedRows(profile, orientation, plane,
                                    shifted, KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER)
                                    .stream().mapToInt(List::size).sum();
                            for (int index = 0; index < left.size(); index++) {
                                var original = left.get(index);
                                var swapped = above.get(index);
                                if (!profile.split || index < mainCount) {
                                    assertEquals(original.left(), swapped.left(), EPSILON);
                                    assertEquals(original.right(), swapped.right(), EPSILON);
                                }
                                assertEquals(original.top(), swapped.top(), EPSILON);
                                assertEquals(original.bottom(), swapped.bottom(), EPSILON);
                                String expected = original.action().equals("SHIFT") ? "BACKSPACE"
                                        : original.action().equals("BACKSPACE") ? "SHIFT" : original.action();
                                assertEquals(expected, swapped.action());
                            }
                        }
                    }
                }
            }
        }
    }

    private static boolean standardTablePlane(KeyboardLayoutProfile profile, KeyboardLayoutProfile.Plane plane) {
        return profile == KeyboardLayoutProfile.STANDARD
                && (plane == KeyboardLayoutProfile.Plane.CANGJIE || plane == KeyboardLayoutProfile.Plane.SIMPLEX);
    }

    private static KeyboardLayoutGeometry.Key keyWithAction(List<KeyboardLayoutGeometry.Key> keys, String action) {
        return keys.stream().filter(key -> key.action().equals(action)).findFirst().orElseThrow();
    }

    private static void assertSameSlot(String context, KeyboardLayoutGeometry.Key expected,
            KeyboardLayoutGeometry.Key actual) {
        assertEquals(context, expected.left(), actual.left(), EPSILON);
        assertEquals(context, expected.right(), actual.right(), EPSILON);
        assertEquals(context, expected.top(), actual.top(), EPSILON);
        assertEquals(context, expected.bottom(), actual.bottom(), EPSILON);
    }

    private static List<List<String>> originalRows(KeyboardLayoutProfile.Plane plane, boolean shifted) {
        if (plane == KeyboardLayoutProfile.Plane.NUMBER_SYMBOLS) return shifted ? SHIFTED_NUMBER_ROWS : NUMBER_ROWS;
        return plane == KeyboardLayoutProfile.Plane.ENGLISH && shifted ? SHIFTED_ENGLISH_ROWS : ORIGINAL_ROWS;
    }

    private static List<List<String>> expectedRows(KeyboardLayoutProfile profile,
            KeyboardLayoutProfile.Plane plane, boolean shifted,
            KeyboardLayoutProfile.DeletePosition position) {
        var rows = originalRows(plane, shifted);
        List<List<String>> result = new ArrayList<>();
        for (int index = 0; index < rows.size(); index++) {
            List<String> row = rows.get(index).stream().map(action ->
                    position == KeyboardLayoutProfile.DeletePosition.ABOVE_ENTER && action.equals("SHIFT")
                            ? "BACKSPACE" : action).collect(Collectors.toCollection(ArrayList::new));
            if (standardTablePlane(profile, plane) && index == rows.size() - 1) assertTrue(row.remove("/"));
            if (profile.split) row.add(PUNCTUATION_INSERT_INDEX, SPLIT_PUNCTUATION.get(index));
            result.add(row);
        }
        return result;
    }

    private static List<String> expectedFunctions(KeyboardLayoutProfile profile,
            KeyboardLayoutProfile.DeletePosition position) {
        List<String> result = ORIGINAL_FUNCTIONS.stream()
                .filter(action -> !profile.split || !(action.equals("，") || action.equals("。")))
                .map(action -> position == KeyboardLayoutProfile.DeletePosition.ABOVE_ENTER && action.equals("BACKSPACE")
                        ? "SHIFT" : action).collect(Collectors.toCollection(ArrayList::new));
        if (profile.split) result.add(result.indexOf("SPACE") + 1, "SPACE");
        return result;
    }

    private static List<String> flatten(List<List<String>> rows) {
        return rows.stream().flatMap(List::stream).collect(Collectors.toCollection(ArrayList::new));
    }

    private static List<String> actions(List<KeyboardLayoutGeometry.Key> keys) {
        return keys.stream().map(KeyboardLayoutGeometry.Key::action).collect(Collectors.toList());
    }

    private static Map<String, Long> counts(List<String> actions) {
        return actions.stream().collect(Collectors.groupingBy(action -> action, Collectors.counting()));
    }

    private static void assertRowBands(String context, List<KeyboardLayoutGeometry.Key> keys,
            List<List<String>> rows) {
        float height = 1f / (rows.size() + 1);
        int index = 0;
        for (int row = 0; row < rows.size(); row++) {
            for (String ignored : rows.get(row)) {
                var key = keys.get(index++);
                assertEquals(context, row * height, key.top(), EPSILON);
                assertEquals(context, (row + 1) * height, key.bottom(), EPSILON);
            }
        }
        for (var key : keys.subList(index, keys.size())) {
            assertEquals(context, rows.size() * height, key.top(), EPSILON);
            assertEquals(context, 1, key.bottom(), EPSILON);
        }
    }

    private static void assertValidSlots(String context, List<KeyboardLayoutGeometry.Key> keys) {
        assertFalse(context, keys.isEmpty());
        for (int index = 0; index < keys.size(); index++) {
            var key = keys.get(index);
            assertTrue(context + "/" + key.action(), key.right() > key.left() && key.bottom() > key.top());
            assertTrue(context + "/" + key.action(), key.left() >= -EPSILON && key.top() >= -EPSILON
                    && key.right() <= 1 + EPSILON && key.bottom() <= 1 + EPSILON);
            for (int previous = 0; previous < index; previous++) {
                var other = keys.get(previous);
                if (key.left() < other.right() - EPSILON && other.left() < key.right() - EPSILON
                        && key.top() < other.bottom() - EPSILON && other.top() < key.bottom() - EPSILON) {
                    fail(context + ": overlapping slots " + key.action() + "/" + other.action());
                }
            }
        }
    }
}
