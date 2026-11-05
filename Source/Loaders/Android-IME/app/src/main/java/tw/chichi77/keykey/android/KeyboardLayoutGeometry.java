package tw.chichi77.keykey.android;

import java.util.ArrayList;
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
        float half = (1 - gap) / 2;
        int perSide = cellCount / 2;
        var slots = new ArrayList<StripSlot>();
        for (int index = 0; index < cellCount; index++) {
            int column = index % perSide;
            float origin = index < perSide ? 0 : half + gap;
            slots.add(new StripSlot(origin + half * column / perSide,
                    column == perSide - 1 ? origin + half : origin + half * (column + 1) / perSide));
        }
        return List.copyOf(slots);
    }

    static List<List<String>> resolvedRows(KeyboardLayoutProfile profile,
            KeyboardLayoutProfile.Orientation orientation, KeyboardLayoutProfile.Plane plane,
            boolean shifted, KeyboardLayoutProfile.DeletePosition deletePosition) {
        var rows = profile.layout(orientation).rows(plane, shifted, deletePosition);
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
        var layout = profile.layout(orientation);
        var rows = resolvedRows(profile, orientation, plane, shifted, deletePosition);
        float effectiveColumns = 0;
        for (int row = 0; row < rows.size(); row++) {
            effectiveColumns = Math.max(effectiveColumns, rows.get(row).size() + layout.rowOffset(plane, row));
        }
        float rowHeight = 1f / (rows.size() + 1);
        float gap = widthDp > 0 ? centreGapDp(widthDp) / widthDp : 0;
        List<Key> result = new ArrayList<>();
        for (int row = 0; row < rows.size(); row++) {
            var actions = rows.get(row);
            if (profile.split) {
                int boundary = actions.size() / 2;
                addSplitGroup(result, actions, boundary, gap, row * rowHeight, (row + 1) * rowHeight, null);
            } else {
                float columns = profile.staggered ? effectiveColumns : actions.size();
                float offset = layout.rowOffset(plane, row);
                for (int column = 0; column < actions.size(); column++) {
                    float right = (offset + column + 1) / columns;
                    if (profile.staggered && row == rows.size() - 1 && column == actions.size() - 1) right = 1;
                    result.add(new Key(actions.get(column), (offset + column) / columns,
                            row * rowHeight, right, (row + 1) * rowHeight));
                }
            }
        }
        var functions = resolvedFunctionKeys(profile, orientation, deletePosition, integrated, showGlobe);
        if (profile.split) {
            int boundary = functions.indexOf("SPACE") + 1;
            float columnsPerSide = rows.get(0).size() / 2f;
            var weights = new ArrayList<Float>();
            for (String action : functions) {
                weights.add(switch (action) {
                    case "MODE" -> showGlobe ? 1f : 1.5f;
                    case "SPACE" -> 0f;
                    case "BACKSPACE", "ENTER" -> 2f;
                    default -> 1f;
                });
            }
            fillSplitSpaceWeight(functions, weights, 0, boundary, columnsPerSide);
            fillSplitSpaceWeight(functions, weights, boundary, functions.size(), columnsPerSide);
            addSplitGroup(result, functions, boundary, gap,
                    rows.size() * rowHeight, 1, weights);
        } else {
            var weights = new ArrayList<Float>();
            for (String action : functions) {
                float weight = layout.functionWeight(action, deletePosition);
                weights.add(showGlobe && action.equals("MODE") ? 1f : weight);
            }
            // Non-split layouts retain their existing mode/space control budget.
            float releasedModeWeight = showGlobe ? layout.functionWeight("MODE", deletePosition) - 1f : 0;
            donateSpaceWeight(functions, weights, 0, functions.size(), releasedModeWeight);
            addGroup(result, functions, 0, functions.size(), 0, 1,
                    rows.size() * rowHeight, 1, weights);
        }
        return List.copyOf(result);
    }

    private static void fillSplitSpaceWeight(List<String> actions, List<Float> weights,
            int start, int end, float columnsPerSide) {
        float fixed = 0;
        int space = -1;
        for (int index = start; index < end; index++) {
            if (actions.get(index).equals("SPACE")) space = index;
            else fixed += weights.get(index);
        }
        // Control units are actual main-key columns; space takes the remainder.
        weights.set(space, columnsPerSide - fixed);
    }

    private static void donateSpaceWeight(List<String> actions, List<Float> weights, int start, int end,
            float releasedModeWeight) {
        float donation = 0;
        int space = -1;
        for (int index = start; index < end; index++) {
            if (actions.get(index).equals("SPACE")) space = index;
            if (actions.get(index).equals("GLOBE") || actions.get(index).equals("DISMISS")) donation += weights.get(index);
            if (actions.get(index).equals("MODE")) donation -= releasedModeWeight;
        }
        if (space >= 0 && donation > 0) weights.set(space, Math.max(.5f, weights.get(space) - donation));
    }

    private static void addSplitGroup(List<Key> result, List<String> actions, int boundary,
            float gap, float top, float bottom, List<Float> weights) {
        float half = (1 - gap) / 2;
        addGroup(result, actions, 0, boundary, 0, half, top, bottom, weights);
        addGroup(result, actions, boundary, actions.size(), half + gap, 1, top, bottom, weights);
    }

    private static void addGroup(List<Key> result, List<String> actions, int start, int end,
            float left, float right, float top, float bottom, List<Float> weights) {
        float total = 0;
        for (int index = start; index < end; index++) total += weights == null ? 1 : weights.get(index);
        float cursor = left;
        for (int index = start; index < end; index++) {
            float next = index == end - 1 ? right
                    : cursor + (right - left) * (weights == null ? 1 : weights.get(index)) / total;
            result.add(new Key(actions.get(index), cursor, top, next, bottom));
            cursor = next;
        }
    }

    private KeyboardLayoutGeometry() {}
}
