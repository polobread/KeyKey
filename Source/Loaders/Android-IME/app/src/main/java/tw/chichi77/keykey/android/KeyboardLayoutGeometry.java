package tw.chichi77.keykey.android;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/** Normalized key slots shared by drawing and hit testing, independent of Android views. */
final class KeyboardLayoutGeometry {
    record Key(String action, float left, float top, float right, float bottom) {}
    record StripSlot(float left, float right) {}
    static final List<String> SPLIT_PUNCTUATION = List.of("，", "。", "、", "？");

    static float centreGapDp(float widthDp) { return Math.min(80, widthDp * .1f); }

    static List<StripSlot> splitStripSlots(int cellCount, float widthDp) {
        if (cellCount <= 0 || cellCount % 2 != 0) {
            throw new IllegalArgumentException("A split strip needs equal halves");
        }
        float gap = widthDp > 0 ? centreGapDp(widthDp) / widthDp : 0;
        float[] edges = GuanyinmaNative.nativeKeyboardRowLayout(0, 0, cellCount / 2, gap,
                uniformWeights(cellCount));
        var slots = new ArrayList<StripSlot>(cellCount);
        for (int index = 0; index < cellCount; index++) {
            slots.add(new StripSlot(edges[index * 2], edges[index * 2 + 1]));
        }
        return List.copyOf(slots);
    }

    static List<List<String>> resolvedRows(KeyboardLayoutProfile profile,
            KeyboardLayoutProfile.Orientation orientation, KeyboardLayoutProfile.Plane plane,
            boolean shifted, KeyboardLayoutProfile.DeletePosition deletePosition) {
        return resolvedRows(profile, orientation, plane, shifted, deletePosition, BopomofoKeyboardLayout.STANDARD);
    }

    static List<List<String>> resolvedRows(KeyboardLayoutProfile profile,
            KeyboardLayoutProfile.Orientation orientation, KeyboardLayoutProfile.Plane plane,
            boolean shifted, KeyboardLayoutProfile.DeletePosition deletePosition,
            BopomofoKeyboardLayout keyboardLayout) {
        var rows = profile.layout(orientation).rows(plane, shifted, deletePosition, keyboardLayout);
        if (!profile.split) return rows;
        // Split is one twelve-column design on phones and tablets in either direction.
        var result = new ArrayList<List<String>>();
        for (int row = 0; row < rows.size(); row++) {
            var actions = new ArrayList<>(rows.get(row));
            if (row < SPLIT_PUNCTUATION.size()) actions.add(Math.min(5, actions.size()), SPLIT_PUNCTUATION.get(row));
            result.add(List.copyOf(actions));
        }
        return List.copyOf(result);
    }

    static List<String> resolvedFunctionKeys(KeyboardLayoutProfile profile,
            KeyboardLayoutProfile.Orientation orientation,
            KeyboardLayoutProfile.DeletePosition deletePosition) {
        return resolvedFunctionKeys(profile, orientation, deletePosition, false, false);
    }

    static List<String> resolvedFunctionKeys(KeyboardLayoutProfile profile,
            KeyboardLayoutProfile.Orientation orientation,
            KeyboardLayoutProfile.DeletePosition deletePosition,
            boolean integrated, boolean showGlobe) {
        var result = new ArrayList<>(profile.layout(orientation).functionKeys(deletePosition));
        if (profile.split) {
            int space = result.indexOf("SPACE");
            if (space >= 0) result.add(space + 1, "SPACE");
            result.removeIf(key -> key.equals("，") || key.equals("。"));
        }
        if (showGlobe) result.add(0, "GLOBE");
        if (integrated && !profile.split) result.add(result.indexOf("SETTINGS") + 1, "DISMISS");
        return List.copyOf(result);
    }

    static List<Key> keys(KeyboardLayoutProfile profile, KeyboardLayoutProfile.Orientation orientation,
            KeyboardLayoutProfile.Plane plane, boolean shifted, KeyboardLayoutProfile.DeletePosition deletePosition) {
        return keys(profile, orientation, plane, shifted, deletePosition, 414);
    }

    static List<Key> keys(KeyboardLayoutProfile profile, KeyboardLayoutProfile.Orientation orientation,
            KeyboardLayoutProfile.Plane plane, boolean shifted,
            KeyboardLayoutProfile.DeletePosition deletePosition, float widthDp) {
        return keys(profile, orientation, plane, shifted, deletePosition, widthDp, false, false);
    }

    static List<Key> keys(KeyboardLayoutProfile profile, KeyboardLayoutProfile.Orientation orientation,
            KeyboardLayoutProfile.Plane plane, boolean shifted,
            KeyboardLayoutProfile.DeletePosition deletePosition, float widthDp,
            boolean integrated, boolean showGlobe) {
        return keys(profile, orientation, plane, shifted, deletePosition, widthDp, integrated, showGlobe,
                BopomofoKeyboardLayout.STANDARD);
    }

    static List<Key> keys(KeyboardLayoutProfile profile, KeyboardLayoutProfile.Orientation orientation,
            KeyboardLayoutProfile.Plane plane, boolean shifted,
            KeyboardLayoutProfile.DeletePosition deletePosition, float widthDp,
            boolean integrated, boolean showGlobe, BopomofoKeyboardLayout keyboardLayout) {
        var layout = profile.layout(orientation);
        var rows = resolvedRows(profile, orientation, plane, shifted, deletePosition, keyboardLayout);
        float effectiveColumns = 0;
        for (int row = 0; row < rows.size(); row++) {
            effectiveColumns = Math.max(effectiveColumns, rows.get(row).size() + layout.rowOffset(plane, row));
        }
        float rowHeight = 1f / (rows.size() + 1);
        float gap = widthDp > 0 ? centreGapDp(widthDp) / widthDp : 0;
        List<Key> result = new ArrayList<>();
        for (int row = 0; row < rows.size(); row++) {
            var actions = rows.get(row);
            int boundary = profile.split ? actions.size() / 2 : 0;
            double columns = profile.staggered ? effectiveColumns : 0;
            double leading = profile.staggered ? layout.rowOffset(plane, row) : 0;
            double[] weights = uniformWeights(actions.size());
            if (profile.staggered && row == rows.size() - 1) {
                // The last key on the standard row extends to the right edge.
                weights[weights.length - 1] = columns - leading - (weights.length - 1);
            }
            addRow(result, actions, leading, columns, boundary, profile.split ? gap : 0,
                    row * rowHeight, (row + 1) * rowHeight, weights);
        }
        var functions = resolvedFunctionKeys(profile, orientation, deletePosition, integrated, showGlobe);
        if (profile.split) {
            int boundary = functions.indexOf("SPACE") + 1;
            float columnsPerSide = rows.get(0).size() / 2f;
            double[] weights = new double[functions.size()];
            for (int index = 0; index < functions.size(); index++) {
                weights[index] = switch (functions.get(index)) {
                    case "MODE" -> showGlobe ? 1 : 1.5;
                    case "SPACE" -> 0;
                    case "BACKSPACE", "ENTER" -> 2;
                    default -> 1;
                };
            }
            fillSplitSpaceWeight(functions, weights, 0, boundary, columnsPerSide);
            fillSplitSpaceWeight(functions, weights, boundary, functions.size(), columnsPerSide);
            addRow(result, functions, 0, 0, boundary, gap, rows.size() * rowHeight, 1, weights);
        } else {
            double[] weights = new double[functions.size()];
            for (int index = 0; index < functions.size(); index++) {
                String action = functions.get(index);
                weights[index] = showGlobe && action.equals("MODE") ? 1
                        : layout.functionWeight(action, deletePosition);
            }
            // Non-split layouts retain their existing mode/space control budget.
            float releasedModeWeight = showGlobe ? layout.functionWeight("MODE", deletePosition) - 1f : 0;
            donateSpaceWeight(functions, weights, releasedModeWeight);
            addRow(result, functions, 0, 0, 0, 0, rows.size() * rowHeight, 1, weights);
        }
        return List.copyOf(result);
    }

    private static void fillSplitSpaceWeight(List<String> actions, double[] weights,
            int start, int end, float columnsPerSide) {
        double fixed = 0;
        int space = -1;
        for (int index = start; index < end; index++) {
            if (actions.get(index).equals("SPACE")) space = index;
            else fixed += weights[index];
        }
        // Control units are actual main-key columns; space takes the remainder.
        weights[space] = columnsPerSide - fixed;
    }

    private static void donateSpaceWeight(List<String> actions, double[] weights, float releasedModeWeight) {
        double donation = 0;
        int space = -1;
        for (int index = 0; index < actions.size(); index++) {
            String action = actions.get(index);
            if (action.equals("SPACE")) space = index;
            if (action.equals("GLOBE") || action.equals("DISMISS")) donation += weights[index];
            if (action.equals("MODE")) donation -= releasedModeWeight;
        }
        if (space >= 0 && donation > 0) weights[space] = Math.max(.5, weights[space] - donation);
    }

    private static double[] uniformWeights(int count) {
        double[] weights = new double[count];
        Arrays.fill(weights, 1);
        return weights;
    }

    private static void addRow(List<Key> result, List<String> actions, double leading, double columns,
            int splitIndex, float gap, float top, float bottom, double[] weights) {
        float[] edges = GuanyinmaNative.nativeKeyboardRowLayout(leading, columns, splitIndex, gap, weights);
        for (int index = 0; index < actions.size(); index++) {
            result.add(new Key(actions.get(index), edges[index * 2], top, edges[index * 2 + 1], bottom));
        }
    }

    private KeyboardLayoutGeometry() {}
}
