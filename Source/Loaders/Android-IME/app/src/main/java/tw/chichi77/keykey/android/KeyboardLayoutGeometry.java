package tw.chichi77.keykey.android;

import java.util.ArrayList;
import java.util.List;

/** Normalized key slots shared by drawing and hit testing, independent of Android views. */
final class KeyboardLayoutGeometry {
    record Key(String action, float left, float top, float right, float bottom) {}
    static final float EXPANDED_WIDTH_DP = 600;
    static final List<String> SPLIT_PUNCTUATION = List.of("，", "。", "、", "？");

    static boolean isExpanded(KeyboardLayoutProfile profile, float widthDp) {
        return profile.split && widthDp >= EXPANDED_WIDTH_DP;
    }

    static float centreGapDp(float widthDp) { return Math.min(80, widthDp * .1f); }

    static List<List<String>> resolvedRows(KeyboardLayoutProfile profile,
            KeyboardLayoutProfile.Orientation orientation, KeyboardLayoutProfile.Plane plane,
            boolean shifted, KeyboardLayoutProfile.DeletePosition deletePosition, float widthDp) {
        var rows = profile.layout(orientation).rows(plane, shifted, deletePosition);
        if (!isExpanded(profile, widthDp)) return rows;
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
            KeyboardLayoutProfile.DeletePosition deletePosition, float widthDp) {
        var result = new ArrayList<>(profile.layout(orientation).functionKeys(deletePosition));
        if (profile.split) {
            int space = result.indexOf("SPACE");
            if (space >= 0) result.add(space + 1, "SPACE");
            if (isExpanded(profile, widthDp)) result.removeIf(key -> key.equals("，") || key.equals("。"));
        }
        return List.copyOf(result);
    }

    static List<Key> keys(KeyboardLayoutProfile profile, KeyboardLayoutProfile.Orientation orientation,
            KeyboardLayoutProfile.Plane plane, boolean shifted, KeyboardLayoutProfile.DeletePosition deletePosition) {
        return keys(profile, orientation, plane, shifted, deletePosition, 414);
    }

    static List<Key> keys(KeyboardLayoutProfile profile, KeyboardLayoutProfile.Orientation orientation,
            KeyboardLayoutProfile.Plane plane, boolean shifted,
            KeyboardLayoutProfile.DeletePosition deletePosition, float widthDp) {
        var layout = profile.layout(orientation);
        var rows = resolvedRows(profile, orientation, plane, shifted, deletePosition, widthDp);
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
                int boundary = Math.min(isExpanded(profile, widthDp) ? 6 : 5, actions.size());
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
        var functions = resolvedFunctionKeys(profile, orientation, deletePosition, widthDp);
        var weights = new ArrayList<Float>();
        for (String action : functions) {
            String weighted = deletePosition == KeyboardLayoutProfile.DeletePosition.ABOVE_ENTER
                    && action.equals("SHIFT") ? "BACKSPACE" : action;
            float weight = isExpanded(profile, widthDp) ? switch (weighted) {
                case "MODE" -> 1.5f;
                case "SYMBOL", "SETTINGS" -> 1.25f;
                case "SPACE", "BACKSPACE", "ENTER" -> 2f;
                default -> 1f;
            } : layout.functionWeight(action, deletePosition);
            weights.add(weight);
        }
        if (profile.split) {
            addSplitGroup(result, functions, functions.indexOf("SPACE") + 1, gap,
                    rows.size() * rowHeight, 1, weights);
        } else {
            addGroup(result, functions, 0, functions.size(), 0, 1,
                    rows.size() * rowHeight, 1, weights);
        }
        return List.copyOf(result);
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
