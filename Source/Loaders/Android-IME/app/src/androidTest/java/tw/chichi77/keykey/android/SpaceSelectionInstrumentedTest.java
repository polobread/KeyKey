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
