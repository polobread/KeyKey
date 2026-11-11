package tw.chichi77.keykey.android;

import static org.junit.Assert.*;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ActivityInfo;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Insets;
import android.graphics.Rect;
import android.graphics.RectF;
import android.os.Build;
import android.os.SystemClock;
import android.view.InputDevice;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.view.inputmethod.InputMethodManager;
import android.view.inspector.WindowInspector;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.CheckBox;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry;
import androidx.test.runner.lifecycle.Stage;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public final class KeyboardBottomSpaceInstrumentedTest {
    @Test
    public void settingsDefaultOnPersistIndependentlyAndFloatingDisablesBottomControls() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        SharedPreferences preferences = CandidateWindowSettings.preferences(context);
        String[] keys = {KeyboardBottomSpaceSettings.KEY_TOUCH_ENABLED,
                KeyboardBottomSpaceSettings.KEY_HARDWARE_ENABLED,
                CandidateWindowSettings.KEY_FLOATING_ENABLED,
                CandidateWindowSettings.KEY_NUMBER_ROW, CandidateWindowSettings.KEY_FAILURE,
                KeyboardBottomControlsSettings.KEY_ENABLED};
        Map<String, ?> previous = preferences.getAll();
        Activity activity = null;
        try {
            preferences.edit().remove(keys[0]).remove(keys[1])
                    .remove(KeyboardBottomControlsSettings.KEY_ENABLED)
                    .putBoolean(keys[2], false).putBoolean(keys[3], true).commit();
            assertFalse(KeyboardBottomControlsSettings.enabled(context));
            assertTrue(KeyboardBottomSpaceSettings.touchEnabled(context));
            assertTrue(KeyboardBottomSpaceSettings.hardwareEnabled(context));
            activity = openSettings(context);
            Activity current = activity;
            instrumentation.runOnMainSync(() -> {
                LinearLayout page = settingsPage(current);
                LinearLayout appearance = findGroup(page, "外觀與操作");
                LinearLayout hardware = findGroup(page, "實體鍵盤");
                appearance.getChildAt(0).performClick();
                hardware.getChildAt(0).performClick();
                CheckBox touchSpace = findCheck(appearance.getChildAt(1), "預留底部切換語言空間");
                CheckBox integrated = findCheck(appearance.getChildAt(1),
                        context.getString(R.string.integrated_bottom_controls_enabled));
                CheckBox hardwareSpace = findCheck(hardware.getChildAt(1), "預留底部切換語言空間");
                CheckBox floating = findCheck(hardware.getChildAt(1), "使用浮動候選字窗");
                CheckBox numbers = findCheck(hardware.getChildAt(1), "顯示虛擬數字與符號鍵");
                assertNotNull(integrated);
                assertFalse(integrated.isChecked());
                assertTrue(touchSpace.isChecked());
                assertTrue(hardwareSpace.isChecked());
                integrated.performClick();
                assertTrue(KeyboardBottomControlsSettings.enabled(context));
                assertTrue(preferences.getBoolean(KeyboardBottomControlsSettings.KEY_ENABLED, false));
                assertFalse(touchSpace.isEnabled());
                assertTrue(touchSpace.isChecked());
                assertTrue(touchSpace.getAlpha() < 1f);
                assertTrue(hardwareSpace.isEnabled());
                assertTrue(KeyboardBottomSpaceSettings.hardwareEnabled(context));
                touch(touchSpace);
                assertTrue("Disabling the reserve control must retain its saved value",
                        KeyboardBottomSpaceSettings.touchEnabled(context));
                integrated.performClick();
                assertFalse(KeyboardBottomControlsSettings.enabled(context));
                assertTrue(touchSpace.isEnabled());
                assertEquals(1f, touchSpace.getAlpha(), 0f);
                assertTrue(touchSpace.isChecked());
                touchSpace.performClick();
                assertFalse(KeyboardBottomSpaceSettings.touchEnabled(context));
                assertTrue(KeyboardBottomSpaceSettings.hardwareEnabled(context));
                hardwareSpace.performClick();
                assertFalse(KeyboardBottomSpaceSettings.hardwareEnabled(context));
                assertTrue(numbers.isChecked());
                floating.performClick();
                assertFalse(hardwareSpace.isEnabled());
                assertFalse(numbers.isEnabled());
                assertTrue(hardwareSpace.getAlpha() < 1f);
                assertTrue(numbers.getAlpha() < 1f);
                assertTrue(touchSpace.isEnabled());
                touch(hardwareSpace);
                touch(numbers);
                assertFalse(hardwareSpace.isChecked());
                assertTrue(numbers.isChecked());
                floating.performClick();
                assertTrue(hardwareSpace.isEnabled());
                assertTrue(numbers.isEnabled());
                assertEquals(1f, hardwareSpace.getAlpha(), 0f);
                assertFalse(hardwareSpace.isChecked());
                assertTrue(numbers.isChecked());
                integrated.performClick();
                assertTrue(KeyboardBottomControlsSettings.enabled(context));
                assertFalse(touchSpace.isEnabled());
                assertFalse(touchSpace.isChecked());
                assertFalse(KeyboardBottomSpaceSettings.touchEnabled(context));
                assertTrue(hardwareSpace.isEnabled());
                assertFalse(KeyboardBottomSpaceSettings.hardwareEnabled(context));
                current.finish();
            });
            activity = openSettings(context);
            Activity reopened = activity;
            instrumentation.runOnMainSync(() -> {
                LinearLayout page = settingsPage(reopened);
                assertFalse(findCheck(findGroup(page, "外觀與操作").getChildAt(1),
                        "預留底部切換語言空間").isChecked());
                assertFalse(findCheck(findGroup(page, "實體鍵盤").getChildAt(1),
                        "預留底部切換語言空間").isChecked());
                assertTrue(findCheck(findGroup(page, "實體鍵盤").getChildAt(1),
                        "顯示虛擬數字與符號鍵").isChecked());
                var appearance = findGroup(page, "外觀與操作");
                CheckBox integrated = findCheck(appearance.getChildAt(1),
                        context.getString(R.string.integrated_bottom_controls_enabled));
                CheckBox touchSpace = findCheck(appearance.getChildAt(1), "預留底部切換語言空間");
                assertTrue(integrated.isChecked());
                assertTrue(KeyboardBottomControlsSettings.enabled(context));
                assertFalse(touchSpace.isEnabled());
                assertFalse(touchSpace.isChecked());
                assertTrue(findCheck(findGroup(page, "實體鍵盤").getChildAt(1),
                        "預留底部切換語言空間").isEnabled());
                integrated.performClick();
                assertFalse(KeyboardBottomControlsSettings.enabled(context));
                assertFalse(preferences.getBoolean(KeyboardBottomControlsSettings.KEY_ENABLED, true));
                assertTrue(touchSpace.isEnabled());
                assertFalse(touchSpace.isChecked());
                touchSpace.performClick();
                assertTrue(KeyboardBottomSpaceSettings.touchEnabled(context));
                assertFalse(KeyboardBottomSpaceSettings.hardwareEnabled(context));
            });
        } finally {
            if (activity != null) {
                Activity current = activity;
                instrumentation.runOnMainSync(current::finish);
            }
            instrumentation.waitForIdleSync();
            SharedPreferences.Editor restore = preferences.edit();
            for (String key : keys) {
                restore.remove(key);
                Object value = previous.get(key);
                if (value instanceof Boolean bool) restore.putBoolean(key, bool);
                else if (value instanceof String string) restore.putString(key, string);
            }
            restore.commit();
        }
    }

    @Test
    public void togglesRemoveOnlyReservedSpaceWithoutResizingOrMovingKeyboardContent() {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            Context base = InstrumentationRegistry.getInstrumentation().getTargetContext();
            for (int orientation : new int[]{Configuration.ORIENTATION_PORTRAIT,
                    Configuration.ORIENTATION_LANDSCAPE}) {
                Configuration configuration = new Configuration(base.getResources().getConfiguration());
                configuration.orientation = orientation;
                Context context = base.createConfigurationContext(configuration);
                int padding = Math.round((orientation == Configuration.ORIENTATION_PORTRAIT ? 40 : 35)
                        * context.getResources().getDisplayMetrics().density);
                BopomofoKeyboardView view = new BopomofoKeyboardView(context);
                view.setMode(orientation == Configuration.ORIENTATION_PORTRAIT
                        ? BopomofoKeyboardView.Mode.PORTRAIT : BopomofoKeyboardView.Mode.LANDSCAPE);
                for (int percent : new int[]{50, 100, 200}) {
                    view.setTouchKeyboardHeightPercents(percent, percent);
                    verifyContentUnchanged(view, padding, true);
                }
                view.setMode(BopomofoKeyboardView.Mode.HARDWARE);
                for (boolean numberRows : new boolean[]{false, true}) {
                    view.setHardwareNumberRowEnabled(numberRows);
                    verifyContentUnchanged(view, padding, false);
                }
                view.setMode(BopomofoKeyboardView.Mode.HARDWARE_FLOATING);
                view.setBottomSpaceEnabled(true, true);
                int floatingHeight = render(view).getHeight();
                view.setBottomSpaceEnabled(false, false);
                assertEquals(floatingHeight, render(view).getHeight());
            }
        });
    }

    @Test
    public void constrainedHostShrinksInsteadOfGivingReservedSpaceToKeys() {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            Context base = InstrumentationRegistry.getInstrumentation().getTargetContext();
            for (int orientation : new int[]{Configuration.ORIENTATION_PORTRAIT,
                    Configuration.ORIENTATION_LANDSCAPE}) {
                Configuration configuration = new Configuration(base.getResources().getConfiguration());
                configuration.orientation = orientation;
                Context context = base.createConfigurationContext(configuration);
                float density = context.getResources().getDisplayMetrics().density;
                int padding = Math.round((orientation == Configuration.ORIENTATION_PORTRAIT ? 40 : 35)
                        * density);
                BopomofoKeyboardView view = new BopomofoKeyboardView(context);
                view.setMode(orientation == Configuration.ORIENTATION_PORTRAIT
                        ? BopomofoKeyboardView.Mode.PORTRAIT : BopomofoKeyboardView.Mode.LANDSCAPE);
                verifyConstrainedContent(view, padding, Math.round(190 * density));
                view.setTouchKeyboardHeightPercents(200, 200);
                verifyConstrainedContent(view, padding, Math.round(300 * density));
                view.setMode(BopomofoKeyboardView.Mode.HARDWARE);
                view.setHardwareNumberRowEnabled(true);
                verifyConstrainedContent(view, padding, Math.round(170 * density));
            }
        });
    }

    private static void verifyConstrainedContent(BopomofoKeyboardView view, int padding, int maximum) {
        int spec = View.MeasureSpec.makeMeasureSpec(maximum, View.MeasureSpec.AT_MOST);
        view.setBottomSpaceEnabled(true, true);
        Bitmap reserved = render(view, spec);
        view.setBottomSpaceEnabled(false, false);
        Bitmap flush = render(view, spec);
        assertEquals("A constrained IME must release the entire reserved space", padding,
                reserved.getHeight() - flush.getHeight());
        Bitmap content = Bitmap.createBitmap(reserved, 0, 0, flush.getWidth(), flush.getHeight());
        assertTrue("Disabling padding must not enlarge keys", flush.sameAs(content));
    }

    @Test
    public void reopenedTouchKeyboardFillsItsWindowWithoutSubtractingSpaceTwice() {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
            for (BopomofoKeyboardView.Mode mode : new BopomofoKeyboardView.Mode[]{
                    BopomofoKeyboardView.Mode.PORTRAIT, BopomofoKeyboardView.Mode.LANDSCAPE}) {
                for (int percent : new int[]{50, 100, 200}) {
                    BopomofoKeyboardView keyboard = new BopomofoKeyboardView(context);
                    keyboard.setMode(mode);
                    keyboard.setTouchKeyboardHeightPercents(percent, percent);
                    keyboard.setBottomSpaceEnabled(false, false);
                    FrameLayout window = new FrameLayout(context);
                    window.addView(keyboard, new FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
                    int availableWidth = context.getResources().getDisplayMetrics().widthPixels;
                    int width = View.MeasureSpec.makeMeasureSpec(availableWidth, View.MeasureSpec.EXACTLY);
                    window.measure(width, View.MeasureSpec.makeMeasureSpec(2000, View.MeasureSpec.AT_MOST));
                    int height = window.getMeasuredHeight();
                    int content = keyboard.getMeasuredHeight();
                    // The framework measures again with the newly allocated IME window size.
                    window.measure(width, View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY));
                    window.layout(0, 0, availableWidth, height);
                    assertEquals("Remeasuring the window must not shorten the keyboard content",
                            content, keyboard.getMeasuredHeight());
                    assertEquals("No blank bottom strip after reopening", window.getHeight(), keyboard.getBottom());
                }
            }
        });
    }

    @Test
    public void clientWidthFeedbackKeepsKeyboardHeightAndStillHonorsRealParentCaps() {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            Context base = InstrumentationRegistry.getInstrumentation().getTargetContext();
            Configuration configuration = new Configuration(base.getResources().getConfiguration());
            configuration.orientation = Configuration.ORIENTATION_LANDSCAPE;
            configuration.densityDpi = 420;
            Context context = base.createConfigurationContext(configuration);
            float density = context.getResources().getDisplayMetrics().density;
            int fullWidth = Math.round(900 * density);
            int clientWidth = fullWidth - Math.round(66 * density);
            int reserve = Math.round(35 * density);
            var profile = KeyboardLayoutProfile.ALIGNED;
            for (int percent : new int[]{100, 50, 200}) {
                for (boolean integrated : new boolean[]{true, false}) {
                    var keyboard = new BopomofoKeyboardView(context);
                    keyboard.setMode(BopomofoKeyboardView.Mode.LANDSCAPE);
                    keyboard.setLayoutProfile(profile);
                    keyboard.setTouchKeyboardHeightPercents(percent, percent);
                    keyboard.setBottomSpaceEnabled(true, true);
                    keyboard.setIntegratedBottomControls(integrated, false);
                    var window = new FrameLayout(context);
                    window.addView(keyboard, new FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
                    measureWindow(window, fullWidth, Math.round(800 * density), View.MeasureSpec.AT_MOST);
                    KeyboardContent before = drawnMainKeys(keyboard, integrated);
                    int allocatedHeight = window.getMeasuredHeight();
                    // WM first allocates our requested height, then the cutout changes only
                    // the client width. This AT_MOST child pass is not a new vertical cap.
                    measureWindow(window, clientWidth, allocatedHeight, View.MeasureSpec.EXACTLY);
                    KeyboardContent after = drawnMainKeys(keyboard, integrated);
                    String sample = "landscape/" + percent + "%/integrated=" + integrated
                            + "/width=" + fullWidth + "->" + clientWidth;
                    assertEquals(sample + ": allocated=" + allocatedHeight
                            + ", after=" + after.totalHeight(), before.totalHeight(), after.totalHeight());
                    assertEquals(sample, window.getHeight(), keyboard.getBottom());
                    assertEquals(sample, before.mainKeys().size(), after.mainKeys().size());
                    for (int index = 0; index < before.mainKeys().size(); index++) {
                        assertEquals(sample, before.mainKeys().get(index).top, after.mainKeys().get(index).top, .01f);
                        assertEquals(sample, before.mainKeys().get(index).bottom, after.mainKeys().get(index).bottom, .01f);
                    }
                    // A genuinely smaller upstream budget must still constrain the child.
                    int realCap = Math.round((percent == 50 ? 100 : 190) * density);
                    measureWindow(window, clientWidth, realCap, View.MeasureSpec.AT_MOST);
                    int wanted = Math.round(Math.round(profile.layout(
                            KeyboardLayoutProfile.Orientation.LANDSCAPE).contentHeightDp * density) * percent / 100f);
                    int expectedContent = Math.min(wanted, Math.max(0, realCap - reserve));
                    assertEquals(sample + ": real cap", expectedContent + (integrated ? 0 : reserve),
                            keyboard.getMeasuredHeight());
                    assertTrue(sample, keyboard.getMeasuredHeight() <= realCap);
                    for (RectF key : drawnMainKeys(keyboard, integrated).mainKeys()) {
                        assertTrue(sample + ": content must stay inside the capped child", key.bottom <= keyboard.getHeight());
                    }
                }
            }
        });
    }

    @Test
    public void integratedInsetsUseOnlyRemainingNavigationAndKeepCappedContentSafe() {
        org.junit.Assume.assumeTrue(Build.VERSION.SDK_INT >= 30);
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        instrumentation.runOnMainSync(() -> {
            Context context = instrumentation.getTargetContext();
            float density = context.getResources().getDisplayMetrics().density;
            int width = context.getResources().getDisplayMetrics().widthPixels;
            int cap = Math.round(800 * density);
            int originalReserve = Math.round(35 * density);
            var keyboard = new BopomofoKeyboardView(context);
            keyboard.setMode(BopomofoKeyboardView.Mode.LANDSCAPE);
            keyboard.setLayoutProfile(KeyboardLayoutProfile.ALIGNED);
            keyboard.setBottomSpaceEnabled(true, true);
            keyboard.setIntegratedBottomControls(true, false);
            var window = new FrameLayout(context);
            window.addView(keyboard, new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
            measureWindow(window, width, cap, View.MeasureSpec.AT_MOST);
            KeyboardContent original = drawnMainKeys(keyboard, true);
            for (int insetDp : new int[]{24, 64, 0}) {
                int inset = Math.round(insetDp * density);
                keyboard.onApplyWindowInsets(new WindowInsets.Builder()
                        .setInsets(WindowInsets.Type.navigationBars(), Insets.of(0, 0, 0, inset))
                        .setVisible(WindowInsets.Type.navigationBars(), inset > 0).build());
                int oldWindowHeight = window.getMeasuredHeight();
                measureWindow(window, width, oldWindowHeight, View.MeasureSpec.EXACTLY);
                for (RectF key : drawnMainKeys(keyboard, true).mainKeys()) {
                    assertTrue("Even an old-window cap must leave the delivered navigation area safe",
                            key.bottom <= keyboard.getHeight() - inset);
                }
                measureWindow(window, width, cap, View.MeasureSpec.AT_MOST);
                KeyboardContent current = drawnMainKeys(keyboard, true);
                assertEquals("Only the remaining inset contributes to the window", original.totalHeight() + inset,
                        current.totalHeight());
                assertEquals("A genuine upstream pass restores the intended content", original.mainKeys(), current.mainKeys());
                int realCap = Math.round(180 * density);
                measureWindow(window, width, realCap, View.MeasureSpec.AT_MOST);
                assertTrue(keyboard.getHeight() <= realCap);
                for (RectF key : drawnMainKeys(keyboard, true).mainKeys()) {
                    assertTrue("A genuine small cap must protect the delivered navigation area",
                            key.bottom <= keyboard.getHeight() - inset);
                }
                // Restore the upstream budget before the next independent inset sample.
                measureWindow(window, width, cap, View.MeasureSpec.AT_MOST);
            }
            // A parent's already-consumed navigation area arrives as zero.
            assertEquals(original.totalHeight(), keyboard.getHeight());
            keyboard.onApplyWindowInsets(new WindowInsets.Builder()
                    .setInsets(WindowInsets.Type.navigationBars(), Insets.of(0, 0, 0, Math.round(64 * density))).build());
            keyboard.setIntegratedBottomControls(false, false);
            measureWindow(window, width, cap, View.MeasureSpec.AT_MOST);
            assertEquals("Non-integrated layout keeps its saved reservation", original.totalHeight() + originalReserve,
                    keyboard.getHeight());
        });
    }

    @Test
    public void integratedControlsToggleRestoresReservationAfterParentFeedbackAndKeepsRealCap() {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
            float density = context.getResources().getDisplayMetrics().density;
            verifyIntegratedWindowFeedback(context, 100, Math.round(800 * density), false);
            verifyIntegratedWindowFeedback(context, 200, Math.round(300 * density), true);
        });
    }

    private static void verifyIntegratedWindowFeedback(Context context, int percent,
            int availableHeight, boolean capped) {
        int padding = Math.round(40 * context.getResources().getDisplayMetrics().density);
        BopomofoKeyboardView keyboard = new BopomofoKeyboardView(context);
        keyboard.setMode(BopomofoKeyboardView.Mode.PORTRAIT);
        keyboard.setLayoutProfile(KeyboardLayoutProfile.ALIGNED);
        keyboard.setTouchKeyboardHeightPercents(percent, percent);
        keyboard.setBottomSpaceEnabled(true, true);
        // Apply the persisted ON state before the first measure, as service startup does.
        keyboard.setIntegratedBottomControls(true, false);
        FrameLayout window = new FrameLayout(context);
        window.addView(keyboard, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        int width = context.getResources().getDisplayMetrics().widthPixels;
        String sample = "height=" + percent + "%/cap=" + availableHeight;
        measureWindow(window, width, availableHeight, View.MeasureSpec.AT_MOST);
        KeyboardContent original = drawnMainKeys(keyboard, true);
        assertFalse(sample, original.mainKeys().isEmpty());
        if (capped) {
            assertEquals(sample + ": the real screen cap must reserve its original budget",
                    availableHeight - padding, original.totalHeight());
        } else {
            assertTrue(sample + ": this sample must leave room to restore the reservation",
                    original.totalHeight() + padding < availableHeight);
        }
        // An exact parent window gives its WRAP_CONTENT child an AT_MOST spec.
        // This height came from the child itself, rather than a new upstream cap.
        measureWindow(window, width, window.getMeasuredHeight(), View.MeasureSpec.EXACTLY);
        assertIntegratedContent(sample + "/initial feedback", keyboard, true, original, padding);
        assertEquals(sample, window.getHeight(), keyboard.getBottom());

        for (boolean integrated : new boolean[]{false, true, false}) {
            String stage = sample + "/integrated=" + integrated;
            int oldWindowHeight = window.getMeasuredHeight();
            keyboard.setIntegratedBottomControls(integrated, false);
            // First the existing IME window measures using its old allocated height.
            measureWindow(window, width, oldWindowHeight, View.MeasureSpec.EXACTLY);
            KeyboardContent feedback = drawnMainKeys(keyboard, integrated);
            assertTrue(stage + ": the child must respect the old window's AT_MOST cap",
                    feedback.totalHeight() <= oldWindowHeight);
            assertEquals(stage + ": old-window feedback must not shrink main keys",
                    original.mainKeys(), feedback.mainKeys());
            // A normal WRAP_CONTENT pass reuses the genuine upstream budget.
            // The child never asks its old AT_MOST parent for an oversized height.
            measureWindow(window, width, availableHeight, View.MeasureSpec.AT_MOST);
            assertIntegratedContent(stage + "/upstream cap", keyboard, integrated, original, padding);
            assertTrue(stage, keyboard.getMeasuredHeight() <= availableHeight);
            assertTrue(stage, window.getMeasuredHeight() <= availableHeight);
            assertEquals(stage, keyboard.getMeasuredHeight(), window.getMeasuredHeight());
            // The framework feeds back the parent's newly measured window height.
            measureWindow(window, width, window.getMeasuredHeight(), View.MeasureSpec.EXACTLY);
            assertIntegratedContent(stage + "/new window", keyboard, integrated, original, padding);
            assertEquals(stage + ": the new window must contain the whole keyboard",
                    window.getHeight(), keyboard.getBottom());
        }
    }

    private static void measureWindow(FrameLayout window, int width, int height, int heightMode) {
        window.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(height, heightMode));
        window.layout(0, 0, window.getMeasuredWidth(), window.getMeasuredHeight());
    }

    private static void assertIntegratedContent(String stage, BopomofoKeyboardView keyboard,
            boolean integrated, KeyboardContent original, int padding) {
        KeyboardContent current = drawnMainKeys(keyboard, integrated);
        assertEquals(stage + ": toggling integration must only add or remove the reservation",
                original.totalHeight() + (integrated ? 0 : padding), current.totalHeight());
        assertEquals(stage + ": main keys must retain their positions and sizes",
                original.mainKeys(), current.mainKeys());
    }

    private static KeyboardContent drawnMainKeys(BopomofoKeyboardView keyboard, boolean integrated) {
        var bounds = new ArrayList<RectF>();
        keyboard.draw(new Canvas() {
            @Override public void drawRoundRect(RectF rect, float rx, float ry, Paint paint) {
                bounds.add(new RectF(rect));
            }
        });
        int mainCount = KeyboardLayoutGeometry.resolvedRows(KeyboardLayoutProfile.ALIGNED,
                KeyboardLayoutProfile.Orientation.PORTRAIT, KeyboardLayoutProfile.Plane.BOPOMOFO,
                false, KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER)
                .stream().mapToInt(List::size).sum();
        int functionCount = KeyboardLayoutGeometry.resolvedFunctionKeys(KeyboardLayoutProfile.ALIGNED,
                KeyboardLayoutProfile.Orientation.PORTRAIT, KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER,
                integrated, false).size();
        // Candidate cells precede the key rows; the function row is drawn last.
        int end = bounds.size() - functionCount;
        assertTrue("The main keys must actually be drawn", end >= mainCount);
        return new KeyboardContent(keyboard.getMeasuredHeight(),
                List.copyOf(bounds.subList(end - mainCount, end)));
    }

    private record KeyboardContent(int totalHeight, List<RectF> mainKeys) {}

    @Test
    public void cappedIntegratedContainerKeepsContentAtTheWindowBottom() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        instrumentation.runOnMainSync(() -> {
            Context context = instrumentation.getTargetContext();
            float density = context.getResources().getDisplayMetrics().density;
            int width = context.getResources().getDisplayMetrics().widthPixels;
            int cap = Math.round(190 * density);
            for (var mode : new BopomofoKeyboardView.Mode[]{BopomofoKeyboardView.Mode.PORTRAIT,
                    BopomofoKeyboardView.Mode.LANDSCAPE}) {
                for (int percent : new int[]{100, 200}) {
                    var keyboard = new BopomofoKeyboardView(context);
                    keyboard.setMode(mode);
                    keyboard.setTouchKeyboardHeightPercents(percent, percent);
                    keyboard.setIntegratedBottomControls(true, false);
                    var container = new KeyboardInputView(context, keyboard);
                    measureWindow(container, width, cap, View.MeasureSpec.AT_MOST);
                    KeyboardContent original = drawnMainKeys(keyboard, true);
                    assertEquals(cap, container.getHeight());
                    assertEquals(container.getHeight(), keyboard.getBottom());
                    measureWindow(container, width, cap, View.MeasureSpec.EXACTLY);
                    assertEquals("Parent feedback must keep the capped content dimensions",
                            original.mainKeys(), drawnMainKeys(keyboard, true).mainKeys());
                    assertEquals("No transparent strip below a capped keyboard",
                            container.getHeight(), keyboard.getBottom());
                }
            }
        });
    }

    @Test
    public void liveInputMethodReleasesHostSpaceWhenBottomSpaceIsDisabled() throws Exception {
        org.junit.Assume.assumeTrue(Build.VERSION.SDK_INT >= 30);
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        SharedPreferences preferences = CandidateWindowSettings.preferences(context);
        Map<String, ?> previous = preferences.getAll();
        String[] keys = {KeyboardBottomSpaceSettings.KEY_TOUCH_ENABLED,
                KeyboardBottomSpaceSettings.KEY_HARDWARE_ENABLED,
                CandidateWindowSettings.KEY_FLOATING_ENABLED, KeyboardBottomControlsSettings.KEY_ENABLED};
        Activity activity = null;
        try {
            preferences.edit().putBoolean(keys[0], true).putBoolean(keys[1], true)
                    .putBoolean(keys[2], false).putBoolean(keys[3], false).commit();
            activity = instrumentation.startActivitySync(new Intent()
                    .setClassName(context, "tw.chichi77.keykey.android.ImeTestActivity")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            Activity initial = activity;
            instrumentation.runOnMainSync(() ->
                    initial.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT));
            // Rotation can recreate the host. Measure the resumed window, rather
            // than retaining the old landscape Activity and its stale insets.
            activity = awaitPortraitHost();
            Activity host = activity;
            instrumentation.runOnMainSync(() -> {
                EditText editor = findEditor(host.findViewById(android.R.id.content));
                assertNotNull(editor);
                editor.requestFocus();
                context.getSystemService(InputMethodManager.class)
                        .showSoftInput(editor, InputMethodManager.SHOW_IMPLICIT);
            });
            int reserved = awaitImeHeight(host, -1);
            assertTrue("IME never opened", reserved > 0);
            int padding = Math.round(40 * context.getResources().getDisplayMetrics().density);
            instrumentation.runOnMainSync(() -> {
                KeyboardBottomSpaceSettings.setTouchEnabled(context, false);
                KeyboardBottomSpaceSettings.setHardwareEnabled(context, false);
            });
            int flush = awaitImeHeight(host, reserved - padding);
            assertEquals("Turning off the bottom space must release host window space", padding,
                    reserved - flush);
            instrumentation.runOnMainSync(() -> context.getSystemService(InputMethodManager.class)
                    .hideSoftInputFromWindow(host.getWindow().getDecorView().getWindowToken(), 0));
            assertEquals(0, awaitImeHeight(host, 0));
            instrumentation.runOnMainSync(() -> context.getSystemService(InputMethodManager.class)
                    .showSoftInput(findEditor(host.findViewById(android.R.id.content)), InputMethodManager.SHOW_IMPLICIT));
            assertEquals("Reopening must preserve the reduced IME height", flush, awaitImeHeight(host, flush));
            instrumentation.runOnMainSync(() -> {
                KeyboardBottomSpaceSettings.setTouchEnabled(context, true);
                KeyboardBottomSpaceSettings.setHardwareEnabled(context, true);
            });
            assertEquals(reserved, awaitImeHeight(host, reserved));
        } finally {
            if (activity != null) {
                Activity host = activity;
                instrumentation.runOnMainSync(host::finish);
            }
            SharedPreferences.Editor restore = preferences.edit();
            for (String key : keys) {
                restore.remove(key);
                if (previous.get(key) instanceof Boolean value) restore.putBoolean(key, value);
            }
            restore.commit();
        }
    }

    @Test
    public void settingsPreviewKeepsTheOppositeEdgeFixedAndSavesByOrientation() throws Exception {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        SharedPreferences preferences = CandidateWindowSettings.preferences(context);
        String[] keys = {
                KeyboardSizeSettings.KEY_PORTRAIT_PERCENT, KeyboardSizeSettings.KEY_LANDSCAPE_PERCENT,
                KeyboardSizeSettings.KEY_PORTRAIT_SCALE, KeyboardSizeSettings.KEY_LANDSCAPE_SCALE,
                KeyboardSizeSettings.KEY_PORTRAIT_GAP, KeyboardSizeSettings.KEY_LANDSCAPE_GAP,
        };
        Map<String, ?> previous = preferences.getAll();
        Activity settings = null;
        try {
            var reset = preferences.edit();
            for (String key : keys) reset.remove(key);
            reset.putInt(KeyboardSizeSettings.KEY_PORTRAIT_PERCENT, 110)
                    .putInt(KeyboardSizeSettings.KEY_LANDSCAPE_PERCENT, 90).commit();
            settings = openSettings(context);
            Activity initial = settings;
            instrumentation.runOnMainSync(() ->
                    initial.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT));
            settings = awaitActivity(SettingsActivity.class, Configuration.ORIENTATION_PORTRAIT);
            Activity portraitEditor = openResizeControls(settings);
            instrumentation.runOnMainSync(() -> {
                BopomofoKeyboardView keyboard = resizeKeyboard(portraitEditor);
                assertEquals(Math.round(keyboard.defaultTouchHeight() * 1.1f),
                        keyboard.visibleTouchEdges().contentHeight());
            });
            int distance = Math.round(20 * context.getResources().getDisplayMetrics().density);

            Rect top = resizeBounds(portraitEditor, "拖曳鍵盤上緣");
            Rect bottom = resizeBounds(portraitEditor, "拖曳鍵盤下緣");
            dragResizeHandle(portraitEditor, bottom, distance, () -> {
                assertEquals(top, resizeBounds(portraitEditor, "拖曳鍵盤上緣"));
                assertEquals(bottom, resizeBounds(portraitEditor, "拖曳鍵盤下緣"));
            });
            dragResizeHandle(portraitEditor, top, -distance, () -> {
                awaitResizeEdge(portraitEditor, "拖曳鍵盤上緣", top.centerY() - distance / 2);
                assertEquals(bottom.centerY(), resizeBounds(portraitEditor, "拖曳鍵盤下緣").centerY(), 2);
            });
            Rect raisedTop = resizeBounds(portraitEditor, "拖曳鍵盤上緣");
            dragResizeHandle(portraitEditor, bottom, -distance, () -> {
                awaitResizeEdge(portraitEditor, "拖曳鍵盤下緣", bottom.centerY() - distance / 2);
                assertEquals(raisedTop.centerY(), resizeBounds(portraitEditor, "拖曳鍵盤上緣").centerY(), 2);
            });
            Rect raisedBottom = resizeBounds(portraitEditor, "拖曳鍵盤下緣");
            assertFalse(preferences.contains(KeyboardSizeSettings.KEY_PORTRAIT_GAP));
            clickResizeControl(portraitEditor, "完成");
            settings = awaitActivity(SettingsActivity.class, Configuration.ORIENTATION_PORTRAIT);
            KeyboardSizeSettings.Size portrait = KeyboardSizeSettings.size(context, false);
            assertTrue(portrait.bottomGapDp() > 0);
            assertFalse(preferences.contains(KeyboardSizeSettings.KEY_LANDSCAPE_SCALE));

            Activity reopened = openResizeControls(settings);
            assertEquals(raisedTop.centerY(), resizeBounds(reopened, "拖曳鍵盤上緣").centerY(), 2);
            assertEquals(raisedBottom.centerY(), resizeBounds(reopened, "拖曳鍵盤下緣").centerY(), 2);
            clickResizeControl(reopened, "恢復預設");
            clickResizeControl(reopened, "取消");
            assertEquals(portrait, KeyboardSizeSettings.size(context, false));
            settings = awaitActivity(SettingsActivity.class, Configuration.ORIENTATION_PORTRAIT);

            Activity rotating = openResizeControls(settings);
            clickResizeControl(rotating, "恢復預設");
            instrumentation.runOnMainSync(() ->
                    rotating.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE));
            Activity landscapeEditor = awaitActivity(KeyboardResizeActivity.class,
                    Configuration.ORIENTATION_LANDSCAPE);
            awaitResizeControls(landscapeEditor);
            instrumentation.runOnMainSync(() -> {
                BopomofoKeyboardView keyboard = resizeKeyboard(landscapeEditor);
                assertEquals(BopomofoKeyboardView.Mode.LANDSCAPE, keyboard.mode());
                assertEquals(Math.round(keyboard.defaultTouchHeight() * .9f),
                        keyboard.visibleTouchEdges().contentHeight());
            });
            Rect landscapeTop = resizeBounds(landscapeEditor, "拖曳鍵盤上緣");
            Rect landscapeBottom = resizeBounds(landscapeEditor, "拖曳鍵盤下緣");
            dragResizeHandle(landscapeEditor, landscapeBottom, -distance, () -> {
                awaitResizeEdge(landscapeEditor, "拖曳鍵盤下緣", landscapeBottom.centerY() - distance / 2);
                assertEquals(landscapeTop.centerY(), resizeBounds(landscapeEditor, "拖曳鍵盤上緣").centerY(), 2);
            });
            clickResizeControl(landscapeEditor, "完成");
            assertTrue(KeyboardSizeSettings.size(context, true).bottomGapDp() > 0);
            assertEquals(portrait, KeyboardSizeSettings.size(context, false));
        } finally {
            if (settings != null) {
                Activity current = settings;
                instrumentation.runOnMainSync(() -> {
                    for (Activity activity : List.copyOf(ActivityLifecycleMonitorRegistry.getInstance()
                            .getActivitiesInStage(Stage.RESUMED))) {
                        if (activity instanceof KeyboardResizeActivity || activity instanceof SettingsActivity) {
                            activity.finish();
                        }
                    }
                    current.finish();
                });
            }
            SharedPreferences.Editor restore = preferences.edit();
            for (String key : keys) {
                restore.remove(key);
                if (previous.get(key) instanceof Integer value) restore.putInt(key, value);
                if (previous.get(key) instanceof Float value) restore.putFloat(key, value);
            }
            restore.commit();
        }
    }

    @Test
    public void keyboardSettingsKeyOpensSettingsDirectly() throws Exception {
        org.junit.Assume.assumeTrue(Build.VERSION.SDK_INT >= 30);
        org.junit.Assume.assumeTrue("Use a disposable emulator with KeyKey selected",
                "true".equals(InstrumentationRegistry.getArguments().getString("keykey.isolatedDevice")));
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        Activity host = instrumentation.startActivitySync(new Intent()
                .setClassName(context, "tw.chichi77.keykey.android.ImeTestActivity")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        Activity settings = null;
        try {
            IntegratedBottomControlsInstrumentedTest.showEditorKeyboard(host, context);
            assertTrue(awaitImeHeight(host, -1) > 0);
            instrumentation.runOnMainSync(() -> {
                BopomofoKeyboardView keyboard = IntegratedBottomControlsInstrumentedTest.findKeyboard();
                assertTrue(keyboard.isTouchMode());
                ((BopomofoImeService) keyboard.getContext()).onKey("SETTINGS");
            });
            settings = awaitActivity(SettingsActivity.class, host.getResources().getConfiguration().orientation);
        } finally {
            Activity current = settings;
            instrumentation.runOnMainSync(() -> {
                if (current != null) current.finish();
                host.finish();
            });
        }
    }

    private static Activity awaitActivity(Class<? extends Activity> type, int orientation) throws Exception {
        Activity[] result = {null};
        IntegratedBottomControlsInstrumentedTest.await(() -> {
            for (Activity activity : ActivityLifecycleMonitorRegistry.getInstance()
                    .getActivitiesInStage(Stage.RESUMED)) {
                if (type.isInstance(activity)
                        && activity.getResources().getConfiguration().orientation == orientation) {
                    result[0] = activity;
                    return true;
                }
            }
            return false;
        });
        return result[0];
    }

    private static Activity openResizeControls(Activity settings) throws Exception {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            LinearLayout appearance = findGroup(settingsPage(settings), "外觀與操作");
            View body = appearance.getChildAt(1);
            if (body.getVisibility() != View.VISIBLE) appearance.getChildAt(0).performClick();
            View entry = findResizeControl(body, "調整鍵盤高度");
            assertNotNull(entry);
            assertTrue(entry.performClick());
        });
        Activity editor = awaitActivity(KeyboardResizeActivity.class,
                settings.getResources().getConfiguration().orientation);
        awaitResizeControls(editor);
        return editor;
    }

    private static void awaitResizeControls(Activity editor) throws Exception {
        IntegratedBottomControlsInstrumentedTest.await(() -> {
            View handle = findResizeControl(editor, "拖曳鍵盤下緣");
            return handle != null && handle.getWidth() > 0;
        });
    }

    private static void awaitResizeEdge(Activity editor, String label, int maximumY) throws Exception {
        IntegratedBottomControlsInstrumentedTest.await(() ->
                boundsOf(findResizeControl(editor, label)).centerY() <= maximumY);
    }

    private static void clickResizeControl(Activity editor, String title) {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() ->
                assertTrue("Could not activate " + title, findResizeControl(editor, title).performClick()));
    }

    private static Rect resizeBounds(Activity editor, String label) {
        Rect[] result = {null};
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() ->
                result[0] = boundsOf(findResizeControl(editor, label)));
        return result[0];
    }

    private static Rect boundsOf(View view) {
        int[] origin = new int[2];
        view.getLocationOnScreen(origin);
        return new Rect(origin[0], origin[1], origin[0] + view.getWidth(), origin[1] + view.getHeight());
    }

    private static View findResizeControl(Activity editor, String label) {
        return findResizeControl(editor.findViewById(android.R.id.content), label);
    }

    private static BopomofoKeyboardView resizeKeyboard(Activity editor) {
        ViewGroup content = editor.findViewById(android.R.id.content);
        LinearLayout page = (LinearLayout) content.getChildAt(0);
        return ((KeyboardResizeView) page.getChildAt(1)).keyboard;
    }

    private static View findResizeControl(View view, String label) {
        if (!view.isShown()) return null;
        if (label.contentEquals(view.getContentDescription() == null ? "" : view.getContentDescription())
                || view instanceof TextView text && label.contentEquals(text.getText())) return view;
        if (view instanceof ViewGroup group) {
            for (int i = 0; i < group.getChildCount(); i++) {
                View match = findResizeControl(group.getChildAt(i), label);
                if (match != null) return match;
            }
        }
        return null;
    }

    @FunctionalInterface
    private interface WhileDragging {
        void verify() throws Exception;
    }

    private static void dragResizeHandle(Activity editor, Rect handle, int distance, WhileDragging verify) throws Exception {
        long down = SystemClock.uptimeMillis();
        float x = handle.centerX();
        float y = handle.centerY();
        assertResizeKeycapsVisible(editor, true);
        sendResizeTouch(down, MotionEvent.ACTION_DOWN, x, y);
        try {
            sendResizeTouch(down, MotionEvent.ACTION_MOVE, x, y + distance);
            InstrumentationRegistry.getInstrumentation().waitForIdleSync();
            assertResizeKeycapsVisible(editor, false);
            verify.verify();
        } finally {
            sendResizeTouch(down, MotionEvent.ACTION_UP, x, y + distance);
        }
        assertResizeKeycapsVisible(editor, true);
    }

    private static void assertResizeKeycapsVisible(Activity editor, boolean expected) {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            var keyboard = resizeKeyboard(editor);
            boolean[] drew = new boolean[2];
            keyboard.draw(new Canvas() {
                @Override public void drawRoundRect(RectF bounds, float rx, float ry, Paint paint) {
                    drew[0] = true;
                }
                @Override public void drawText(String text, float x, float y, Paint paint) {
                    drew[1] = true;
                }
            });
            assertEquals("Keycaps must only be hidden during a drag", expected, drew[0]);
            assertEquals("Key labels must only be hidden during a drag", expected, drew[1]);
        });
    }

    private static void sendResizeTouch(long down, int action, float x, float y) {
        MotionEvent event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, x, y, 0);
        event.setSource(InputDevice.SOURCE_TOUCHSCREEN);
        try {
            assertTrue(InstrumentationRegistry.getInstrumentation().getUiAutomation()
                    .injectInputEvent(event, true));
        } finally {
            event.recycle();
        }
    }

    private static Activity awaitPortraitHost() throws InterruptedException {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        long deadline = SystemClock.uptimeMillis() + 10000;
        do {
            Activity[] result = {null};
            instrumentation.runOnMainSync(() -> {
                for (Activity activity : androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
                        .getInstance().getActivitiesInStage(androidx.test.runner.lifecycle.Stage.RESUMED)) {
                    if (activity.getClass().getSimpleName().equals("ImeTestActivity")
                            && activity.getResources().getConfiguration().orientation
                                    == Configuration.ORIENTATION_PORTRAIT) result[0] = activity;
                }
            });
            if (result[0] != null) return result[0];
            Thread.sleep(100);
        } while (SystemClock.uptimeMillis() < deadline);
        throw new AssertionError("Portrait test host did not resume");
    }

    private static int awaitImeHeight(Activity host, int expected) throws InterruptedException {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        int[] height = {0};
        long deadline = SystemClock.uptimeMillis() + 10000;
        int previous = -1;
        int stable = 0;
        do {
            instrumentation.runOnMainSync(() -> {
                WindowInsets insets = host.getWindow().getDecorView().getRootWindowInsets();
                height[0] = insets == null ? 0 : insets.getInsets(WindowInsets.Type.ime()).bottom;
            });
            boolean matches = expected < 0 ? height[0] > 0 : height[0] == expected;
            stable = matches && height[0] == previous ? stable + 1 : 0;
            if (stable >= 3) return height[0];
            previous = height[0];
            Thread.sleep(100);
        } while (SystemClock.uptimeMillis() < deadline);
        return height[0];
    }

    private static EditText findEditor(View root) {
        if (root instanceof EditText editor) return editor;
        if (root instanceof ViewGroup group) {
            for (int index = 0; index < group.getChildCount(); index++) {
                EditText editor = findEditor(group.getChildAt(index));
                if (editor != null) return editor;
            }
        }
        return null;
    }

    private static void verifyContentUnchanged(BopomofoKeyboardView view, int padding, boolean touch) {
        view.setBottomSpaceEnabled(true, true);
        Bitmap reserved = render(view);
        view.setBottomSpaceEnabled(touch, !touch);
        assertEquals(reserved.getHeight(), render(view).getHeight()); // The other mode is independent.
        view.setBottomSpaceEnabled(!touch, touch);
        Bitmap flush = render(view);
        assertEquals(padding, reserved.getHeight() - flush.getHeight());
        Bitmap content = Bitmap.createBitmap(reserved, 0, 0, flush.getWidth(), flush.getHeight());
        assertTrue("Bottom-space toggle changed rendered keys or candidates", flush.sameAs(content));
    }

    private static Bitmap render(BopomofoKeyboardView view) {
        return render(view, View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED));
    }

    private static Bitmap render(BopomofoKeyboardView view, int heightMeasureSpec) {
        int availableWidth = view.getResources().getDisplayMetrics().widthPixels;
        view.measure(View.MeasureSpec.makeMeasureSpec(availableWidth, View.MeasureSpec.EXACTLY), heightMeasureSpec);
        view.layout(0, 0, view.getMeasuredWidth(), view.getMeasuredHeight());
        Bitmap bitmap = Bitmap.createBitmap(view.getWidth(), view.getHeight(), Bitmap.Config.ARGB_8888);
        view.draw(new Canvas(bitmap));
        return bitmap;
    }

    private static Activity openSettings(Context context) {
        return InstrumentationRegistry.getInstrumentation().startActivitySync(new Intent(context,
                SettingsActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
    }

    private static LinearLayout settingsPage(Activity activity) {
        ViewGroup root = activity.findViewById(android.R.id.content);
        return (LinearLayout) ((ScrollView) root.getChildAt(0)).getChildAt(0);
    }

    private static LinearLayout findGroup(LinearLayout page, String title) {
        for (int i = 0; i < page.getChildCount(); i++) {
            if (page.getChildAt(i) instanceof LinearLayout group && group.getChildCount() == 2) {
                CharSequence description = group.getChildAt(0).getContentDescription();
                if (description != null && description.toString().contains(title)) return group;
            }
        }
        throw new AssertionError("Missing group: " + title);
    }

    private static CheckBox findCheck(View root, String label) {
        if (root instanceof CheckBox check && check.getText().toString().equals(label)) return check;
        if (root instanceof ViewGroup group) {
            for (int i = 0; i < group.getChildCount(); i++) {
                CheckBox check = findCheck(group.getChildAt(i), label);
                if (check != null) return check;
            }
        }
        return null;
    }

    private static void touch(View view) {
        long time = SystemClock.uptimeMillis();
        MotionEvent down = MotionEvent.obtain(time, time, MotionEvent.ACTION_DOWN, 10, 10, 0);
        MotionEvent up = MotionEvent.obtain(time, time + 10, MotionEvent.ACTION_UP, 10, 10, 0);
        view.dispatchTouchEvent(down);
        view.dispatchTouchEvent(up);
        down.recycle();
        up.recycle();
    }
}
