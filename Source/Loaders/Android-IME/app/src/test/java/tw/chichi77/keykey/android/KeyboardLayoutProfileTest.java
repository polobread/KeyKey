package tw.chichi77.keykey.android;

import static org.junit.Assert.*;

import java.util.EnumMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.Test;

public final class KeyboardLayoutProfileTest {
    @Test public void registeredProfilesHaveUsableGeometryAndStableIdentifiers() {
        var identifiers = new HashSet<String>();
        for (KeyboardLayoutProfile profile : KeyboardLayoutProfile.available()) {
            assertFalse(profile.id.isEmpty());
            assertTrue("Profile identifiers must be unique", identifiers.add(profile.id));
            assertSame(profile, KeyboardLayoutProfile.forId(profile.id));
            for (KeyboardLayoutProfile.Orientation orientation : KeyboardLayoutProfile.Orientation.values()) {
                var layout = profile.layout(orientation);
                assertNotNull(layout);
                assertTrue(layout.contentHeightDp > 0);
                assertTrue(layout.compositionCellCount > 0);
                assertFalse(layout.functionKeys().isEmpty());
                for (String key : layout.functionKeys()) assertTrue(layout.functionWeight(key) > 0);
                for (KeyboardLayoutProfile.Plane plane : KeyboardLayoutProfile.Plane.values()) {
                    for (boolean shifted : new boolean[] {false, true}) {
                        var rows = layout.rows(plane, shifted);
                        assertFalse(rows.isEmpty());
                        for (var row : rows) {
                            assertFalse(row.isEmpty());
                            for (String action : row) assertFalse(action.isEmpty());
                        }
                    }
                }
            }
        }
    }

    @Test public void resolvesEachOrientationPlaneAndShiftVariantIndependently() {
        var layouts = new EnumMap<KeyboardLayoutProfile.Orientation, KeyboardLayoutProfile.Layout>(
                KeyboardLayoutProfile.Orientation.class);
        var normalSentinels = new EnumMap<KeyboardLayoutProfile.Orientation,
                Map<KeyboardLayoutProfile.Plane, String>>(KeyboardLayoutProfile.Orientation.class);
        var shiftedSentinels = new EnumMap<KeyboardLayoutProfile.Orientation,
                Map<KeyboardLayoutProfile.Plane, String>>(KeyboardLayoutProfile.Orientation.class);
        for (var orientation : KeyboardLayoutProfile.Orientation.values()) {
            var planes = new EnumMap<KeyboardLayoutProfile.Plane, KeyboardLayoutProfile.KeyPlane>(
                    KeyboardLayoutProfile.Plane.class);
            var normal = new EnumMap<KeyboardLayoutProfile.Plane, String>(KeyboardLayoutProfile.Plane.class);
            var shifted = new EnumMap<KeyboardLayoutProfile.Plane, String>(KeyboardLayoutProfile.Plane.class);
            for (var plane : KeyboardLayoutProfile.Plane.values()) {
                String normalAction = UUID.randomUUID().toString();
                String shiftedAction = UUID.randomUUID().toString();
                normal.put(plane, normalAction);
                shifted.put(plane, shiftedAction);
                planes.put(plane, new KeyboardLayoutProfile.KeyPlane(
                        new String[][] {{normalAction}}, new String[][] {{shiftedAction}}));
            }
            normalSentinels.put(orientation, normal);
            shiftedSentinels.put(orientation, shifted);
            String functionAction = UUID.randomUUID().toString();
            layouts.put(orientation, new KeyboardLayoutProfile.Layout(1, 1, planes,
                    List.of(functionAction), Map.of(functionAction, 1f)));
        }
        String identifier = UUID.randomUUID().toString();
        var profile = new KeyboardLayoutProfile(identifier, identifier, layouts);
        for (var orientation : KeyboardLayoutProfile.Orientation.values()) {
            for (var plane : KeyboardLayoutProfile.Plane.values()) {
                assertEquals(List.of(List.of(normalSentinels.get(orientation).get(plane))),
                        profile.layout(orientation).rows(plane, false));
                assertEquals(List.of(List.of(shiftedSentinels.get(orientation).get(plane))),
                        profile.layout(orientation).rows(plane, true));
            }
        }
    }

    @Test public void unavailableSavedProfileUsesTheExistingDefault() {
        String unknownIdentifier = UUID.randomUUID().toString();
        assertSame(KeyboardLayoutProfile.FULL, KeyboardLayoutProfile.forId(unknownIdentifier));
        assertSame(KeyboardLayoutProfile.FULL, KeyboardLayoutProfile.forId(null));
    }
}
