package tw.chichi77.keykey.android;

import static org.junit.Assert.*;
import static org.junit.Assume.assumeTrue;

import android.accessibilityservice.AccessibilityService;
import android.app.Activity;
import android.app.Instrumentation;
import android.content.Context;
import android.content.Intent;
import android.graphics.Rect;
import android.graphics.RectF;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.inspector.WindowInspector;
import android.view.inputmethod.InputMethodManager;
import android.view.inputmethod.BaseInputConnection;
import android.view.inputmethod.InputConnection;
import android.widget.EditText;
import android.widget.TextView;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.io.File;
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.BooleanSupplier;
import java.util.function.Supplier;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Explicit isolated-device QA. Real InputDispatcher/IME/InputConnection;
 * injected KeyEvents do not certify USB or Bluetooth transport. */
@RunWith(AndroidJUnit4.class)
public final class PhysicalKeyboardRegressionInstrumentedTest {
    private final Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
    private final Context context = instrumentation.getTargetContext();
    private final JSONArray evidence = new JSONArray();
    private Activity activity;
    private EditText editor;
    private InputDevice keyboard;
    private BopomofoImeService activeService;
    private final java.util.Map<Integer, Long> keyDownTimes = new java.util.HashMap<>();
    private String floating;
    private int rotation;

    @Before public void requireIsolatedDevice() throws Exception {
        assumeTrue("Run only on an explicitly selected disposable device",
                "true".equals(InstrumentationRegistry.getArguments().getString("keykey.isolatedDevice")));
        instrumentation.waitForIdleSync();
        // Let the previous host finish normally before resetting persisted learning.
        // Never clear its composition or acknowledge effects on its behalf.
        await(this::imeLearningIsQuiet);
        main(() -> {
            // Match Settings' supported reset. On main, its preference notification
            // refreshes an existing quiet FE before this operation returns.
            try (UserPhraseRepository data = UserPhraseRepository.open(context)) {
                data.resetSmartLearning();
            }
            return true;
        });
        instrumentation.waitForIdleSync();
        await(this::imeLearningIsQuiet);
    }

    private boolean imeLearningIsQuiet() {
        // Adapter-only cases also run on older Android releases without this inspector.
        if (android.os.Build.VERSION.SDK_INT < 29) return true;
        for (View root : WindowInspector.getGlobalWindowViews()) {
            BopomofoKeyboardView view = keyboardView(root);
            if (view == null || !(view.getContext() instanceof BopomofoImeService service)) continue;
            HostInputEngine current = (HostInputEngine) field(service, "engine");
            if (current != null && (current.hasComposition() || current.hasPendingPhoneticReading()
                    || !current.displayedCandidates().isEmpty()
                    || (Boolean) field(current, "pendingHostEffects"))) return false;
        }
        return true;
    }

    @Test public void adapterSelectsTheRightHandTargetAtEveryCursorPosition() throws Exception {
        for (int position = 0; position <= 2; position++) {
            try (GuanyinmaInputEngine engine = isolatedEngine()) {
                engine.setHardwareSmartEditing(true);
                type(engine, "su3cl3");
                engine.moveSmartCompositionCursor(position - 2);
                engine.openSmartCandidates();
                String selected = position == 0 ? "妳" : "郝";
                int index = engine.displayedCandidates().indexOf(selected);
                assertTrue("The target must start at the cursor (or final character at the end)", index >= 0);
                engine.selectDisplayedCandidate(index);
                assertEquals(position == 0 ? "妳好" : "你郝", engine.completedSmartText());
                assertEquals(position == 0 ? 1 : 2, engine.composingCaretUtf16Offset());
                type(engine, "a8 ");
                String result = engine.completedSmartText();
                assertEquals(3, result.codePointCount(0, result.length()));
                assertTrue(position == 0 ? result.startsWith("妳") && result.endsWith("好") : result.startsWith("你郝"));
                assertNull(engine.lastError());
            }
        }
    }

    @Test public void adapterForwardDeleteRemovesTheReadingBeforeFurtherInput() throws Exception {
        for (int position = 0; position <= 2; position++) {
            try (GuanyinmaInputEngine engine = isolatedEngine()) {
                engine.setHardwareSmartEditing(true);
                type(engine, "su3cl3");
                engine.moveSmartCompositionCursor(position - 2);
                assertFalse(engine.deleteForward().deleteBeforeCursor());
                assertEquals(position == 0 ? "好" : position == 1 ? "你" : "你好", engine.completedSmartText());
                type(engine, "a8 ");
                String result = engine.completedSmartText();
                assertEquals(position == 2 ? 3 : 2, result.codePointCount(0, result.length()));
                assertTrue(position == 0 ? result.endsWith("好") : result.startsWith("你"));
                assertNull(engine.lastError());
            }
        }
    }

    @Test public void adapterForwardDeleteClearsTheLastMarkedCharacter() throws Exception {
        try (GuanyinmaInputEngine engine = isolatedEngine()) {
            engine.setHardwareSmartEditing(true);
            type(engine, "su3");
            engine.moveSmartCompositionCursor(-1);
            assertTrue(engine.deleteForward().discardComposingText());
            assertFalse(engine.hasComposition());
            type(engine, "cl3");
            assertEquals("好", engine.completedSmartText());
        }
    }

    @Test public void touchSelectionStillReturnsToTheEditableTail() throws Exception {
        try (GuanyinmaInputEngine engine = isolatedEngine()) {
            for (char key : "su3cl3".toCharArray()) engine.handleSoftKey(String.valueOf(key));
            assertTrue(engine.selectTouchSmartCell(0));
            int index = engine.displayedCandidates().indexOf("妳");
            assertTrue(index >= 0);
            engine.selectDisplayedCandidate(index);
            assertEquals("妳好", engine.completedSmartText());
            assertEquals(2, engine.composingCaretUtf16Offset());
        }
    }

    private GuanyinmaInputEngine isolatedEngine() throws Exception {
        File user = new File(context.getCacheDir(), "physical-regression-" + UUID.randomUUID() + ".db");
        return new GuanyinmaInputEngine(SharedModelDatabase.install(context).getAbsolutePath(),
                user.getAbsolutePath(), ChineseInputMethod.SMART, BopomofoKeyboardLayout.STANDARD,
                new TableInputOptions(ChineseInputMethod.SMART), false, true, false, text -> true);
    }

    private static void type(InputEngine engine, String keys) {
        for (char key : keys.toCharArray()) engine.handleHardwareCharacter(key);
    }

    @Test public void verticalPortrait() throws Exception { exercise("vertical", 0); }
    @Test public void verticalLandscape() throws Exception { exercise("vertical", 1); }
    @Test public void horizontalPortrait() throws Exception { exercise("horizontal", 0); }
    @Test public void horizontalLandscape() throws Exception { exercise("horizontal", 1); }
    @Test public void bottomPortrait() throws Exception { exercise("off", 0); }
    @Test public void bottomLandscape() throws Exception { exercise("off", 1); }

    @Test public void quickSettingsSingleRow() throws Exception { exerciseQuickSettings(false); }
    @Test public void quickSettingsSmartTwoRows() throws Exception { exerciseQuickSettings(true); }

    @Test public void desktopProfileOmitToneAndMiddleCandidateUseTheSameService() throws Exception {
        prepareHost("off", 0);
        BopomofoKeyboardLayoutSettings.setLayout(context, BopomofoKeyboardLayout.HANYU_PINYIN, false);
        BopomofoCompositionModeSettings.setOmitTone(context, true, false);
        HardwareSmartSettings.setEnabled(context, HardwareSmartSettings.CURSOR_AT_END, true);
        HardwareSmartSettings.setEnabled(context, HardwareSmartSettings.RETURNS_TO_END, false);
        try {
            fresh("smart");
            type("nihao");
            assertTrue(main(() -> ((HostInputEngine) engine()).hasPendingPhoneticReading()));
            key(KeyEvent.KEYCODE_ENTER);
            expectText("你好");
            BopomofoCompositionModeSettings.setOmitTone(context, false, false);
            BopomofoKeyboardLayoutSettings.setLayout(context, BopomofoKeyboardLayout.STANDARD, false);
            type("su3cl3");
            expectText("你好你好");
            key(KeyEvent.KEYCODE_DPAD_LEFT);
            key(KeyEvent.KEYCODE_DPAD_DOWN);
            assertTrue(main(() -> engine().displayedCandidates().contains("妳")));
            int index = main(() -> engine().displayedCandidates().indexOf("妳"));
            key(KeyEvent.KEYCODE_1 + index);
            key(KeyEvent.KEYCODE_ENTER);
            expectText("你好妳好");
            assertNull(main(() -> ((HostInputEngine) engine()).coreError()));
        } finally {
            if (activity != null) main(() -> { activity.finish(); return true; });
            BopomofoCompositionModeSettings.setOmitTone(context, false, false);
            BopomofoKeyboardLayoutSettings.setLayout(context, BopomofoKeyboardLayout.STANDARD, false);
            HardwareSmartSettings.setEnabled(context, HardwareSmartSettings.CURSOR_AT_END, false);
        }
    }

    private void exerciseQuickSettings(boolean twoRows) throws Exception {
        prepareHost("off", 0);
        CandidateWindowSettings.setSmartTwoRowsEnabled(context, twoRows);
        ChineseInputMethodSettings.setSimplifiedChineseOutput(context, false, false);
        try {
            fresh("smart");
            assertEquals(twoRows, main(() -> engine().isTouchSmartComposition()));
            type("tk ");
            expectText("車");
            assertTrue(main(() -> engine().hasComposition()));

            InputConnection connection = main(() -> service().getCurrentInputConnection());
            assertNotNull(connection);
            int keyboardHeight = main(() -> keyboardView().getHeight());
            tapHardwareLanguage();
            await(() -> popupControl("文字輸出：繁體", true) != null);
            captureHardwareEvidence(twoRows ? "two-row-quick-panel" : "single-row-quick-panel");
            assertSame(connection, main(() -> service().getCurrentInputConnection()));
            assertEquals(keyboardHeight, (int) main(() -> keyboardView().getHeight()));
            assertTrue(main(() -> engine().hasComposition()));
            expectText("車");

            tapHardwareLanguage();
            await(() -> popupControl("文字輸出：繁體", true) == null);
            assertTrue(main(() -> engine().hasComposition()));
            tapHardwareLanguage();
            tapPopupControl("文字輸出：繁體", true);
            await(() -> popupControl("文字輸出：簡體", true) != null
                    && !engine().hasComposition());
            expectText("車");
            type("tk ");
            key(KeyEvent.KEYCODE_ENTER);
            expectText("車车");
            if (main(() -> popupControl("文字輸出：簡體", true) == null)) tapHardwareLanguage();
            tapPopupControl("文字輸出：簡體", true);
            await(() -> popupControl("文字輸出：繁體", true) != null);

            String method = ChineseInputMethod.SMART.displayName;
            for (ChineseInputMethod next : List.of(ChineseInputMethod.TRADITIONAL, ChineseInputMethod.CANGJIE,
                    ChineseInputMethod.SIMPLEX, ChineseInputMethod.SMART)) {
                chooseQuickInputMethod(method, next.displayName);
                await(() -> engine().chineseInputMethod() == next && !engine().isEnglishMode());
                method = next.displayName;
            }
            chooseQuickInputMethod(method, "英文");
            await(() -> engine().isEnglishMode());
            chooseQuickInputMethod("英文", ChineseInputMethod.TRADITIONAL.displayName);
            await(() -> engine().chineseInputMethod() == ChineseInputMethod.TRADITIONAL
                    && !engine().isEnglishMode());
            chooseQuickInputMethod(ChineseInputMethod.TRADITIONAL.displayName, "英文");
            await(() -> engine().isEnglishMode());

            tapPopupControl("字元寬度：半形", true);
            await(() -> popupControl("字元寬度：全形", true) != null && engine().isHardwareFullWidth());
            type("A");
            expectText("車车Ａ");
            chord(KeyEvent.KEYCODE_SHIFT_LEFT, KeyEvent.KEYCODE_SPACE);
            assertFalse(main(() -> engine().isHardwareFullWidth()));
            type("b");
            expectText("車车Ａb");
            chord(KeyEvent.KEYCODE_CTRL_LEFT, KeyEvent.KEYCODE_SPACE);
            assertFalse(main(() -> engine().isEnglishMode()));
            assertEquals(ChineseInputMethod.TRADITIONAL, main(() -> engine().chineseInputMethod()));
            chord(KeyEvent.KEYCODE_CTRL_LEFT, KeyEvent.KEYCODE_SPACE);
            assertTrue(main(() -> engine().isEnglishMode()));
            assertTrue(main(editor::hasFocus));
            expectText("車车Ａb");
            openSettingsAndReturnToEditor();
            expectText("車车Ａb");
        } finally {
            if (activity != null) main(() -> { activity.finish(); return true; });
        }
    }

    private void captureHardwareEvidence(String label) throws java.io.IOException {
        if (!"true".equals(InstrumentationRegistry.getArguments().getString("keykey.captureEvidence"))) return;
        var bitmap = instrumentation.getUiAutomation().takeScreenshot();
        assertNotNull(bitmap);
        File image = new File(context.getExternalFilesDir(null), "physical-" + label + ".png");
        try (var output = new java.io.FileOutputStream(image)) {
            assertTrue(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, output));
        } finally { bitmap.recycle(); }
    }

    private void openSettingsAndReturnToEditor() throws Exception {
        if (main(() -> popupControl("設定", false) == null)) tapHardwareLanguage();
        Instrumentation.ActivityMonitor monitor = instrumentation.addMonitor(
                SettingsActivity.class.getName(), null, false);
        Activity settings = null;
        try {
            tapPopupControl("設定", false);
            settings = instrumentation.waitForMonitorWithTimeout(monitor, 7000);
            assertNotNull("The panel must open the existing settings screen", settings);
            await(settings::hasWindowFocus);
            recordSettingsReturn(settings, "before-system-back");
            Activity openedSettings = settings;
            boolean settingsHadIme = main(() -> {
                var insets = openedSettings.getWindow().getDecorView().getRootWindowInsets();
                return insets != null && insets.isVisible(android.view.WindowInsets.Type.ime());
            });
            assertTrue(instrumentation.getUiAutomation().performGlobalAction(
                    AccessibilityService.GLOBAL_ACTION_BACK));
            // Returning to the editor is the contract; Android may retain the
            // closing Activity instance after its window no longer owns input.
            Activity closingSettings = settings;
            await(() -> activity.hasWindowFocus() || closingSettings.isFinishing()
                    || !closingSettings.getWindow().getDecorView().getRootWindowInsets()
                            .isVisible(android.view.WindowInsets.Type.ime()));
            recordSettingsReturn(settings, "after-system-back");
            // Android first dismisses a visible hardware IME strip. Only send
            // the navigation Back after that happened while Settings stayed open.
            if (settingsHadIme && main(() -> closingSettings.hasWindowFocus() && !closingSettings.isFinishing()
                    && !closingSettings.getWindow().getDecorView().getRootWindowInsets()
                            .isVisible(android.view.WindowInsets.Type.ime()))) {
                assertTrue(instrumentation.getUiAutomation().performGlobalAction(
                        AccessibilityService.GLOBAL_ACTION_BACK));
                recordSettingsReturn(settings, "after-settings-navigation-back");
            }
            try {
                await(() -> !closingSettings.hasWindowFocus()
                        && activity.hasWindowFocus() && editor.hasFocus());
            } catch (AssertionError error) {
                recordSettingsReturn(settings, "return-timeout");
                throw error;
            }
            await(() -> !closingSettings.getWindow().getDecorView().isAttachedToWindow()
                    || !closingSettings.getWindow().getDecorView().isShown());
            showKeyboard();
            awaitKeyboardFrame();
            assertNull(main(() -> popupControl("設定", false)));
            tapHardwareLanguage();
            await(() -> popupControl("設定", false) != null);
        } finally {
            instrumentation.removeMonitor(monitor);
            if (settings != null) {
                Activity openedSettings = settings;
                main(() -> { openedSettings.finish(); return true; });
            }
        }
    }

    private void recordSettingsReturn(Activity settings, String stage) {
        String details = main(() -> {
            var resumed = new ArrayList<String>();
            for (Activity item : androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
                    .getInstance().getActivitiesInStage(androidx.test.runner.lifecycle.Stage.RESUMED)) {
                resumed.add(item.getClass().getSimpleName() + ":focused=" + item.hasWindowFocus());
            }
            var insets = settings.getWindow().getDecorView().getRootWindowInsets();
            return "stage=" + stage + ", resumed=" + resumed
                    + ", settingsFocus=" + settings.hasWindowFocus()
                    + ", settingsFinishing=" + settings.isFinishing()
                    + ", settingsDestroyed=" + settings.isDestroyed()
                    + ", settingsImeVisible=" + (insets != null && insets.isVisible(android.view.WindowInsets.Type.ime()))
                    + ", hostFocus=" + activity.hasWindowFocus() + ", editorFocus=" + editor.hasFocus();
        });
        Bundle status = new Bundle();
        status.putString("keykey_settings_return", details);
        instrumentation.sendStatus(0, status);
    }

    private void chooseQuickInputMethod(String current, String next) throws Exception {
        tapPopupControl("輸入方式：" + current, true);
        tapPopupControl(next, false);
        await(() -> popupControl("輸入方式：" + next, true) != null);
    }

    private void tapHardwareLanguage() {
        float[] coordinates = main(() -> {
            BopomofoKeyboardView view = keyboardView();
            assertNotNull(view);
            List<?> hits = (List<?>) field(view, "hits");
            Object button = hits.stream().filter(hit -> "HARDWARE_LANGUAGE".equals(field(hit, "key")))
                    .findFirst().orElseThrow(() -> new AssertionError("Missing candidate strip language key"));
            RectF bounds = (RectF) field(button, "bounds");
            int[] origin = new int[2];
            view.getLocationOnScreen(origin);
            return new float[]{origin[0] + bounds.centerX(), origin[1] + bounds.centerY()};
        });
        tapScreen(coordinates[0], coordinates[1]);
    }

    private void tapPopupControl(String label, boolean byDescription) throws Exception {
        await(() -> popupControl(label, byDescription) != null);
        float[] coordinates = main(() -> {
            View view = popupControl(label, byDescription);
            assertNotNull(label, view);
            int[] origin = new int[2];
            view.getLocationOnScreen(origin);
            return new float[]{origin[0] + view.getWidth() / 2f, origin[1] + view.getHeight() / 2f};
        });
        tapScreen(coordinates[0], coordinates[1]);
    }

    private View popupControl(String label, boolean byDescription) {
        for (View root : WindowInspector.getGlobalWindowViews()) {
            View result = popupControl(root, label, byDescription);
            if (result != null) return result;
        }
        return null;
    }

    private View popupControl(View view, String label, boolean byDescription) {
        if (!view.isShown() || view.getWidth() <= 0 || view.getHeight() <= 0) return null;
        if (view instanceof TextView text && label.contentEquals(String.valueOf(
                byDescription ? text.getContentDescription() : text.getText()))) return text;
        if (view instanceof ViewGroup group) for (int index = 0; index < group.getChildCount(); index++) {
            View result = popupControl(group.getChildAt(index), label, byDescription);
            if (result != null) return result;
        }
        return null;
    }

    private void tapScreen(float x, float y) {
        long downTime = SystemClock.uptimeMillis();
        for (int action : new int[]{MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP}) {
            MotionEvent event = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action, x, y, 0);
            event.setSource(InputDevice.SOURCE_TOUCHSCREEN);
            try {
                assertTrue(instrumentation.getUiAutomation().injectInputEvent(event, true));
            } finally {
                event.recycle();
            }
        }
        instrumentation.waitForIdleSync();
    }

    private void prepareHost(String mode, int pose) throws Exception {
        floating = mode;
        rotation = pose;
        for (int id : InputDevice.getDeviceIds()) {
            InputDevice device = InputDevice.getDevice(id);
            if (device != null && !device.isVirtual()
                    && device.getKeyboardType() == InputDevice.KEYBOARD_TYPE_ALPHABETIC) {
                keyboard = device;
                break;
            }
        }
        assertNotNull("Enable the emulator's hardware keyboard", keyboard);
        assertTrue(instrumentation.getUiAutomation().setRotation(rotation));
        CandidateWindowSettings.preferences(context).edit()
                .putBoolean(CandidateWindowSettings.KEY_SMART_TWO_ROWS, false)
                .putBoolean(CandidateWindowSettings.KEY_NUMBER_ROW, false)
                .putString(KeyboardSettingsProfile.key(false, BopomofoKeyboardLayoutSettings.KEY_LAYOUT), BopomofoKeyboardLayout.STANDARD.value).commit();
    }

    private void exercise(String mode, int pose) throws Exception {
        prepareHost(mode, pose);
        try {
            paragraphAndEnter();
            forwardDelete();
            shortcutsAndEditing();
            fourMethods();
            candidateNavigationAndSelection();
            rotationAndReopen();
            // Candidate learning from 郝 belongs at the end of this scenario.
            sentenceMiddleSelectionAndBackspace();
        } finally {
            if (activity != null) main(() -> { activity.finish(); return true; });
            JSONObject report = new JSONObject();
            report.put("floating", floating); report.put("rotation", rotation);
            report.put("eventSource", "InputDispatcher KeyEvents with attached hardware key map; injected");
            report.put("evidence", evidence);
            Bundle status = new Bundle(); status.putString("keykey_physical_report", report.toString());
            instrumentation.sendStatus(0, status);
        }
    }

    private void paragraphAndEnter() throws Exception {
        fresh("smart");
        String[] syllables = {"fu/3", "ru84", "ul4", "fm4", "s83", "xu3", "j06", "sk7", "fm4", "c93",
                "1u0 ", "up ", "jo4", "s84", "xu3", "u.3", "1u3", "ru ", "su6"};
        String expected = "請假要去哪裡玩呢去海邊因為那裡有比基尼";
        for (int i = 0; i < syllables.length; i++) {
            type(syllables[i]);
            // A clean user store may rank 完 before 玩. Select the intended word
            // explicitly so this checks editing/host boundaries, not model ranking.
            if (i == 6) {
                key(KeyEvent.KEYCODE_DPAD_LEFT); key(KeyEvent.KEYCODE_DPAD_DOWN);
                int pageCount = main(() -> engine().pageCount());
                int selected = -1;
                for (int page = 0; page < pageCount; page++) {
                    selected = main(() -> engine().displayedCandidates().indexOf("玩"));
                    if (selected >= 0) break;
                    key(KeyEvent.KEYCODE_PAGE_DOWN);
                }
                assertTrue("玩 must be available for the fixed paragraph", selected >= 0);
                key(KeyEvent.KEYCODE_1 + selected);
            }
            if (i == 9 || i == 10 || i == 18) {
                expectText(expected.substring(0, i + 1));
                record("paragraph-syllable-" + (i + 1));
            }
        }
        int tailStart = main(() -> BaseInputConnection.getComposingSpanStart(editor.getText()));
        assertTrue("The evicted prefix must remain outside the marked range", tailStart > 0);
        for (int pose : new int[] {rotation == 0 ? 1 : 0, rotation}) {
            assertTrue(instrumentation.getUiAutomation().setRotation(pose));
            await(() -> BaseInputConnection.getComposingSpanStart(editor.getText()) == tailStart
                    && BaseInputConnection.getComposingSpanEnd(editor.getText()) == expected.length()
                    && editor.getSelectionStart() == expected.length());
            expectText(expected);
        }
        record("paragraph-evicted-prefix-after-rotation");
        key(KeyEvent.KEYCODE_ENTER);
        expectText(expected);
        assertTrue(main(editor::hasFocus));
        assertFalse(main(() -> engine().hasComposition()));
        record("enter-confirms-without-changing-field");
        key(KeyEvent.KEYCODE_DEL);
        expectText(expected.substring(0, expected.length() - 1));
        record("committed-backspace");
        AtomicInteger enterEvents = new AtomicInteger();
        main(() -> { editor.setOnEditorActionListener((view, action, event) -> {
            enterEvents.incrementAndGet(); return true;
        }); return true; });
        key(KeyEvent.KEYCODE_ENTER);
        assertEquals("The host receives one Down/Up pair", 2, enterEvents.get());
        assertTrue(main(editor::hasFocus)); record("plain-enter-sends-one-pair-to-host");
        main(() -> { editor.setOnEditorActionListener(null); return true; });
        key(KeyEvent.KEYCODE_ENTER);
        await(() -> editors().size() > 1 && editors().get(1).hasFocus());
        record("plain-enter-changes-exactly-one-field");
    }

    private void forwardDelete() throws Exception {
        fresh("smart"); type("su3"); key(KeyEvent.KEYCODE_DPAD_LEFT);
        key(KeyEvent.KEYCODE_FORWARD_DEL); expectText("");
        type("cl3"); expectText("好"); record("forward-delete-last-character-and-resume");
        fresh("smart"); type("su3cl3"); key(KeyEvent.KEYCODE_DPAD_LEFT);
        key(KeyEvent.KEYCODE_FORWARD_DEL); expectText("你");
        type("a8 ");
        assertEquals(2, text().codePointCount(0, text().length()));
        assertTrue(text().startsWith("你"));
        record("forward-delete-stays-deleted");
        key(KeyEvent.KEYCODE_ENTER);
        key(KeyEvent.KEYCODE_DPAD_LEFT);
        int oldLength = text().length();
        key(KeyEvent.KEYCODE_FORWARD_DEL);
        await(() -> editor.getText().length() == oldLength - 1);
        record("plain-forward-delete-reaches-host");
    }

    private void shortcutsAndEditing() throws Exception {
        fresh("smart"); type("su3c"); key(KeyEvent.KEYCODE_ESCAPE); expectText("你");
        type("cl"); key(KeyEvent.KEYCODE_DEL);
        assertFalse(main(() -> engine().readingText()).isEmpty());
        key(KeyEvent.KEYCODE_ESCAPE); expectText("你");
        record("escape-and-pending-backspace");
        fresh("smart"); chord(KeyEvent.KEYCODE_CTRL_LEFT, KeyEvent.KEYCODE_SPACE);
        assertTrue(main(() -> engine().isEnglishMode()));
        type("abc09"); expectText("abc09");
        chord(KeyEvent.KEYCODE_SHIFT_LEFT, KeyEvent.KEYCODE_SPACE);
        assertTrue(main(() -> engine().isHardwareFullWidth()));
        type("Az09!~ "); expectText("abc09Ａｚ０９！～　");
        chord(KeyEvent.KEYCODE_SHIFT_LEFT, KeyEvent.KEYCODE_SPACE);
        type("x");
        chord(KeyEvent.KEYCODE_CTRL_LEFT, KeyEvent.KEYCODE_COMMA);
        chord(KeyEvent.KEYCODE_CTRL_LEFT, KeyEvent.KEYCODE_PERIOD);
        expectText("abc09Ａｚ０９！～　x，。");
        record("language-width-and-punctuation-shortcuts");
        down(KeyEvent.KEYCODE_DEL, 0); Thread.sleep(650); up(KeyEvent.KEYCODE_DEL, 0);
        String after = text();
        assertTrue(after.length() < "abc09Ａｚ０９！～　x，。".length());
        Thread.sleep(600); assertEquals(after, text());
        record("backspace-hold-stops-on-release");
        chord(KeyEvent.KEYCODE_CTRL_LEFT, KeyEvent.KEYCODE_SPACE);
        chord(KeyEvent.KEYCODE_CTRL_LEFT, KeyEvent.KEYCODE_0);
        assertFalse(main(() -> engine().displayedCandidates()).isEmpty());
        key(KeyEvent.KEYCODE_1);
        assertTrue(text().endsWith("，")); record("symbol-shortcut-and-number-selection");
    }

    private void rotationAndReopen() throws Exception {
        fresh("smart"); type("su3"); key(KeyEvent.KEYCODE_DPAD_DOWN);
        assertCandidateWindowCount();
        for (int pose : new int[] {rotation == 0 ? 1 : 0, rotation, rotation == 0 ? 1 : 0, rotation}) {
            assertTrue(instrumentation.getUiAutomation().setRotation(pose));
            Thread.sleep(400); expectText("你"); assertCandidateWindowCount();
            record("rotated-candidates-" + pose);
        }
        key(KeyEvent.KEYCODE_ESCAPE); record("after-rotation-escape");
        key(KeyEvent.KEYCODE_ENTER); record("after-rotation-enter");
        expectText("你");
        main(() -> {
            context.getSystemService(InputMethodManager.class).hideSoftInputFromWindow(editor.getWindowToken(), 0);
            return true;
        });
        await(() -> keyboardView() == null || !keyboardView().isShown());
        assertTrue(main(() -> candidateRoots().isEmpty()));
        showKeyboard(); type("cl3"); key(KeyEvent.KEYCODE_ENTER); expectText("你好");
        record("hide-reopen-without-replay");
    }

    private void fourMethods() throws Exception {
        for (String method : List.of("traditional", "cangjie", "simplex")) {
            fresh(method);
            type(method.equals("traditional") ? "su3" : method.equals("cangjie") ? "onf " : "of ");
            List<String> candidates = main(() -> List.copyOf(engine().displayedCandidates()));
            boolean associated = main(() -> engine().isShowingAssociatedPhrases());
            String before = text();
            if (!candidates.isEmpty()) {
                if (associated) chord(KeyEvent.KEYCODE_SHIFT_LEFT, KeyEvent.KEYCODE_1);
                else key(KeyEvent.KEYCODE_1);
                expectText((associated ? before : "") + candidates.get(0));
            } else assertFalse(text().isEmpty());
            record("method-" + method);
        }
    }

    private void sentenceMiddleSelectionAndBackspace() throws Exception {
        fresh("smart"); type("su3cl3"); expectText("你好");
        key(KeyEvent.KEYCODE_DPAD_LEFT); key(KeyEvent.KEYCODE_DPAD_DOWN);
        int selected = main(() -> engine().displayedCandidates().indexOf("郝"));
        assertTrue("The right-hand 好 must be the candidate target", selected >= 0);
        key(KeyEvent.KEYCODE_1 + selected); expectText("你郝");
        type("a8 "); expectText("你郝嗎");
        record("middle-selection-and-insertion-target-the-right-hand-word");
        key(KeyEvent.KEYCODE_DPAD_LEFT); key(KeyEvent.KEYCODE_DEL); expectText("你媽");
        record("middle-backspace-removes-the-left-hand-word");
    }

    private void candidateNavigationAndSelection() throws Exception {
        fresh("smart"); type("su3"); key(KeyEvent.KEYCODE_DPAD_DOWN);
        List<String> original = main(() -> List.copyOf(engine().displayedCandidates()));
        assertTrue(original.size() > 1); assertCandidateWindowCount();
        Thread.sleep(1200); assertEquals(original, main(() -> engine().displayedCandidates()));
        key(floating.equals("horizontal") ? KeyEvent.KEYCODE_DPAD_RIGHT : KeyEvent.KEYCODE_DPAD_DOWN);
        assertEquals(1, (int) main(() -> engine().highlightedIndex()));
        assertTrue(main(() -> engine().pageCount()) > 1);
        key(KeyEvent.KEYCODE_PAGE_DOWN); assertEquals(1, (int) main(() -> engine().page()));
        key(KeyEvent.KEYCODE_PAGE_UP); assertEquals(0, (int) main(() -> engine().page()));
        if (!floating.equals("off")) {
            key(floating.equals("vertical") ? KeyEvent.KEYCODE_DPAD_RIGHT : KeyEvent.KEYCODE_DPAD_DOWN);
            assertEquals(1, (int) main(() -> engine().page()));
            key(floating.equals("vertical") ? KeyEvent.KEYCODE_DPAD_LEFT : KeyEvent.KEYCODE_DPAD_UP);
            assertEquals(0, (int) main(() -> engine().page()));
        }
        String selected = main(() -> engine().displayedCandidates().get(1));
        key(KeyEvent.KEYCODE_2); expectText(selected);
        record("numeric-navigation-and-page-selection");
        key(KeyEvent.KEYCODE_ENTER);
        fresh("smart"); type("su3"); key(KeyEvent.KEYCODE_DPAD_DOWN);
        key(floating.equals("horizontal") ? KeyEvent.KEYCODE_DPAD_RIGHT : KeyEvent.KEYCODE_DPAD_DOWN);
        selected = main(() -> engine().displayedCandidates().get(engine().highlightedIndex()));
        down(KeyEvent.KEYCODE_ENTER, 0);
        long now = SystemClock.uptimeMillis();
        assertTrue(instrumentation.getUiAutomation().injectInputEvent(new KeyEvent(now, now,
                KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER, 1, 0, keyboard.getId(), 0,
                0, InputDevice.SOURCE_KEYBOARD), true));
        assertTrue(instrumentation.getUiAutomation().injectInputEvent(new KeyEvent(now, now,
                KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER, 2, 0, keyboard.getId(), 0,
                0, InputDevice.SOURCE_KEYBOARD), true));
        up(KeyEvent.KEYCODE_ENTER, 0); instrumentation.waitForIdleSync();
        expectText(selected);
        assertTrue(main(() -> engine().hasComposition()));
        assertTrue(main(editor::hasFocus)); record("held-enter-selects-once-without-field-jump");
        key(KeyEvent.KEYCODE_ENTER);
        assertFalse(main(() -> engine().hasComposition()));
        assertTrue(main(editor::hasFocus)); record("next-enter-confirms-after-release");
    }

    @Test public void candidateReplacementStillHonorsTheNextRealHostCursorAndRangeChange() throws Exception {
        prepareHost("off", 0);
        try {
            fresh("smart"); type("su3cl3"); expectText("你好");
            key(KeyEvent.KEYCODE_DPAD_LEFT); key(KeyEvent.KEYCODE_DPAD_DOWN);
            int selected = main(() -> engine().displayedCandidates().indexOf("郝"));
            assertTrue(selected >= 0);
            key(KeyEvent.KEYCODE_1 + selected); expectText("你郝");
            key(KeyEvent.KEYCODE_DPAD_LEFT);
            await(() -> editor.getSelectionStart() == 1 && editor.getSelectionEnd() == 1);
            // These are genuine TextView/IMM notifications, not a fabricated
            // call to onUpdateSelection. A stale implicit-end intent must not
            // swallow the application's next cursor or range operation.
            main(() -> { editor.setSelection(2); return true; });
            await(() -> !engine().hasComposition());
            expectText("你郝");
            record("candidate-replacement-then-real-host-cursor");

            fresh("smart"); type("su3cl3");
            String before = text();
            assertEquals(2, before.length());
            assertTrue(main(() -> engine().hasComposition()));
            main(() -> { editor.setSelection(0, 1); return true; });
            await(() -> !engine().hasComposition());
            expectText(before);
            record("real-host-range-is-not-an-own-selection-ack");
        } finally {
            if (activity != null) main(() -> { activity.finish(); return true; });
        }
    }

    @Test public void repeatedRestartsPreserveTheOwnedRangeAndCaret() throws Exception {
        prepareHost("off", 0);
        try {
            fresh("smart");
            main(() -> { editor.setText("前:後"); editor.setSelection(2); return true; });
            restartEditor();
            type("su3cl3"); expectText("前:你好後"); key(KeyEvent.KEYCODE_DPAD_LEFT);
            for (int i = 0; i < 2; i++) {
                restartEditor();
                await(() -> BaseInputConnection.getComposingSpanStart(editor.getText()) == 2
                        && BaseInputConnection.getComposingSpanEnd(editor.getText()) == 4
                        && editor.getSelectionStart() == 3);
                expectText("前:你好後");
            }
            key(KeyEvent.KEYCODE_FORWARD_DEL); expectText("前:你後");
            type("a8 "); expectText("前:你媽後");
            key(KeyEvent.KEYCODE_ENTER); expectText("前:你媽後");
            assertFalse(main(() -> engine().hasComposition()));
            fresh("smart"); type("su3c"); String pending = text();
            restartEditor(); expectText(pending);
            type("l3"); expectText("你好"); key(KeyEvent.KEYCODE_ENTER); expectText("你好");
        } finally {
            if (activity != null) main(() -> { activity.finish(); return true; });
        }
    }

    @Test public void unverifiableRestartKeepsHostTextWithoutReplayingComposition() throws Exception {
        prepareHost("off", 0);
        try {
            for (String fault : List.of("unavailable", "mismatch")) {
                fresh("smart"); type("su3"); expectText("你");
                main(() -> { activity.getIntent().putExtra("restartExtraction", fault); return true; });
                restartEditor();
                await(() -> !engine().hasComposition()
                        && BaseInputConnection.getComposingSpanStart(editor.getText()) == -1);
                expectText("你");
                assertEquals("", main(() -> field(service(), "appliedComposingText")));
                main(() -> { activity.getIntent().removeExtra("restartExtraction"); return true; });
                type("cl3"); expectText("你好");
                key(KeyEvent.KEYCODE_ENTER); expectText("你好");
            }
        } finally {
            if (activity != null) main(() -> { activity.finish(); return true; });
        }
    }

    @Test public void enterOwnershipDoesNotConsumeANewModifiedKeyPress() throws Exception {
        prepareHost("off", 0);
        try {
            fresh("smart"); type("su3cl3");
            BopomofoImeService currentService = main(this::service);
            long first = SystemClock.uptimeMillis();
            // Model the callbacks when an IME switch prevents the original Up
            // from reaching this service. This is a callback-contract test.
            assertTrue(main(() -> currentService.onKeyDown(KeyEvent.KEYCODE_ENTER,
                    new KeyEvent(first, first, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER, 0))));
            expectText("你好");
            long next = first + 1;
            int ctrl = KeyEvent.META_CTRL_ON | KeyEvent.META_CTRL_LEFT_ON;
            assertFalse(main(() -> currentService.onKeyDown(KeyEvent.KEYCODE_ENTER,
                    new KeyEvent(next, next, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER, 0, ctrl))));
            assertFalse(main(() -> currentService.onKeyUp(KeyEvent.KEYCODE_ENTER,
                    new KeyEvent(next, next + 1, KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER, 0, ctrl))));
            expectText("你好");
        } finally {
            if (activity != null) main(() -> { activity.finish(); return true; });
        }
    }

    private void restartEditor() throws Exception {
        BopomofoImeService currentService = main(this::service);
        InputConnection previous = main(currentService::getCurrentInputConnection);
        main(() -> { context.getSystemService(InputMethodManager.class).restartInput(editor); return true; });
        await(() -> currentService.getCurrentInputConnection() != null
                && currentService.getCurrentInputConnection() != previous);
        instrumentation.waitForIdleSync();
    }

    private void fresh(String method) throws Exception {
        InputConnection previous = main(() -> activeService == null
                ? null : activeService.getCurrentInputConnection());
        if (activity != null) main(() -> { activity.finish(); return true; });
        activity = instrumentation.startActivitySync(new Intent()
                .setClassName(context, context.getPackageName() + ".ImeTestActivity")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK)
                .putExtra("floating", floating).putExtra("method", method));
        editor = main(() -> findEditors(activity.findViewById(android.R.id.content)).get(0));
        showKeyboard(previous);
        assertTrue(main(() -> (Boolean) field(service(), "hardwareKeyboard")));
        if (main(() -> engine().isEnglishMode())) chord(KeyEvent.KEYCODE_CTRL_LEFT, KeyEvent.KEYCODE_SPACE);
        if (main(() -> engine().isHardwareFullWidth())) chord(KeyEvent.KEYCODE_SHIFT_LEFT, KeyEvent.KEYCODE_SPACE);
    }

    private void showKeyboard() throws Exception { showKeyboard(null); }

    private void showKeyboard(InputConnection previous) throws Exception {
        try {
            await(activity::hasWindowFocus);
            main(() -> { editor.requestFocus(); return true; });
            InputMethodManager manager = context.getSystemService(InputMethodManager.class);
            await(() -> manager.isActive(editor));
            // This test explicitly opens the hardware strip, like tapping
            // the system keyboard button. am instrument restarts the target
            // process, so a cold IME may bind after the first show request.
            main(() -> { manager.showSoftInput(editor, 0); return true; });
            long retryUntil = SystemClock.uptimeMillis() + 10000;
            long[] retryAt = {SystemClock.uptimeMillis() + 1000};
            await(() -> {
                BopomofoKeyboardView view = keyboardView();
                if (view != null && view.isShown()) {
                    BopomofoImeService service = (BopomofoImeService) view.getContext();
                    if (service.getCurrentInputConnection() != null
                            && service.getCurrentInputConnection() != previous
                            && service.getCurrentInputEditorInfo() != null
                            && editor.getPrivateImeOptions().equals(
                                    service.getCurrentInputEditorInfo().privateImeOptions)
                            && activity.hasWindowFocus() && manager.isActive(editor)) {
                        activeService = service;
                        return true;
                    }
                }
                long now = SystemClock.uptimeMillis();
                if (now <= retryUntil && now >= retryAt[0] && activity.hasWindowFocus()
                        && editor.hasFocus() && manager.isActive(editor)) {
                    manager.showSoftInput(editor, 0);
                    retryAt[0] = now + 1000;
                }
                return false;
            });
        } catch (AssertionError error) {
            recordHostReadiness(previous);
            throw error;
        }
    }

    private void awaitKeyboardFrame() throws Exception {
        var drawn = new java.util.concurrent.CountDownLatch(1);
        main(() -> {
            BopomofoKeyboardView view = keyboardView();
            assertNotNull(view);
            view.getViewTreeObserver().addOnPreDrawListener(new android.view.ViewTreeObserver.OnPreDrawListener() {
                @Override public boolean onPreDraw() {
                    if (view.isShown() && view.getHeight() > 0 && !view.isLayoutRequested()) {
                        view.getViewTreeObserver().removeOnPreDrawListener(this);
                        drawn.countDown();
                    }
                    return true;
                }
            });
            view.invalidate();
            return true;
        });
        assertTrue("The current IME frame must settle before tapping its controls",
                drawn.await(3, java.util.concurrent.TimeUnit.SECONDS));
    }

    private void recordHostReadiness(InputConnection previous) {
        String details = main(() -> {
            var manager = context.getSystemService(InputMethodManager.class);
            BopomofoKeyboardView found = null;
            for (View root : WindowInspector.getGlobalWindowViews()) {
                BopomofoKeyboardView candidate = keyboardView(root);
                if (candidate != null) { found = candidate; break; }
            }
            String state = "hostFocus=" + activity.hasWindowFocus() + ", editorFocus=" + editor.hasFocus()
                    + ", managerActive=" + manager.isActive(editor) + ", desiredEditor=" + editor.getPrivateImeOptions()
                    + ", keyboard=" + found;
            if (found != null) {
                BopomofoImeService service = (BopomofoImeService) found.getContext();
                var info = service.getCurrentInputEditorInfo();
                state += ", viewShown=" + found.isShown() + ", viewHeight=" + found.getHeight()
                        + ", currentEditor=" + (info == null ? null : info.privateImeOptions)
                        + ", hasConnection=" + (service.getCurrentInputConnection() != null)
                        + ", oldConnection=" + (service.getCurrentInputConnection() == previous);
            }
            return state;
        });
        Bundle status = new Bundle();
        status.putString("keykey_host_readiness_failure", details);
        instrumentation.sendStatus(0, status);
    }

    private List<EditText> editors() { return findEditors(activity.findViewById(android.R.id.content)); }
    private List<EditText> findEditors(View view) {
        List<EditText> result = new ArrayList<>();
        if (view instanceof EditText text) result.add(text);
        if (view instanceof ViewGroup group) for (int i = 0; i < group.getChildCount(); i++) result.addAll(findEditors(group.getChildAt(i)));
        return result;
    }
    private BopomofoKeyboardView keyboardView() {
        for (View root : WindowInspector.getGlobalWindowViews()) {
            BopomofoKeyboardView found = keyboardView(root);
            if (found != null && found.isShown()) return found;
        }
        return null;
    }
    private BopomofoKeyboardView keyboardView(View view) {
        if (view instanceof BopomofoKeyboardView keyboard) return keyboard;
        if (view instanceof ViewGroup group) for (int i = 0; i < group.getChildCount(); i++) {
            BopomofoKeyboardView found = keyboardView(group.getChildAt(i));
            if (found != null) return found;
        }
        return null;
    }
    private BopomofoImeService service() {
        assertNotNull("Wait for the current host connection before reading the service", activeService);
        return activeService;
    }
    private InputEngine engine() { return (InputEngine) field(service(), "engine"); }
    private static Object field(Object owner, String name) {
        try { Field field = owner.getClass().getDeclaredField(name); field.setAccessible(true); return field.get(owner); }
        catch (ReflectiveOperationException error) { throw new AssertionError(error); }
    }
    private <T> T main(Supplier<T> operation) {
        Object[] result = {null}; instrumentation.runOnMainSync(() -> result[0] = operation.get()); return (T) result[0];
    }
    private void await(BooleanSupplier condition) throws Exception {
        long deadline = SystemClock.uptimeMillis() + 7000;
        while (SystemClock.uptimeMillis() < deadline) {
            if (main(condition::getAsBoolean)) return;
            Thread.sleep(60);
        }
        fail("Timed out waiting for current host/IME state");
    }
    private String text() { return main(() -> editor.getText().toString()); }
    private void expectText(String expected) throws Exception {
        try { await(() -> editor.getText().toString().equals(expected)); }
        catch (AssertionError error) {
            try { record("text-assertion-failure"); }
            catch (Exception diagnostic) { error.addSuppressed(diagnostic); }
            throw new AssertionError("Expected text <" + expected + "> but was <" + text()
                    + ">, editorFocus=" + main(editor::hasFocus), error);
        }
    }
    private void type(String text) throws Exception {
        KeyEvent[] events = keyboard.getKeyCharacterMap().getEvents(text.toCharArray()); assertNotNull(events);
        // getEvents can choose a command chord even when an ordinary printable
        // stroke exists (qwerty2 chooses Shift+Alt+K for ~). Those Alt/Ctrl/Meta
        // chords deliberately belong to the host, not the IME text path.
        if (java.util.Arrays.stream(events).anyMatch(PhysicalKeyboardRegressionInstrumentedTest::commandModifier)) {
            var printable = new ArrayList<KeyEvent>();
            for (char character : text.toCharArray()) {
                KeyEvent[] mapped = keyboard.getKeyCharacterMap().getEvents(new char[]{character});
                assertNotNull(mapped);
                if (java.util.Arrays.stream(mapped).anyMatch(PhysicalKeyboardRegressionInstrumentedTest::commandModifier)) {
                    mapped = ordinaryPrintableStroke(character);
                }
                printable.addAll(java.util.Arrays.asList(mapped));
            }
            events = printable.toArray(new KeyEvent[0]);
        }
        for (KeyEvent event : events) inject(event.getAction(), event.getKeyCode(), event.getMetaState());
        instrumentation.waitForIdleSync(); Thread.sleep(80);
    }
    private static boolean commandModifier(KeyEvent event) {
        return event.isAltPressed() || event.isCtrlPressed() || event.isMetaPressed();
    }
    private KeyEvent[] ordinaryPrintableStroke(char character) {
        int shift = KeyEvent.META_SHIFT_ON | KeyEvent.META_SHIFT_LEFT_ON;
        for (int meta : new int[]{0, shift}) {
            for (int code = 0; code <= KeyEvent.getMaxKeyCode(); code++) {
                if (keyboard.getKeyCharacterMap().get(code, meta) != character) continue;
                var events = new ArrayList<KeyEvent>();
                if (meta != 0) events.add(new KeyEvent(0, 0, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_SHIFT_LEFT, 0, meta));
                events.add(new KeyEvent(0, 0, KeyEvent.ACTION_DOWN, code, 0, meta));
                events.add(new KeyEvent(0, 0, KeyEvent.ACTION_UP, code, 0, meta));
                if (meta != 0) events.add(new KeyEvent(0, 0, KeyEvent.ACTION_UP, KeyEvent.KEYCODE_SHIFT_LEFT, 0, 0));
                return events.toArray(new KeyEvent[0]);
            }
        }
        throw new AssertionError("The attached key map has no ordinary printable stroke for " + character);
    }
    private void inject(int action, int code, int meta) throws Exception {
        long now = SystemClock.uptimeMillis();
        // InputDispatcher expects a press and its release to share downTime.
        // Keep the original 8ms cadence while matching real hardware pairs.
        if (action == KeyEvent.ACTION_DOWN) keyDownTimes.put(code, now);
        long downTime = keyDownTimes.getOrDefault(code, now);
        assertTrue(instrumentation.getUiAutomation().injectInputEvent(new KeyEvent(downTime, now, action, code, 0,
                meta, keyboard.getId(), 0, 0, InputDevice.SOURCE_KEYBOARD), true));
        if (action == KeyEvent.ACTION_UP) keyDownTimes.remove(code);
        Thread.sleep(8);
    }
    private void down(int code, int meta) throws Exception { inject(KeyEvent.ACTION_DOWN, code, meta); }
    private void up(int code, int meta) throws Exception { inject(KeyEvent.ACTION_UP, code, meta); }
    private void key(int code) throws Exception { down(code, 0); up(code, 0); instrumentation.waitForIdleSync(); Thread.sleep(80); }
    private void chord(int modifier, int code) throws Exception {
        int meta = modifier == KeyEvent.KEYCODE_CTRL_LEFT ? KeyEvent.META_CTRL_ON | KeyEvent.META_CTRL_LEFT_ON
                : KeyEvent.META_SHIFT_ON | KeyEvent.META_SHIFT_LEFT_ON;
        down(modifier, meta); down(code, meta); up(code, meta); up(modifier, 0);
        instrumentation.waitForIdleSync(); Thread.sleep(80);
    }
    private Set<View> candidateRoots() {
        Set<View> roots = new HashSet<>(); for (View root : WindowInspector.getGlobalWindowViews()) candidateRoots(root, roots); return roots;
    }
    private void candidateRoots(View view, Set<View> roots) {
        if (view instanceof TextView text && text.isShown() && text.getContentDescription() != null
                && text.getContentDescription().toString().matches("第 \\d+ 個候選，.*")) roots.add(view.getRootView());
        if (view instanceof ViewGroup group) for (int i = 0; i < group.getChildCount(); i++) candidateRoots(group.getChildAt(i), roots);
    }
    private void assertCandidateWindowCount() throws Exception {
        int expected = floating.equals("off") ? 0 : 1;
        await(() -> candidateRoots().size() == expected);
        assertNull(CandidateWindowSettings.failure(context));
        main(() -> {
            Rect display = context.getSystemService(android.view.WindowManager.class).getMaximumWindowMetrics().getBounds();
            for (View root : candidateRoots()) {
                int[] xy = new int[2]; root.getLocationOnScreen(xy);
                assertTrue(display.contains(new Rect(xy[0], xy[1], xy[0] + root.getWidth(), xy[1] + root.getHeight())));
            }
            return true;
        });
    }
    private void record(String stage) throws Exception {
        JSONObject row = main(() -> {
            try {
                JSONObject result = new JSONObject(); result.put("stage", stage); result.put("text", editor.getText().toString());
                result.put("editorHasFocus", editor.hasFocus());
                result.put("markedStart", BaseInputConnection.getComposingSpanStart(editor.getText()));
                result.put("markedEnd", BaseInputConnection.getComposingSpanEnd(editor.getText()));
                result.put("selectionStart", editor.getSelectionStart()); result.put("selectionEnd", editor.getSelectionEnd());
                result.put("appliedText", field(service(), "appliedComposingText"));
                result.put("appliedStart", field(service(), "composingRegionStart")); result.put("focusedField", editors().indexOf(activity.getCurrentFocus()));
                result.put("composing", engine().composingText()); result.put("reading", engine().readingText());
                result.put("candidateWindows", candidateRoots().size()); result.put("page", engine().page());
                result.put("highlight", engine().highlightedIndex()); return result;
            } catch (Exception error) { throw new AssertionError(error); }
        });
        evidence.put(row);
        Bundle status = new Bundle(); status.putString("keykey_physical_stage", row.toString()); instrumentation.sendStatus(0, status);
    }
}
