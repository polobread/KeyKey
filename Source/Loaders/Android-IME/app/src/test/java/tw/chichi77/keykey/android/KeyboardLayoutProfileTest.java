package tw.chichi77.keykey.android;

import static org.junit.Assert.*;

import java.util.EnumMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.junit.Test;

public final class KeyboardLayoutProfileTest {
    @Test public void registeredLayoutsHaveUsableGeometryAndStableIdentifiers() {
        var identifiers = new HashSet<String>();
        for (var profile : KeyboardLayoutProfile.available()) {
            assertFalse(profile.id.isEmpty());
            assertTrue("Layout identifiers must be unique", identifiers.add(profile.id));
            assertSame(profile, KeyboardLayoutProfile.forId(profile.id));
            for (var orientation : KeyboardLayoutProfile.Orientation.values()) {
                var layout = profile.layout(orientation);
                assertNotNull(layout);
                assertTrue(layout.contentHeightDp > 0);
                assertTrue(layout.compositionCellCount > 0);
                assertFalse(layout.functionKeys().isEmpty());
                for (String key : layout.functionKeys()) assertTrue(layout.functionWeight(key) > 0);
                for (var plane : KeyboardLayoutProfile.Plane.values()) {
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
        assertEquals(Set.of("standard", "aligned", "aligned-split"), identifiers);
        assertTrue(KeyboardLayoutProfile.STANDARD.staggered);
        assertFalse(KeyboardLayoutProfile.STANDARD.split);
        assertFalse(KeyboardLayoutProfile.ALIGNED.staggered);
        assertFalse(KeyboardLayoutProfile.ALIGNED.split);
        assertFalse(KeyboardLayoutProfile.ALIGNED_SPLIT.staggered);
        assertTrue(KeyboardLayoutProfile.ALIGNED_SPLIT.split);
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

    @Test public void savedOptionIdentifiersRoundTripAndUnknownValuesUseDefaults() {
        for (var spacing : KeyboardLayoutProfile.KeycapArea.values()) {
            assertSame(spacing, KeyboardLayoutProfile.KeycapArea.forId(spacing.id));
        }
        for (var font : KeyboardLayoutProfile.FontSize.values()) {
            assertSame(font, KeyboardLayoutProfile.FontSize.forId(font.id));
        }
        for (var position : KeyboardLayoutProfile.DeletePosition.values()) {
            assertSame(position, KeyboardLayoutProfile.DeletePosition.forId(position.id));
        }
        assertEquals(1f, KeyboardLayoutProfile.KeycapArea.SMALL.fraction, 0);
        assertEquals(.9f, KeyboardLayoutProfile.KeycapArea.MEDIUM.fraction, 0);
        assertEquals(.8f, KeyboardLayoutProfile.KeycapArea.LARGE.fraction, 0);
        for (String unknown : new String[] {null, "", "unknown"}) {
            assertSame(KeyboardLayoutProfile.ALIGNED, KeyboardLayoutProfile.forId(unknown));
            assertSame(KeyboardLayoutProfile.KeycapArea.SMALL, KeyboardLayoutProfile.KeycapArea.forId(unknown));
            assertSame(KeyboardLayoutProfile.FontSize.NORMAL, KeyboardLayoutProfile.FontSize.forId(unknown));
            assertSame(KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER,
                    KeyboardLayoutProfile.DeletePosition.forId(unknown));
        }
        assertOptions(KeyboardLayoutProfile.ALIGNED, KeyboardLayoutProfile.KeycapArea.SMALL,
                KeyboardLayoutProfile.FontSize.NORMAL, KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER,
                KeyboardLayoutProfile.resolveOptions(null, null, null, null, null, null));
    }

    @Test public void oldVisualStylesMigrateToIndependentOptions() {
        for (var position : KeyboardLayoutProfile.DeletePosition.values()) {
            for (String legacyArea : new String[] {null, "90", "85"}) {
                assertLegacyOptions("full", legacyArea, position, KeyboardLayoutProfile.ALIGNED,
                        KeyboardLayoutProfile.KeycapArea.SMALL, KeyboardLayoutProfile.FontSize.NORMAL);
                assertLegacyOptions("staggered", legacyArea, position, KeyboardLayoutProfile.STANDARD,
                        KeyboardLayoutProfile.KeycapArea.SMALL, KeyboardLayoutProfile.FontSize.NORMAL);
                assertLegacyOptions("large-full", legacyArea, position, KeyboardLayoutProfile.ALIGNED,
                        KeyboardLayoutProfile.KeycapArea.SMALL, KeyboardLayoutProfile.FontSize.LARGE);
                assertLegacyOptions("large-staggered", legacyArea, position, KeyboardLayoutProfile.STANDARD,
                        KeyboardLayoutProfile.KeycapArea.SMALL, KeyboardLayoutProfile.FontSize.LARGE);
                assertLegacyOptions("unknown", legacyArea, position, KeyboardLayoutProfile.ALIGNED,
                        KeyboardLayoutProfile.KeycapArea.SMALL, KeyboardLayoutProfile.FontSize.NORMAL);
            }
            for (String legacyArea : new String[] {null, "90", "unknown"}) {
                assertLegacyOptions("full-spaced", legacyArea, position, KeyboardLayoutProfile.ALIGNED,
                        KeyboardLayoutProfile.KeycapArea.MEDIUM, KeyboardLayoutProfile.FontSize.NORMAL);
            }
            assertLegacyOptions("full-spaced", "85", position, KeyboardLayoutProfile.ALIGNED,
                    KeyboardLayoutProfile.KeycapArea.LARGE, KeyboardLayoutProfile.FontSize.NORMAL);
        }
        // Legacy style IDs are migration input rather than additional registered layouts.
        assertSame(KeyboardLayoutProfile.ALIGNED, KeyboardLayoutProfile.forId("staggered"));
        assertSame(KeyboardLayoutProfile.ALIGNED, KeyboardLayoutProfile.forId("large-staggered"));
    }

    @Test public void explicitNewOptionsOverrideLegacyValuesIndependently() {
        for (var profile : KeyboardLayoutProfile.available()) {
            for (var spacing : KeyboardLayoutProfile.KeycapArea.values()) {
                for (var font : KeyboardLayoutProfile.FontSize.values()) {
                    for (var position : KeyboardLayoutProfile.DeletePosition.values()) {
                        for (String legacy : List.of("full-spaced", "large-staggered")) {
                            assertOptions(profile, spacing, font, position, KeyboardLayoutProfile.resolveOptions(
                                    profile.id, spacing.id, font.id, position.id, legacy, "85"));
                        }
                    }
                }
            }
        }
        assertOptions(KeyboardLayoutProfile.ALIGNED_SPLIT, KeyboardLayoutProfile.KeycapArea.SMALL,
                KeyboardLayoutProfile.FontSize.LARGE, KeyboardLayoutProfile.DeletePosition.ABOVE_ENTER,
                KeyboardLayoutProfile.resolveOptions("aligned-split", null, null, "above-enter",
                        "large-staggered", "85"));
        assertOptions(KeyboardLayoutProfile.STANDARD, KeyboardLayoutProfile.KeycapArea.LARGE,
                KeyboardLayoutProfile.FontSize.LARGE, KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER,
                KeyboardLayoutProfile.resolveOptions(null, "80", null, null, "large-staggered", "90"));
        assertOptions(KeyboardLayoutProfile.ALIGNED, KeyboardLayoutProfile.KeycapArea.LARGE,
                KeyboardLayoutProfile.FontSize.LARGE, KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER,
                KeyboardLayoutProfile.resolveOptions(null, null, "large", null, "full-spaced", "85"));
    }

    @Test public void invalidNewValuesResetOnlyTheirOwnOption() {
        for (String invalid : List.of("unknown", "")) {
            assertOptions(KeyboardLayoutProfile.ALIGNED, KeyboardLayoutProfile.KeycapArea.SMALL,
                    KeyboardLayoutProfile.FontSize.LARGE, KeyboardLayoutProfile.DeletePosition.ABOVE_ENTER,
                    KeyboardLayoutProfile.resolveOptions(invalid, null, null, "above-enter",
                            "large-staggered", "85"));
            assertOptions(KeyboardLayoutProfile.ALIGNED, KeyboardLayoutProfile.KeycapArea.SMALL,
                    KeyboardLayoutProfile.FontSize.NORMAL, KeyboardLayoutProfile.DeletePosition.ABOVE_ENTER,
                    KeyboardLayoutProfile.resolveOptions(null, invalid, null, "above-enter", "full-spaced", "85"));
            assertOptions(KeyboardLayoutProfile.STANDARD, KeyboardLayoutProfile.KeycapArea.SMALL,
                    KeyboardLayoutProfile.FontSize.NORMAL, KeyboardLayoutProfile.DeletePosition.ABOVE_ENTER,
                    KeyboardLayoutProfile.resolveOptions(null, null, invalid, "above-enter", "large-staggered", "85"));
            assertOptions(KeyboardLayoutProfile.STANDARD, KeyboardLayoutProfile.KeycapArea.SMALL,
                    KeyboardLayoutProfile.FontSize.LARGE, KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER,
                    KeyboardLayoutProfile.resolveOptions(null, null, null, invalid, "large-staggered", "85"));
        }
    }

    private static void assertLegacyOptions(String legacyProfile, String legacyArea,
            KeyboardLayoutProfile.DeletePosition position, KeyboardLayoutProfile expectedLayout,
            KeyboardLayoutProfile.KeycapArea expectedSpacing, KeyboardLayoutProfile.FontSize expectedFont) {
        assertOptions(expectedLayout, expectedSpacing, expectedFont, position,
                KeyboardLayoutProfile.resolveOptions(null, null, null, position.id, legacyProfile, legacyArea));
    }

    private static void assertOptions(KeyboardLayoutProfile layout, KeyboardLayoutProfile.KeycapArea spacing,
            KeyboardLayoutProfile.FontSize font, KeyboardLayoutProfile.DeletePosition position,
            KeyboardLayoutProfile.VisualOptions actual) {
        assertSame(layout, actual.layout());
        assertSame(spacing, actual.spacing());
        assertSame(font, actual.fontSize());
        assertSame(position, actual.deletePosition());
    }
}
