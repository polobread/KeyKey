package tw.chichi77.keykey.android;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.provider.Settings;
import android.view.View;
import android.view.ViewGroup;
import android.widget.EditText;
import android.widget.Spinner;
import android.widget.Switch;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.util.ArrayList;

@RunWith(AndroidJUnit4.class)
public final class SimplifiedChineseOutputInstrumentedTest {
    @Test
    public void settingFollowsTheInputMethodPickerAndDefaultsOff() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        var preferences = ChineseInputMethodSettings.preferences(context);
        String key = ChineseInputMethodSettings.KEY_SIMPLIFIED_CHINESE_OUTPUT;
        Object previous = preferences.getAll().get(key);
        Activity activity = null;
        try {
            preferences.edit().remove(key).commit();
            activity = instrumentation.startActivitySync(new Intent(context, SettingsActivity.class)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            Activity settings = activity;
            instrumentation.runOnMainSync(() -> {
                var matches = new ArrayList<View>();
                settings.findViewById(android.R.id.content).findViewsWithText(matches,
                        context.getString(R.string.simplified_chinese_output), View.FIND_VIEWS_WITH_TEXT);
                assertEquals(1, matches.size());
                assertTrue(matches.get(0) instanceof Switch);
                Switch toggle = (Switch) matches.get(0);
                ViewGroup parent = (ViewGroup) toggle.getParent();
                assertTrue(parent.getChildAt(parent.indexOfChild(toggle) - 1) instanceof Spinner);
                assertFalse(toggle.isChecked());
                toggle.performClick();
                assertTrue(ChineseInputMethodSettings.simplifiedChineseOutput(context));
                toggle.performClick();
                assertFalse(ChineseInputMethodSettings.simplifiedChineseOutput(context));
            });
        } finally {
            if (activity != null) {
                Activity settings = activity;
                instrumentation.runOnMainSync(settings::finish);
            }
            if (previous instanceof Boolean enabled) preferences.edit().putBoolean(key, enabled).commit();
            else preferences.edit().remove(key).commit();
        }
    }

    @Test
    public void packagedDesktopTableConvertsHanOnceAndPreservesOtherText() {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        var converter = SimplifiedChineseOutput.load(context.getAssets());
        assertEquals("台湾、体验、冈 ∕≦ＡＢＣ𠮷🏳️‍🌈",
                converter.convert("臺灣、體驗、岡 ∕≦ＡＢＣ𠮷🏳️‍🌈"));
    }

    @Test
    public void simplifiedTouchSmartRolloverDoesNotDuplicateTheCommittedPrefix() throws Exception {
        org.junit.Assume.assumeTrue("The live keyboard inspector requires Android 10 / API 29",
                android.os.Build.VERSION.SDK_INT >= 29);
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        String ime = Settings.Secure.getString(context.getContentResolver(),
                Settings.Secure.DEFAULT_INPUT_METHOD);
        org.junit.Assume.assumeTrue("Select KeyKey on an isolated touch emulator", ime != null
                && ime.contains(context.getPackageName()));
        var preferences = ChineseInputMethodSettings.preferences(context);
        var previous = preferences.getAll();
        String[] keys = {ChineseInputMethodSettings.KEY_SIMPLIFIED_CHINESE_OUTPUT,
                ChineseInputMethodSettings.KEY_METHOD, BopomofoCompositionModeSettings.KEY_MODE,
                BopomofoCompositionModeSettings.KEY_OMIT_TONE,
                BopomofoKeyboardLayoutSettings.KEY_LAYOUT};
        Activity activity = null;
        try {
            preferences.edit().putBoolean(keys[0], true)
                    .putString(keys[1], ChineseInputMethod.SMART.name())
                    .putString(keys[2], "smart")
                    .putBoolean(keys[3], false)
                    .putString(keys[4], BopomofoKeyboardLayout.STANDARD.value).commit();
            activity = instrumentation.startActivitySync(new Intent()
                    .setClassName(context, context.getPackageName() + ".ImeTestActivity")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            IntegratedBottomControlsInstrumentedTest.showEditorKeyboard(activity, context);
            EditText editor = IntegratedBottomControlsInstrumentedTest.findEditor(
                    activity.findViewById(android.R.id.content));
            instrumentation.runOnMainSync(() -> typeCars(11));
            String simplified = "车".repeat(11);
            IntegratedBottomControlsInstrumentedTest.await(
                    () -> simplified.contentEquals(editor.getText()));

            instrumentation.runOnMainSync(() -> {
                ChineseInputMethodSettings.setSimplifiedChineseOutput(context, false);
                typeCars(1);
            });
            IntegratedBottomControlsInstrumentedTest.await(
                    () -> (simplified + "車").contentEquals(editor.getText()));
        } finally {
            if (activity != null) {
                Activity host = activity;
                instrumentation.runOnMainSync(host::finish);
            }
            var edit = preferences.edit();
            for (String key : keys) {
                if (previous.get(key) instanceof Boolean enabled) edit.putBoolean(key, enabled);
                else if (previous.get(key) instanceof String value) edit.putString(key, value);
                else edit.remove(key);
            }
            edit.commit();
        }
    }

    private static void typeCars(int count) {
        var keyboard = IntegratedBottomControlsInstrumentedTest.findKeyboard();
        assertTrue("The emulator must be using the touch keyboard", keyboard.isTouchMode());
        var service = (BopomofoImeService) keyboard.getContext();
        for (int index = 0; index < count; index++) {
            service.onKey("t");
            service.onKey("k");
            service.onKey("SPACE");
        }
    }
}
