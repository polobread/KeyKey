package tw.chichi77.keykey.android;

import static org.junit.Assert.*;

import android.app.Instrumentation;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.inputmethod.BaseInputConnection;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.view.inputmethod.InputConnectionWrapper;
import android.widget.EditText;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.io.File;
import java.io.FileOutputStream;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.function.Supplier;
import org.junit.After;
import org.junit.Before;
import org.junit.Rule;
import org.junit.rules.TestName;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Focused real Rust/EditText contracts; never run against a user's device. */
@RunWith(AndroidJUnit4.class)
public final class HostTransactionSafetyInstrumentedTest {
    @Rule public final TestName testName = new TestName();
    private final Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
    private final Context context = instrumentation.getTargetContext();
    private final Set<String> changedSettings = new LinkedHashSet<>();
    private SharedPreferences preferences;
    private Map<String, ?> previous;
    private ImeTestActivity host;
    private EditText editor;

    @Before public void requireIsolatedDevice() {
        org.junit.Assume.assumeTrue(Build.VERSION.SDK_INT >= 30);
        org.junit.Assume.assumeTrue("Run only on an owned disposable device",
                "true".equals(InstrumentationRegistry.getArguments().getString("keykey.isolatedDevice")));
        preferences = KeyboardSettingsProfile.preferences(context);
        previous = preferences.getAll();
        main(() -> {
            var edit = preferences.edit();
            for (boolean virtual : new boolean[]{true, false}) {
                put(edit, KeyboardSettingsProfile.key(virtual, ChineseInputMethodSettings.KEY_METHOD), ChineseInputMethod.SMART.name());
                put(edit, KeyboardSettingsProfile.key(virtual, BopomofoKeyboardLayoutSettings.KEY_LAYOUT), BopomofoKeyboardLayout.STANDARD.value);
                put(edit, KeyboardSettingsProfile.key(virtual, BopomofoCompositionModeSettings.KEY_OMIT_TONE), false);
                put(edit, KeyboardSettingsProfile.key(virtual, BopomofoCompositionModeSettings.KEY_SPACE_SELECTS_CANDIDATES), false);
                put(edit, KeyboardSettingsProfile.key(virtual, ChineseInputMethodSettings.KEY_SIMPLIFIED_CHINESE_OUTPUT), false);
            }
            put(edit, CandidateWindowSettings.KEY_FLOATING_ENABLED, false);
            put(edit, CandidateWindowSettings.KEY_SMART_TWO_ROWS, false);
            edit.commit();
            return true;
        });
    }

    @After public void restoreHostAndPreferences() {
        if (host != null) {
            captureHostIfAvailable();
            main(() -> { host.finish(); return true; });
        }
        if (previous == null) return;
        main(() -> {
            var edit = preferences.edit();
            for (String key : changedSettings) {
                edit.remove(key);
                Object value = previous.get(key);
                if (value instanceof String text) edit.putString(key, text);
                else if (value instanceof Boolean enabled) edit.putBoolean(key, enabled);
            }
            edit.commit();
            return true;
        });
    }

    @Test public void rejectedCommitStopsBeforeReplacingTheRemainingComposition() throws Exception {
        launchHost("", false);
        File user = new File(context.getCacheDir(), "host-rejection-" + UUID.randomUUID() + ".db");
        BopomofoImeService[] fixture = {null};
        try {
            main(() -> {
                try (HostInputEngine engine = new HostInputEngine(SharedModelDatabase.install(context).getAbsolutePath(),
                        user.getAbsolutePath(), ChineseInputMethod.SMART, BopomofoKeyboardLayout.STANDARD,
                        new TableInputOptions(ChineseInputMethod.SMART), false, true, text -> true)) {
                    engine.setHardwareSmartEditing(true);
                    BopomofoImeService service = new BopomofoImeService();
                    fixture[0] = service;
                    setField(service, "engine", engine);
                    setField(service, "lastSelectionStart", 0);
                    setField(service, "lastSelectionEnd", 0);
                    setField(service, "hostSelectionWriteStarted", true);
                    InputConnection local = editor.onCreateInputConnection(new EditorInfo());
                    assertNotNull("A real EditText public IC is required", local);
                    RejectingCommitConnection connection = new RejectingCommitConnection(local);
                    for (int syllable = 0; syllable < 10; syllable++) {
                        for (char key : "su3".toCharArray()) applyAccepted(service, engine, connection, engine.handleHardwareCharacter(key));
                    }
                    assertEquals("Ten completed syllables stay in the desktop marked range", "你".repeat(10), editor.getText().toString());
                    assertEquals(0, BaseInputConnection.getComposingSpanStart(editor.getText()));
                    for (char key : "su".toCharArray()) applyAccepted(service, engine, connection, engine.handleHardwareCharacter(key));
                    String before = editor.getText().toString();
                    int oldSelection = editor.getSelectionStart();
                    int oldMarkedEnd = BaseInputConnection.getComposingSpanEnd(editor.getText());
                    InputEngine.Result overflow = engine.handleHardwareCharacter('3');
                    assertFalse("The eleventh syllable must really evict a nonempty prefix", overflow.committedText().isEmpty());
                    assertTrue("The same result must retain an editable suffix", engine.hasComposition());
                    assertFalse(engine.composingText().isEmpty());
                    connection.rejectNextCommit = true;
                    int composingCalls = connection.composingCalls;
                    int selectionCalls = connection.selectionCalls;
                    assertFalse("A false host result must fail the real product transaction", applyToConnection(service, connection, overflow));
                    assertEquals(1, connection.rejectedCommits);
                    assertEquals("No suffix replacement may follow a rejected prefix commit", composingCalls, connection.composingCalls);
                    assertEquals("No caret positioning may follow a rejected prefix commit", selectionCalls, connection.selectionCalls);
                    assertEquals("The host keeps the entire pre-transaction marked text", before, editor.getText().toString());
                    assertEquals(oldSelection, editor.getSelectionStart());
                    assertEquals(oldMarkedEnd, BaseInputConnection.getComposingSpanEnd(editor.getText()));
                    assertTrue("The rejected effects are deliberately not acknowledged", (Boolean) field(engine, "pendingHostEffects"));
                    String retained = engine.composingText();
                    assertTrue("Pending effects block a later core key", engine.handleHardwareCharacter('c').committedText().isEmpty());
                    assertEquals(retained, engine.composingText());
                    evidence("same-process-public-IC", "rejectedPrefix=" + overflow.committedText()
                            + ", unchangedHost=" + before + ", noSuffixWrite=true, pendingEffects=true");
                } catch (Exception error) { throw new AssertionError(error); }
                return true;
            });
        } finally {
            if (fixture[0] != null) main(() -> {
                ((ExecutorService) field(fixture[0], "cursorAnchorRequests")).shutdownNow();
                ((ExecutorService) field(fixture[0], "dictionaryLoader")).shutdownNow();
                return true;
            });
            for (String suffix : new String[]{"", "-wal", "-shm"}) new File(user.getPath() + suffix).delete();
        }
    }

    @Test public void removedComposingSpanAndRealHostCaretMoveDoNotReplayOldComposition() throws Exception {
        InputDevice keyboard = null;
        for (int id : InputDevice.getDeviceIds()) {
            InputDevice device = InputDevice.getDevice(id);
            if (device != null && !device.isVirtual() && device.getKeyboardType() == InputDevice.KEYBOARD_TYPE_ALPHABETIC) {
                keyboard = device; break;
            }
        }
        assertNotNull("Enable the disposable emulator's hardware keyboard", keyboard);
        launchHost("前:後", true);
        BopomofoImeService service = main(() -> (BopomofoImeService) IntegratedBottomControlsInstrumentedTest.findKeyboard().getContext());
        typeHardware(keyboard, "su3cl3");
        IntegratedBottomControlsInstrumentedTest.await(() -> editor.getText().toString().equals("前:你好後")
                && BaseInputConnection.getComposingSpanStart(editor.getText()) == 2
                && ((OwnSelectionTracker) field(service, "ownSelections")).pendingCount() == 0);
        main(() -> {
            assertFalse("This case must use real desktop marked composition", engine(service).isTouchSmartComposition());
            assertTrue(engine(service).hasComposition());
            // Genuine TextView/IMM callback: do not fabricate onUpdateSelection.
            BaseInputConnection.removeComposingSpans(editor.getText());
            editor.setSelection(0);
            return true;
        });
        IntegratedBottomControlsInstrumentedTest.await(() -> !engine(service).hasComposition());
        main(() -> {
            assertEquals("The removed old range already exists in host text; never insert it again at the new caret",
                    "前:你好後", editor.getText().toString());
            assertEquals(0, editor.getSelectionStart());
            assertEquals(-1, BaseInputConnection.getComposingSpanStart(editor.getText()));
            return true;
        });
        typeHardware(keyboard, "cl3");
        IntegratedBottomControlsInstrumentedTest.await(() -> editor.getText().toString().equals("好前:你好後"));
        main(() -> {
            assertEquals("好", engine(service).completedSmartText());
            assertTrue(engine(service).hasComposition());
            evidence("live-IMM-external-selection", "oldHost=前:你好後, caret=0, nextHost=" + editor.getText());
            return true;
        });
    }

    private void captureHostIfAvailable() {
        // Optional evidence is captured after the assertions and before teardown;
        // screenshot availability must never decide this input contract's result.
        try {
            instrumentation.waitForIdleSync();
            Bitmap screenshot = instrumentation.getUiAutomation().takeScreenshot();
            if (screenshot == null) return;
            try (FileOutputStream output = new FileOutputStream(new File(context.getCacheDir(),
                    "host-safety-" + testName.getMethodName() + ".png"))) {
                screenshot.compress(Bitmap.CompressFormat.PNG, 100, output);
            } finally { screenshot.recycle(); }
        } catch (Exception unavailable) { /* Evidence is optional. */ }
    }

    private void launchHost(String initial, boolean showLiveIme) throws Exception {
        host = (ImeTestActivity) instrumentation.startActivitySync(new Intent()
                .setClassName(context, context.getPackageName() + ".ImeTestActivity")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK)
                .putExtra("probeInitialText", initial)
                .putExtra("probeSelectionStart", initial.isEmpty() ? 0 : 2)
                .putExtra("probeSelectionEnd", initial.isEmpty() ? 0 : 2));
        editor = main(() -> IntegratedBottomControlsInstrumentedTest.findEditor(host.findViewById(android.R.id.content)));
        if (!showLiveIme) {
            // The rejection contract calls the real product transaction against
            // a same-process public IC. A visible remote IME is not its fixture.
            IntegratedBottomControlsInstrumentedTest.await(host::hasWindowFocus);
            main(() -> { editor.requestFocus(); return true; });
            instrumentation.waitForIdleSync();
            return;
        }
        IntegratedBottomControlsInstrumentedTest.showEditorKeyboard(host, context);
    }

    private void typeHardware(InputDevice keyboard, String text) throws Exception {
        KeyEvent[] events = keyboard.getKeyCharacterMap().getEvents(text.toCharArray());
        assertNotNull(events);
        long downTime = 0;
        for (KeyEvent event : events) {
            long now = SystemClock.uptimeMillis();
            if (event.getAction() == KeyEvent.ACTION_DOWN) downTime = now;
            assertTrue(instrumentation.getUiAutomation().injectInputEvent(new KeyEvent(downTime, now,
                    event.getAction(), event.getKeyCode(), 0, event.getMetaState(), keyboard.getId(), 0, 0,
                    InputDevice.SOURCE_KEYBOARD), true));
            SystemClock.sleep(8);
        }
        instrumentation.waitForIdleSync();
    }

    private static final class RejectingCommitConnection extends InputConnectionWrapper {
        boolean rejectNextCommit;
        int rejectedCommits, composingCalls, selectionCalls;
        RejectingCommitConnection(InputConnection target) { super(target, false); }
        @Override public boolean commitText(CharSequence text, int cursor) {
            if (rejectNextCommit) { rejectNextCommit = false; rejectedCommits++; return false; }
            return super.commitText(text, cursor);
        }
        @Override public boolean setComposingText(CharSequence text, int cursor) {
            composingCalls++; return super.setComposingText(text, cursor);
        }
        @Override public boolean setSelection(int start, int end) {
            selectionCalls++; return super.setSelection(start, end);
        }
    }

    private static void applyAccepted(BopomofoImeService service, HostInputEngine engine,
            InputConnection connection, InputEngine.Result result) {
        assertTrue(applyToConnection(service, connection, result));
        engine.acknowledgeHostEffects();
    }
    private static boolean applyToConnection(BopomofoImeService service, InputConnection connection, InputEngine.Result result) {
        try {
            Method method = BopomofoImeService.class.getDeclaredMethod("applyToConnection", InputConnection.class,
                    InputEngine.Result.class, boolean.class);
            method.setAccessible(true);
            return (Boolean) method.invoke(service, connection, result, false);
        } catch (InvocationTargetException error) { throw new AssertionError(error.getCause()); }
        catch (ReflectiveOperationException error) { throw new AssertionError(error); }
    }
    private void put(SharedPreferences.Editor edit, String key, Object value) {
        changedSettings.add(key);
        if (value instanceof String text) edit.putString(key, text);
        else if (value instanceof Boolean enabled) edit.putBoolean(key, enabled);
    }
    private void evidence(String kind, String detail) {
        Bundle evidence = new Bundle(); evidence.putString("keykey_host_safety", kind + ": " + detail);
        instrumentation.sendStatus(0, evidence);
    }
    private static HostInputEngine engine(BopomofoImeService service) { return (HostInputEngine) field(service, "engine"); }
    private static Object field(Object target, String name) {
        try { Field field = target.getClass().getDeclaredField(name); field.setAccessible(true); return field.get(target); }
        catch (ReflectiveOperationException error) { throw new AssertionError(error); }
    }
    private static void setField(Object target, String name, Object value) {
        try { Field field = target.getClass().getDeclaredField(name); field.setAccessible(true); field.set(target, value); }
        catch (ReflectiveOperationException error) { throw new AssertionError(error); }
    }
    @SuppressWarnings("unchecked") private <T> T main(Supplier<T> operation) {
        Object[] result = {null}; instrumentation.runOnMainSync(() -> result[0] = operation.get()); return (T) result[0];
    }
}
