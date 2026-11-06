package tw.chichi77.keykey.android;

import static org.junit.Assert.*;

import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.view.inputmethod.InputMethodManager;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import org.junit.Assume;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Opt-in on a disposable owned device: this intentionally changes the active IME. */
@RunWith(AndroidJUnit4.class)
@android.annotation.TargetApi(30)
public final class PlatformInputMethodSwitchInstrumentedTest {
    @Test public void globeSwitchesToAnotherEnabledInputMethodOnOwnedDevice() throws Exception {
        Assume.assumeTrue(Build.VERSION.SDK_INT >= 30);
        Assume.assumeTrue("Run this isolated smoke separately with an owned test device",
                Boolean.parseBoolean(InstrumentationRegistry.getArguments()
                        .getString("keykey.ownedPlatformSwitchSmoke", "false")));
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        String selected = Settings.Secure.getString(context.getContentResolver(), Settings.Secure.DEFAULT_INPUT_METHOD);
        assertTrue(selected.contains(context.getPackageName()));
        assertTrue(context.getSystemService(InputMethodManager.class).getEnabledInputMethodList().size() > 1);
        var activity = instrumentation.startActivitySync(new Intent()
                .setClassName(context, "tw.chichi77.keykey.android.ImeTestActivity")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        try {
            IntegratedBottomControlsInstrumentedTest.showEditorKeyboard(activity, context);
            instrumentation.runOnMainSync(() -> ((BopomofoImeService)
                    IntegratedBottomControlsInstrumentedTest.findKeyboard().getContext()).onKey("GLOBE"));
            IntegratedBottomControlsInstrumentedTest.await(() -> !selected.equals(Settings.Secure.getString(
                    context.getContentResolver(), Settings.Secure.DEFAULT_INPUT_METHOD)));
            Bundle evidence = new Bundle(); evidence.putString("keykey_platform_switch", "api=" + Build.VERSION.SDK_INT + ", switched=true");
            instrumentation.sendStatus(0, evidence);
        } finally {
            instrumentation.runOnMainSync(activity::finish);
        }
    }
}
