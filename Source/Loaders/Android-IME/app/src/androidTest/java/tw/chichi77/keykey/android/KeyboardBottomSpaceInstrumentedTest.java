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
    public void bottomSpaceSettingAppliesOnlyToHardwareAndFloatingDisablesIt() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        SharedPreferences preferences = CandidateWindowSettings.preferences(context);
        String[] keys = {KeyboardBottomSpaceSettings.KEY_HARDWARE_ENABLED,
                CandidateWindowSettings.KEY_FLOATING_ENABLED, CandidateWindowSettings.KEY_NUMBER_ROW,
                KeyboardBottomControlsSettings.KEY_ENABLED};
        Map<String, ?> previous = preferences.getAll();
        Activity activity = null;
        try {
            preferences.edit().remove(keys[0]).putBoolean(keys[1], false)
                    .putBoolean(keys[2], true).remove(keys[3]).commit();
            assertFalse(KeyboardBottomControlsSettings.enabled(context));
            assertTrue(KeyboardBottomSpaceSettings.hardwareEnabled(context));
            activity = openSettings(context);
            Activity current = activity;
            instrumentation.runOnMainSync(() -> {
                LinearLayout page = settingsPage(current);
                LinearLayout appearance = findGroup(page, "外觀與操作");
                LinearLayout hardware = findGroup(page, "實體鍵盤");
                appearance.getChildAt(0).performClick();
                hardware.getChildAt(0).performClick();
                assertNull("Touch bottom space is determined automatically",
                        findCheck(appearance.getChildAt(1), "預留底部切換語言空間"));
                CheckBox integrated = findCheck(appearance.getChildAt(1),
                        context.getString(R.string.integrated_bottom_controls_enabled));
                CheckBox hardwareSpace = findCheck(hardware.getChildAt(1), "預留底部切換語言空間");
                CheckBox floating = findCheck(hardware.getChildAt(1), "使用浮動候選字窗");
                CheckBox numbers = findCheck(hardware.getChildAt(1), "顯示虛擬數字與符號鍵");
                assertNotNull(integrated);
                assertFalse(integrated.isChecked());
                assertTrue(hardwareSpace.isChecked());
                integrated.performClick();
                assertTrue(KeyboardBottomControlsSettings.enabled(context));
                assertTrue(hardwareSpace.isEnabled());
                assertTrue(KeyboardBottomSpaceSettings.hardwareEnabled(context));
                hardwareSpace.performClick();
                assertFalse(KeyboardBottomSpaceSettings.hardwareEnabled(context));
                assertTrue(numbers.isChecked());
                floating.performClick();
                assertFalse(hardwareSpace.isEnabled());
                assertFalse(numbers.isEnabled());
                assertTrue(hardwareSpace.getAlpha() < 1f);
                assertTrue(numbers.getAlpha() < 1f);
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
                current.finish();
            });
            activity = openSettings(context);
            Activity reopened = activity;
            instrumentation.runOnMainSync(() -> {
                LinearLayout page = settingsPage(reopened);
                var appearance = findGroup(page, "外觀與操作");
                var hardware = findGroup(page, "實體鍵盤");
                CheckBox integrated = findCheck(appearance.getChildAt(1),
                        context.getString(R.string.integrated_bottom_controls_enabled));
                CheckBox hardwareSpace = findCheck(hardware.getChildAt(1), "預留底部切換語言空間");
                assertTrue(integrated.isChecked());
                assertFalse(hardwareSpace.isChecked());
                assertTrue(hardwareSpace.isEnabled());
                integrated.performClick();
                assertFalse(KeyboardBottomControlsSettings.enabled(context));
                assertFalse(KeyboardBottomSpaceSettings.hardwareEnabled(context));
                assertTrue(findCheck(hardware.getChildAt(1), "顯示虛擬數字與符號鍵").isChecked());
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
                if (previous.get(key) instanceof Boolean bool) restore.putBoolean(key, bool);
            }
            restore.commit();
        }
    }

    @Test
    public void keyboardWithoutSystemInsetsHasNoTouchReserveAndHardwarePaddingRemainsIndependent() {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            Context base = InstrumentationRegistry.getInstrumentation().getTargetContext();
            for (int orientation : new int[]{Configuration.ORIENTATION_PORTRAIT,
                    Configuration.ORIENTATION_LANDSCAPE}) {
                Configuration configuration = new Configuration(base.getResources().getConfiguration());
                configuration.orientation = orientation;
                Context context = base.createConfigurationContext(configuration);
                BopomofoKeyboardView view = new BopomofoKeyboardView(context);
                view.setMode(orientation == Configuration.ORIENTATION_PORTRAIT
                        ? BopomofoKeyboardView.Mode.PORTRAIT : BopomofoKeyboardView.Mode.LANDSCAPE);
                for (int percent : new int[]{50, 100, 200}) {
                    view.setTouchKeyboardHeightPercents(percent, percent);
                    for (boolean integrated : new boolean[]{false, true}) {
                        view.setIntegratedBottomControls(integrated, integrated);
                        int expectedHeight = Math.round(view.defaultTouchHeight() * percent / 100f);
                        view.setHardwareBottomSpaceEnabled(true);
                        Bitmap original = render(view);
                        assertEquals("Touch without a system inset uses only its keyboard height",
                                expectedHeight, original.getHeight());
                        view.setHardwareBottomSpaceEnabled(false);
                        assertTrue("The hardware setting must not move any touch keys",
                                original.sameAs(render(view)));
                    }
                }
                float density = context.getResources().getDisplayMetrics().density;
                int hardwarePadding = Math.round((orientation == Configuration.ORIENTATION_PORTRAIT ? 40 : 35)
                        * density);
                view.setMode(BopomofoKeyboardView.Mode.HARDWARE);
                for (boolean numberRows : new boolean[]{false, true}) {
                    view.setHardwareNumberRowEnabled(numberRows);
                    verifyHardwareContentUnchanged(view, hardwarePadding,
                            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED));
                }
                verifyHardwareContentUnchanged(view, hardwarePadding,
                        View.MeasureSpec.makeMeasureSpec(Math.round(170 * density), View.MeasureSpec.AT_MOST));
                view.setMode(BopomofoKeyboardView.Mode.HARDWARE_FLOATING);
                view.setHardwareBottomSpaceEnabled(true);
                int floatingHeight = render(view).getHeight();
                view.setHardwareBottomSpaceEnabled(false);
                assertEquals(floatingHeight, render(view).getHeight());
            }
        });
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
            var profile = KeyboardLayoutProfile.ALIGNED;
            for (int percent : new int[]{100, 50, 200}) {
                for (boolean integrated : new boolean[]{true, false}) {
                    var keyboard = new BopomofoKeyboardView(context);
                    keyboard.setMode(BopomofoKeyboardView.Mode.LANDSCAPE);
                    keyboard.setLayoutProfile(profile);
                    keyboard.setTouchKeyboardHeightPercents(percent, percent);
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
                    assertEquals(sample + ": real cap", Math.min(wanted, realCap), keyboard.getMeasuredHeight());
                    assertTrue(sample, keyboard.getMeasuredHeight() <= realCap);
                    for (RectF key : drawnMainKeys(keyboard, integrated).mainKeys()) {
                        assertTrue(sample + ": content must stay inside the capped child", key.bottom <= keyboard.getHeight());
                    }
                }
            }
        });
    }

    @Test
    public void touchInsetsUseOnlyTheLargerVisibleBottomAreaAndKeepCappedContentSafe() {
        org.junit.Assume.assumeTrue(Build.VERSION.SDK_INT >= 30);
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        instrumentation.runOnMainSync(() -> {
            Context context = instrumentation.getTargetContext();
            float density = context.getResources().getDisplayMetrics().density;
            int width = context.getResources().getDisplayMetrics().widthPixels;
            int cap = Math.round(800 * density);
            for (boolean integrated : new boolean[]{false, true}) {
                var keyboard = new BopomofoKeyboardView(context);
                keyboard.setMode(BopomofoKeyboardView.Mode.LANDSCAPE);
                keyboard.setLayoutProfile(KeyboardLayoutProfile.ALIGNED);
                keyboard.setIntegratedBottomControls(integrated, false);
                var window = new KeyboardInputView(context, keyboard);
                measureWindow(window, width, cap, View.MeasureSpec.AT_MOST);
                KeyboardContent original = drawnMainKeys(keyboard, integrated);
                for (int[] sample : new int[][]{{24, 0}, {24, 48}, {64, 48}, {0, 0}}) {
                    int nav = Math.round(sample[0] * density);
                    int caption = Build.VERSION.SDK_INT >= 36 ? Math.round(sample[1] * density) : 0;
                    int reserved = Math.max(nav, caption);
                    WindowInsets.Builder insets = new WindowInsets.Builder()
                            .setInsets(WindowInsets.Type.navigationBars(), Insets.of(0, 0, 0, nav))
                            .setVisible(WindowInsets.Type.navigationBars(), nav > 0);
                    if (Build.VERSION.SDK_INT >= 36) {
                        insets.setInsets(WindowInsets.Type.captionBar(), Insets.of(0, 0, 0, caption))
                                .setVisible(WindowInsets.Type.captionBar(), caption > 0);
                    }
                    window.dispatchApplyWindowInsets(insets.build());
                    int oldWindowHeight = window.getMeasuredHeight();
                    measureWindow(window, width, oldWindowHeight, View.MeasureSpec.EXACTLY);
                    for (RectF key : drawnMainKeys(keyboard, integrated).mainKeys()) {
                        assertTrue("Keys must clear the bottom inset in the old window",
                                key.bottom <= keyboard.getHeight() - reserved);
                    }
                    measureWindow(window, width, cap, View.MeasureSpec.AT_MOST);
                    KeyboardContent current = drawnMainKeys(keyboard, integrated);
                    assertEquals("The bottom sources overlap, so they must not be added",
                            original.totalHeight() + reserved, current.totalHeight());
                    assertEquals("The requested height must restore the intended content",
                            original.mainKeys(), current.mainKeys());
                    int realCap = Math.round(180 * density);
                    measureWindow(window, width, realCap, View.MeasureSpec.AT_MOST);
                    assertTrue(keyboard.getHeight() <= realCap);
                    for (RectF key : drawnMainKeys(keyboard, integrated).mainKeys()) {
                        assertTrue("Keys must clear the bottom inset even with a small cap",
                                key.bottom <= keyboard.getHeight() - reserved);
                    }
                    // Give the next sample the same real upstream budget.
                    measureWindow(window, width, cap, View.MeasureSpec.AT_MOST);
                }
                assertEquals(original.totalHeight(), keyboard.getHeight());
            }
        });
    }

    @Test
    public void integratedControlsToggleKeepsContentStableUnderParentFeedbackAndRealCaps() {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
            float density = context.getResources().getDisplayMetrics().density;
            verifyIntegratedWindowFeedback(context, 100, Math.round(800 * density));
            verifyIntegratedWindowFeedback(context, 200, Math.round(300 * density));
        });
    }

    private static void verifyIntegratedWindowFeedback(Context context, int percent, int availableHeight) {
        var keyboard = new BopomofoKeyboardView(context);
        keyboard.setMode(BopomofoKeyboardView.Mode.PORTRAIT);
        keyboard.setLayoutProfile(KeyboardLayoutProfile.ALIGNED);
        keyboard.setTouchKeyboardHeightPercents(percent, percent);
        keyboard.setIntegratedBottomControls(true, false);
        var window = new KeyboardInputView(context, keyboard);
        int width = context.getResources().getDisplayMetrics().widthPixels;
        String sample = "height=" + percent + "%/cap=" + availableHeight;
        measureWindow(window, width, availableHeight, View.MeasureSpec.AT_MOST);
        KeyboardContent original = drawnMainKeys(keyboard, true);
        assertFalse(sample, original.mainKeys().isEmpty());
        assertEquals(sample, Math.min(availableHeight, Math.round(keyboard.defaultTouchHeight() * percent / 100f)),
                original.totalHeight());
        for (boolean integrated : new boolean[]{false, true, false}) {
            keyboard.setIntegratedBottomControls(integrated, false);
            // Match Android's exact feedback pass before it next provides a real upstream budget.
            measureWindow(window, width, window.getMeasuredHeight(), View.MeasureSpec.EXACTLY);
            assertEquals(sample, original, drawnMainKeys(keyboard, integrated));
            measureWindow(window, width, availableHeight, View.MeasureSpec.AT_MOST);
            assertEquals(sample, original, drawnMainKeys(keyboard, integrated));
            assertEquals(sample, keyboard.getHeight(), window.getHeight());
            assertEquals(sample, window.getHeight(), keyboard.getBottom());
        }
    }

    @Test
    public void touchKeyboardPaintsToItsLaidOutHeightAfterAShorterMeasureProbe() {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            Context base = InstrumentationRegistry.getInstrumentation().getTargetContext();
            Configuration configuration = new Configuration(base.getResources().getConfiguration());
            configuration.orientation = Configuration.ORIENTATION_PORTRAIT;
            configuration.densityDpi = 420;
            Context context = base.createConfigurationContext(configuration);
            float density = context.getResources().getDisplayMetrics().density;
            int caption = Math.round(48 * density);
            int shorterBy = Math.round(24 * density);
            int keyMargin = Math.round(2 * density);
            int width = 1080;
            int widthSpec = View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY);

            for (float gapDp : new float[]{0f, 16f}) {
                var keyboard = new BopomofoKeyboardView(context);
                keyboard.setMode(BopomofoKeyboardView.Mode.PORTRAIT);
                keyboard.setLayoutProfile(KeyboardLayoutProfile.ALIGNED);
                keyboard.setLayoutOptions(KeyboardLayoutProfile.KeycapArea.SMALL,
                        KeyboardLayoutProfile.FontSize.NORMAL, KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER);
                keyboard.setSystemBottomInset(caption);
                keyboard.setTouchKeyboardSizes(new KeyboardSizeSettings.Size(1f, gapDp),
                        KeyboardSizeSettings.DEFAULT_SIZE);
                int desiredContent = keyboard.defaultTouchHeight();
                int gap = Math.round(gapDp * density);
                int laidOutHeight = desiredContent + gap + caption;
                int probeHeight = laidOutHeight - shorterBy;
                var expected = new KeyboardEdgeGeometry(desiredContent + gap, gap);
                String sample = "Custom gap: " + gapDp + " dp";

                keyboard.measure(widthSpec, View.MeasureSpec.makeMeasureSpec(laidOutHeight, View.MeasureSpec.AT_MOST));
                keyboard.layout(0, 0, width, laidOutHeight);
                assertEquals(sample, expected, keyboard.visibleTouchEdges());
                assertEquals(sample, desiredContent - keyMargin, lastPaintedKeyBottom(keyboard), 1f);

                // Pixel can measure at the old height while its last screen layout is still full.
                keyboard.measure(widthSpec, View.MeasureSpec.makeMeasureSpec(probeHeight, View.MeasureSpec.AT_MOST));
                assertEquals(sample, probeHeight, keyboard.getMeasuredHeight());
                assertEquals(sample, laidOutHeight, keyboard.getHeight());
                assertEquals(sample, expected, keyboard.visibleTouchEdges());
                assertEquals(sample, desiredContent - keyMargin, lastPaintedKeyBottom(keyboard), 1f);

                // Only a truly shorter layout reduces the space for keys.
                keyboard.layout(0, 0, width, probeHeight);
                int smallerContent = desiredContent - shorterBy;
                assertEquals(sample, new KeyboardEdgeGeometry(smallerContent + gap, gap), keyboard.visibleTouchEdges());
                assertEquals(sample, smallerContent - keyMargin, lastPaintedKeyBottom(keyboard), 1f);
            }
        });
    }

    private static float lastPaintedKeyBottom(BopomofoKeyboardView keyboard) {
        float[] bottom = {0};
        keyboard.draw(new Canvas() {
            @Override public void drawRoundRect(RectF bounds, float rx, float ry, Paint paint) {
                bottom[0] = Math.max(bottom[0], bounds.bottom);
            }
        });
        return bottom[0];
    }

    private static void measureWindow(FrameLayout window, int width, int height, int heightMode) {
        window.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(height, heightMode));
        window.layout(0, 0, window.getMeasuredWidth(), window.getMeasuredHeight());
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
    public void liveInputMethodRetainsTheCustomBottomGapAcrossReopen() throws Exception {
        org.junit.Assume.assumeTrue(Build.VERSION.SDK_INT >= 30);
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        SharedPreferences preferences = CandidateWindowSettings.preferences(context);
        Map<String, ?> previous = preferences.getAll();
        String[] keys = {KeyboardSizeSettings.KEY_PORTRAIT_SCALE, KeyboardSizeSettings.KEY_PORTRAIT_GAP,
                KeyboardBottomControlsSettings.KEY_ENABLED};
        Activity activity = null;
        var geometry = new ArrayList<String>();
        try {
            preferences.edit().putFloat(keys[0], 1f).putFloat(keys[1], 0f).putBoolean(keys[2], false).commit();
            activity = instrumentation.startActivitySync(new Intent()
                    .setClassName(context, "tw.chichi77.keykey.android.ImeTestActivity")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
            Activity initial = activity;
            instrumentation.runOnMainSync(() ->
                    initial.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT));
            rotateDisplayTo(context, Configuration.ORIENTATION_PORTRAIT);
            // Rotation can recreate the host. Read insets from the resumed window.
            activity = awaitPortraitHost();
            Activity host = activity;
            instrumentation.runOnMainSync(() -> {
                EditText editor = findEditor(host.findViewById(android.R.id.content));
                assertNotNull(editor);
                editor.requestFocus();
                context.getSystemService(InputMethodManager.class)
                        .showSoftInput(editor, InputMethodManager.SHOW_IMPLICIT);
            });
            IntegratedBottomControlsInstrumentedTest.showEditorKeyboard(host, context);
            IntegratedBottomControlsInstrumentedTest.await(() -> {
                var keyboard = IntegratedBottomControlsInstrumentedTest.findKeyboard();
                return keyboard != null && keyboard.mode() == BopomofoKeyboardView.Mode.PORTRAIT
                        && keyboard.getResources().getConfiguration().orientation == Configuration.ORIENTATION_PORTRAIT
                        && host.getResources().getConfiguration().orientation == Configuration.ORIENTATION_PORTRAIT;
            });
            int flush = awaitImeHeight(host, -1);
            assertTrue("IME never opened", flush > 0);
            geometry.add("initial: " + hostGeometry(host));
            Thread.sleep(500);
            geometry.add("initial+500ms: " + hostGeometry(host));
            Thread.sleep(1000);
            flush = awaitImeHeight(host, -1);
            String before = hostGeometry(host);
            geometry.add("before+1500ms: " + before);
            captureGapEvidence(context, "settled-before-custom-gap");
            float gapDp = 22f;
            int gap = Math.round(gapDp * context.getResources().getDisplayMetrics().density);
            instrumentation.runOnMainSync(() ->
                    KeyboardSizeSettings.setSize(context, false, new KeyboardSizeSettings.Size(1f, gapDp)));
            int custom = awaitImeHeight(host, flush + gap);
            String after = hostGeometry(host);
            geometry.add("after: " + after);
            captureGapEvidence(context, "after-custom-gap");
            assertEquals("Setting a custom gap must add exactly that much to the window; before="
                    + before + "; after=" + after, gap, custom - flush);
            instrumentation.runOnMainSync(() -> context.getSystemService(InputMethodManager.class)
                    .hideSoftInputFromWindow(host.getWindow().getDecorView().getWindowToken(), 0));
            assertEquals(0, awaitImeHeight(host, 0));
            instrumentation.runOnMainSync(() -> context.getSystemService(InputMethodManager.class)
                    .showSoftInput(findEditor(host.findViewById(android.R.id.content)), InputMethodManager.SHOW_IMPLICIT));
            assertEquals("Reopening must preserve the saved custom gap", custom, awaitImeHeight(host, custom));
            instrumentation.runOnMainSync(() ->
                    KeyboardSizeSettings.setSize(context, false, KeyboardSizeSettings.DEFAULT_SIZE));
            assertEquals(flush, awaitImeHeight(host, flush));
        } finally {
            if (activity != null) {
                Activity host = activity;
                instrumentation.runOnMainSync(host::finish);
            }
            SharedPreferences.Editor restore = preferences.edit();
            for (String key : keys) {
                restore.remove(key);
                if (previous.get(key) instanceof Boolean value) restore.putBoolean(key, value);
                else if (previous.get(key) instanceof Float value) restore.putFloat(key, value);
            }
            restore.commit();
            android.os.Bundle status = new android.os.Bundle();
            status.putStringArrayList("keykey_live_bottom_gap_geometry", geometry);
            instrumentation.sendStatus(0, status);
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
            rotateDisplayTo(context, Configuration.ORIENTATION_PORTRAIT);
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
            rotateDisplayTo(context, Configuration.ORIENTATION_LANDSCAPE);
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
    public void nonFiniteResizeCoordinatesPreserveTheLastValidHeightAndEndDragging() throws Exception {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        var preferences = CandidateWindowSettings.preferences(context);
        String[] keys = {KeyboardSizeSettings.KEY_PORTRAIT_PERCENT, KeyboardSizeSettings.KEY_LANDSCAPE_PERCENT,
                KeyboardSizeSettings.KEY_PORTRAIT_SCALE, KeyboardSizeSettings.KEY_LANDSCAPE_SCALE,
                KeyboardSizeSettings.KEY_PORTRAIT_GAP, KeyboardSizeSettings.KEY_LANDSCAPE_GAP};
        Map<String, ?> previous = preferences.getAll();
        Activity[] activities = {null, null};
        try {
            var reset = preferences.edit();
            for (String key : keys) reset.remove(key);
            reset.commit();
            activities[0] = openSettings(context);
            activities[1] = openResizeControls(activities[0]);
            Activity editor = activities[1];
            int distance = Math.round(20 * context.getResources().getDisplayMetrics().density);
            instrumentation.runOnMainSync(() -> {
                var keyboard = resizeKeyboard(editor);
                View handle = findResizeControl(editor, "拖曳鍵盤下緣");
                var initial = keyboard.visibleTouchEdges();
                for (float invalid : new float[]{Float.NaN, Float.POSITIVE_INFINITY, Float.NEGATIVE_INFINITY}) {
                    long time = SystemClock.uptimeMillis();
                    dispatchResizeTouch(handle, time, MotionEvent.ACTION_DOWN, invalid);
                    assertEquals(initial, keyboard.visibleTouchEdges());
                    assertResizePaint(keyboard, true);
                    dispatchResizeTouch(handle, time, MotionEvent.ACTION_CANCEL, invalid);
                }
                KeyboardEdgeGeometry lastValid = initial;
                for (float invalidUp : new float[]{Float.NaN, Float.POSITIVE_INFINITY}) {
                    findResizeControl(editor, "恢復預設").performClick();
                    float startY = boundsOf(handle).centerY();
                    long time = SystemClock.uptimeMillis();
                    dispatchResizeTouch(handle, time, MotionEvent.ACTION_DOWN, startY);
                    dispatchResizeTouch(handle, time, MotionEvent.ACTION_MOVE, startY - distance);
                    lastValid = keyboard.visibleTouchEdges();
                    assertEquals(distance, lastValid.bottom());
                    for (float invalid : new float[]{Float.NaN, Float.NEGATIVE_INFINITY}) {
                        dispatchResizeTouch(handle, time, MotionEvent.ACTION_MOVE, invalid);
                        assertEquals(lastValid, keyboard.visibleTouchEdges());
                    }
                    assertResizePaint(keyboard, false);
                    dispatchResizeTouch(handle, time, MotionEvent.ACTION_UP, invalidUp);
                    assertEquals(lastValid, keyboard.visibleTouchEdges());
                    assertResizePaint(keyboard, true);
                }
                float startY = boundsOf(handle).centerY();
                long time = SystemClock.uptimeMillis();
                dispatchResizeTouch(handle, time, MotionEvent.ACTION_DOWN, startY);
                dispatchResizeTouch(handle, time, MotionEvent.ACTION_MOVE, startY - distance);
                assertEquals(lastValid.bottom() + distance, keyboard.visibleTouchEdges().bottom());
                dispatchResizeTouch(handle, time, MotionEvent.ACTION_CANCEL, Float.NaN);
                assertEquals(lastValid, keyboard.visibleTouchEdges());
                assertResizePaint(keyboard, true);
                boolean landscape = keyboard.mode() == BopomofoKeyboardView.Mode.LANDSCAPE;
                assertTrue(findResizeControl(editor, "完成").performClick());
                assertEquals(distance / context.getResources().getDisplayMetrics().density,
                        KeyboardSizeSettings.size(context, landscape).bottomGapDp(), .001f);
                assertEquals(KeyboardSizeSettings.DEFAULT_SIZE, KeyboardSizeSettings.size(context, !landscape));
            });
        } finally {
            instrumentation.runOnMainSync(() -> {
                for (Activity activity : activities) if (activity != null) activity.finish();
            });
            var restore = preferences.edit();
            for (String key : keys) {
                restore.remove(key);
                if (previous.get(key) instanceof Integer value) restore.putInt(key, value);
                else if (previous.get(key) instanceof Float value) restore.putFloat(key, value);
            }
            restore.commit();
        }
    }

    private static void dispatchResizeTouch(View handle, long down, int action, float screenY) {
        int[] location = new int[2];
        handle.getLocationOnScreen(location);
        MotionEvent event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action,
                location[0] + handle.getWidth() / 2f, screenY, 0);
        event.setSource(InputDevice.SOURCE_TOUCHSCREEN);
        event.offsetLocation(-location[0], -location[1]);
        try { assertTrue(handle.dispatchTouchEvent(event)); }
        finally { event.recycle(); }
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
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
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
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() ->
                assertResizePaint(resizeKeyboard(editor), expected));
    }

    private static void assertResizePaint(BopomofoKeyboardView keyboard, boolean expected) {
        boolean[] drew = new boolean[2];
        keyboard.draw(new Canvas() {
            @Override public void drawRoundRect(RectF bounds, float rx, float ry, Paint paint) { drew[0] = true; }
            @Override public void drawText(String text, float x, float y, Paint paint) { drew[1] = true; }
        });
        assertEquals("Keycaps must only be hidden during a drag", expected, drew[0]);
        assertEquals("Key labels must only be hidden during a drag", expected, drew[1]);
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

    private static void captureGapEvidence(Context context, String label) throws java.io.IOException {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        if (!"true".equals(InstrumentationRegistry.getArguments().getString("keykey.captureEvidence"))) return;
        android.graphics.Bitmap bitmap = instrumentation.getUiAutomation().takeScreenshot();
        assertNotNull(bitmap);
        java.io.File image = new java.io.File(context.getExternalFilesDir(null), "bottom-gap-" + label + ".png");
        try (var output = new java.io.FileOutputStream(image)) {
            assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, output));
        } finally {
            bitmap.recycle();
        }
    }

    private static String hostGeometry(Activity host) {
        String[] result = {""};
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            var keyboard = IntegratedBottomControlsInstrumentedTest.findKeyboard();
            WindowInsets hostInsets = host.getWindow().getDecorView().getRootWindowInsets();
            int[] location = new int[2];
            if (keyboard != null) keyboard.getLocationOnScreen(location);
            result[0] = "hostOrientation=" + host.getResources().getConfiguration().orientation
                    + ", hostIme=" + (hostInsets == null ? -1 : hostInsets.getInsets(WindowInsets.Type.ime()).bottom)
                    + ", hostNav=" + (hostInsets == null ? -1 : hostInsets.getInsets(WindowInsets.Type.navigationBars()).bottom)
                    + ", keyboardMode=" + (keyboard == null ? null : keyboard.mode())
                    + ", keyboardTop=" + location[1] + ", keyboardHeight=" + (keyboard == null ? -1 : keyboard.getHeight())
                    + ", keyboardMeasured=" + (keyboard == null ? -1 : keyboard.getMeasuredHeight());
            if (keyboard != null) {
                for (String fieldName : new String[]{"systemBottomInset", "lastReservedHeight", "lastDesiredContentHeight",
                        "lastDesiredBottomGap", "measuredHeightBudget", "lastWindowBounds", "measuredEdges"}) {
                    try {
                        var field = BopomofoKeyboardView.class.getDeclaredField(fieldName);
                        field.setAccessible(true);
                        result[0] += ", " + fieldName + "=" + field.get(keyboard);
                    } catch (ReflectiveOperationException ignored) { }
                }
                View container = (View) keyboard.getParent();
                int[] containerLocation = new int[2];
                container.getLocationOnScreen(containerLocation);
                View root = keyboard.getRootView();
                int[] rootLocation = new int[2];
                root.getLocationOnScreen(rootLocation);
                result[0] += ", containerTop=" + containerLocation[1] + ", containerHeight=" + container.getHeight()
                        + ", rootTop=" + rootLocation[1] + ", rootHeight=" + root.getHeight()
                        + ", metrics=" + keyboard.getContext().getSystemService(android.view.WindowManager.class)
                                .getCurrentWindowMetrics().getBounds();
            }
        });
        return result[0];
    }

    static void rotateDisplayTo(Context context, int orientation) throws Exception {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        var display = context.getSystemService(android.view.WindowManager.class).getDefaultDisplay();
        android.graphics.Point size = new android.graphics.Point();
        display.getRealSize(size);
        var displayMode = display.getMode();
        boolean naturalLandscape = displayMode.getPhysicalWidth() > displayMode.getPhysicalHeight();
        int rotation = (orientation == Configuration.ORIENTATION_LANDSCAPE) == naturalLandscape ? 0 : 1;
        assertTrue(instrumentation.getUiAutomation().setRotation(rotation));
        IntegratedBottomControlsInstrumentedTest.await(() -> {
            android.graphics.Point actual = new android.graphics.Point();
            display.getRealSize(actual);
            return display.getRotation() == rotation
                    && (actual.x > actual.y) == (orientation == Configuration.ORIENTATION_LANDSCAPE);
        });
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

    private static void verifyHardwareContentUnchanged(BopomofoKeyboardView view, int padding, int heightSpec) {
        view.setHardwareBottomSpaceEnabled(true);
        Bitmap reserved = render(view, heightSpec);
        view.setHardwareBottomSpaceEnabled(false);
        Bitmap flush = render(view, heightSpec);
        assertEquals(padding, reserved.getHeight() - flush.getHeight());
        Bitmap content = Bitmap.createBitmap(reserved, 0, 0, flush.getWidth(), flush.getHeight());
        assertTrue("The hardware bottom-space toggle must leave painted keys and candidates unchanged",
                flush.sameAs(content));
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
                SettingsActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
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
