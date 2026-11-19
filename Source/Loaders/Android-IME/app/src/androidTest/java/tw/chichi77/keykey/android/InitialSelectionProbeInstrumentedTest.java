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
        String[] keys = {KeyboardSettingsProfile.key(true, ChineseInputMethodSettings.KEY_METHOD), BopomofoCompositionModeSettings.KEY_MODE,
                KeyboardSettingsProfile.key(true, BopomofoCompositionModeSettings.KEY_OMIT_TONE), KeyboardSettingsProfile.key(true, BopomofoKeyboardLayoutSettings.KEY_LAYOUT)};
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

    @Test public void unavailableEmptyRestartStillProbesAtTheFirstActualWrite() throws Exception {
        org.junit.Assume.assumeTrue(Build.VERSION.SDK_INT >= 30);
        org.junit.Assume.assumeTrue("Use an owned disposable touch device",
                "true".equals(InstrumentationRegistry.getArguments().getString("keykey.isolatedDevice")));
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        var preferences = CandidateWindowSettings.preferences(context);
        var previous = preferences.getAll();
        String[] keys = {KeyboardSettingsProfile.key(true, ChineseInputMethodSettings.KEY_METHOD), BopomofoCompositionModeSettings.KEY_MODE,
                KeyboardSettingsProfile.key(true, BopomofoCompositionModeSettings.KEY_OMIT_TONE), KeyboardSettingsProfile.key(true, BopomofoKeyboardLayoutSettings.KEY_LAYOUT)};
        try {
            preferences.edit().putString(keys[0], ChineseInputMethod.SMART.name())
                    .putString(keys[1], BopomofoCompositionModeSettings.valueForMode(BopomofoCompositionMode.SMART))
                    .putBoolean(keys[2], false).putString(keys[3], BopomofoKeyboardLayout.STANDARD.value).commit();
            IntegratedBottomControlsInstrumentedTest.await(() -> {
                var view = IntegratedBottomControlsInstrumentedTest.findKeyboard();
                return view == null || !engine((BopomofoImeService) view.getContext()).hasComposition();
            });
            instrumentation.runOnMainSync(() -> { try (var data = UserPhraseRepository.open(context)) { data.resetSmartLearning(); } });
            for (String behavior : new String[]{"unavailable", "partial", "outside", "overflow"}) {
                ImeTestActivity host = (ImeTestActivity) instrumentation.startActivitySync(new Intent()
                        .setClassName(context, "tw.chichi77.keykey.android.ImeTestActivity")
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK)
                        .putExtra("initialSelectionUnknown", true)
                        .putExtra("holdInitialSelectionUntilWrite", true)
                        .putExtra("releaseInitialBatchAfterCommitMs", 450)
                        .putExtra("probeInitialText", "前:")
                        .putExtra("probeSelectionStart", 2).putExtra("probeSelectionEnd", 2));
                try {
                    IntegratedBottomControlsInstrumentedTest.showEditorKeyboard(host, context);
                    EditText editor = IntegratedBottomControlsInstrumentedTest.findEditor(host.findViewById(android.R.id.content));
                    BopomofoImeService[] service = {null};
                    instrumentation.runOnMainSync(() -> {
                        service[0] = (BopomofoImeService) IntegratedBottomControlsInstrumentedTest.findKeyboard().getContext();
                        assertTrue(IntegratedBottomControlsInstrumentedTest.findKeyboard().isTouchMode());
                        assertEquals("前:", editor.getText().toString());
                        assertEquals(0, host.extractionProbeCalls.get());
                        assertEquals(-1, field(service[0], "lastSelectionStart"));
                        assertFalse(engine(service[0]).hasComposition());
                        var connection = service[0].getCurrentInputConnection();
                        host.getIntent().putExtra("restartExtraction", behavior);
                        var stale = new android.view.inputmethod.EditorInfo();
                        stale.inputType = editor.getInputType(); stale.imeOptions = editor.getImeOptions();
                        stale.initialSelStart = stale.initialSelEnd = 0;
                        // A real current public IC, but no owned text and no usable
                        // restart snapshot: stale EditorInfo zero is not an anchor.
                        service[0].onStartInput(stale, true);
                        assertSame(connection, service[0].getCurrentInputConnection());
                        assertEquals("One attempted restart snapshot", 1, host.extractionProbeCalls.get());
                        assertFalse("An unavailable empty restart must leave the first actual write unprobed",
                                (Boolean) field(service[0], "hostSelectionWriteStarted"));
                        assertEquals(-1, field(service[0], "lastSelectionStart"));
                        assertEquals(-1, field(service[0], "lastSelectionEnd"));
                        assertNull(field(service[0], "pendingInitialAnchor"));
                        assertEquals("", field(service[0], "appliedComposingText"));
                        assertEquals("", ((TouchSmartHostTextState) field(service[0], "touchHostText")).editableText());
                        assertEquals(0, ((OwnSelectionTracker) field(service[0], "ownSelections")).pendingCount());
                        host.getIntent().removeExtra("restartExtraction");
                        service[0].onKey("s"); service[0].onKey("u");
                        assertTrue(engine(service[0]).hasComposition());
                        assertEquals("前:", editor.getText().toString());
                        assertEquals("Local phonetic input must not consume the first-write probe", 1, host.extractionProbeCalls.get());
                        assertFalse((Boolean) field(service[0], "hostSelectionWriteStarted"));
                        service[0].onKey("3");
                        assertEquals("The first actual write refreshes the real prefix caret", 2, host.extractionProbeCalls.get());
                        assertEquals("前:你", editor.getText().toString());
                        assertEquals(3, field(service[0], "lastSelectionStart"));
                        assertEquals(3, field(service[0], "lastSelectionEnd"));
                    });
                    // Wait for the application's deliberately held batch to end
                    // and for its genuine own-selection ACK to reach the IME.
                    IntegratedBottomControlsInstrumentedTest.await(() ->
                            ((OwnSelectionTracker) field(service[0], "ownSelections")).pendingCount() == 0
                                    && editor.getText().toString().equals("前:你"));
                    instrumentation.runOnMainSync(() -> {
                        assertEquals(2, host.extractionProbeCalls.get());
                        assertEquals(-1, BaseInputConnection.getComposingSpanStart(editor.getText()));
                        assertTrue("Own ACK must retain the first editable syllable", engine(service[0]).hasComposition());
                        assertEquals("你", engine(service[0]).completedSmartText());
                        assertEquals(1, engine(service[0]).touchSmartEditableCount());
                        assertEquals("你", ((TouchSmartHostTextState) field(service[0], "touchHostText")).editableText());
                        for (char key : "cl3".toCharArray()) service[0].onKey(String.valueOf(key));
                    });
                    IntegratedBottomControlsInstrumentedTest.await(() -> editor.getText().toString().equals("前:你好")
                            && ((OwnSelectionTracker) field(service[0], "ownSelections")).pendingCount() == 0);
                    instrumentation.runOnMainSync(() -> {
                        assertEquals("你好", engine(service[0]).completedSmartText());
                        assertEquals(2, engine(service[0]).touchSmartEditableCount());
                        assertEquals("你好", ((TouchSmartHostTextState) field(service[0], "touchHostText")).editableText());
                        assertEquals("No further query after the accepted current caret", 2, host.extractionProbeCalls.get());
                    });
                    Bundle evidence = new Bundle();
                    evidence.putString("keykey_empty_restart_probe", "behavior=" + behavior
                            + ", restartCalls=1, finalCalls=" + host.extractionProbeCalls.get()
                            + ", actualText=" + editor.getText() + ", editableSyllables=2, sameActivity=true");
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
