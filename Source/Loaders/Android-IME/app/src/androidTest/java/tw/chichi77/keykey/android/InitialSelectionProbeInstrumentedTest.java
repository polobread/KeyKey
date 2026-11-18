package tw.chichi77.keykey.android;

import static org.junit.Assert.*;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.os.Looper;
import android.os.SystemClock;
import android.view.inputmethod.BaseInputConnection;
import android.widget.EditText;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.lang.reflect.Field;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Real same-process public IC: hold its app batch so no early baseline can hide the probe. */
@RunWith(AndroidJUnit4.class)
public final class InitialSelectionProbeInstrumentedTest {
    @Test public void unknownFirstWriteQueriesOnceOutsideItsBatchWithoutBlockingTheSharedMainLooper() throws Exception {
        org.junit.Assume.assumeTrue(Build.VERSION.SDK_INT >= 30);
        org.junit.Assume.assumeTrue("Use an owned disposable touch device",
                "true".equals(InstrumentationRegistry.getArguments().getString("keykey.isolatedDevice")));
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        var preferences = CandidateWindowSettings.preferences(context);
        var previous = preferences.getAll();
        String[] keys = {ChineseInputMethodSettings.KEY_METHOD, BopomofoCompositionModeSettings.KEY_MODE,
                BopomofoCompositionModeSettings.KEY_OMIT_TONE, BopomofoKeyboardLayoutSettings.KEY_LAYOUT};
        try {
            preferences.edit().putString(keys[0], ChineseInputMethod.SMART.name())
                    .putString(keys[1], BopomofoCompositionModeSettings.valueForMode(BopomofoCompositionMode.SMART))
                    .putBoolean(keys[2], false).putString(keys[3], BopomofoKeyboardLayout.STANDARD.value).commit();
            IntegratedBottomControlsInstrumentedTest.await(() -> {
                var view = IntegratedBottomControlsInstrumentedTest.findKeyboard();
                return view == null || !engine((BopomofoImeService) view.getContext()).hasComposition();
            });
            instrumentation.runOnMainSync(() -> { try (var data = UserPhraseRepository.open(context)) { data.resetSmartLearning(); } });
            for (String behavior : new String[]{"known", "full", "reverse", "unavailable", "partial", "outside", "overflow"}) {
                boolean unknown = !behavior.equals("known");
                boolean valid = behavior.equals("known") || behavior.equals("full") || behavior.equals("reverse");
                boolean reverse = behavior.equals("reverse");
                String initial = reverse ? "前😀甲乙後" : "前:";
                Intent launch = new Intent().setClassName(context, "tw.chichi77.keykey.android.ImeTestActivity")
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK)
                        .putExtra("initialSelectionUnknown", unknown)
                        .putExtra("holdInitialSelectionUntilWrite", true)
                        .putExtra("releaseInitialBatchAfterCommitMs", 450)
                        .putExtra("probeInitialText", initial)
                        .putExtra("probeSelectionStart", reverse ? 5 : initial.length())
                        .putExtra("probeSelectionEnd", reverse ? 3 : initial.length());
                if (!valid) launch.putExtra("restartExtraction", behavior);
                ImeTestActivity host = (ImeTestActivity) instrumentation.startActivitySync(launch);
                try {
                    IntegratedBottomControlsInstrumentedTest.showEditorKeyboard(host, context);
                    EditText editor = IntegratedBottomControlsInstrumentedTest.findEditor(host.findViewById(android.R.id.content));
                    BopomofoImeService[] service = {null};
                    long[] callerMillis = {0};
                    instrumentation.runOnMainSync(() -> {
                        assertSame(Looper.getMainLooper(), Looper.myLooper());
                        service[0] = (BopomofoImeService) IntegratedBottomControlsInstrumentedTest.findKeyboard().getContext();
                        assertTrue(IntegratedBottomControlsInstrumentedTest.findKeyboard().isTouchMode());
                        if (unknown) {
                            assertEquals(-1, service[0].getCurrentInputEditorInfo().initialSelStart);
                            assertEquals("The app-held batch must keep this genuinely unknown until the first write",
                                    -1, field(service[0], "lastSelectionStart"));
                        }
                        service[0].onKey("s"); service[0].onKey("u");
                        assertTrue(engine(service[0]).hasComposition());
                        assertEquals(initial, editor.getText().toString());
                        assertEquals("Local-only pending keys must not query the host", 0, host.extractionProbeCalls.get());
                        long before = SystemClock.uptimeMillis();
                        service[0].onKey("3");
                        callerMillis[0] = SystemClock.uptimeMillis() - before;
                        // Measure the IME caller's entire shared-main operation,
                        // not just a host body that could run after a timeout.
                        assertTrue("The same-main probe must not wait for its own looper: " + callerMillis[0] + "ms",
                                callerMillis[0] < 1000);
                        assertEquals(unknown ? 1 : 0, host.extractionProbeCalls.get());
                        if (valid) assertEquals(reverse ? 4 : 3, field(service[0], "lastSelectionStart"));
                        else {
                            assertEquals("Rejected snapshots must not invent an absolute anchor", -1,
                                    field(service[0], "lastSelectionStart"));
                            service[0].onKey("BACKSPACE");
                            assertEquals("An unknown same-IC second write must not probe again", 1, host.extractionProbeCalls.get());
                        }
                    });
                    String first = valid ? reverse ? "前😀你後" : "前:你" : initial;
                    IntegratedBottomControlsInstrumentedTest.await(() -> editor.getText().toString().equals(first));
                    SystemClock.sleep(550); // Let this deliberately delayed host finish its own batch.
                    instrumentation.runOnMainSync(() -> {
                        assertEquals(unknown ? 1 : 0, host.extractionProbeCalls.get());
                        assertEquals(-1, BaseInputConnection.getComposingSpanStart(editor.getText()));
                        if (valid) {
                            assertTrue(engine(service[0]).hasComposition());
                            assertEquals("你", engine(service[0]).completedSmartText());
                            for (char key : "cl3".toCharArray()) service[0].onKey(String.valueOf(key));
                        } else assertFalse(engine(service[0]).hasComposition());
                    });
                    if (valid) {
                        String all = reverse ? "前😀你好後" : "前:你好";
                        IntegratedBottomControlsInstrumentedTest.await(() -> editor.getText().toString().equals(all));
                        instrumentation.runOnMainSync(() -> {
                            assertEquals("你好", engine(service[0]).completedSmartText());
                            assertEquals(unknown ? 1 : 0, host.extractionProbeCalls.get());
                        });
                    }
                    Bundle evidence = new Bundle();
                    evidence.putString("keykey_initial_probe", "behavior=" + behavior + ", calls=" + host.extractionProbeCalls.get()
                            + ", callerMillis=" + callerMillis[0] + ", hostBodyMaxMillis=" + host.extractionProbeMaxMillis.get()
                            + ", hostCallsOnMain=" + host.extractionProbeCallsOnMain.get()
                            + ", actualText=" + editor.getText() + ", sameActivity=true");
                    instrumentation.sendStatus(0, evidence);
                } finally {
                    instrumentation.runOnMainSync(host::finish);
                }
            }
        } finally {
            var edit = preferences.edit();
            for (String key : keys) {
                edit.remove(key); Object value = previous.get(key);
                if (value instanceof String text) edit.putString(key, text);
                else if (value instanceof Boolean enabled) edit.putBoolean(key, enabled);
            }
            edit.commit();
        }
    }

    private static HostInputEngine engine(BopomofoImeService service) { return (HostInputEngine) field(service, "engine"); }
    private static Object field(Object target, String name) {
        try { Field field = target.getClass().getDeclaredField(name); field.setAccessible(true); return field.get(target); }
        catch (ReflectiveOperationException error) { throw new AssertionError(error); }
    }
}
