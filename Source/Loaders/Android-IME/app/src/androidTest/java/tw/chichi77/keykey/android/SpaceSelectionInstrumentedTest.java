package tw.chichi77.keykey.android;

import static org.junit.Assert.*;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.view.View;
import android.view.ViewGroup;
import android.widget.CheckBox;
import android.widget.ScrollView;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public final class SpaceSelectionInstrumentedTest {
    @Test public void settingDefaultsOffAndPersistsFromSettingsUI() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        SharedPreferences prefs = BopomofoCompositionModeSettings.preferences(context);
        String key = BopomofoCompositionModeSettings.KEY_SPACE_SELECTS_CANDIDATES;
        Object previous = prefs.getAll().get(key);
        Activity activity = null;
        try {
            prefs.edit().remove(key).commit();
            assertFalse(BopomofoCompositionModeSettings.spaceSelectsCandidates(context));
            activity = instrumentation.startActivitySync(new Intent(context,
                    SettingsActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            Activity current = activity;
            instrumentation.runOnMainSync(() -> {
                View root = ((ScrollView) ((ViewGroup) current.findViewById(android.R.id.content))
                        .getChildAt(0)).getChildAt(0);
                CheckBox toggle = findToggle(root);
                assertNotNull(toggle);
                assertFalse(toggle.isChecked());
                toggle.setChecked(true);
                assertTrue(BopomofoCompositionModeSettings.spaceSelectsCandidates(context));
                current.finish();
            });
            activity = instrumentation.startActivitySync(new Intent(context,
                    SettingsActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            Activity reopened = activity;
            instrumentation.runOnMainSync(() -> {
                assertTrue(findToggle(reopened.findViewById(android.R.id.content)).isChecked());
                findToggle(reopened.findViewById(android.R.id.content)).setChecked(false);
                assertFalse(BopomofoCompositionModeSettings.spaceSelectsCandidates(context));
            });
        } finally {
            if (activity != null) {
                Activity current = activity;
                instrumentation.runOnMainSync(current::finish);
            }
            if (previous instanceof Boolean value) prefs.edit().putBoolean(key, value).commit();
            else prefs.edit().remove(key).commit();
        }
    }

    @Test public void bothKeyboardsUseOnePreferenceAndExplicitCandidatesStayIndependent()
            throws Exception {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        SharedPreferences prefs = BopomofoCompositionModeSettings.preferences(context);
        String key = BopomofoCompositionModeSettings.KEY_SPACE_SELECTS_CANDIDATES;
        Object previous = prefs.getAll().get(key);
        try (SmartMandarinStore store = SmartMandarinStore.open(context, null)) {
            for (boolean hardware : new boolean[]{false, true}) {
                BopomofoEngine engine = new BopomofoEngine(CinDictionary.empty(), store,
                        BopomofoCompositionMode.SMART);
                BopomofoCompositionModeSettings.setSpaceSelectsCandidates(context, false);
                engine.setSpaceSelectsCandidates(BopomofoCompositionModeSettings.spaceSelectsCandidates(context));
                type(engine, hardware, "su3cl3");
                String expected = engine.composingText();
                assertFalse(expected.isEmpty());
                BopomofoEngine.Result result = hardware ? engine.handleHardwareSpace() : engine.handleSoftKey("SPACE");
                assertEquals("", result.committedText());
                assertEquals(expected + " ", engine.composingText());
                assertTrue(engine.hasComposition());
                type(engine, hardware, "su3");
                engine.openSmartCandidates(); // The action used by Down-arrow.
                assertTrue(engine.isShowingSmartCandidates());
                expected = engine.composingText();
                assertEquals("", engine.space().committedText());
                assertEquals(expected + " ", engine.composingText());
                assertTrue(engine.hasComposition());
                if (hardware) { engine.moveSmartCompositionCursor(-5); engine.openSmartCandidates(); }
                else assertTrue(engine.selectTouchSmartCell(0));
                int alternate = engine.displayedCandidates().indexOf("妳");
                assertTrue(alternate >= 0);
                engine.selectDisplayedCandidate(alternate);
                assertTrue(engine.composingText().startsWith("妳好 "));
                assertTrue(engine.composingText().endsWith("你 "));
                engine.reset();
                BopomofoCompositionModeSettings.setSpaceSelectsCandidates(context, true);
                engine.setSpaceSelectsCandidates(BopomofoCompositionModeSettings.spaceSelectsCandidates(context));
                type(engine, hardware, "su3");
                assertEquals("", engine.space().committedText());
                assertTrue(engine.isShowingSmartCandidates());
                var firstPage = engine.displayedCandidates();
                assertEquals("", engine.space().committedText());
                if (engine.pageCount() > 1) assertNotEquals(firstPage, engine.displayedCandidates());
                else assertEquals(firstPage, engine.displayedCandidates());
                engine.reset();
            }
        } finally {
            if (previous instanceof Boolean value) prefs.edit().putBoolean(key, value).commit();
            else prefs.edit().remove(key).commit();
        }
    }

    private static void type(BopomofoEngine engine, boolean hardware, String keys) {
        for (char key : keys.toCharArray()) {
            if (hardware) engine.handleHardwareCharacter(key);
            else engine.handleSoftKey(String.valueOf(key));
        }
    }

    private static CheckBox findToggle(View root) {
        if (root instanceof CheckBox check && check.getText().toString().equals("使用空白鍵選字")) return check;
        if (root instanceof ViewGroup group) {
            for (int i = 0; i < group.getChildCount(); i++) {
                CheckBox result = findToggle(group.getChildAt(i));
                if (result != null) return result;
            }
        }
        return null;
    }
}
