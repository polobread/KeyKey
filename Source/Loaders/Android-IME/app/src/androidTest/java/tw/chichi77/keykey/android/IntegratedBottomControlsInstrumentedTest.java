package tw.chichi77.keykey.android;

import static org.junit.Assert.*;

import android.accessibilityservice.AccessibilityService;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Rect;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.provider.Settings;
import android.view.View;
import android.view.MotionEvent;
import android.view.ViewConfiguration;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.inspector.WindowInspector;
import android.view.inputmethod.InputMethodManager;
import android.widget.EditText;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.function.BooleanSupplier;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.json.JSONObject;

/** Run with KeyKey selected and a second enabled IME on an isolated test device. */
@RunWith(AndroidJUnit4.class)
@android.annotation.TargetApi(30)
public final class IntegratedBottomControlsInstrumentedTest {
    @Test public void persistedIntegrationRestoresContentAndHostHeightAcrossRepeatedToggles() throws Exception {
        org.junit.Assume.assumeTrue(Build.VERSION.SDK_INT >= 30);
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        assertTrue("Select KeyKey on the isolated device before this test", Settings.Secure.getString(
                context.getContentResolver(), Settings.Secure.DEFAULT_INPUT_METHOD).contains(context.getPackageName()));
        var preferences = CandidateWindowSettings.preferences(context);
        Map<String, ?> previous = preferences.getAll();
        String[] keys = {KeyboardBottomControlsSettings.KEY_ENABLED, KeyboardBottomSpaceSettings.KEY_TOUCH_ENABLED,
                KeyboardLayoutProfileSettings.KEY_LAYOUT, KeyboardLayoutProfileSettings.KEY_FONT_LEVEL,
                KeyboardLayoutProfileSettings.KEY_DELETE_POSITION, KeyboardLayoutProfileSettings.KEY_SPACING,
                KeyboardSizeSettings.KEY_PORTRAIT_PERCENT, KeyboardSizeSettings.KEY_LANDSCAPE_PERCENT};
        Activity activity = null;
        var phases = new ArrayList<HeightSnapshot>();
        try {
            preferences.edit().putBoolean(keys[0], true).putBoolean(keys[1], true)
                    .putString(keys[2], KeyboardLayoutProfile.ALIGNED.id)
                    .putString(keys[3], KeyboardLayoutProfile.FontSize.LARGE.id)
                    .putString(keys[4], KeyboardLayoutProfile.DeletePosition.ABOVE_ENTER.id)
                    .putString(keys[5], KeyboardLayoutProfile.KeycapArea.SMALL.id)
                    .putInt(keys[6], KeyboardSizeSettings.DEFAULT_PERCENT)
                    .putInt(keys[7], KeyboardSizeSettings.DEFAULT_PERCENT).commit();
            activity = instrumentation.startActivitySync(new Intent()
                    .setClassName(context, "tw.chichi77.keykey.android.ImeTestActivity")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            Activity host = activity;
            showEditorKeyboard(host, context);
            for (boolean integrated : new boolean[] {true, false, true, false}) {
                instrumentation.runOnMainSync(() -> KeyboardBottomControlsSettings.setEnabled(context, integrated));
                await(() -> labels(findKeyboard()).contains("▼") == integrated);
                instrumentation.waitForIdleSync();
                Thread.sleep(300);
                instrumentation.runOnMainSync(() -> {
                    HeightSnapshot snapshot = captureHeight(host, integrated);
                    phases.add(snapshot);
                    Bundle evidence = new Bundle();
                    evidence.putString("keykey_integration_height", snapshot.json.toString());
                    instrumentation.sendStatus(0, evidence);
                });
            }
            float density = context.getResources().getDisplayMetrics().density;
            int reserve = Math.round(40 * density);
            for (int index = 0; index < phases.size(); index++) {
                HeightSnapshot phase = phases.get(index);
                assertEquals("Toggling must preserve the painted keyboard content", phases.get(0).contentBottom,
                        phase.contentBottom, 1f);
                assertEquals("The IME view must restore only its saved bottom reservation",
                        phases.get(0).viewHeight + (index % 2 == 1 ? reserve : 0), phase.viewHeight);
                assertEquals("The application must observe the real IME window's height",
                        phase.imeWindowHeight, phase.appImeBottom);
            }
            assertEquals(phases.get(0).appImeBottom, phases.get(2).appImeBottom);
            assertEquals(phases.get(1).appImeBottom, phases.get(3).appImeBottom);
            assertTrue("Disabling integration must return the reserved height to the IME, not shrink its keys",
                    phases.get(1).appImeBottom >= phases.get(0).appImeBottom + reserve);
        } finally {
            var editor = preferences.edit();
            for (String key : keys) {
                editor.remove(key);
                if (previous.get(key) instanceof Boolean value) editor.putBoolean(key, value);
                else if (previous.get(key) instanceof String value) editor.putString(key, value);
                else if (previous.get(key) instanceof Integer value) editor.putInt(key, value);
            }
            editor.commit();
            if (activity != null) {
                Activity host = activity;
                instrumentation.runOnMainSync(host::finish);
            }
        }
    }

    private record HeightSnapshot(int viewHeight, float contentBottom, int imeWindowHeight,
            int appImeBottom, JSONObject json) {}

    private static HeightSnapshot captureHeight(Activity host, boolean integrated) {
        var view = findKeyboard();
        float[] contentBottom = {0};
        view.draw(new Canvas() {
            @Override public void drawRoundRect(RectF bounds, float rx, float ry, Paint paint) {
                contentBottom[0] = Math.max(contentBottom[0], bounds.bottom);
            }
        });
        View imeDecor = ((BopomofoImeService) view.getContext()).getWindow().getWindow().getDecorView();
        View appDecor = host.getWindow().getDecorView();
        Rect visible = new Rect(); appDecor.getWindowVisibleDisplayFrame(visible);
        int[] viewLocation = new int[2]; view.getLocationOnScreen(viewLocation);
        var appInsets = appDecor.getRootWindowInsets();
        var imeInsets = view.getRootWindowInsets();
        int appImeBottom = appInsets.getInsets(WindowInsets.Type.ime()).bottom;
        JSONObject evidence = new JSONObject(Map.ofEntries(
                Map.entry("integrated", integrated), Map.entry("viewHeight", view.getHeight()),
                Map.entry("contentBottom", contentBottom[0]), Map.entry("viewScreenY", viewLocation[1]),
                Map.entry("imeWindowHeight", imeDecor.getHeight()), Map.entry("imeWindowPaddingBottom", imeDecor.getPaddingBottom()),
                Map.entry("appImeBottom", appImeBottom), Map.entry("appWindowHeight", appDecor.getHeight()),
                Map.entry("appVisibleFrame", visible.toShortString()),
                Map.entry("currentWindowBounds", view.getContext().getSystemService(android.view.WindowManager.class)
                        .getCurrentWindowMetrics().getBounds().toShortString()),
                Map.entry("captionVisible", Build.VERSION.SDK_INT >= 36 && imeInsets.isVisible(WindowInsets.Type.captionBar())),
                Map.entry("captionBottom", imeInsets.getInsets(WindowInsets.Type.captionBar()).bottom),
                Map.entry("navigationBottom", imeInsets.getInsets(WindowInsets.Type.navigationBars()).bottom)));
        return new HeightSnapshot(view.getHeight(), contentBottom[0], imeDecor.getHeight(), appImeBottom, evidence);
    }

    @Test public void liveImePreservesPendingTextAndRestoresCaption() throws Exception {
        org.junit.Assume.assumeTrue(Build.VERSION.SDK_INT >= 30);
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        var preferences = CandidateWindowSettings.preferences(context);
        Map<String, ?> previous = preferences.getAll();
        String[] keys = {KeyboardBottomControlsSettings.KEY_ENABLED, KeyboardBottomSpaceSettings.KEY_TOUCH_ENABLED};
        String selected = Settings.Secure.getString(context.getContentResolver(), Settings.Secure.DEFAULT_INPUT_METHOD);
        assertTrue("Select KeyKey on the isolated device before this test", selected.contains(context.getPackageName()));
        assertTrue("Enable a second IME to verify real switching", context.getSystemService(InputMethodManager.class)
                .getEnabledInputMethodList().size() > 1);
        Activity activity = null;
        WindowInsetsController[] observedController = {null};
        int[] controllable = {0};
        WindowInsetsController.OnControllableInsetsChangedListener observer = (controller, types) -> controllable[0] = types;
        try {
            preferences.edit().putBoolean(keys[0], false).putBoolean(keys[1], true).commit();
            activity = instrumentation.startActivitySync(new Intent()
                    .setClassName(context, "tw.chichi77.keykey.android.ImeTestActivity")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            Activity host = activity;
            showEditorKeyboard(host, context);
            int[] originalHeight = {0}; boolean[] captionBefore = {false};
            List<String> pending = new ArrayList<>(); String[] fieldBefore = {""};
            instrumentation.runOnMainSync(() -> {
                BopomofoKeyboardView view = findKeyboard();
                originalHeight[0] = view.getHeight();
                BopomofoImeService service = (BopomofoImeService) view.getContext();
                service.onKey("s");
                pending.addAll(stripLabels(view));
                fieldBefore[0] = findEditor(host.findViewById(android.R.id.content)).getText().toString();
                assertTrue("The test must start with an unfinished reading", pending.contains("ㄋ"));
                if (Build.VERSION.SDK_INT >= 36) {
                    observedController[0] = view.getWindowInsetsController();
                    assertNotNull(observedController[0]);
                    observedController[0].addOnControllableInsetsChangedListener(observer);
                    captionBefore[0] = view.getRootWindowInsets().isVisible(WindowInsets.Type.captionBar());
                }
                KeyboardBottomControlsSettings.setEnabled(context, true);
            });
            int reservation = Math.round(40 * context.getResources().getDisplayMetrics().density);
            await(() -> findKeyboard() != null && findKeyboard().getHeight() == originalHeight[0] - reservation);
            boolean canHide = Build.VERSION.SDK_INT >= 36 && captionBefore[0]
                    && brieflyAwait(() -> !findKeyboard().getRootWindowInsets().isVisible(WindowInsets.Type.captionBar()));
            instrumentation.runOnMainSync(() -> {
                BopomofoKeyboardView view = findKeyboard();
                assertEquals(pending, stripLabels(view));
                assertEquals(fieldBefore[0], findEditor(host.findViewById(android.R.id.content)).getText().toString());
                assertTrue(labels(view).contains("▼"));
                if (canHide) assertTrue("A real hidden caption must delegate an accessible switcher", labels(view).contains("🌐"));
                Bundle captionEvidence = new Bundle();
                captionEvidence.putString("keykey_caption_phase", "api=" + Build.VERSION.SDK_INT
                        + ", initiallyVisible=" + captionBefore[0] + ", controllable=" + controllable[0]
                        + ", nowVisible=" + (Build.VERSION.SDK_INT >= 36
                                && view.getRootWindowInsets().isVisible(WindowInsets.Type.captionBar()))
                        + ", callbackGlobeVisible=" + labels(view).contains("🌐"));
                instrumentation.sendStatus(0, captionEvidence);
            });
            longPressSettings();
            // The API37 picker is visually present but can be omitted from the
            // accessibility window tree. Cancel through the public global action;
            // the still-visible keyboard and unchanged reading verify the result.
            instrumentation.waitForIdleSync();
            Thread.sleep(350);
            assertTrue(instrumentation.getUiAutomation().performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK));
            await(() -> findKeyboard() != null && findKeyboard().isShown());
            instrumentation.runOnMainSync(() -> {
                assertEquals("Cancelling the picker must preserve the reading", pending, stripLabels(findKeyboard()));
                assertEquals(fieldBefore[0], findEditor(host.findViewById(android.R.id.content)).getText().toString());
                KeyboardBottomControlsSettings.setEnabled(context, false);
            });
            await(() -> findKeyboard() != null && findKeyboard().getHeight() == originalHeight[0]);
            if (canHide) {
                await(() -> findKeyboard().getRootWindowInsets().isVisible(WindowInsets.Type.captionBar()));
                await(() -> !labels(findKeyboard()).contains("🌐"));
            }
            longPressSettings();
            instrumentation.waitForIdleSync();
            Thread.sleep(350);
            assertTrue(instrumentation.getUiAutomation().performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK));
            await(() -> findKeyboard() != null && findKeyboard().isShown());
            instrumentation.runOnMainSync(() -> {
                assertTrue(KeyboardBottomSpaceSettings.touchEnabled(context));
                assertEquals(pending, stripLabels(findKeyboard()));
                assertEquals(fieldBefore[0], findEditor(host.findViewById(android.R.id.content)).getText().toString());
                assertEquals("Long pressing Settings must not switch the selected IME", selected,
                        Settings.Secure.getString(context.getContentResolver(), Settings.Secure.DEFAULT_INPUT_METHOD));
                KeyboardBottomControlsSettings.setEnabled(context, true);
                // Keep platform visibility/switching coverage independent from
                // the separately tested unfinished-reading handoff contract.
                ((BopomofoImeService) findKeyboard().getContext()).onKey("BACKSPACE");
                assertFalse(stripLabels(findKeyboard()).contains("ㄋ"));
                ((BopomofoImeService) findKeyboard().getContext()).onKey("DISMISS");
            });
            await(() -> {
                var insets = host.getWindow().getDecorView().getRootWindowInsets();
                return insets != null && !insets.isVisible(WindowInsets.Type.ime());
            });
            instrumentation.runOnMainSync(() -> {
                assertEquals("Dismissal must not insert any new text", fieldBefore[0],
                        findEditor(host.findViewById(android.R.id.content)).getText().toString());
                context.getSystemService(InputMethodManager.class).showSoftInput(
                        findEditor(host.findViewById(android.R.id.content)), InputMethodManager.SHOW_IMPLICIT);
            });
            await(() -> findKeyboard() != null && findKeyboard().isShown());
            if (canHide) {
                await(() -> !findKeyboard().getRootWindowInsets().isVisible(WindowInsets.Type.captionBar()));
                await(() -> labels(findKeyboard()).contains("🌐"));
            }
            Bundle evidence = new Bundle();
            evidence.putString("keykey_bottom_controls", "api=" + Build.VERSION.SDK_INT
                    + ", captionInitiallyVisible=" + captionBefore[0] + ", controllable=" + controllable[0]
                    + ", actualCaptionHideAndRestore=" + canHide + ", callbackOnOffAndReopen=" + canHide
                    + ", settingsLongPressOnOff=true, pickerCancelPreserved=true, dismiss=true, reopened=true");
            instrumentation.sendStatus(0, evidence);
        } finally {
            if (Build.VERSION.SDK_INT >= 36 && observedController[0] != null) {
                instrumentation.runOnMainSync(() -> observedController[0].removeOnControllableInsetsChangedListener(observer));
            }
            var editor = preferences.edit();
            for (String key : keys) {
                editor.remove(key);
                if (previous.get(key) instanceof Boolean value) editor.putBoolean(key, value);
            }
            editor.commit();
            if (activity != null) {
                Activity host = activity;
                instrumentation.runOnMainSync(host::finish);
            }
        }
    }

    @Test public void unfinishedReadingIsCancelledWhenDismissingTheKeyboard() throws Exception {
        org.junit.Assume.assumeTrue(Build.VERSION.SDK_INT >= 30);
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        String selected = Settings.Secure.getString(context.getContentResolver(), Settings.Secure.DEFAULT_INPUT_METHOD);
        assertTrue("Select KeyKey on the isolated device before this test", selected.contains(context.getPackageName()));
        Activity activity = instrumentation.startActivitySync(new Intent()
                .setClassName(context, "tw.chichi77.keykey.android.ImeTestActivity")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        try {
            showEditorKeyboard(activity, context);
            instrumentation.runOnMainSync(() -> {
                BopomofoImeService service = (BopomofoImeService) findKeyboard().getContext();
                service.onKey("s");
                assertTrue(stripLabels(findKeyboard()).contains("ㄋ"));
                service.onKey("DISMISS");
            });
            await(() -> !activity.getWindow().getDecorView().getRootWindowInsets().isVisible(WindowInsets.Type.ime()));
            instrumentation.runOnMainSync(() -> assertEquals("Unfinished reading must not be inserted on dismissal", "",
                    findEditor(activity.findViewById(android.R.id.content)).getText().toString()));
        } finally {
            instrumentation.runOnMainSync(activity::finish);
        }
    }

    @Test public void explicitHideKeepsConfirmedPrefixAndOnlyCompletedTextForEveryMethod() throws Exception {
        org.junit.Assume.assumeTrue(Build.VERSION.SDK_INT >= 30);
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        var preferences = CandidateWindowSettings.preferences(context);
        var previous = preferences.getAll();
        String[] keys = {ChineseInputMethodSettings.KEY_METHOD, BopomofoCompositionModeSettings.KEY_MODE};
        try {
            for (var method : ChineseInputMethod.values()) {
                instrumentation.runOnMainSync(() -> ChineseInputMethodSettings.setMethod(context, method));
                Activity activity = instrumentation.startActivitySync(new Intent()
                        .setClassName(context, "tw.chichi77.keykey.android.ImeTestActivity")
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
                try {
                    instrumentation.runOnMainSync(() -> {
                        EditText editor = findEditor(activity.findViewById(android.R.id.content));
                        editor.setText("已確認"); editor.setSelection(editor.length());
                    });
                    showEditorKeyboard(activity, context);
                    BopomofoImeService[] service = {null};
                    instrumentation.runOnMainSync(() -> {
                        service[0] = (BopomofoImeService) findKeyboard().getContext();
                        String input = method == ChineseInputMethod.SMART ? "su3cl3su"
                                : method == ChineseInputMethod.TRADITIONAL ? "su" : "a";
                        for (char key : input.toCharArray()) service[0].onKey(String.valueOf(key));
                        service[0].onKey("DISMISS");
                    });
                    await(() -> !activity.getWindow().getDecorView().getRootWindowInsets().isVisible(WindowInsets.Type.ime()));
                    instrumentation.runOnMainSync(() -> {
                        service[0].onKey("DISMISS");
                        assertEquals(method.name() + ": cancellation must preserve confirmed text and not replay on repeated hide",
                                "已確認" + (method == ChineseInputMethod.SMART ? "你好" : ""),
                                findEditor(activity.findViewById(android.R.id.content)).getText().toString());
                    });
                } finally {
                    instrumentation.runOnMainSync(activity::finish);
                }
            }
        } finally {
            var edit = preferences.edit();
            for (String key : keys) {
                edit.remove(key);
                if (previous.get(key) instanceof String value) edit.putString(key, value);
            }
            edit.commit();
        }
    }

    static void showEditorKeyboard(Activity activity, Context context) throws Exception {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        InputMethodManager manager = context.getSystemService(InputMethodManager.class);
        EditText[] editor = {null};
        await(activity::hasWindowFocus);
        instrumentation.runOnMainSync(() -> {
            editor[0] = findEditor(activity.findViewById(android.R.id.content));
            assertNotNull(editor[0]); editor[0].requestFocus();
        });
        // showSoftInput only serves the active editor; window focus alone is
        // insufficient when instrumentation has just restarted the IME process.
        await(() -> manager.isActive(editor[0]));
        instrumentation.runOnMainSync(() -> manager.showSoftInput(editor[0], InputMethodManager.SHOW_IMPLICIT));
        await(() -> findKeyboard() != null && findKeyboard().isShown() && findKeyboard().getHeight() > 0);
    }

    static void await(BooleanSupplier condition) throws Exception {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        long deadline = SystemClock.uptimeMillis() + 10000;
        boolean[] matches = {false};
        while (SystemClock.uptimeMillis() < deadline) {
            instrumentation.runOnMainSync(() -> matches[0] = condition.getAsBoolean());
            if (matches[0]) return;
            Thread.sleep(100);
        }
        fail("Timed out waiting for the requested IME state");
    }

    private static boolean brieflyAwait(BooleanSupplier condition) throws Exception {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        long deadline = SystemClock.uptimeMillis() + 2000;
        boolean[] matches = {false};
        while (SystemClock.uptimeMillis() < deadline) {
            instrumentation.runOnMainSync(() -> matches[0] = condition.getAsBoolean());
            if (matches[0]) return true;
            Thread.sleep(100);
        }
        return false;
    }

    static BopomofoKeyboardView findKeyboard() {
        for (View root : WindowInspector.getGlobalWindowViews()) {
            BopomofoKeyboardView found = findKeyboard(root);
            if (found != null && found.isAttachedToWindow()) return found;
        }
        return null;
    }

    private static BopomofoKeyboardView findKeyboard(View root) {
        if (root instanceof BopomofoKeyboardView view) return view;
        if (root instanceof ViewGroup group) for (int index = 0; index < group.getChildCount(); index++) {
            BopomofoKeyboardView view = findKeyboard(group.getChildAt(index));
            if (view != null) return view;
        }
        return null;
    }

    static EditText findEditor(View root) {
        if (root instanceof EditText editor) return editor;
        if (root instanceof ViewGroup group) for (int index = 0; index < group.getChildCount(); index++) {
            EditText editor = findEditor(group.getChildAt(index));
            if (editor != null) return editor;
        }
        return null;
    }

    private static List<String> labels(BopomofoKeyboardView view) { return capturedLabels(view, false); }
    private static void longPressSettings() throws Exception {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        RectF[] settings = {null};
        instrumentation.runOnMainSync(() -> {
            var view = findKeyboard();
            view.draw(new Canvas() {
                RectF lastKey;
                @Override public void drawRoundRect(RectF bounds, float rx, float ry, Paint paint) {
                    lastKey = new RectF(bounds);
                }
                @Override public void drawText(String value, float x, float y, Paint paint) {
                    if (value.equals("設")) settings[0] = lastKey;
                }
            });
            assertNotNull("The live touch keyboard must provide Settings", settings[0]);
            sendSettingsTouch(view, MotionEvent.ACTION_DOWN, settings[0]);
        });
        Thread.sleep(ViewConfiguration.getLongPressTimeout() + 150L);
        instrumentation.runOnMainSync(() -> sendSettingsTouch(findKeyboard(), MotionEvent.ACTION_UP, settings[0]));
    }

    private static void sendSettingsTouch(View view, int action, RectF key) {
        long time = SystemClock.uptimeMillis();
        MotionEvent event = MotionEvent.obtain(time, time, action, key.centerX(), key.centerY(), 0);
        try { view.onTouchEvent(event); } finally { event.recycle(); }
    }

    private static List<String> stripLabels(BopomofoKeyboardView view) { return capturedLabels(view, true); }
    private static List<String> capturedLabels(BopomofoKeyboardView view, boolean stripOnly) {
        var labels = new ArrayList<String>();
        view.draw(new Canvas() {
            int keys;
            @Override public void drawRoundRect(RectF bounds, float rx, float ry, Paint paint) { keys++; }
            @Override public void drawText(String value, float x, float y, Paint paint) {
                if (!stripOnly || keys <= view.compositionCellCount()) labels.add(value);
            }
        });
        return labels;
    }
}
