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
import android.os.Build;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.view.inputmethod.InputMethodManager;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.CheckBox;
import android.widget.LinearLayout;
import android.widget.ScrollView;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

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
                CandidateWindowSettings.KEY_NUMBER_ROW, CandidateWindowSettings.KEY_FAILURE};
        Map<String, ?> previous = preferences.getAll();
        Activity activity = null;
        try {
            preferences.edit().remove(keys[0]).remove(keys[1])
                    .putBoolean(keys[2], false).putBoolean(keys[3], true).commit();
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
                CheckBox hardwareSpace = findCheck(hardware.getChildAt(1), "預留底部切換語言空間");
                CheckBox floating = findCheck(hardware.getChildAt(1), "使用浮動候選字窗");
                CheckBox numbers = findCheck(hardware.getChildAt(1), "顯示虛擬數字與符號鍵");
                assertTrue(touchSpace.isChecked());
                assertTrue(hardwareSpace.isChecked());
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
            });
        } finally {
            if (activity != null) {
                Activity current = activity;
                instrumentation.runOnMainSync(current::finish);
            }
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
                    int width = View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY);
                    window.measure(width, View.MeasureSpec.makeMeasureSpec(2000, View.MeasureSpec.AT_MOST));
                    int height = window.getMeasuredHeight();
                    int content = keyboard.getMeasuredHeight();
                    // The framework measures again with the newly allocated IME window size.
                    window.measure(width, View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY));
                    window.layout(0, 0, 1080, height);
                    assertEquals("Remeasuring the window must not shorten the keyboard content",
                            content, keyboard.getMeasuredHeight());
                    assertEquals("No blank bottom strip after reopening", window.getHeight(), keyboard.getBottom());
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
                CandidateWindowSettings.KEY_FLOATING_ENABLED};
        Activity activity = null;
        try {
            preferences.edit().putBoolean(keys[0], true).putBoolean(keys[1], true)
                    .putBoolean(keys[2], false).commit();
            activity = instrumentation.startActivitySync(new Intent()
                    .setClassName(context, "tw.chichi77.keykey.android.ImeTestActivity")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            Activity host = activity;
            instrumentation.runOnMainSync(() -> {
                host.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT);
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
        view.measure(View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY), heightMeasureSpec);
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
