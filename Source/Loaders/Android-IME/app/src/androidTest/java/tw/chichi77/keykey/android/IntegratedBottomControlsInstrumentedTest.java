package tw.chichi77.keykey.android;

import static org.junit.Assert.*;

import android.accessibilityservice.AccessibilityService;
import android.app.Activity;
import android.app.UiAutomation;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.res.Configuration;
import android.graphics.Canvas;
import android.graphics.Insets;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Rect;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.provider.Settings;
import android.view.InputDevice;
import android.view.View;
import android.view.Surface;
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
        String[] keys = {KeyboardBottomControlsSettings.KEY_ENABLED,
                KeyboardLayoutProfileSettings.KEY_LAYOUT, KeyboardLayoutProfileSettings.KEY_FONT_LEVEL,
                KeyboardLayoutProfileSettings.KEY_DELETE_POSITION, KeyboardLayoutProfileSettings.KEY_SPACING,
                KeyboardSizeSettings.KEY_PORTRAIT_PERCENT, KeyboardSizeSettings.KEY_LANDSCAPE_PERCENT};
        Activity activity = null;
        var phases = new ArrayList<HeightSnapshot>();
        try {
            preferences.edit().putBoolean(keys[0], true)
                    .putString(keys[1], KeyboardLayoutProfile.ALIGNED.id)
                    .putString(keys[2], KeyboardLayoutProfile.FontSize.LARGE.id)
                    .putString(keys[3], KeyboardLayoutProfile.DeletePosition.ABOVE_ENTER.id)
                    .putString(keys[4], KeyboardLayoutProfile.KeycapArea.SMALL.id)
                    .putInt(keys[5], KeyboardSizeSettings.DEFAULT_PERCENT)
                    .putInt(keys[6], KeyboardSizeSettings.DEFAULT_PERCENT).commit();
            activity = instrumentation.startActivitySync(new Intent()
                    .setClassName(context, "tw.chichi77.keykey.android.ImeTestActivity")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
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
            for (int index = 0; index < phases.size(); index++) {
                HeightSnapshot phase = phases.get(index);
                assertEquals("Toggling must preserve the painted keyboard content", phases.get(0).contentBottom,
                        phase.contentBottom, 1f);
                assertEquals("Each setting must settle to the same window height",
                        phases.get(index % 2).viewHeight, phase.viewHeight);
                assertEquals("The application must observe the real IME window's height",
                        phase.imeWindowHeight, phase.appImeBottom);
                assertOnlySystemBottomSpace(phase, density);
            }
            assertEquals(phases.get(0).appImeBottom, phases.get(2).appImeBottom);
            assertEquals(phases.get(1).appImeBottom, phases.get(3).appImeBottom);
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

    private static void assertOnlySystemBottomSpace(HeightSnapshot phase, float density) {
        float extra = phase.imeWindowHeight - (phase.contentBottom + Math.round(2 * density));
        int systemBottom = Math.max(phase.json.optInt("navigationBottom"), phase.json.optInt("captionBottom"));
        assertTrue("The IME may reserve only the visible system bottom area: " + phase.json,
                extra >= -1 && extra <= systemBottom + 1);
    }

    private record HeightSnapshot(int viewHeight, float contentBottom, int imeWindowHeight,
            int appImeBottom, Rect firstCell, JSONObject json) {}

    private static HeightSnapshot captureHeight(Activity host, boolean integrated) {
        var view = findKeyboard();
        float[] contentBottom = {0};
        Rect firstCell = new Rect();
        view.draw(new Canvas() {
            @Override public void drawRoundRect(RectF bounds, float rx, float ry, Paint paint) {
                if (firstCell.isEmpty()) bounds.roundOut(firstCell);
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
        return new HeightSnapshot(view.getHeight(), contentBottom[0], imeDecor.getHeight(), appImeBottom, firstCell, evidence);
    }

    @Test public void liveImePreservesPendingTextAndRestoresCaption() throws Exception {
        org.junit.Assume.assumeTrue(Build.VERSION.SDK_INT >= 30);
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        var preferences = CandidateWindowSettings.preferences(context);
        Map<String, ?> previous = preferences.getAll();
        String key = KeyboardBottomControlsSettings.KEY_ENABLED;
        String selected = Settings.Secure.getString(context.getContentResolver(), Settings.Secure.DEFAULT_INPUT_METHOD);
        assertTrue("Select KeyKey on the isolated device before this test", selected.contains(context.getPackageName()));
        assertTrue("Enable a second IME to verify real switching", context.getSystemService(InputMethodManager.class)
                .getEnabledInputMethodList().size() > 1);
        Activity activity = null;
        WindowInsetsController[] observedController = {null};
        int[] controllable = {0};
        WindowInsetsController.OnControllableInsetsChangedListener observer = (controller, types) -> controllable[0] = types;
        try {
            preferences.edit().putBoolean(key, false).commit();
            activity = instrumentation.startActivitySync(new Intent()
                    .setClassName(context, "tw.chichi77.keykey.android.ImeTestActivity")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
            Activity host = activity;
            showEditorKeyboard(host, context);
            awaitStableImeGeometry(host);
            int[] originalHeight = {0}; boolean[] captionBefore = {false};
            List<String> pending = new ArrayList<>(); String[] fieldBefore = {""};
            instrumentation.runOnMainSync(() -> {
                BopomofoKeyboardView view = findKeyboard();
                originalHeight[0] = view.getHeight();
                Bundle initialGeometry = new Bundle();
                initialGeometry.putString("keykey_caption_initial_geometry", captureHeight(host, false).json.toString());
                instrumentation.sendStatus(0, initialGeometry);
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
            instrumentation.waitForIdleSync();
            Thread.sleep(300);
            boolean canHide = Build.VERSION.SDK_INT >= 36 && captionBefore[0]
                    && brieflyAwait(() -> !findKeyboard().getRootWindowInsets().isVisible(WindowInsets.Type.captionBar()));
            instrumentation.runOnMainSync(() -> {
                BopomofoKeyboardView view = findKeyboard();
                assertEquals(pending, stripLabels(view));
                assertEquals(fieldBefore[0], findEditor(host.findViewById(android.R.id.content)).getText().toString());
                assertTrue(labels(view).contains("▼"));
                if (canHide) assertTrue("A real hidden caption must delegate an accessible switcher", labels(view).contains("🌐"));
                assertOnlySystemBottomSpace(captureHeight(host, true),
                        view.getResources().getDisplayMetrics().density);
                Bundle captionEvidence = new Bundle();
                captionEvidence.putString("keykey_caption_phase", "api=" + Build.VERSION.SDK_INT
                        + ", initiallyVisible=" + captionBefore[0] + ", controllable=" + controllable[0]
                        + ", nowVisible=" + (Build.VERSION.SDK_INT >= 36
                                && view.getRootWindowInsets().isVisible(WindowInsets.Type.captionBar()))
                        + ", callbackGlobeVisible=" + labels(view).contains("🌐"));
                instrumentation.sendStatus(0, captionEvidence);
            });
            longPressSettings();
            // The picker can be omitted from the API37 accessibility tree.
            // Observe the real system window before Back and wait for the host
            // to regain focus; the keyboard may remain shown underneath it.
            cancelInputMethodPicker(host);
            await(() -> findKeyboard() != null && findKeyboard().isShown());
            instrumentation.runOnMainSync(() -> {
                assertEquals("Cancelling the picker must preserve the reading", pending, stripLabels(findKeyboard()));
                assertEquals(fieldBefore[0], findEditor(host.findViewById(android.R.id.content)).getText().toString());
                KeyboardBottomControlsSettings.setEnabled(context, false);
            });
            try {
                await(() -> findKeyboard() != null && findKeyboard().getHeight() == originalHeight[0]);
            } catch (AssertionError failure) {
                String[] actual = {"no keyboard"};
                instrumentation.runOnMainSync(() -> {
                    if (findKeyboard() != null) actual[0] = captureHeight(host, false).json.toString();
                });
                throw new AssertionError("Original height=" + originalHeight[0] + "; settled actual=" + actual[0], failure);
            }
            if (canHide) {
                await(() -> findKeyboard().getRootWindowInsets().isVisible(WindowInsets.Type.captionBar()));
                await(() -> !labels(findKeyboard()).contains("🌐"));
            }
            longPressSettings();
            cancelInputMethodPicker(host);
            await(() -> findKeyboard() != null && findKeyboard().isShown());
            instrumentation.runOnMainSync(() -> {
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
            var editor = preferences.edit().remove(key);
            if (previous.get(key) instanceof Boolean value) editor.putBoolean(key, value);
            editor.commit();
            if (activity != null) {
                Activity host = activity;
                instrumentation.runOnMainSync(host::finish);
            }
        }
    }

    @Test public void integratedImeKeepsTheSameEditorAndSafeBottomAcrossNativeRotations() throws Exception {
        org.junit.Assume.assumeTrue(Build.VERSION.SDK_INT >= 30);
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        assertTrue(Settings.Secure.getString(context.getContentResolver(),
                Settings.Secure.DEFAULT_INPUT_METHOD).contains(context.getPackageName()));
        var preferences = CandidateWindowSettings.preferences(context);
        Map<String, ?> previous = preferences.getAll();
        String[] keys = {KeyboardBottomControlsSettings.KEY_ENABLED,
                KeyboardLayoutProfileSettings.KEY_LAYOUT, KeyboardSizeSettings.KEY_PORTRAIT_PERCENT,
                KeyboardSizeSettings.KEY_LANDSCAPE_PERCENT, KeyboardLayoutProfileSettings.KEY_SPACING,
                ChineseInputMethodSettings.KEY_METHOD, BopomofoCompositionModeSettings.KEY_MODE,
                BopomofoKeyboardLayoutSettings.KEY_LAYOUT};
        Activity activity = null;
        int originalRotation = Surface.ROTATION_0;
        boolean originalAutoRotate = Settings.System.getInt(context.getContentResolver(),
                Settings.System.ACCELEROMETER_ROTATION, 1) != 0;
        try {
            preferences.edit().putBoolean(keys[0], true)
                    .putString(keys[1], KeyboardLayoutProfile.ALIGNED.id)
                    .putInt(keys[2], KeyboardSizeSettings.DEFAULT_PERCENT)
                    .putInt(keys[3], KeyboardSizeSettings.DEFAULT_PERCENT)
                    .putString(keys[4], KeyboardLayoutProfile.KeycapArea.SMALL.id)
                    .putString(keys[5], ChineseInputMethod.SMART.name())
                    .putString(keys[6], BopomofoCompositionModeSettings.valueForMode(BopomofoCompositionMode.SMART))
                    .putString(keys[7], BopomofoKeyboardLayout.STANDARD.value).commit();
            activity = instrumentation.startActivitySync(new Intent()
                    .setClassName(context, "tw.chichi77.keykey.android.ImeTestActivity")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
            Activity host = activity;
            originalRotation = host.getDisplay().getRotation();
            EditText editor = findEditor(host.findViewById(android.R.id.content));
            instrumentation.runOnMainSync(() -> editor.setText(""));
            showEditorKeyboard(host, context);
            BopomofoImeService service = (BopomofoImeService) findKeyboard().getContext();
            Object windowToken = findKeyboard().getWindowToken();
            instrumentation.runOnMainSync(() -> {
                for (char key : "su3cl3".toCharArray()) service.onKey(String.valueOf(key));
            });
            await(() -> "你好".equals(editor.getText().toString()));
            var widths = new ArrayList<Integer>();
            android.graphics.Point displaySize = new android.graphics.Point();
            host.getDisplay().getRealSize(displaySize);
            boolean naturalLandscape = (originalRotation == Surface.ROTATION_0
                    || originalRotation == Surface.ROTATION_180)
                    ? displaySize.x > displaySize.y : displaySize.y > displaySize.x;
            int[] rotations = naturalLandscape
                    ? new int[]{Surface.ROTATION_90, Surface.ROTATION_0,
                            Surface.ROTATION_180, Surface.ROTATION_90}
                    : new int[]{Surface.ROTATION_0, Surface.ROTATION_90,
                            Surface.ROTATION_270, Surface.ROTATION_0};
            for (int phaseIndex = 0; phaseIndex < rotations.length; phaseIndex++) {
                int rotation = rotations[phaseIndex];
                boolean reopen = phaseIndex > 0 && phaseIndex != 2;
                if (reopen) {
                    instrumentation.runOnMainSync(() -> service.onKey("DISMISS"));
                    await(() -> !host.getWindow().getDecorView().getRootWindowInsets()
                            .isVisible(WindowInsets.Type.ime()));
                }
                assertTrue(instrumentation.getUiAutomation().setRotation(rotation));
                int orientation = phaseIndex == 0 || phaseIndex == rotations.length - 1
                        ? android.content.res.Configuration.ORIENTATION_PORTRAIT
                        : android.content.res.Configuration.ORIENTATION_LANDSCAPE;
                await(() -> host.getDisplay().getRotation() == rotation
                        && host.getResources().getConfiguration().orientation == orientation
                        && service.getResources().getConfiguration().orientation == orientation);
                if (reopen) showEditorKeyboard(host, context);
                await(() -> findKeyboard() != null && findKeyboard().isShown()
                        && findKeyboard().getRootWindowInsets() != null
                        && host.getWindow().getDecorView().getRootWindowInsets().isVisible(WindowInsets.Type.ime()));
                instrumentation.waitForIdleSync();
                Thread.sleep(300);
                instrumentation.runOnMainSync(() -> {
                    assertFalse(host.isDestroyed());
                    assertSame("Rotation must keep the same text field", editor,
                            findEditor(host.findViewById(android.R.id.content)));
                    assertEquals("Rotation must preserve the host text without replay", "你好", editor.getText().toString());
                    assertSame("Rotation must keep the same IME service", service, findKeyboard().getContext());
                    assertEquals("Rotation must keep the same IME window", windowToken, findKeyboard().getWindowToken());
                    HeightSnapshot phase = captureHeight(host, true);
                    widths.add(findKeyboard().getWidth());
                    Rect viewport = host.getSystemService(android.view.WindowManager.class).getCurrentWindowMetrics().getBounds();
                    assertEquals("The real display axis must change", orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE,
                            viewport.width() > viewport.height());
                    int navBottom = host.getWindow().getDecorView().getRootWindowInsets()
                            .getInsets(WindowInsets.Type.navigationBars()).bottom;
                    int navigationTop = viewport.bottom - navBottom;
                    var keyboard = findKeyboard();
                    int[] location = new int[2];
                    keyboard.getLocationOnScreen(location);
                    Rect visible = new Rect();
                    assertTrue(keyboard.getLocalVisibleRect(visible));
                    assertFalse("The Smart Mandarin composition row must be drawn", phase.firstCell.isEmpty());
                    assertTrue("The full composition cell must be inside the visible keyboard",
                            visible.contains(phase.firstCell));
                    int firstPaintedTop = location[1] + phase.firstCell.top;
                    assertTrue("The composition row must start within the IME area reserved by the host",
                            firstPaintedTop >= viewport.bottom - phase.appImeBottom);
                    float lastPaintedBottom = location[1] + phase.contentBottom;
                    float density = findKeyboard().getResources().getDisplayMetrics().density;
                    int expectedContent = Math.round(KeyboardLayoutProfile.ALIGNED.layout(
                            orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE
                                    ? KeyboardLayoutProfile.Orientation.LANDSCAPE
                                    : KeyboardLayoutProfile.Orientation.PORTRAIT).contentHeightDp * density);
                    int statusTop = host.getWindow().getDecorView().getRootWindowInsets()
                            .getInsets(WindowInsets.Type.statusBars()).top;
                    if (expectedContent + navBottom <= viewport.height() - statusTop) {
                        assertEquals("An ample real viewport must restore the configured keyboard height",
                                expectedContent, phase.contentBottom + Math.round(2 * density), 1f);
                    }
                    JSONObject geometry = new JSONObject(Map.of("geometry", phase.json,
                            "displayRotation", rotation, "hostNavigationTop", navigationTop,
                            "firstCellScreenTop", firstPaintedTop, "lastPaintedScreenBottom", lastPaintedBottom,
                            "reopenedAfterRotation", reopen, "sameEditorAndImeWindow", true));
                    Bundle evidence = new Bundle();
                    evidence.putString("keykey_native_rotation_geometry", geometry.toString());
                    instrumentation.sendStatus(0, evidence);
                    assertEquals("Decor and allocated IME frame must agree after rotation", phase.appImeBottom, phase.imeWindowHeight);
                    assertTrue("The final key row must stay above the system navigation area",
                            lastPaintedBottom <= navigationTop + 1);
                });
            }
            assertNotEquals("The keyboard must really change width across rotation", widths.get(0), widths.get(1));
            instrumentation.runOnMainSync(() -> assertMissingNavigationDispatchKeepsWindowHeight(findKeyboard()));
            instrumentation.waitForIdleSync();

            RectF cellOnScreen = new RectF();
            instrumentation.runOnMainSync(() -> {
                var keyboard = findKeyboard();
                for (char key : "su3".toCharArray()) service.onKey(String.valueOf(key));
                cellOnScreen.set(drawnKeyBounds(keyboard, "你").get(0));
                int[] location = new int[2];
                keyboard.getLocationOnScreen(location);
                cellOnScreen.offset(location[0], location[1]);
            });
            long downTime = SystemClock.uptimeMillis();
            for (int action : new int[]{MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP}) {
                MotionEvent touch = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action,
                        cellOnScreen.centerX(), cellOnScreen.top + 2, 0);
                touch.setSource(InputDevice.SOURCE_TOUCHSCREEN);
                try {
                    assertTrue(instrumentation.getUiAutomation().injectInputEvent(touch, true));
                } finally {
                    touch.recycle();
                }
            }
            await(() -> labels(findKeyboard()).contains("▲"));
        } finally {
            instrumentation.getUiAutomation().setRotation(originalRotation);
            if (originalAutoRotate) instrumentation.getUiAutomation().setRotation(UiAutomation.ROTATION_UNFREEZE);
            var restore = preferences.edit();
            for (String key : keys) {
                restore.remove(key);
                if (previous.get(key) instanceof Boolean value) restore.putBoolean(key, value);
                else if (previous.get(key) instanceof String value) restore.putString(key, value);
                else if (previous.get(key) instanceof Integer value) restore.putInt(key, value);
            }
            restore.commit();
            if (activity != null) {
                Activity host = activity;
                instrumentation.runOnMainSync(host::finish);
            }
        }
    }

    private static void assertMissingNavigationDispatchKeepsWindowHeight(BopomofoKeyboardView keyboard) {
        View inputView = (View) keyboard.getParent();
        WindowInsets original = keyboard.getRootWindowInsets();
        int navigationType = WindowInsets.Type.navigationBars();
        int navigationBottom = original.getInsets(navigationType).bottom;
        if (navigationBottom == 0) return; // The hidden and side-bar cases have no bottom reservation.
        Rect viewport = keyboard.getContext().getSystemService(android.view.WindowManager.class)
                .getCurrentWindowMetrics().getBounds();
        int[] location = new int[2];
        inputView.getLocationOnScreen(location);
        int bottom = location[1] + inputView.getHeight();
        int offset = viewport.bottom - bottom;
        WindowInsets missing = new WindowInsets.Builder(original).setInsets(navigationType, Insets.NONE).build();
        int exactWidth = View.MeasureSpec.makeMeasureSpec(inputView.getWidth(), View.MeasureSpec.EXACTLY);
        int freeHeight = View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED);
        inputView.offsetTopAndBottom(offset);
        try {
            inputView.dispatchApplyWindowInsets(original);
            inputView.measure(exactWidth, freeHeight);
            int expectedHeight = inputView.getMeasuredHeight();
            inputView.dispatchApplyWindowInsets(missing);
            inputView.measure(exactWidth, freeHeight);
            assertEquals("A missing dispatch must not shrink the IME window over a visible navigation bar",
                    expectedHeight, inputView.getMeasuredHeight());

            int originalTop = inputView.getTop();
            int originalBottom = inputView.getBottom();
            try {
                // Reproduce the framework laying out its old frame after the
                // keyboard has already measured with the recovered inset.
                inputView.layout(inputView.getLeft(), originalBottom - expectedHeight + navigationBottom,
                        inputView.getRight(), originalBottom);
                assertEquals("No key may start above a short IME frame", 0, keyboard.getTop());
                assertTrue("The keyboard must stay within the actual frame",
                        keyboard.getBottom() <= inputView.getHeight());
            } finally {
                inputView.layout(inputView.getLeft(), originalTop, inputView.getRight(), originalBottom);
            }

            inputView.offsetTopAndBottom(-navigationBottom);
            try {
                inputView.dispatchApplyWindowInsets(missing);
                inputView.measure(exactWidth, freeHeight);
                assertEquals("Space already reserved by an ancestor must be counted only once",
                        expectedHeight - navigationBottom, inputView.getMeasuredHeight());
            } finally {
                inputView.offsetTopAndBottom(navigationBottom);
            }
        } finally {
            inputView.offsetTopAndBottom(-offset);
            inputView.requestApplyInsets();
            inputView.requestLayout();
        }
    }

    @Test public void splitTopControlsCloseCandidatesAndDismissAcrossIntegrationModes() throws Exception {
        org.junit.Assume.assumeTrue(Build.VERSION.SDK_INT >= 30);
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        assertTrue("Select KeyKey on the isolated device before this test", Settings.Secure.getString(
                context.getContentResolver(), Settings.Secure.DEFAULT_INPUT_METHOD).contains(context.getPackageName()));
        var preferences = CandidateWindowSettings.preferences(context);
        Map<String, ?> previous = preferences.getAll();
        String[] keys = {KeyboardBottomControlsSettings.KEY_ENABLED, KeyboardLayoutProfileSettings.KEY_LAYOUT,
                ChineseInputMethodSettings.KEY_METHOD, BopomofoCompositionModeSettings.KEY_MODE,
                BopomofoKeyboardLayoutSettings.KEY_LAYOUT, KeyboardLayoutProfileSettings.KEY_DELETE_POSITION};
        Activity activity = null;
        try {
            preferences.edit().putBoolean(keys[0], false)
                    .putString(keys[1], KeyboardLayoutProfile.ALIGNED_SPLIT.id)
                    .putString(keys[2], ChineseInputMethod.SMART.name())
                    .putString(keys[3], BopomofoCompositionModeSettings.valueForMode(BopomofoCompositionMode.SMART))
                    .putString(keys[4], BopomofoKeyboardLayout.STANDARD.value)
                    .putString(keys[5], KeyboardLayoutProfile.DeletePosition.ABOVE_ENTER.id).commit();
            activity = instrumentation.startActivitySync(new Intent()
                    .setClassName(context, "tw.chichi77.keykey.android.ImeTestActivity")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
            Activity host = activity;
            instrumentation.runOnMainSync(() -> findEditor(host.findViewById(android.R.id.content)).setText(""));
            showEditorKeyboard(host, context);
            instrumentation.runOnMainSync(() -> {
                BopomofoKeyboardView view = findKeyboard();
                assertFalse(KeyboardBottomControlsSettings.enabled(context));
                List<RectF> dismiss = drawnKeyBounds(view, "▼");
                assertEquals("Integration OFF must still provide exactly one top dismiss key", 1, dismiss.size());
                List<RectF> firstReadingKey = drawnKeyBounds(view, "ㄅ");
                assertFalse("The test must use the standard Chinese touch keyboard", firstReadingKey.isEmpty());
                assertTrue("The independent dismiss key belongs above the main keys",
                        dismiss.get(0).bottom <= firstReadingKey.get(0).top);
            });
            instrumentation.runOnMainSync(() -> KeyboardBottomControlsSettings.setEnabled(context, true));
            instrumentation.waitForIdleSync();
            instrumentation.runOnMainSync(() -> {
                BopomofoKeyboardView view = findKeyboard();
                assertTrue(KeyboardBottomControlsSettings.enabled(context));
                List<RectF> dismiss = drawnKeyBounds(view, "▼");
                assertEquals("Integration ON must not duplicate the split top dismiss key in the footer", 1, dismiss.size());
                RectF mainColumn = drawnKeyBounds(view, "ㄅ").get(0);
                assertTrue("The only dismiss key must remain above the main rows", dismiss.get(0).bottom <= mainColumn.top);
                for (String label : List.of("符", "設", "⇧")) {
                    List<RectF> controls = drawnKeyBounds(view, label);
                    assertEquals("The split keyboard must draw one " + label + " control", 1, controls.size());
                    assertEquals(label + " must use one main-key column", mainColumn.width(), controls.get(0).width(), 1f);
                }
                List<RectF> spaces = drawnKeyBounds(view, "空白");
                assertEquals("Split mode keeps one space key in each half", 2, spaces.size());
                for (RectF space : spaces) {
                    assertTrue("The remaining columns must give space more room than a single control",
                            space.width() > mainColumn.width());
                }
                BopomofoImeService service = (BopomofoImeService) view.getContext();
                for (char key : "su3cl3".toCharArray()) service.onKey(String.valueOf(key));
            });
            await(() -> "你好".equals(findEditor(host.findViewById(android.R.id.content)).getText().toString()));
            List<String> completed = new ArrayList<>();
            instrumentation.runOnMainSync(() -> {
                completed.addAll(stripLabels(findKeyboard()));
                tapDrawnKey(findKeyboard(), "你");
            });
            await(() -> labels(findKeyboard()).contains("×"));
            instrumentation.runOnMainSync(() -> tapDrawnKey(findKeyboard(), "×"));
            await(() -> !labels(findKeyboard()).contains("×"));
            instrumentation.runOnMainSync(() -> {
                assertEquals("Closing candidates must preserve the completed composition", completed, stripLabels(findKeyboard()));
                assertEquals("你好", findEditor(host.findViewById(android.R.id.content)).getText().toString());
                tapDrawnKey(findKeyboard(), "⌫");
            });
            await(() -> "你".equals(findEditor(host.findViewById(android.R.id.content)).getText().toString()));
            // A pending reading cannot open core candidates. Its close no-op
            // contract is tested by the adapter; do not fabricate a visible ×.
            instrumentation.runOnMainSync(() -> {
                BopomofoImeService service = (BopomofoImeService) findKeyboard().getContext();
                for (char key : "su".toCharArray()) service.onKey(String.valueOf(key));
                String pendingText = String.join("", stripLabels(findKeyboard()));
                assertEquals("Top-strip text must preserve the unfinished reading across separate symbol cells",
                        "你ㄋㄧ", pendingText);
                assertEquals("你", findEditor(host.findViewById(android.R.id.content)).getText().toString());
                tapDrawnKey(findKeyboard(), "▼");
            });
            await(() -> !host.getWindow().getDecorView().getRootWindowInsets().isVisible(WindowInsets.Type.ime()));
            instrumentation.runOnMainSync(() -> assertEquals("Top dismiss keeps only completed text", "你",
                    findEditor(host.findViewById(android.R.id.content)).getText().toString()));
            showEditorKeyboard(host, context);
            instrumentation.runOnMainSync(() -> {
                assertTrue(KeyboardBottomControlsSettings.enabled(context));
                String reopenedText = String.join("", stripLabels(findKeyboard()));
                assertFalse("Reopening must not replay cancelled symbols: " + reopenedText,
                        reopenedText.contains("ㄋ") || reopenedText.contains("ㄧ"));
                BopomofoImeService service = (BopomofoImeService) findKeyboard().getContext();
                for (char key : "cl3".toCharArray()) service.onKey(String.valueOf(key));
            });
            await(() -> "你好".equals(findEditor(host.findViewById(android.R.id.content)).getText().toString()));
            Bundle evidence = new Bundle();
            evidence.putString("keykey_split_top_controls",
                    "integrationOffAndOn=true, uniqueTopDismiss=true, oneColumnControls=true, spaceRoom=true, "
                    + "smartCellTouch=true, candidateCloseTouch=true, backspaceTouch=true, "
                    + "topDismissTouch=true, completedPreserved=true, pendingCancelled=true, reopenNoReplay=true");
            instrumentation.sendStatus(0, evidence);
        } finally {
            var edit = preferences.edit();
            for (String key : keys) {
                edit.remove(key);
                if (previous.get(key) instanceof Boolean value) edit.putBoolean(key, value);
                else if (previous.get(key) instanceof String value) edit.putString(key, value);
            }
            edit.commit();
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
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
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
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
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

    @Test public void restartedTouchUsesTheCurrentCaretAndReleasesAMovedMutableSuffix() throws Exception {
        org.junit.Assume.assumeTrue(Build.VERSION.SDK_INT >= 30);
        org.junit.Assume.assumeTrue("Use a disposable emulator with KeyKey selected",
                "true".equals(InstrumentationRegistry.getArguments().getString("keykey.isolatedDevice")));
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        var preferences = CandidateWindowSettings.preferences(context);
        Map<String, ?> previous = preferences.getAll();
        String[] keys = {ChineseInputMethodSettings.KEY_METHOD, BopomofoCompositionModeSettings.KEY_MODE,
                BopomofoCompositionModeSettings.KEY_OMIT_TONE, BopomofoKeyboardLayoutSettings.KEY_LAYOUT};
        ImeTestActivity host = null;
        try {
            preferences.edit().putString(keys[0], ChineseInputMethod.SMART.name())
                    .putString(keys[1], BopomofoCompositionModeSettings.valueForMode(BopomofoCompositionMode.SMART))
                    .putBoolean(keys[2], false).putString(keys[3], BopomofoKeyboardLayout.STANDARD.value).commit();
            host = (ImeTestActivity) instrumentation.startActivitySync(new Intent()
                    .setClassName(context, "tw.chichi77.keykey.android.ImeTestActivity")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK)
                    .putExtra("initialSelectionUnknown", false)); // Public host extraction counter, known anchor.
            ImeTestActivity activity = host;
            showEditorKeyboard(activity, context);
            EditText editor = findEditor(activity.findViewById(android.R.id.content));
            instrumentation.runOnMainSync(() -> {
                BopomofoImeService service = (BopomofoImeService) findKeyboard().getContext();
                for (char key : "su3cl3".toCharArray()) service.onKey(String.valueOf(key));
                assertEquals("你好", editor.getText().toString());
                assertEquals("Known fresh typing adds no snapshot query", 0, activity.extractionProbeCalls.get());
                android.view.inputmethod.EditorInfo stale = new android.view.inputmethod.EditorInfo();
                stale.inputType = editor.getInputType(); stale.imeOptions = editor.getImeOptions();
                stale.initialSelStart = stale.initialSelEnd = 0;
                // Callback contract on the real current IC: rotation may replay
                // the field's original EditorInfo, although its caret is now 2.
                service.onStartInput(stale, true);
                assertEquals("A restart uses exactly one shared full snapshot", 1, activity.extractionProbeCalls.get());
                assertFalse(drawnKeyBounds(findKeyboard(), "你").isEmpty());
                for (char key : "su3".toCharArray()) service.onKey(String.valueOf(key));
                assertEquals("你好你", editor.getText().toString());
                assertEquals("Subsequent known writes do not query again", 1, activity.extractionProbeCalls.get());
                assertFalse("A synchronous own ACK must leave the new character editable",
                        drawnKeyBounds(findKeyboard(), "你").isEmpty());
                // Hold the application's public batch: the restart sees a real
                // external caret before its selection callback reaches the IME.
                editor.beginBatchEdit();
                try {
                    editor.setSelection(0);
                    service.onStartInput(stale, true);
                    assertEquals("你好你", editor.getText().toString());
                    assertTrue("A moved suffix is released without deleting host text",
                            drawnKeyBounds(findKeyboard(), "你").isEmpty());
                } finally { editor.endBatchEdit(); }
                for (char key : "su3".toCharArray()) service.onKey(String.valueOf(key));
                assertEquals("你你好你", editor.getText().toString());
            });
        } finally {
            if (host != null) { ImeTestActivity activity = host; instrumentation.runOnMainSync(activity::finish); }
            var edit = preferences.edit();
            for (String key : keys) {
                edit.remove(key);
                if (previous.get(key) instanceof Boolean value) edit.putBoolean(key, value);
                else if (previous.get(key) instanceof String value) edit.putString(key, value);
            }
            edit.commit();
        }
    }

    @Test public void touchPinyinTypesSmartAndTraditionalInTheHost() throws Exception {
        org.junit.Assume.assumeTrue(Build.VERSION.SDK_INT >= 30);
        org.junit.Assume.assumeTrue("Use a disposable emulator with KeyKey selected",
                "true".equals(InstrumentationRegistry.getArguments().getString("keykey.isolatedDevice")));
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        var preferences = CandidateWindowSettings.preferences(context);
        Map<String, ?> previous = preferences.getAll();
        String[] keys = {KeyboardBottomControlsSettings.KEY_ENABLED, KeyboardLayoutProfileSettings.KEY_LAYOUT,
                ChineseInputMethodSettings.KEY_METHOD, BopomofoCompositionModeSettings.KEY_MODE,
                BopomofoKeyboardLayoutSettings.KEY_LAYOUT, KeyboardLayoutProfileSettings.KEY_DELETE_POSITION,
                BopomofoCompositionModeSettings.KEY_OMIT_TONE};
        Activity activity = null;
        try {
            preferences.edit().putBoolean(keys[0], false)
                    .putString(keys[1], KeyboardLayoutProfile.ALIGNED.id)
                    .putString(keys[2], ChineseInputMethod.SMART.name())
                    .putString(keys[3], BopomofoCompositionModeSettings.valueForMode(BopomofoCompositionMode.SMART))
                    .putString(keys[4], BopomofoKeyboardLayout.HANYU_PINYIN.value)
                    .putString(keys[5], KeyboardLayoutProfile.DeletePosition.ABOVE_ENTER.id)
                    .remove(keys[6]).commit();
            activity = instrumentation.startActivitySync(new Intent()
                    .setClassName(context, "tw.chichi77.keykey.android.ImeTestActivity")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
            Activity host = activity;
            instrumentation.runOnMainSync(() ->
                    host.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT));
            KeyboardBottomSpaceInstrumentedTest.rotateDisplayTo(context, Configuration.ORIENTATION_PORTRAIT);
            await(() -> host.getResources().getConfiguration().orientation == Configuration.ORIENTATION_PORTRAIT);
            EditText editor = findEditor(host.findViewById(android.R.id.content));
            assertNotNull(editor);
            instrumentation.runOnMainSync(() -> editor.setText(""));
            showEditorKeyboard(host, context);
            instrumentation.runOnMainSync(() -> {
                BopomofoKeyboardView view = findKeyboard();
                assertFalse("The Pinyin keyboard must show letters rather than Zhuyin caps", labels(view).contains("ㄅ"));
                tapDrawnKey(view, "n");
                tapDrawnKey(view, "i");
                assertEquals("ni", String.join("", stripLabels(view)));
                tapDrawnKey(view, "⌫");
                assertEquals("n", String.join("", stripLabels(view)));
                assertEquals("", editor.getText().toString());
                for (char key : "i3hao3".toCharArray()) tapDrawnKey(view, String.valueOf(key));
            });
            assertPinyinHostText(editor, "你好");

            // Let the original Smart composition finish before rotating the
            // host. Wait for the landscape editor's connection before typing.
            instrumentation.runOnMainSync(() ->
                    ChineseInputMethodSettings.setMethod(context, ChineseInputMethod.TRADITIONAL));
            await(() -> labels(findKeyboard()).contains("漢語拼音"));
            instrumentation.runOnMainSync(() ->
                    host.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE));
            KeyboardBottomSpaceInstrumentedTest.rotateDisplayTo(context, Configuration.ORIENTATION_LANDSCAPE);
            await(() -> host.getResources().getConfiguration().orientation == Configuration.ORIENTATION_LANDSCAPE);
            showEditorKeyboard(host, context);
            await(() -> findKeyboard().getResources().getConfiguration().orientation == Configuration.ORIENTATION_LANDSCAPE
                    && labels(findKeyboard()).contains("漢語拼音"));
            instrumentation.runOnMainSync(() -> {
                BopomofoKeyboardView view = findKeyboard();
                for (char key : "zhong".toCharArray()) tapDrawnKey(view, String.valueOf(key));
            });
            assertPinyinHostText(editor, "你好zhong");
            instrumentation.runOnMainSync(() -> tapDrawnKey(findKeyboard(), "一聲"));
            await(() -> labels(findKeyboard()).contains("中"));
            instrumentation.runOnMainSync(() -> tapDrawnKey(findKeyboard(), "中"));
            assertPinyinHostText(editor, "你好中");
        } finally {
            if (activity != null) {
                Activity host = activity;
                instrumentation.runOnMainSync(host::finish);
            }
            var edit = preferences.edit();
            for (String key : keys) {
                edit.remove(key);
                if (previous.get(key) instanceof Boolean value) edit.putBoolean(key, value);
                else if (previous.get(key) instanceof String value) edit.putString(key, value);
            }
            edit.commit();
        }
    }

    @Test public void touchOmitToneShowsSingleCellChoicesAndRollsOverMarkedReading() throws Exception {
        org.junit.Assume.assumeTrue(Build.VERSION.SDK_INT >= 30);
        org.junit.Assume.assumeTrue("Use a disposable emulator with KeyKey selected",
                "true".equals(InstrumentationRegistry.getArguments().getString("keykey.isolatedDevice")));
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        var preferences = CandidateWindowSettings.preferences(context);
        Map<String, ?> previous = preferences.getAll();
        String[] keys = {ChineseInputMethodSettings.KEY_METHOD, BopomofoCompositionModeSettings.KEY_MODE,
                BopomofoKeyboardLayoutSettings.KEY_LAYOUT, BopomofoCompositionModeSettings.KEY_OMIT_TONE};
        Activity activity = null;
        try {
            preferences.edit().putString(keys[0], ChineseInputMethod.SMART.name())
                    .putString(keys[1], BopomofoCompositionModeSettings.valueForMode(BopomofoCompositionMode.SMART))
                    .putString(keys[2], BopomofoKeyboardLayout.HANYU_PINYIN.value)
                    .remove(keys[3]).commit();
            activity = instrumentation.startActivitySync(new Intent()
                    .setClassName(context, "tw.chichi77.keykey.android.ImeTestActivity")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
            Activity host = activity;
            EditText editor = findEditor(host.findViewById(android.R.id.content));
            assertNotNull(editor);
            instrumentation.runOnMainSync(() -> editor.setText(""));
            showEditorKeyboard(host, context);
            instrumentation.runOnMainSync(() -> {
                BopomofoKeyboardView view = findKeyboard();
                for (char key : "nihao".toCharArray()) tapDrawnKey(view, String.valueOf(key));
                assertFalse(labels(view).contains("你"));
                for (int index = 0; index < 5; index++) tapDrawnKey(view, "⌫");
                BopomofoCompositionModeSettings.setOmitTone(context, true);
            });
            instrumentation.runOnMainSync(() -> {
                BopomofoKeyboardView view = findKeyboard();
                RectF tone = drawnKeyBounds(view, "3").get(0);
                for (char key : "nihao".toCharArray()) tapDrawnKey(view, String.valueOf(key));
                assertGridPhrase(view, "nihao", "你", "好", "3", tone);
            });
            assertMarkedReading(editor, "", "nihao");

            instrumentation.runOnMainSync(() -> {
                BopomofoKeyboardView view = findKeyboard();
                tapDrawnKey(view, "你");
                tapDrawnKey(view, "妳");
                assertTrue(labels(view).contains("妳"));
                assertTrue(labels(view).contains("好"));
            });
            assertMarkedReading(editor, "", "nihao");

            instrumentation.runOnMainSync(() -> {
                BopomofoKeyboardView view = findKeyboard();
                for (char key : "ni".toCharArray()) tapDrawnKey(view, String.valueOf(key));
                assertTrue(labels(view).containsAll(List.of("妳", "好", "你")));
                ((BopomofoImeService) view.getContext()).onKey("ENTER");
            });
            assertPinyinHostText(editor, "妳好你");

            instrumentation.runOnMainSync(() -> {
                BopomofoKeyboardView view = findKeyboard();
                for (char key : "ni3hao3".toCharArray()) tapDrawnKey(view, String.valueOf(key));
                ((BopomofoImeService) view.getContext()).onKey("ENTER");
            });
            String pinyinPrefix = "妳好你你好";
            assertPinyinHostText(editor, pinyinPrefix);
            String prefix = assertOmitToneRollover(context, editor, pinyinPrefix,
                    List.of("z", "h", "u", "a", "n", "g"), "zhuang", "3");
            instrumentation.runOnMainSync(() -> BopomofoKeyboardLayoutSettings.setLayout(
                    context, BopomofoKeyboardLayout.STANDARD));
            await(() -> labels(findKeyboard()).contains("ㄋ"));
            instrumentation.runOnMainSync(() -> {
                BopomofoKeyboardView view = findKeyboard();
                RectF tone = drawnKeyBounds(view, "ˇ").get(0);
                for (String key : List.of("ㄋ", "ㄧ", "ㄏ", "ㄠ")) tapDrawnKey(view, key);
                assertGridPhrase(view, "ㄋㄧㄏㄠ", "你", "好", "ˇ", tone);
            });
            assertMarkedReading(editor, prefix, "ㄋㄧㄏㄠ");
            instrumentation.runOnMainSync(() -> {
                for (int index = 0; index < 4; index++) tapDrawnKey(findKeyboard(), "⌫");
            });
            assertPinyinHostText(editor, prefix);

            String committed = assertOmitToneRollover(context, editor, prefix,
                    List.of("ㄋ", "ㄧ"), "ㄋㄧ", "ˇ");

            instrumentation.runOnMainSync(() -> {
                BopomofoKeyboardView view = findKeyboard();
                tapDrawnKey(view, "ㄋ");
                tapDrawnKey(view, "ㄧ");
            });
            assertMarkedReading(editor, committed, "ㄋㄧ");
            instrumentation.runOnMainSync(() -> editor.setSelection(0));
            assertPinyinHostText(editor, committed);
            instrumentation.runOnMainSync(() -> {
                assertEquals(0, editor.getSelectionStart());
                editor.setSelection(committed.length());
                BopomofoKeyboardLayoutSettings.setLayout(context, BopomofoKeyboardLayout.HSU);
            });
            assertTrue(BopomofoCompositionModeSettings.omitTone(context));
            await(() -> labels(findKeyboard()).contains("e"));
            instrumentation.runOnMainSync(() -> {
                BopomofoKeyboardView view = findKeyboard();
                RectF tone = drawnKeyBounds(view, "f").get(0);
                for (char key : "nehw".toCharArray()) tapDrawnKey(view, String.valueOf(key));
                assertGridPhrase(view, "nehw", "你", "好", "f", tone);
            });
            assertMarkedReading(editor, committed, "nehw");
            instrumentation.runOnMainSync(() -> {
                BopomofoKeyboardView view = findKeyboard();
                tapDrawnKey(view, "你");
                tapDrawnKey(view, "妳");
                assertEquals(List.of("妳", "好"), drawnGridCharacters(view, "e"));
            });
            assertMarkedReading(editor, committed, "nehw");
            instrumentation.runOnMainSync(() ->
                    ((BopomofoImeService) findKeyboard().getContext()).onKey("ENTER"));
            String hsuPrefix = committed + "妳好";
            assertPinyinHostText(editor, hsuPrefix);

            List<String> tonedHsu = new ArrayList<>();
            instrumentation.runOnMainSync(() -> {
                BopomofoKeyboardView view = findKeyboard();
                for (char key : "nefhwf".toCharArray()) tapDrawnKey(view, String.valueOf(key));
                tonedHsu.addAll(drawnGridCharacters(view, "e"));
                assertEquals(List.of("你", "好"), tonedHsu);
            });
            assertMarkedReading(editor, hsuPrefix, "nefhwf");
            instrumentation.runOnMainSync(() ->
                    ((BopomofoImeService) findKeyboard().getContext()).onKey("ENTER"));
            String hsuTonedPrefix = hsuPrefix + String.join("", tonedHsu);
            assertPinyinHostText(editor, hsuTonedPrefix);
            assertOmitToneRollover(context, editor, hsuTonedPrefix, List.of("b", "y"), "by", "e");
        } finally {
            if (activity != null) {
                Activity host = activity;
                instrumentation.runOnMainSync(host::finish);
            }
            var edit = preferences.edit();
            for (String key : keys) {
                edit.remove(key);
                if (previous.get(key) instanceof Boolean value) edit.putBoolean(key, value);
                else if (previous.get(key) instanceof String value) edit.putString(key, value);
            }
            edit.commit();
        }
    }

    private static String assertOmitToneRollover(Context context, EditText editor,
            String prefix, List<String> keys, String syllable, String toneKey) throws Exception {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        String elevenReadings = syllable.repeat(11);
        instrumentation.runOnMainSync(() -> {
            BopomofoKeyboardView view = findKeyboard();
            for (int index = 0; index < 11; index++) {
                for (String key : keys) tapDrawnKey(view, key);
            }
            assertEquals(11, drawnGridCharacters(view, toneKey).size());
        });
        assertMarkedReading(editor, prefix, elevenReadings);

        List<String> tailCells = new ArrayList<>();
        instrumentation.runOnMainSync(() -> {
            BopomofoKeyboardView view = findKeyboard();
            for (String key : keys) tapDrawnKey(view, key);
            tailCells.addAll(drawnGridCharacters(view, toneKey));
            assertFalse(tailCells.isEmpty());
            assertTrue(tailCells.size() <= 11);
        });
        String tailReading = syllable.repeat(tailCells.size());
        String[] hostText = {""};
        await(() -> {
            hostText[0] = editor.getText().toString();
            return hostText[0].length() >= prefix.length() + tailReading.length()
                    && hostText[0].startsWith(prefix) && hostText[0].endsWith(tailReading)
                    && hostText[0].codePointCount(prefix.length(),
                            hostText[0].length() - tailReading.length()) == 12 - tailCells.size();
        });
        String shifted = hostText[0].substring(prefix.length(), hostText[0].length() - tailReading.length());
        assertTrue(shifted.codePoints().allMatch(IntegratedBottomControlsInstrumentedTest::isHan));
        assertMarkedReading(editor, prefix + shifted, tailReading);
        android.view.inputmethod.InputConnection[] previous = {null};
        instrumentation.runOnMainSync(() -> {
            previous[0] = ((BopomofoImeService) findKeyboard().getContext()).getCurrentInputConnection();
            context.getSystemService(InputMethodManager.class).restartInput(editor);
        });
        await(() -> {
            BopomofoKeyboardView view = findKeyboard();
            return view != null && ((BopomofoImeService) view.getContext()).getCurrentInputConnection() != null
                    && ((BopomofoImeService) view.getContext()).getCurrentInputConnection() != previous[0];
        });
        assertMarkedReading(editor, prefix + shifted, tailReading);
        instrumentation.runOnMainSync(() ->
                ((BopomofoImeService) findKeyboard().getContext()).onKey("ENTER"));
        String committed = prefix + shifted + String.join("", tailCells);
        assertPinyinHostText(editor, committed);
        return committed;
    }

    private static List<String> drawnGridCharacters(BopomofoKeyboardView view, String toneKey) {
        float keyTop = drawnKeyBounds(view, toneKey).get(0).top;
        List<String> values = new ArrayList<>();
        view.draw(new Canvas() {
            @Override public void drawText(String value, float x, float y, Paint paint) {
                if (y < keyTop && value.codePointCount(0, value.length()) == 1
                        && isHan(value.codePointAt(0))) values.add(value);
            }
        });
        return values;
    }

    private static boolean isHan(int codePoint) {
        return Character.UnicodeScript.of(codePoint) == Character.UnicodeScript.HAN;
    }

    private static void assertGridPhrase(BopomofoKeyboardView view, String reading,
            String first, String second, String toneKey, RectF tone) {
        assertEquals(11, view.compositionCellCount());
        assertFalse(labels(view).contains(reading));
        assertFalse(labels(view).contains(first + second));
        RectF firstCell = drawnKeyBounds(view, first).get(0);
        RectF secondCell = drawnKeyBounds(view, second).get(0);
        assertTrue(firstCell.right <= secondCell.left);
        assertTrue(secondCell.bottom <= tone.top);
        assertTrue(drawnKeyBounds(view, toneKey).contains(tone));
    }

    private static void assertMarkedReading(EditText editor, String prefix, String reading) throws Exception {
        await(() -> (prefix + reading).contentEquals(editor.getText())
                && android.view.inputmethod.BaseInputConnection.getComposingSpanStart(editor.getText()) == prefix.length()
                && android.view.inputmethod.BaseInputConnection.getComposingSpanEnd(editor.getText())
                        == prefix.length() + reading.length()
                && editor.getSelectionStart() == prefix.length() + reading.length()
                && editor.getSelectionEnd() == prefix.length() + reading.length());
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            assertEquals(prefix.length(), android.view.inputmethod.BaseInputConnection.getComposingSpanStart(
                    editor.getText()));
            assertEquals(prefix.length() + reading.length(),
                    android.view.inputmethod.BaseInputConnection.getComposingSpanEnd(editor.getText()));
        });
    }

    private static void assertPinyinHostText(EditText editor, String expected) throws Exception {
        String[] actual = {""};
        try {
            await(() -> {
                actual[0] = editor.getText().toString();
                return expected.equals(actual[0]);
            });
        } catch (AssertionError timeout) {
            throw new AssertionError("Expected Pinyin host text [" + expected
                    + "], got [" + actual[0] + "]", timeout);
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
        instrumentation.runOnMainSync(() -> manager.showSoftInput(editor[0], 0));
        long retryUntil = SystemClock.uptimeMillis() + 10000;
        long[] retryAt = {SystemClock.uptimeMillis() + 1000};
        await(() -> {
            BopomofoKeyboardView view = findKeyboard();
            boolean current = view != null && view.isShown() && view.getHeight() > 0
                    && ((BopomofoImeService) view.getContext()).getCurrentInputConnection() != null
                    && ((BopomofoImeService) view.getContext()).getCurrentInputEditorInfo() != null
                    && editor[0].getPrivateImeOptions().equals(((BopomofoImeService) view.getContext())
                            .getCurrentInputEditorInfo().privateImeOptions)
                    && view.getResources().getConfiguration().orientation
                            == activity.getResources().getConfiguration().orientation;
            if (current) return true;
            long now = SystemClock.uptimeMillis();
            if (now <= retryUntil && now >= retryAt[0] && activity.hasWindowFocus()
                    && editor[0].hasFocus() && manager.isActive(editor[0])) {
                manager.showSoftInput(editor[0], 0);
                retryAt[0] = now + 1000;
            }
            return false;
        });
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

    /** Observe real frames and host insets before using a height as a restoration baseline. */
    static void awaitStableImeGeometry(Activity host) throws Exception {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        View[] observed = {null};
        android.view.ViewTreeObserver.OnPreDrawListener[] listener = {null};
        boolean[] settled = {false};
        String[] previous = {null};
        int[] equalFrames = {0};
        long[] stableSince = {0};
        instrumentation.runOnMainSync(() -> {
            BopomofoKeyboardView view = findKeyboard();
            assertNotNull(view);
            observed[0] = view;
            listener[0] = () -> {
                View app = host.getWindow().getDecorView();
                View ime = ((BopomofoImeService) view.getContext()).getWindow().getWindow().getDecorView();
                var appInsets = app.getRootWindowInsets();
                var imeInsets = view.getRootWindowInsets();
                if (!view.isShown() || view.isLayoutRequested() || app.isLayoutRequested()
                        || appInsets == null || imeInsets == null
                        || !appInsets.isVisible(WindowInsets.Type.ime())
                        || appInsets.getInsets(WindowInsets.Type.ime()).bottom <= 0) {
                    previous[0] = null;
                    equalFrames[0] = 0;
                    settled[0] = false;
                } else {
                    int[] location = new int[2]; view.getLocationOnScreen(location);
                    String geometry = location[0] + ":" + location[1] + ":" + view.getWidth()
                            + ":" + view.getHeight() + ":" + view.getMeasuredHeight()
                            + ":" + ime.getWidth() + ":" + ime.getHeight()
                            + ":" + app.getWidth() + ":" + app.getHeight()
                            + ":" + appInsets.getInsets(WindowInsets.Type.ime())
                            + ":" + imeInsets.getInsets(WindowInsets.Type.navigationBars() | WindowInsets.Type.captionBar());
                    if (geometry.equals(previous[0])) equalFrames[0]++;
                    else {
                        previous[0] = geometry;
                        equalFrames[0] = 1;
                        stableSince[0] = SystemClock.uptimeMillis();
                    }
                    settled[0] = equalFrames[0] >= 3 && SystemClock.uptimeMillis() - stableSince[0] >= 100;
                }
                if (!settled[0]) view.postInvalidateOnAnimation();
                return true;
            };
            view.getViewTreeObserver().addOnPreDrawListener(listener[0]);
            view.postInvalidateOnAnimation();
        });
        try {
            await(() -> settled[0]);
        } finally {
            instrumentation.runOnMainSync(() -> observed[0].getViewTreeObserver().removeOnPreDrawListener(listener[0]));
        }
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
    private static List<RectF> drawnKeyBounds(BopomofoKeyboardView view, String label) {
        var matches = new ArrayList<RectF>();
        view.draw(new Canvas() {
            RectF lastKey;
            @Override public void drawRoundRect(RectF bounds, float rx, float ry, Paint paint) {
                lastKey = new RectF(bounds);
            }
            @Override public void drawText(String value, float x, float y, Paint paint) {
                if (label.equals(value) && lastKey != null) matches.add(new RectF(lastKey));
            }
        });
        return matches;
    }

    private static void tapDrawnKey(BopomofoKeyboardView view, String label) {
        List<RectF> matches = drawnKeyBounds(view, label);
        assertFalse("The live keyboard must draw " + label, matches.isEmpty());
        // A candidate next-page arrow can also say ▼. The topmost matching
        // control is the independent dismiss key, never the bottom integration.
        RectF key = matches.get(0);
        for (RectF candidate : matches) if (candidate.top < key.top) key = candidate;
        long down = SystemClock.uptimeMillis();
        for (int action : new int[] {MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP}) {
            MotionEvent event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action,
                    key.centerX(), key.centerY(), 0);
            try { assertTrue(view.onTouchEvent(event)); } finally { event.recycle(); }
        }
    }

    private static void cancelInputMethodPicker(Activity host) throws Exception {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        awaitInputMethodPicker(true);
        assertTrue(instrumentation.getUiAutomation().performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK));
        awaitInputMethodPicker(false);
        await(host::hasWindowFocus);
        Bundle evidence = new Bundle();
        evidence.putString("keykey_picker_cancel", "systemDialogObserved=true, dialogGone=true, hostFocus=true");
        instrumentation.sendStatus(0, evidence);
    }

    private static void awaitInputMethodPicker(boolean expectedVisible) throws Exception {
        long deadline = SystemClock.uptimeMillis() + 10000;
        String lastWindows = "";
        while (SystemClock.uptimeMillis() < deadline) {
            // Public shell diagnostics expose the WM type even when the system
            // picker has no accessibility root. Do not block the application main
            // thread or infer visibility from the keyboard underneath the dialog.
            try (var input = new android.os.ParcelFileDescriptor.AutoCloseInputStream(
                    InstrumentationRegistry.getInstrumentation().getUiAutomation()
                            .executeShellCommand("dumpsys window windows"));
                    var output = new java.io.ByteArrayOutputStream()) {
                byte[] buffer = new byte[8192];
                for (int count; (count = input.read(buffer)) != -1;) output.write(buffer, 0, count);
                lastWindows = output.toString(java.nio.charset.StandardCharsets.UTF_8.name());
            }
            boolean visible = false;
            for (String window : lastWindows.split("\\n\\s*Window #\\d+ Window\\{")) {
                if (window.contains("ty=INPUT_METHOD_DIALOG") && window.contains("mHasSurface=true")
                        && window.contains("isOnScreen=true") && window.contains("isVisible=true")) {
                    visible = true;
                    break;
                }
            }
            if (visible == expectedVisible) return;
            Thread.sleep(100);
        }
        fail("The system input-method picker did not become " + (expectedVisible ? "visible" : "hidden")
                + "; window diagnostics=" + lastWindows);
    }

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
