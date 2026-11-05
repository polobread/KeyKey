package tw.chichi77.keykey.android;

import static org.junit.Assert.*;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import org.junit.Test;

public final class KeyboardIntegratedControlsTest {
    private static final float EPSILON = .00001f;
    private static final Set<String> NEW_CONTROLS = Set.of("GLOBE", "DISMISS");

    @Test public void switcherPolicyOnlyShowsTheModernSystemRequestedButton() {
        var policy = new KeyboardBottomControlsPolicy();
        assertFalse(policy.showGlobe(true));
        assertFalse(policy.showGlobe(false));
        // A request can arrive before any view asks for its initial state.
        policy.onCustomSwitcherRequested(true);
        assertTrue(policy.showGlobe(true));
        assertTrue(policy.showGlobe(true));
        assertFalse(policy.showGlobe(false));
        policy.onCustomSwitcherRequested(true);
        assertTrue(policy.showGlobe(true));
        assertFalse(policy.showGlobe(false));
        policy.onCustomSwitcherRequested(false);
        assertFalse(policy.showGlobe(true));
        assertFalse(policy.showGlobe(false));
        policy.onCustomSwitcherRequested(false);
        assertFalse(policy.showGlobe(true));
        assertFalse(policy.showGlobe(false));
    }

    @Test public void disabledControlsKeepTheExistingGeometryAndFunctionOrder() {
        for (var placement : placements()) {
            assertEquals(placement.legacyKeys(), placement.keys(false, false));
            assertEquals(KeyboardLayoutGeometry.resolvedFunctionKeys(placement.profile, placement.orientation,
                            placement.deletePosition),
                    KeyboardLayoutGeometry.resolvedFunctionKeys(placement.profile, placement.orientation,
                            placement.deletePosition, false, false));
        }
    }

    @Test public void requestedControlsShareTheModeAndSpaceBudgetWithoutChangingRowsOrOtherControls() {
        for (var placement : placements()) {
            var original = placement.legacyKeys();
            int mainKeyCount = KeyboardLayoutGeometry.resolvedRows(placement.profile, placement.orientation,
                    placement.plane, placement.shifted, placement.deletePosition)
                    .stream().mapToInt(List::size).sum();
            var originalFunctions = original.subList(mainKeyCount, original.size());
            for (boolean integrated : new boolean[] {false, true}) {
                for (boolean showGlobe : new boolean[] {false, true}) {
                    String context = placement + "/integrated=" + integrated + "/globe=" + showGlobe;
                    var keys = placement.keys(integrated, showGlobe);
                    assertEquals(context, original.subList(0, mainKeyCount), keys.subList(0, mainKeyCount));
                    var functions = keys.subList(mainKeyCount, keys.size());
                    assertEquals(context, KeyboardLayoutGeometry.resolvedFunctionKeys(placement.profile,
                                    placement.orientation, placement.deletePosition, integrated, showGlobe),
                            actions(functions));
                    var expectedActions = new HashMap<>(counts(original));
                    if (integrated && !placement.profile.split) expectedActions.merge("DISMISS", 1L, Long::sum);
                    if (showGlobe) expectedActions.merge("GLOBE", 1L, Long::sum);
                    assertEquals(context, expectedActions, counts(keys));
                    assertEquals(context, actions(originalFunctions), functions.stream()
                            .filter(key -> !NEW_CONTROLS.contains(key.action()))
                            .map(KeyboardLayoutGeometry.Key::action).collect(Collectors.toList()));
                    assertRequestedOrder(context, functions, integrated && !placement.profile.split, showGlobe);
                    assertExistingControlWidths(context, originalFunctions, functions);
                    assertModeWidth(context, originalFunctions, functions, showGlobe,
                            placement.profile.split);
                    for (var function : functions) {
                        assertEquals(context, originalFunctions.get(0).top(), function.top(), EPSILON);
                        assertEquals(context, originalFunctions.get(0).bottom(), function.bottom(), EPSILON);
                    }
                    assertWidthBudget(context, originalFunctions, functions);
                    if (placement.profile.split) {
                        assertCentralGap(context, keys, placement.width);
                        for (boolean left : new boolean[] {true, false}) {
                            var originalHalf = half(originalFunctions, left);
                            var modifiedHalf = half(functions, left);
                            String halfContext = context + (left ? "/left" : "/right");
                            assertEquals(halfContext, actions(originalHalf), modifiedHalf.stream()
                                    .filter(key -> !NEW_CONTROLS.contains(key.action()))
                                    .map(KeyboardLayoutGeometry.Key::action).collect(Collectors.toList()));
                            assertWidthBudget(halfContext, originalHalf, modifiedHalf);
                        }
                    }
                    assertUsableSlots(context, keys);
                }
            }
        }
    }

    @Test public void splitBottomControlsUseMainColumnWidthsAndGiveTheRestToSpace() {
        for (var placement : placements()) {
            if (!placement.profile.split) continue;
            for (boolean showGlobe : new boolean[] {false, true}) {
                String context = placement + "/globe=" + showGlobe;
                var keys = placement.keys(false, showGlobe);
                assertEquals(context + ": top dismiss makes bottom integration geometry redundant",
                        keys, placement.keys(true, showGlobe));
                var rows = KeyboardLayoutGeometry.resolvedRows(placement.profile, placement.orientation,
                        placement.plane, placement.shifted, placement.deletePosition);
                int mainCount = rows.stream().mapToInt(List::size).sum();
                float column = width(keys.get(0));
                var functions = keys.subList(mainCount, keys.size());
                assertFalse(context, actions(functions).contains("DISMISS"));
                for (String action : List.of("SYMBOL", "SETTINGS")) {
                    assertEquals(context + "/" + action, column, width(key(functions, action)), EPSILON);
                }
                assertEquals(context + "/MODE", column * (showGlobe ? 1 : 1.5f),
                        width(key(functions, "MODE")), EPSILON);
                if (showGlobe) assertEquals(context + "/GLOBE", column, width(key(functions, "GLOBE")), EPSILON);
                assertEquals(context + "/ENTER", 2 * column, width(key(functions, "ENTER")), EPSILON);
                String control = placement.deletePosition == KeyboardLayoutProfile.DeletePosition.ABOVE_ENTER
                        ? "SHIFT" : "BACKSPACE";
                assertEquals(context + "/" + control, column * (control.equals("SHIFT") ? 1 : 2),
                        width(key(functions, control)), EPSILON);
                var spaces = functions.stream().filter(item -> item.action().equals("SPACE"))
                        .collect(Collectors.toList());
                assertEquals(context, 2, spaces.size());
                assertEquals(context + "/leftSpace", column * (showGlobe ? 2 : 2.5f), width(spaces.get(0)), EPSILON);
                assertEquals(context + "/rightSpace", column * (control.equals("SHIFT") ? 3 : 2),
                        width(spaces.get(1)), EPSILON);
                for (boolean left : new boolean[] {true, false}) {
                    assertEquals(context + ": each half keeps the main-column budget",
                            column * rows.get(0).size() / 2, totalWidth(half(functions, left)), EPSILON);
                }
            }
        }
    }

    private static void assertRequestedOrder(String context, List<KeyboardLayoutGeometry.Key> functions,
            boolean integrated, boolean showGlobe) {
        var actions = actions(functions);
        if (showGlobe) assertEquals(context, "GLOBE", actions.get(0));
        else assertFalse(context, actions.contains("GLOBE"));
        if (integrated) {
            int settings = actions.indexOf("SETTINGS");
            assertTrue(context, settings >= 0 && settings + 1 < actions.size());
            assertEquals(context, "DISMISS", actions.get(settings + 1));
        } else assertFalse(context, actions.contains("DISMISS"));
    }

    private static void assertExistingControlWidths(String context, List<KeyboardLayoutGeometry.Key> original,
            List<KeyboardLayoutGeometry.Key> modified) {
        var before = original.stream().filter(key -> !contributesWidth(key))
                .collect(Collectors.toList());
        var after = modified.stream().filter(key -> !contributesWidth(key)
                && !NEW_CONTROLS.contains(key.action())).collect(Collectors.toList());
        assertEquals(context, actions(before), actions(after));
        for (int index = 0; index < before.size(); index++) {
            assertEquals(context + "/" + before.get(index).action(),
                    width(before.get(index)), width(after.get(index)), EPSILON);
        }
    }

    private static void assertModeWidth(String context, List<KeyboardLayoutGeometry.Key> original,
            List<KeyboardLayoutGeometry.Key> modified, boolean showGlobe, boolean split) {
        float before = width(key(original, "MODE"));
        float after = width(key(modified, "MODE"));
        if (showGlobe) {
            // The existing 1.65-slot mode key (1.5 in split) becomes one slot.
            assertEquals(context, before / (split ? 1.5f : 1.65f), after, EPSILON);
            assertEquals(context, after, width(key(modified, "GLOBE")), EPSILON);
        } else assertEquals(context, before, after, EPSILON);
    }

    private static void assertWidthBudget(String context, List<KeyboardLayoutGeometry.Key> original,
            List<KeyboardLayoutGeometry.Key> modified) {
        float before = totalWidth(original.stream().filter(KeyboardIntegratedControlsTest::contributesWidth)
                .collect(Collectors.toList()));
        float after = totalWidth(modified.stream().filter(KeyboardIntegratedControlsTest::contributesWidth)
                .collect(Collectors.toList()));
        float newWidth = totalWidth(modified.stream().filter(key -> NEW_CONTROLS.contains(key.action()))
                .collect(Collectors.toList()));
        assertEquals(context, before - after, newWidth, EPSILON);
        assertEquals(context, totalWidth(original), totalWidth(modified), EPSILON);
    }

    private static boolean contributesWidth(KeyboardLayoutGeometry.Key key) {
        return key.action().equals("SPACE") || key.action().equals("MODE");
    }

    private static KeyboardLayoutGeometry.Key key(List<KeyboardLayoutGeometry.Key> keys, String action) {
        return keys.stream().filter(key -> key.action().equals(action)).findFirst().orElseThrow();
    }

    private static float width(KeyboardLayoutGeometry.Key key) {
        return key.right() - key.left();
    }

    private static void assertCentralGap(String context, List<KeyboardLayoutGeometry.Key> keys, float width) {
        float gap = Math.min(80, width * .1f) / width;
        float leftEdge = (1 - gap) / 2;
        float rightEdge = (1 + gap) / 2;
        for (var key : keys) {
            assertTrue(context + ": central gap contains " + key.action(),
                    key.right() <= leftEdge + EPSILON || key.left() >= rightEdge - EPSILON);
        }
        assertEquals(context, leftEdge, half(keys, true).stream()
                .mapToDouble(KeyboardLayoutGeometry.Key::right).max().orElseThrow(), EPSILON);
        assertEquals(context, rightEdge, half(keys, false).stream()
                .mapToDouble(KeyboardLayoutGeometry.Key::left).min().orElseThrow(), EPSILON);
    }

    private static List<KeyboardLayoutGeometry.Key> half(List<KeyboardLayoutGeometry.Key> keys, boolean left) {
        return keys.stream().filter(key -> ((key.left() + key.right()) / 2 < .5f) == left)
                .collect(Collectors.toList());
    }

    private static float totalWidth(List<KeyboardLayoutGeometry.Key> keys) {
        return (float) keys.stream().mapToDouble(KeyboardIntegratedControlsTest::width).sum();
    }

    private static List<String> actions(List<KeyboardLayoutGeometry.Key> keys) {
        return keys.stream().map(KeyboardLayoutGeometry.Key::action).collect(Collectors.toList());
    }

    private static Map<String, Long> counts(List<KeyboardLayoutGeometry.Key> keys) {
        return keys.stream().collect(Collectors.groupingBy(KeyboardLayoutGeometry.Key::action, Collectors.counting()));
    }

    private static void assertUsableSlots(String context, List<KeyboardLayoutGeometry.Key> keys) {
        for (int index = 0; index < keys.size(); index++) {
            var key = keys.get(index);
            assertTrue(context, key.right() > key.left() && key.bottom() > key.top());
            assertTrue(context, key.left() >= -EPSILON && key.top() >= -EPSILON
                    && key.right() <= 1 + EPSILON && key.bottom() <= 1 + EPSILON);
            for (var other : keys.subList(0, index)) {
                if (key.left() < other.right() - EPSILON && other.left() < key.right() - EPSILON
                        && key.top() < other.bottom() - EPSILON && other.top() < key.bottom() - EPSILON) {
                    fail(context + ": overlapping slots " + key.action() + "/" + other.action());
                }
            }
        }
    }

    private static List<Placement> placements() {
        var result = new ArrayList<Placement>();
        for (var profile : KeyboardLayoutProfile.available()) {
            for (var orientation : KeyboardLayoutProfile.Orientation.values()) {
                for (var plane : KeyboardLayoutProfile.Plane.values()) {
                    for (boolean shifted : new boolean[] {false, true}) {
                        for (var deletePosition : KeyboardLayoutProfile.DeletePosition.values()) {
                            for (float width : new float[] {240, 320, 390, 599, 600, 1200}) {
                                result.add(new Placement(profile, orientation, plane, shifted, deletePosition, width));
                            }
                        }
                    }
                }
            }
        }
        return result;
    }

    private record Placement(KeyboardLayoutProfile profile, KeyboardLayoutProfile.Orientation orientation,
            KeyboardLayoutProfile.Plane plane, boolean shifted,
            KeyboardLayoutProfile.DeletePosition deletePosition, float width) {
        List<KeyboardLayoutGeometry.Key> legacyKeys() {
            return KeyboardLayoutGeometry.keys(profile, orientation, plane, shifted, deletePosition, width);
        }
        List<KeyboardLayoutGeometry.Key> keys(boolean integrated, boolean showGlobe) {
            return KeyboardLayoutGeometry.keys(profile, orientation, plane, shifted, deletePosition,
                    width, integrated, showGlobe);
        }
        @Override public String toString() {
            return profile.id + "/" + orientation + "/" + plane + "/" + shifted + "/" + deletePosition + "/" + width;
        }
    }
}
