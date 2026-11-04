package tw.chichi77.keykey.android;

import static org.junit.Assert.*;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RectF;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.View;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.util.ArrayList;
import java.util.List;
import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public final class KeyboardRenderingInstrumentedTest {
    private record PlacementCase(KeyboardLayoutProfile.Plane plane,
            ChineseInputMethod method, InputEngine.InputMode inputMode) {}

    private static final List<PlacementCase> PLACEMENTS = List.of(
            new PlacementCase(KeyboardLayoutProfile.Plane.BOPOMOFO,
                    ChineseInputMethod.SMART, InputEngine.InputMode.BOPOMOFO),
            new PlacementCase(KeyboardLayoutProfile.Plane.CANGJIE,
                    ChineseInputMethod.CANGJIE, InputEngine.InputMode.BOPOMOFO),
            new PlacementCase(KeyboardLayoutProfile.Plane.SIMPLEX,
                    ChineseInputMethod.SIMPLEX, InputEngine.InputMode.BOPOMOFO),
            new PlacementCase(KeyboardLayoutProfile.Plane.ENGLISH,
                    ChineseInputMethod.SMART, InputEngine.InputMode.ENGLISH),
            new PlacementCase(KeyboardLayoutProfile.Plane.NUMBER_SYMBOLS,
                    ChineseInputMethod.SMART, InputEngine.InputMode.NUMBER));

    @Test public void spacingShrinksOnlyPaintAndRetainsEdgeTouchesAndCaptionPositions() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        instrumentation.runOnMainSync(() -> {
          for (var profile : KeyboardLayoutProfile.available()) {
            for (var orientation : KeyboardLayoutProfile.Orientation.values()) {
              for (var font : KeyboardLayoutProfile.FontSize.values()) {
                var view = new BopomofoKeyboardView(instrumentation.getTargetContext());
                view.setMode(orientation == KeyboardLayoutProfile.Orientation.PORTRAIT
                        ? BopomofoKeyboardView.Mode.PORTRAIT : BopomofoKeyboardView.Mode.LANDSCAPE);
                view.setKeyPreviewEnabled(false);
                view.setState(List.of(), "", false, List.of(), 0, InputEngine.InputMode.BOPOMOFO,
                        false, false, false, false, 0, 1, -1, InputFieldPolicy.DEFAULT);
                var events = new ArrayList<String>();
                view.setListener(keyListener(events));
                view.setLayoutProfile(profile);
                view.setLayoutOptions(KeyboardLayoutProfile.KeycapArea.SMALL, font,
                        KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER);
                KeyCanvas original = draw(view);
                for (var area : KeyboardLayoutProfile.KeycapArea.values()) {
                    view.setLayoutOptions(area, font, KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER);
                    KeyCanvas spaced = draw(view);
                    assertEquals(original.keys.size(), spaced.keys.size());
                    for (int index = 0; index < original.keys.size(); index++) {
                        RectF before = original.keys.get(index); RectF after = spaced.keys.get(index);
                        assertEquals(before.centerX(), after.centerX(), .01f);
                        assertEquals(before.centerY(), after.centerY(), .01f);
                        assertEquals(area.fraction, after.width() * after.height() / (before.width() * before.height()), .001f);
                    }
                    assertEquals("Caption size and position must not follow the smaller cap", original.texts, spaced.texts);
                    RectF first = original.keys.get(0);
                    if (area != KeyboardLayoutProfile.KeycapArea.SMALL) {
                        assertTrue(first.right - 1 > spaced.keys.get(0).right);
                    }
                    events.clear();
                    tap(view, first.right - 1, first.centerY());
                    assertEquals(List.of("1"), events);
                }
              }
            }
          }
        });
    }

    @Test public void enlargedTextUsesTheSameKeysWithoutHintsAndFitsInsideEachCap() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        instrumentation.runOnMainSync(() -> {
            for (var profile : KeyboardLayoutProfile.available()) {
                for (var orientation : KeyboardLayoutProfile.Orientation.values()) {
                    var view = new BopomofoKeyboardView(instrumentation.getTargetContext());
                    view.setMode(orientation == KeyboardLayoutProfile.Orientation.PORTRAIT
                            ? BopomofoKeyboardView.Mode.PORTRAIT : BopomofoKeyboardView.Mode.LANDSCAPE);
                    view.setState(List.of(), "", false, List.of(), 0, InputEngine.InputMode.BOPOMOFO,
                            false, false, false, false, 0, 1, -1, InputFieldPolicy.DEFAULT);
                    view.setLayoutProfile(profile);
                    view.setLayoutOptions(KeyboardLayoutProfile.KeycapArea.SMALL, KeyboardLayoutProfile.FontSize.NORMAL,
                            KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER);
                    KeyCanvas normal = draw(view);
                  for (var font : KeyboardLayoutProfile.FontSize.values()) {
                    if (font.showsHints()) continue;
                    view.setLayoutOptions(KeyboardLayoutProfile.KeycapArea.SMALL, font,
                            KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER);
                    KeyCanvas large = draw(view);
                    assertEquals(normal.keys, large.keys);
                    if (profile.split) {
                        for (var text : normal.texts) {
                            if (!text.value.contains("/") && !text.value.equals("空白")) continue;
                            RectF key = normal.keys.get(text.keyIndex);
                            assertTrue("Split control caption must fit: " + text.value,
                                    text.ink.left >= key.left - 1 && text.ink.right <= key.right + 1);
                        }
                    }
                    assertTrue(normal.texts.stream().anyMatch(text -> text.value.equals("1")));
                    assertFalse(large.texts.stream().anyMatch(text -> List.of("1", "q", "a").contains(text.value)));
                    for (var text : large.texts) {
                        if (text.keyIndex < 0) continue;
                        RectF key = large.keys.get(text.keyIndex);
                        assertTrue("Large glyph outside cap: " + text.value,
                                text.ink.left >= key.left - 1 && text.ink.right <= key.right + 1
                                && text.ink.top >= key.top - 1 && text.ink.bottom <= key.bottom + 1);
                    }
                    float regular = normal.texts.stream().filter(text -> text.value.equals("ㄅ")).findFirst().orElseThrow().size;
                    float enlarged = large.texts.stream().filter(text -> text.value.equals("ㄅ")).findFirst().orElseThrow().size;
                    assertTrue(enlarged > regular);
                  }
                }
            }
        });
    }

    @Test public void switchingEveryVisualOptionRetainsCompositionAndCandidateLabels() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        instrumentation.runOnMainSync(() -> {
            var view = new BopomofoKeyboardView(instrumentation.getTargetContext());
            view.setState(List.of("你好", "你"), "你好ㄋㄧ", true, List.of("你", "好", "ㄋ", "ㄧ"), 2,
                    InputEngine.InputMode.BOPOMOFO, false, false, false, false, 0, 2, 0, InputFieldPolicy.DEFAULT);
            for (var profile : KeyboardLayoutProfile.available()) {
                view.setLayoutProfile(profile);
                for (var position : KeyboardLayoutProfile.DeletePosition.values()) {
                  for (var font : KeyboardLayoutProfile.FontSize.values()) {
                    view.setLayoutOptions(KeyboardLayoutProfile.KeycapArea.LARGE, font, position);
                    KeyCanvas canvas = draw(view);
                    assertTrue(canvas.texts.stream().anyMatch(text -> text.value.contains("你好")));
                    assertTrue(canvas.texts.stream().anyMatch(text -> text.value.equals("ㄋ")));
                    assertTrue(canvas.texts.stream().anyMatch(text -> text.value.equals("ㄧ")));
                  }
                }
            }
        });
    }

    @Test public void extraLargeLatinSymbolsAndEnterUseTheDisplayedLabelAndKeepTouchActions() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        instrumentation.runOnMainSync(() -> {
            var view = new BopomofoKeyboardView(instrumentation.getTargetContext());
            view.setKeyPreviewEnabled(false);
            var events = new ArrayList<String>();
            view.setListener(keyListener(events));
            float density = view.getResources().getDisplayMetrics().density;
            for (var orientation : KeyboardLayoutProfile.Orientation.values()) {
                view.setMode(orientation == KeyboardLayoutProfile.Orientation.PORTRAIT
                        ? BopomofoKeyboardView.Mode.PORTRAIT : BopomofoKeyboardView.Mode.LANDSCAPE);
                for (var placement : PLACEMENTS) {
                    view.setChineseInputMethod(placement.method());
                    for (boolean temporary : new boolean[] {false, true}) {
                        view.setState(List.of(), "", false, List.of(), 0, placement.inputMode(),
                                false, temporary, false, false, 0, 1, -1, InputFieldPolicy.DEFAULT);
                        view.setLayoutOptions(KeyboardLayoutProfile.KeycapArea.SMALL, KeyboardLayoutProfile.FontSize.EXTRA_LARGE,
                                KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER);
                        KeyCanvas rendered = draw(view);
                        String expected = placement.inputMode() == InputEngine.InputMode.BOPOMOFO && !temporary
                                ? (placement.method().isTable() ? "重" : "ㄈ") : "z";
                        if (placement.inputMode() == InputEngine.InputMode.NUMBER) expected = "~";
                        String expectedLabel = expected;
                        PaintedText main = rendered.texts.stream().filter(text -> text.value.equals(expectedLabel))
                                .findFirst().orElseThrow();
                        RectF key = rendered.keys.get(main.keyIndex);
                        float widthRatio = Math.max(main.ink.width(), main.advance) / (key.width() - 4 * density);
                        float heightRatio = main.ink.height() / (key.height() - 4 * density);
                        assertEquals("Extra large must retain the original full fit for every displayed glyph",
                                1f,
                                Math.max(widthRatio, heightRatio), .08f);
                        events.clear();
                        tap(view, key.centerX(), key.centerY());
                        assertEquals(List.of(placement.inputMode() == InputEngine.InputMode.NUMBER ? "~" : "z"), events);
                        assertEquals(1, rendered.paths.size());
                        // The Enter path occupies half its square; the button and touch target do not shrink.
                        var enterAction = KeyboardLayoutGeometry.keys(KeyboardLayoutProfile.ALIGNED, orientation,
                                placement.plane(), false, KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER,
                                view.getWidth() / density).stream().filter(item -> item.action().equals("ENTER"))
                                .findFirst().orElseThrow();
                        float enterWidth = (enterAction.right() - enterAction.left()) * view.getWidth() - 4 * density;
                        float enterHeight = key.height();
                        float expectedSide = Math.min(enterWidth, enterHeight) - 4 * density;
                        assertEquals(expectedSide / 2f, rendered.paths.get(0).width(), .5f);
                    }
                }
            }
        });
    }

    @Test public void fontLevelsScaleCandidateCompositionAndReadingWithinUnchangedStrips() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        instrumentation.runOnMainSync(() -> {
            var view = new BopomofoKeyboardView(instrumentation.getTargetContext());
            view.setKeyPreviewEnabled(false);
            var events = new ArrayList<String>();
            view.setListener(new BopomofoKeyboardView.Listener() {
                @Override public void onPress() {}
                @Override public void onKey(String key) { events.add(key); }
                @Override public void onCandidate(int index) { events.add("candidate:" + index); }
                @Override public void onSmartCell(int index) { events.add("cell:" + index); }
                @Override public void onPage(int delta) { events.add("page:" + delta); }
            });
            for (var orientation : KeyboardLayoutProfile.Orientation.values()) {
                view.setMode(orientation == KeyboardLayoutProfile.Orientation.PORTRAIT
                        ? BopomofoKeyboardView.Mode.PORTRAIT : BopomofoKeyboardView.Mode.LANDSCAPE);
                List<RectF> original = null;
                float normalCandidate = 0, normalOrdinal = 0;
                for (var font : KeyboardLayoutProfile.FontSize.values()) {
                    view.setLayoutOptions(KeyboardLayoutProfile.KeycapArea.SMALL, font,
                            KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER);
                    view.setState(List.of("你", "a", "很長的候選詞測試"), "你好ㄋㄧ", true,
                            List.of("你", "好", "ㄋ", "ㄧ", "很長的組字測試"), 4, InputEngine.InputMode.BOPOMOFO,
                            false, false, false, false, 0, 2, 0, InputFieldPolicy.DEFAULT);
                    KeyCanvas canvas = draw(view);
                    if (original == null) original = canvas.keys;
                    else assertEquals("Font must not change any strip or key frame", original, canvas.keys);
                    // Candidate overlay is drawn after keys, whose normal hints can also be a/1.
                    PaintedText candidate = canvas.texts.stream().filter(text -> text.value.equals("a"))
                            .reduce((first, last) -> last).orElseThrow();
                    PaintedText ordinal = canvas.texts.stream().filter(text -> text.value.equals("1"))
                            .reduce((first, last) -> last).orElseThrow();
                    if (font.showsHints()) { normalCandidate = candidate.size; normalOrdinal = ordinal.size; }
                    assertEquals(normalOrdinal, ordinal.size, .01f);
                    assertEquals("Candidate text must use the selected strip font level",
                            normalCandidate * font.stripScale, candidate.size, .1f);
                    if (!font.showsHints()) {
                        for (var text : canvas.texts) {
                            if (!List.of("很長的候選詞測試", "很長的組字測試", "ㄋ", "ㄧ").contains(text.value)) continue;
                            assertInside(text, canvas.keys.get(text.keyIndex));
                        }
                    }
                    events.clear();
                    RectF candidateBounds = canvas.keys.get(candidate.keyIndex);
                    tap(view, candidateBounds.centerX(), candidateBounds.centerY());
                    assertEquals(List.of("candidate:1"), events);
                    PaintedText cell = canvas.texts.stream().filter(text -> text.value.equals("ㄋ")).findFirst().orElseThrow();
                    events.clear();
                    RectF cellBounds = canvas.keys.get(cell.keyIndex);
                    tap(view, cellBounds.centerX(), cellBounds.centerY());
                    assertEquals(List.of("cell:2"), events);

                    view.setState(List.of(), "ㄋㄧˇ", false, List.of(), 0, InputEngine.InputMode.BOPOMOFO,
                            false, false, false, false, 0, 1, -1, InputFieldPolicy.DEFAULT);
                    KeyCanvas readingCanvas = draw(view);
                    if (!font.showsHints()) {
                        PaintedText reading = readingCanvas.texts.stream().filter(text -> text.value.equals("ㄋㄧˇ"))
                                .findFirst().orElseThrow();
                        float stripBottom = readingCanvas.keys.get(0).top;
                        assertInside(reading, new RectF(0, 0, view.getWidth(), stripBottom));
                        assertTrue(readingCanvas.texts.stream().anyMatch(text -> text.value.equals("按空白選字")));
                    }
                }
            }
        });
    }

    private static void assertInside(PaintedText text, RectF bounds) {
        assertTrue("Text must fit its unchanged frame: " + text.value,
                text.ink.left >= bounds.left - 1 && text.ink.right <= bounds.right + 1
                && text.ink.top >= bounds.top - 1 && text.ink.bottom <= bounds.bottom + 1);
    }

    @Test public void integratedControlsShareTheExistingRowAndMandatoryGlobeWorksInEveryMode() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        instrumentation.runOnMainSync(() -> {
            var view = new BopomofoKeyboardView(instrumentation.getTargetContext());
            view.setKeyPreviewEnabled(false);
            var events = new ArrayList<String>();
            view.setListener(keyListener(events));
            view.setState(List.of(), "你ㄋ", true, List.of("你", "ㄋ"), 1,
                    InputEngine.InputMode.BOPOMOFO, false, false, false, false, 0, 1, -1, InputFieldPolicy.DEFAULT);
            for (var profile : KeyboardLayoutProfile.available()) {
                view.setLayoutProfile(profile);
                for (var orientation : KeyboardLayoutProfile.Orientation.values()) {
                    view.setMode(orientation == KeyboardLayoutProfile.Orientation.PORTRAIT
                            ? BopomofoKeyboardView.Mode.PORTRAIT : BopomofoKeyboardView.Mode.LANDSCAPE);
                    view.setBottomSpaceEnabled(true, true);
                    view.setIntegratedBottomControls(false, false);
                    KeyCanvas original = draw(view);
                    int originalHeight = view.getHeight();
                    view.setIntegratedBottomControls(true, true);
                    KeyCanvas integrated = draw(view);
                    float density = view.getResources().getDisplayMetrics().density;
                    assertEquals(Math.round((orientation == KeyboardLayoutProfile.Orientation.PORTRAIT ? 40 : 35) * density),
                            originalHeight - view.getHeight());
                    assertEquals(original.keys.size() + 2, integrated.keys.size());
                    for (String label : List.of("🌐", "▼")) {
                        PaintedText text = integrated.texts.stream().filter(item -> item.value.equals(label))
                                .reduce((first, last) -> last).orElseThrow();
                        events.clear(); RectF key = integrated.keys.get(text.keyIndex);
                        tap(view, key.centerX(), key.centerY());
                        assertEquals(List.of(label.equals("🌐") ? "GLOBE" : "DISMISS"), events);
                    }
                    assertTrue(integrated.texts.stream().anyMatch(item -> item.value.equals("ㄋ")));
                    RectF globeKey = integrated.keys.get(integrated.texts.stream()
                            .filter(item -> item.value.equals("🌐")).findFirst().orElseThrow().keyIndex);
                    RectF settingsKey = integrated.keys.get(integrated.texts.stream()
                            .filter(item -> item.value.equals("設")).findFirst().orElseThrow().keyIndex);
                    RectF dismissKey = integrated.keys.get(integrated.texts.stream()
                            .filter(item -> item.value.equals("▼")).findFirst().orElseThrow().keyIndex);
                    assertEquals(integrated.keys.stream().filter(key -> key.top == globeKey.top)
                            .mapToDouble(key -> key.left).min().orElseThrow(), globeKey.left, .01);
                    assertTrue(settingsKey.right < dismissKey.left);
                    for (var inputMode : InputEngine.InputMode.values()) {
                        for (var font : KeyboardLayoutProfile.FontSize.values()) {
                            view.setLayoutOptions(KeyboardLayoutProfile.KeycapArea.SMALL, font,
                                    KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER);
                            view.setState(List.of(), "你ㄋ", true, List.of("你", "ㄋ"), 1,
                                    inputMode, false, false, false, false, 0, 1, -1, InputFieldPolicy.DEFAULT);
                            KeyCanvas compact = draw(view);
                            String[] labels = InputFieldPolicy.DEFAULT.modeCaption(inputMode).split("/");
                            // The same single hit contains both truthful mode labels, without a slash.
                            var upper = compact.texts.stream().filter(item -> item.value.equals(labels[0])
                                    && item.keyIndex > view.compositionCellCount()).reduce((first, last) -> last).orElseThrow();
                            var lower = compact.texts.stream().filter(item -> item.value.equals(labels[1])
                                    && item.keyIndex == upper.keyIndex).findFirst().orElseThrow();
                            RectF modeKey = compact.keys.get(upper.keyIndex);
                            assertTrue(upper.x < modeKey.centerX() && upper.y < modeKey.centerY());
                            assertTrue(lower.x > modeKey.centerX() && lower.y > modeKey.centerY());
                            assertTrue(modeKey.contains(upper.ink) && modeKey.contains(lower.ink));
                            assertEquals(globeKey.width(), modeKey.width(), .01f);
                            events.clear(); tap(view, modeKey.centerX(), modeKey.centerY());
                            assertEquals(List.of("MODE"), events);
                        }
                    }
                    view.setLayoutOptions(KeyboardLayoutProfile.KeycapArea.SMALL, KeyboardLayoutProfile.FontSize.NORMAL,
                            KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER);
                    view.setIntegratedBottomControls(false, true);
                    KeyCanvas mandatory = draw(view);
                    assertEquals(originalHeight, view.getHeight());
                    assertEquals(original.keys.size() + 1, mandatory.keys.size());
                    assertTrue(mandatory.texts.stream().anyMatch(item -> item.value.equals("🌐")));
                    assertFalse(mandatory.texts.stream().anyMatch(item -> item.value.equals("▼")));
                }
            }
            view.setMode(BopomofoKeyboardView.Mode.HARDWARE);
            view.setIntegratedBottomControls(false, false);
            draw(view); int hardwareHeight = view.getHeight();
            view.setIntegratedBottomControls(false, true);
            KeyCanvas hardware = draw(view);
            assertEquals(hardwareHeight, view.getHeight());
            assertTrue(hardware.texts.stream().anyMatch(item -> item.value.equals("🌐")));
            view.setMode(BopomofoKeyboardView.Mode.HARDWARE_FLOATING);
            KeyCanvas floating = draw(view);
            assertEquals(1, floating.keys.size());
            assertEquals(List.of("🌐"), floating.texts.stream().map(item -> item.value)
                    .collect(java.util.stream.Collectors.toList()));
            events.clear(); tap(view, floating.keys.get(0).centerX(), floating.keys.get(0).centerY());
            assertEquals(List.of("GLOBE"), events);
            view.setIntegratedBottomControls(false, false);
            assertTrue(draw(view).keys.isEmpty());
            assertEquals(Math.round(view.getResources().getDisplayMetrics().density), view.getHeight());
        });
    }

    @Test public void pickerKeysLongPressConsumesSettingsAndGlobeGestures() throws Exception {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        var context = instrumentation.getTargetContext();
        android.app.Activity activity = instrumentation.startActivitySync(new android.content.Intent()
                .setClassName(context, "tw.chichi77.keykey.android.ImeTestActivity")
                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK));
        var events = new ArrayList<String>();
        var view = new BopomofoKeyboardView(context);
        final RectF[] key = {null};
        try {
            instrumentation.runOnMainSync(() -> {
                view.setListener(new BopomofoKeyboardView.Listener() {
                    @Override public void onPress() {}
                    @Override public void onKey(String key) { events.add(key); }
                    @Override public void onCandidate(int index) { fail(); }
                    @Override public void onSmartCell(int index) { fail(); }
                    @Override public void onPage(int delta) { fail(); }
                    @Override public void onInputMethodPicker() { events.add("picker"); }
                });
                activity.setContentView(view, new android.view.ViewGroup.LayoutParams(
                        android.view.ViewGroup.LayoutParams.MATCH_PARENT, android.view.ViewGroup.LayoutParams.WRAP_CONTENT));
            });
            instrumentation.waitForIdleSync();
            for (boolean integrated : new boolean[] {false, true}) {
                for (boolean globe : new boolean[] {false, true}) {
                    for (String action : globe ? List.of("SETTINGS", "GLOBE") : List.of("SETTINGS")) {
                        instrumentation.runOnMainSync(() -> {
                            view.setIntegratedBottomControls(integrated, globe);
                            KeyCanvas canvas = draw(view);
                            String label = action.equals("SETTINGS") ? "設" : "🌐";
                            var text = canvas.texts.stream().filter(item -> item.value.equals(label)).findFirst().orElseThrow();
                            key[0] = canvas.keys.get(text.keyIndex);
                            events.clear(); tap(view, key[0].centerX(), key[0].centerY());
                            assertEquals(List.of(action), events);
                            events.clear(); sendTouch(view, MotionEvent.ACTION_DOWN, key[0].centerX(), key[0].centerY());
                        });
                        Thread.sleep(android.view.ViewConfiguration.getLongPressTimeout() + 100L);
                        instrumentation.runOnMainSync(() -> {
                            sendTouch(view, MotionEvent.ACTION_MOVE, -1, -1);
                            sendTouch(view, MotionEvent.ACTION_MOVE, key[0].centerX(), key[0].centerY());
                            sendTouch(view, MotionEvent.ACTION_UP, key[0].centerX(), key[0].centerY());
                            assertEquals(List.of("picker"), events);
                            events.clear(); sendTouch(view, MotionEvent.ACTION_DOWN, key[0].centerX(), key[0].centerY());
                            sendTouch(view, MotionEvent.ACTION_MOVE, -1, -1);
                            sendTouch(view, MotionEvent.ACTION_MOVE, key[0].centerX(), key[0].centerY());
                        });
                        Thread.sleep(android.view.ViewConfiguration.getLongPressTimeout() + 100L);
                        instrumentation.runOnMainSync(() -> {
                            sendTouch(view, MotionEvent.ACTION_UP, key[0].centerX(), key[0].centerY());
                            assertTrue("Leaving the key cancels both actions", events.isEmpty());
                            sendTouch(view, MotionEvent.ACTION_DOWN, key[0].centerX(), key[0].centerY());
                            sendTouch(view, MotionEvent.ACTION_CANCEL, key[0].centerX(), key[0].centerY());
                        });
                        Thread.sleep(android.view.ViewConfiguration.getLongPressTimeout() + 100L);
                        instrumentation.runOnMainSync(() -> assertTrue(events.isEmpty()));
                    }
                }
            }
        } finally {
            instrumentation.runOnMainSync(activity::finish);
        }
    }

    @Test public void standardTableBottomRowMovesOnePitchWithoutMovingTheLastControl() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        instrumentation.runOnMainSync(() -> {
            var profile = KeyboardLayoutProfile.STANDARD;
            for (var orientation : KeyboardLayoutProfile.Orientation.values()) {
                var view = new BopomofoKeyboardView(instrumentation.getTargetContext());
                view.setLayoutProfile(profile);
                view.setMode(orientation == KeyboardLayoutProfile.Orientation.PORTRAIT
                        ? BopomofoKeyboardView.Mode.PORTRAIT : BopomofoKeyboardView.Mode.LANDSCAPE);
                view.setKeyPreviewEnabled(false);
                var events = new ArrayList<String>();
                view.setListener(keyListener(events));
                for (boolean shifted : new boolean[] {false, true}) {
                    for (var position : KeyboardLayoutProfile.DeletePosition.values()) {
                        for (var spacing : KeyboardLayoutProfile.KeycapArea.values()) {
                            for (var font : KeyboardLayoutProfile.FontSize.values()) {
                                view.setLayoutOptions(spacing, font, position);
                                view.setChineseInputMethod(ChineseInputMethod.SMART);
                                view.setState(List.of(), "", false, List.of(), 0, InputEngine.InputMode.BOPOMOFO,
                                        shifted, false, false, false, 0, 1, -1, InputFieldPolicy.DEFAULT);
                                var original = draw(view);
                                var oldActions = keyActions(profile, orientation, KeyboardLayoutProfile.Plane.BOPOMOFO,
                                        shifted, position);
                                RectF oldZ = original.keys.get(oldActions.indexOf("z"));
                                RectF oldX = original.keys.get(oldActions.indexOf("x"));
                                String control = position == KeyboardLayoutProfile.DeletePosition.ABOVE_ENTER
                                        ? "BACKSPACE" : "SHIFT";
                                RectF oldControl = original.keys.get(oldActions.indexOf(control));
                                for (var method : List.of(ChineseInputMethod.CANGJIE, ChineseInputMethod.SIMPLEX)) {
                                    view.setChineseInputMethod(method);
                                    var rendered = draw(view);
                                    var plane = method == ChineseInputMethod.CANGJIE
                                            ? KeyboardLayoutProfile.Plane.CANGJIE : KeyboardLayoutProfile.Plane.SIMPLEX;
                                    var actions = keyActions(profile, orientation, plane, shifted, position);
                                    assertFalse(actions.contains("/"));
                                    assertEquals(oldX, rendered.keys.get(actions.indexOf("z")));
                                    assertEquals(oldControl, rendered.keys.get(actions.indexOf(control)));
                                    assertEquals(original.keys.get(0), rendered.keys.get(0));
                                    assertTrue(rendered.texts.stream().anyMatch(text -> text.value.equals("重")));
                                    events.clear();
                                    tap(view, oldX.centerX(), oldX.centerY());
                                    assertEquals(List.of("z"), events);
                                    events.clear();
                                    tap(view, oldZ.centerX(), oldZ.centerY());
                                    assertTrue("The new leading space must not send a key", events.isEmpty());
                                    tap(view, oldControl.centerX(), oldControl.centerY());
                                    assertEquals(List.of(control), events);
                                }
                            }
                        }
                    }
                }
            }
        });
    }

    private static List<String> keyActions(KeyboardLayoutProfile profile,
            KeyboardLayoutProfile.Orientation orientation, KeyboardLayoutProfile.Plane plane,
            boolean shifted, KeyboardLayoutProfile.DeletePosition position) {
        var result = new ArrayList<String>();
        profile.layout(orientation).rows(plane, shifted, position).forEach(result::addAll);
        result.addAll(profile.layout(orientation).functionKeys(position));
        return result;
    }

    private static BopomofoKeyboardView.Listener keyListener(List<String> events) {
        return new BopomofoKeyboardView.Listener() {
            @Override public void onPress() {}
            @Override public void onKey(String key) { events.add(key); }
            @Override public void onCandidate(int index) { fail("Unexpected candidate"); }
            @Override public void onSmartCell(int index) { fail("Unexpected composition selection"); }
            @Override public void onPage(int delta) { fail("Unexpected page"); }
        };
    }

    private static KeyCanvas draw(BopomofoKeyboardView view) {
        int width = view.getResources().getDisplayMetrics().widthPixels;
        view.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED));
        view.layout(0, 0, view.getMeasuredWidth(), view.getMeasuredHeight());
        KeyCanvas canvas = new KeyCanvas(); view.draw(canvas); return canvas;
    }

    @Test public void touchProfilesRenderReachableActionsAcrossDirectionsAndPlacements() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        instrumentation.runOnMainSync(() -> {
            var context = instrumentation.getTargetContext();
            // Pairwise width samples keep this a frontend smoke, not a full UI matrix.
            int[] sampleWidthsDp = {320, 414, 768};
            int sample = 0;
            for (var profile : KeyboardLayoutProfile.available()) {
                for (var orientation : KeyboardLayoutProfile.Orientation.values()) {
                    var view = new BopomofoKeyboardView(context);
                    view.setLayoutProfile(profile);
                    view.setMode(orientation == KeyboardLayoutProfile.Orientation.PORTRAIT
                            ? BopomofoKeyboardView.Mode.PORTRAIT : BopomofoKeyboardView.Mode.LANDSCAPE);
                    view.setKeyPreviewEnabled(false);
                    var dispatched = new ArrayList<String>();
                    view.setListener(new BopomofoKeyboardView.Listener() {
                        @Override public void onPress() {}
                        @Override public void onKey(String key) { dispatched.add(key); }
                        @Override public void onCandidate(int index) { fail("Unexpected candidate action"); }
                        @Override public void onSmartCell(int index) { fail("Unexpected composition action"); }
                        @Override public void onPage(int delta) { fail("Unexpected page action"); }
                    });
                    for (var mapping : BopomofoKeyboardLayout.values()) {
                        view.setKeyboardLayout(mapping);
                        for (var placement : PLACEMENTS) {
                            view.setChineseInputMethod(placement.method());
                            for (boolean shifted : new boolean[] {false, true}) {
                              for (var deletePosition : KeyboardLayoutProfile.DeletePosition.values()) {
                                view.setLayoutOptions(KeyboardLayoutProfile.KeycapArea.SMALL, KeyboardLayoutProfile.FontSize.NORMAL, deletePosition);
                                // Keep candidates and editable cells empty to isolate key hit testing.
                                view.setState(List.of(), "", false, List.of(), 0, placement.inputMode(),
                                        shifted, false, false, false, 0, 1, -1, InputFieldPolicy.DEFAULT);
                                int width = Math.round(sampleWidthsDp[sample++ % sampleWidthsDp.length]
                                        * context.getResources().getDisplayMetrics().density);
                                view.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                                        View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED));
                                view.layout(0, 0, view.getMeasuredWidth(), view.getMeasuredHeight());
                                var canvas = new KeyCanvas();
                                view.draw(canvas);
                                var expected = new ArrayList<String>();
                                float widthDp = width / context.getResources().getDisplayMetrics().density;
                                KeyboardLayoutGeometry.resolvedRows(profile, orientation, placement.plane(), shifted,
                                        deletePosition, widthDp).forEach(expected::addAll);
                                expected.addAll(KeyboardLayoutGeometry.resolvedFunctionKeys(profile, orientation,
                                        deletePosition, widthDp));
                                assertEquals("Each declared action must have one painted key", expected.size(), canvas.keys.size());
                                dispatched.clear();
                                for (int index = 0; index < canvas.keys.size(); index++) {
                                    RectF bounds = canvas.keys.get(index);
                                    assertTrue("Key must have usable width", bounds.width() > 0);
                                    assertTrue("Key must have usable height", bounds.height() > 0);
                                    assertTrue("Key must remain inside the view", bounds.left >= 0 && bounds.top >= 0
                                            && bounds.right <= view.getWidth() && bounds.bottom <= view.getHeight());
                                    for (int previous = 0; previous < index; previous++) {
                                        assertFalse("Painted keys must not overlap", RectF.intersects(bounds, canvas.keys.get(previous)));
                                    }
                                    tap(view, bounds.centerX(), bounds.centerY());
                                }
                                assertEquals("Painting and hit testing must use the same profile actions", expected, dispatched);
                                if (profile.split) {
                                    dispatched.clear();
                                    for (RectF key : canvas.keys) tap(view, width / 2f, key.centerY());
                                    assertTrue("The centre gap must never dispatch a key", dispatched.isEmpty());
                                }
                              }
                            }
                        }
                    }
                }
            }
        });
    }

    private static void tap(View view, float x, float y) {
        long time = SystemClock.uptimeMillis();
        MotionEvent down = MotionEvent.obtain(time, time, MotionEvent.ACTION_DOWN, x, y, 0);
        MotionEvent up = MotionEvent.obtain(time, time + 1, MotionEvent.ACTION_UP, x, y, 0);
        try {
            view.onTouchEvent(down);
            view.onTouchEvent(up);
        } finally {
            down.recycle();
            up.recycle();
        }
    }

    private static void sendTouch(View view, int action, float x, float y) {
        long time = SystemClock.uptimeMillis();
        MotionEvent event = MotionEvent.obtain(time, time, action, x, y, 0);
        try { view.onTouchEvent(event); } finally { event.recycle(); }
    }

    private static final class KeyCanvas extends Canvas {
        final List<RectF> keys = new ArrayList<>();
        final List<PaintedText> texts = new ArrayList<>();
        final List<RectF> paths = new ArrayList<>();
        @Override public void drawRoundRect(RectF bounds, float rx, float ry, Paint paint) {
            keys.add(new RectF(bounds));
        }
        @Override public void drawText(String value, float x, float y, Paint paint) {
            android.graphics.Rect ink = new android.graphics.Rect();
            paint.getTextBounds(value, 0, value.length(), ink);
            float left = x - paint.measureText(value) / 2;
            texts.add(new PaintedText(value, x, y, paint.getTextSize(), paint.measureText(value), keys.size() - 1,
                    new RectF(left + ink.left, y + ink.top, left + ink.right, y + ink.bottom)));
        }
        @Override public void drawPath(android.graphics.Path path, Paint paint) {
            RectF bounds = new RectF();
            path.computeBounds(bounds, true);
            paths.add(bounds);
        }
    }
    private record PaintedText(String value, float x, float y, float size, float advance, int keyIndex, RectF ink) {}
}
