package tw.chichi77.keykey.android;

import static org.junit.Assert.*;

import android.accessibilityservice.AccessibilityService;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RectF;
import android.os.Build;
import android.os.SystemClock;
import android.view.InputDevice;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsAnimation;
import android.widget.EditText;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.io.File;
import java.lang.reflect.Field;
import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Real system Back and InputDispatcher touch dismissal share the same hide contract. */
@RunWith(AndroidJUnit4.class)
public final class KeyboardHideLifecycleInstrumentedTest {
    @Test public void systemBackCancelsOnlyPendingTextForEveryMethodAndReopensWithoutReplay() throws Exception {
        exerciseHide(true);
    }

    @Test public void visibleDismissKeyCancelsOnlyPendingTextForEveryMethodAndReopensWithoutReplay() throws Exception {
        exerciseHide(false);
    }

    private static void exerciseHide(boolean systemBack) throws Exception {
        org.junit.Assume.assumeTrue(Build.VERSION.SDK_INT >= 30);
        org.junit.Assume.assumeTrue("Use an owned disposable touch device",
                "true".equals(InstrumentationRegistry.getArguments().getString("keykey.isolatedDevice")));
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        var preferences = CandidateWindowSettings.preferences(context);
        var previous = preferences.getAll();
        String[] keys = {KeyboardSettingsProfile.key(true, ChineseInputMethodSettings.KEY_METHOD), BopomofoCompositionModeSettings.KEY_MODE,
                KeyboardSettingsProfile.key(true, BopomofoCompositionModeSettings.KEY_OMIT_TONE), KeyboardSettingsProfile.key(true, BopomofoKeyboardLayoutSettings.KEY_LAYOUT),
                KeyboardBottomControlsSettings.KEY_ENABLED, KeyboardLayoutProfileSettings.KEY_LAYOUT};
        try {
            for (ChineseInputMethod method : ChineseInputMethod.values()) {
                for (boolean omit : method == ChineseInputMethod.SMART ? new boolean[]{false, true} : new boolean[]{false}) {
                    for (boolean completed : new boolean[]{false, true}) {
                        preferences.edit().putString(keys[0], method.name())
                                .putString(keys[1], BopomofoCompositionModeSettings.valueForMode(BopomofoCompositionMode.SMART))
                                .putBoolean(keys[2], omit).putString(keys[3], BopomofoKeyboardLayout.STANDARD.value)
                                .putBoolean(keys[4], true).putString(keys[5], KeyboardLayoutProfile.ALIGNED.id).commit();
                        Activity host = instrumentation.startActivitySync(new Intent()
                                .setClassName(context, "tw.chichi77.keykey.android.ImeTestActivity")
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
                        ImeShowReadiness showReadiness = systemBack ? null : new ImeShowReadiness(host);
                        try {
                            if (showReadiness != null) showReadiness.installBeforeShow();
                            EditText editor = IntegratedBottomControlsInstrumentedTest.findEditor(host.findViewById(android.R.id.content));
                            assertNotNull(editor);
                            String prefix = completed ? "已確認" : "";
                            instrumentation.runOnMainSync(() -> { editor.setText(prefix); editor.setSelection(editor.length()); });
                            IntegratedBottomControlsInstrumentedTest.showEditorKeyboard(host, context);
                            if (showReadiness != null) showReadiness.observeImeAfterShow();
                            BopomofoImeService[] service = {null};
                            if (completed) {
                                instrumentation.runOnMainSync(() -> {
                                    service[0] = (BopomofoImeService) IntegratedBottomControlsInstrumentedTest.findKeyboard().getContext();
                                    String input = method == ChineseInputMethod.SMART ? "su3cl3"
                                            : method == ChineseInputMethod.TRADITIONAL ? "su3"
                                            : method == ChineseInputMethod.SIMPLEX ? "ab" : "a";
                                    for (char key : input.toCharArray()) service[0].onKey(String.valueOf(key));
                                    if (method != ChineseInputMethod.SMART) {
                                        assertFalse("A complete reading must provide a selectable candidate", engine(service[0]).displayedCandidates().isEmpty());
                                        service[0].onCandidate(0);
                                    }
                                });
                                int completedLength = prefix.length() + (method == ChineseInputMethod.SMART ? 2 : 1);
                                IntegratedBottomControlsInstrumentedTest.await(() -> editor.length() == completedLength
                                        && !editor.getText().toString().matches(".*[㄀-ㄯˊˇˋ˙].*"));
                            }
                            String[] confirmed = {null};
                            instrumentation.runOnMainSync(() -> {
                                confirmed[0] = editor.getText().toString();
                                service[0] = (BopomofoImeService) IntegratedBottomControlsInstrumentedTest.findKeyboard().getContext();
                                service[0].onKey(method.isTable() ? "a" : "s");
                                assertTrue("The hide case must contain an unfinished reading", engine(service[0]).hasComposition());
                            });
                            // A real injected tap uses screen coordinates. Observe actual
                            // frames/insets after showing the view, before measuring its key.
                            if (systemBack) IntegratedBottomControlsInstrumentedTest.awaitStableImeGeometry(host);
                            // Observe actual IME visibility before the user action.
                            IntegratedBottomControlsInstrumentedTest.await(() -> host.getWindow().getDecorView()
                                    .getRootWindowInsets().isVisible(WindowInsets.Type.ime()));
                            if (systemBack) {
                                assertTrue(instrumentation.getUiAutomation().performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK));
                            } else {
                                showReadiness.awaitReady();
                                tapVisibleDismiss();
                            }
                            // Predictive Back changes the requested IME insets before
                            // its exit animation and real hide callbacks have completed.
                            IntegratedBottomControlsInstrumentedTest.await(() -> !host.getWindow().getDecorView()
                                    .getRootWindowInsets().isVisible(WindowInsets.Type.ime())
                                    && !service[0].isInputViewShown()
                                    && !service[0].getWindow().getWindow().getDecorView().isShown());
                            instrumentation.runOnMainSync(() -> {
                                assertEquals(method + "/omit=" + omit + "/completed=" + completed, confirmed[0], editor.getText().toString());
                                // Repeat the public lifecycle callbacks only after the real
                                // system/touch hide, proving cancellation is idempotent.
                                service[0].onFinishInputView(false);
                                service[0].onWindowHidden();
                                service[0].onWindowHidden();
                                assertEquals(confirmed[0], editor.getText().toString());
                                assertFalse(engine(service[0]).hasComposition());
                            });
                            IntegratedBottomControlsInstrumentedTest.showEditorKeyboard(host, context);
                            instrumentation.runOnMainSync(() -> {
                                assertSame(editor, IntegratedBottomControlsInstrumentedTest.findEditor(host.findViewById(android.R.id.content)));
                                assertEquals("Reopen must not replay raw text or old commits", confirmed[0], editor.getText().toString());
                                assertFalse(engine(service[0]).hasComposition());
                            });
                            android.os.Bundle evidence = new android.os.Bundle();
                            evidence.putString("keykey_real_hide", "systemBack=" + systemBack + ", method=" + method
                                    + ", omit=" + omit + ", completed=" + completed + ", confirmed=" + confirmed[0]
                                    + ", repeatedCallbacks=true, reopenedWithoutReplay=true");
                            instrumentation.sendStatus(0, evidence);
                        } finally {
                            try {
                                if (showReadiness != null) showReadiness.close();
                            } finally {
                                instrumentation.runOnMainSync(host::finish);
                            }
                        }
                    }
                }
            }
        } finally {
            var edit = preferences.edit();
            for (String key : keys) {
                edit.remove(key);
                Object value = previous.get(key);
                if (value instanceof String text) edit.putString(key, text);
                else if (value instanceof Boolean enabled) edit.putBoolean(key, enabled);
            }
            edit.commit();
        }
    }

    /** A stable layout can precede the end of the system's IME show animation. */
    private static final class ImeAnimationObserver extends WindowInsetsAnimation.Callback {
        final Set<WindowInsetsAnimation> active = Collections.newSetFromMap(new IdentityHashMap<>());
        long revision;

        ImeAnimationObserver() { super(DISPATCH_MODE_CONTINUE_ON_SUBTREE); }

        private void observe(WindowInsetsAnimation animation) {
            if ((animation.getTypeMask() & WindowInsets.Type.ime()) != 0 && active.add(animation)) revision++;
        }

        @Override public void onPrepare(WindowInsetsAnimation animation) { observe(animation); }
        @Override public WindowInsetsAnimation.Bounds onStart(WindowInsetsAnimation animation,
                WindowInsetsAnimation.Bounds bounds) { observe(animation); return bounds; }
        @Override public WindowInsets onProgress(WindowInsets insets, List<WindowInsetsAnimation> running) {
            for (WindowInsetsAnimation animation : running) observe(animation);
            return insets;
        }
        @Override public void onEnd(WindowInsetsAnimation animation) {
            if ((animation.getTypeMask() & WindowInsets.Type.ime()) != 0) {
                active.remove(animation);
                revision++;
            }
        }
    }

    private static final class ImeShowReadiness implements AutoCloseable {
        final Activity host;
        final View hostDecor;
        final ImeAnimationObserver hostObserver = new ImeAnimationObserver();
        View imeDecor;
        ImeAnimationObserver imeObserver;
        long attachmentRevision;

        ImeShowReadiness(Activity host) { this.host = host; hostDecor = host.getWindow().getDecorView(); }

        void installBeforeShow() {
            InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
                hostDecor.setWindowInsetsAnimationCallback(hostObserver);
                observeCurrentIme();
            });
        }

        void observeImeAfterShow() {
            InstrumentationRegistry.getInstrumentation().runOnMainSync(this::observeCurrentIme);
        }

        private boolean observeCurrentIme() {
            var keyboard = IntegratedBottomControlsInstrumentedTest.findKeyboard();
            if (keyboard == null) return false;
            var service = (BopomofoImeService) keyboard.getContext();
            if (service.getWindow() == null || service.getWindow().getWindow() == null) return false;
            View current = service.getWindow().getWindow().getDecorView();
            if (imeDecor != current) {
                if (imeDecor != null) imeDecor.setWindowInsetsAnimationCallback(null);
                imeDecor = current;
                imeObserver = new ImeAnimationObserver();
                imeDecor.setWindowInsetsAnimationCallback(imeObserver);
                attachmentRevision++;
            }
            return true;
        }

        void awaitReady() throws Exception {
            long deadline = SystemClock.uptimeMillis() + 10000;
            do {
                long[] revision = new long[3];
                IntegratedBottomControlsInstrumentedTest.await(() -> {
                    if (!observeCurrentIme() || !hostObserver.active.isEmpty() || !imeObserver.active.isEmpty()) return false;
                    revision[0] = hostObserver.revision;
                    revision[1] = imeObserver.revision;
                    revision[2] = attachmentRevision;
                    return true;
                });
                IntegratedBottomControlsInstrumentedTest.awaitStableImeGeometry(host);
                boolean[] ready = {false};
                InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> ready[0] = observeCurrentIme()
                        && hostObserver.active.isEmpty() && imeObserver.active.isEmpty()
                        && hostObserver.revision == revision[0] && imeObserver.revision == revision[1]
                        && attachmentRevision == revision[2]);
                if (ready[0]) return;
            } while (SystemClock.uptimeMillis() < deadline);
            fail("IME show animation changed while waiting for stable tap geometry");
        }

        @Override public void close() {
            InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
                hostDecor.setWindowInsetsAnimationCallback(null);
                if (imeDecor != null) imeDecor.setWindowInsetsAnimationCallback(null);
            });
        }
    }

    private static void tapVisibleDismiss() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        float[] center = new float[2];
        instrumentation.runOnMainSync(() -> {
            var view = IntegratedBottomControlsInstrumentedTest.findKeyboard();
            assertTrue(view.isTouchMode());
            RectF[] dismiss = {null};
            view.draw(new Canvas() {
                RectF last;
                @Override public void drawRoundRect(RectF bounds, float rx, float ry, Paint paint) { last = new RectF(bounds); }
                @Override public void drawText(String text, float x, float y, Paint paint) {
                    if ("▼".equals(text)) dismiss[0] = last;
                }
            });
            assertNotNull("The real touch keyboard must expose its dismiss key", dismiss[0]);
            int[] location = new int[2]; view.getLocationOnScreen(location);
            center[0] = location[0] + dismiss[0].centerX();
            center[1] = location[1] + dismiss[0].centerY();
            android.os.Bundle evidence = new android.os.Bundle();
            evidence.putString("keykey_dismiss_tap", "local=" + dismiss[0]
                    + ", screen=" + center[0] + ":" + center[1]
                    + ", view=" + location[0] + ":" + location[1] + ":" + view.getWidth() + ":" + view.getHeight());
            instrumentation.sendStatus(0, evidence);
        });
        long down = SystemClock.uptimeMillis();
        for (int action : new int[]{MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP}) {
            MotionEvent event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, center[0], center[1], 0);
            event.setSource(InputDevice.SOURCE_TOUCHSCREEN);
            try { assertTrue(instrumentation.getUiAutomation().injectInputEvent(event, true)); }
            finally { event.recycle(); }
        }
    }

    @Test public void missingConnectionNormalHideAbandonsPendingOnceWithoutReplayingIntoTheNextInput() throws Exception {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        File model = SharedModelDatabase.install(context);
        File user = new File(context.getCacheDir(), "hide-no-host-" + UUID.randomUUID() + ".db");
        try (HostInputEngine engine = new HostInputEngine(model.getAbsolutePath(), user.getAbsolutePath(),
                ChineseInputMethod.SMART, BopomofoKeyboardLayout.STANDARD,
                ChineseInputMethodSettings.options(context, ChineseInputMethod.SMART), false, true, value -> true)) {
            engine.setHardwareSmartEditing(true);
            instrumentation.runOnMainSync(() -> {
                BopomofoImeService service = new BopomofoImeService();
                setField(service, "engine", engine);
                service.onUpdateSelection(7, 7, 7, 7, -1, -1);
                assertEquals("An idle same-selection notification supplies a real omitted initial anchor",
                        7, field(service, "lastSelectionStart"));
                engine.handleHardwareCharacter('f');
                assertTrue(engine.hasComposition());
                setField(service, "appliedComposingText", "ㄑ");
                setField(service, "composingRegionStart", 7);
                setField(service, "lastSelectionStart", 8);
                setField(service, "lastSelectionEnd", 8);
                assertNull(service.getCurrentInputConnection());
                service.onFinishInputView(false);
                service.onWindowHidden();
                service.onWindowHidden();
                assertFalse(engine.hasComposition());
                assertEquals("", field(service, "appliedComposingText"));
                assertEquals(-1, field(service, "composingRegionStart"));
                assertEquals(ChineseInputMethod.SMART, engine.chineseInputMethod());
            });
            InputEngine.Result next = engine.handleHardwareCharacter('u');
            assertEquals("A later input must not receive an earlier raw commit", "", next.committedText());
            assertEquals("ㄧ", engine.composingText());
        } finally {
            user.delete(); new File(user + "-wal").delete(); new File(user + "-shm").delete();
        }
    }

    @Test public void delayedUnmarkedInitialNotificationDoesNotResetAnAcceptedFirstReading() throws Exception {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        File model = SharedModelDatabase.install(context);
        File user = new File(context.getCacheDir(), "selection-callback-" + UUID.randomUUID() + ".db");
        try (HostInputEngine engine = new HostInputEngine(model.getAbsolutePath(), user.getAbsolutePath(),
                ChineseInputMethod.SMART, BopomofoKeyboardLayout.STANDARD,
                ChineseInputMethodSettings.options(context, ChineseInputMethod.SMART), false, true, value -> true)) {
            engine.setHardwareSmartEditing(true);
            instrumentation.runOnMainSync(() -> {
                engine.setHardwareSmartEditing(false);
                engine.handleSoftKey("s");
                assertTrue(engine.hasComposition());
                BopomofoImeService initiallyUnknown = new BopomofoImeService();
                setField(initiallyUnknown, "engine", engine);
                initiallyUnknown.onUpdateSelection(-1, -1, 0, 0, -1, -1);
                assertEquals(0, field(initiallyUnknown, "lastSelectionStart"));
                assertTrue("A first real baseline must preserve local-only pending phonetics", engine.hasComposition());
                assertEquals("", field(initiallyUnknown, "appliedComposingText"));
                initiallyUnknown.onUpdateSelection(0, 0, 2, 2, -1, -1);
                assertFalse("A valid reported external movement is not an initialization", engine.hasComposition());
                engine.setHardwareSmartEditing(true);
                for (int[] move : new int[][]{{0, 0, 0, 0}, {2, 2, 1, 1}}) {
                engine.reset();
                BopomofoImeService service = new BopomofoImeService();
                setField(service, "engine", engine);
                setField(service, "lastSelectionStart", 0);
                setField(service, "lastSelectionEnd", 0);
                EditText host = new EditText(context);
                android.view.inputmethod.BaseInputConnection connection = new android.view.inputmethod.BaseInputConnection(host, true) {
                    @Override public android.text.Editable getEditable() { return host.getText(); }
                };
                engine.handleHardwareCharacter('f');
                try {
                    var write = BopomofoImeService.class.getDeclaredMethod("setOwnComposingText",
                            android.view.inputmethod.InputConnection.class, String.class);
                    write.setAccessible(true);
                    assertEquals(true, write.invoke(service, connection, "ㄑ"));
                } catch (ReflectiveOperationException error) { throw new AssertionError(error); }
                assertEquals("ㄑ", host.getText().toString());
                assertEquals(1, field(service, "lastSelectionStart"));
                setField(service, "pendingInitialAnchor", new OwnSelectionTracker.Anchor(0, 0));
                service.onUpdateSelection(-1, -1, 0, 0, -1, -1);
                assertTrue("A late startup notification must not rewind the snapshot's newer accepted write", engine.hasComposition());
                assertEquals(1, field(service, "lastSelectionStart"));
                assertNull(field(service, "pendingInitialAnchor"));
                service.onUpdateSelection(0, 0, 0, 0, -1, -1);
                assertTrue("A delayed unmarked old==new notification is not an external move", engine.hasComposition());
                assertEquals(1, field(service, "lastSelectionStart"));
                assertEquals(0, field(service, "composingRegionStart"));
                service.onUpdateSelection(0, 0, 1, 1, 0, 1); // actual own marked ACK
                assertTrue(engine.hasComposition());
                service.onUpdateSelection(move[0], move[1], move[2], move[3], 0, 1);
                assertFalse("A real current-span cursor or reported move back to an ACKed caret must still be processed", engine.hasComposition());
                }
            });
        } finally {
            user.delete(); new File(user + "-wal").delete(); new File(user + "-shm").delete();
        }
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
}
