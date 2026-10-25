package tw.chichi77.keykey.android;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.function.Predicate;

/** JNI ownership and native FE adaptation; all core algorithms stay in Rust. */
final class GuanyinmaInputEngine implements InputEngine {
    private static final int PAGE_SIZE = BopomofoEngine.CANDIDATES_PER_PAGE;
    private final String modelPath;
    private final String userDatabasePath;
    private GuanyinmaNative nativeSession;
    private JSONObject snapshot;
    private Predicate<String> candidateFilter;
    private AssociatedPhraseDictionary associated = AssociatedPhraseDictionary.empty();
    private TableInputOptions options;
    private BopomofoKeyboardLayout layout;
    private BopomofoEngine.InputMode mode = BopomofoEngine.InputMode.BOPOMOFO;
    private EnumSet<BopomofoEngine.InputMode> allowedModes = EnumSet.allOf(BopomofoEngine.InputMode.class);
    private boolean shifted, temporaryEnglish, hardwareFullWidth, hardwareSmartEditing, hardwareTouchSmartEditing;
    private boolean useBigrams = true, spaceSelects;
    private enum Overlay { NONE, SYMBOLS, ASSOCIATED }
    private Overlay overlay = Overlay.NONE;
    private List<String> overlayCandidates = List.of();
    private int overlayPage, overlayHighlight;
    private String lastError;
    private long failureEpoch;

    GuanyinmaInputEngine(String modelPath, String userDatabasePath, ChineseInputMethod method,
            BopomofoKeyboardLayout layout, TableInputOptions options, boolean spaceSelects,
            boolean useBigrams, boolean hardwareSmartEditing, Predicate<String> filter) {
        this.modelPath = modelPath; this.userDatabasePath = userDatabasePath;
        this.layout = layout; this.options = InputEngine.copyOptions(options);
        this.spaceSelects = spaceSelects; this.useBigrams = useBigrams;
        this.hardwareSmartEditing = hardwareSmartEditing;
        this.candidateFilter = filter == null ? text -> true : filter;
        GuanyinmaNative opened = GuanyinmaNative.open(modelPath, configuration(method).toString(), candidateFilter);
        try { snapshot = parseSnapshot(opened.snapshot()); nativeSession = opened; }
        catch (RuntimeException | LinkageError error) { opened.close(); throw error; }
    }
    GuanyinmaInputEngine(String modelPath, String userDatabasePath, Predicate<String> filter) {
        this(modelPath, userDatabasePath, ChineseInputMethod.SMART, BopomofoKeyboardLayout.STANDARD,
                new TableInputOptions(ChineseInputMethod.CANGJIE), false, true, false, filter);
    }
    private static JSONObject object(Object... values) {
        try {
            JSONObject result = new JSONObject();
            for (int i = 0; i < values.length; i += 2) result.put((String) values[i], values[i + 1]);
            return result;
        } catch (JSONException error) { throw new IllegalArgumentException("Invalid Guanyinma operation", error); }
    }
    private static String methodName(ChineseInputMethod method) { return method.name().toLowerCase(Locale.ROOT); }
    private static String layoutName(BopomofoKeyboardLayout value) { return value == BopomofoKeyboardLayout.HSU ? "hsu" : "standard"; }
    private JSONObject smartOptions() {
        return object("use_bigrams", useBigrams, "space_opens_candidates", spaceSelects,
            "candidate_cursor_at_end", hardwareSmartEditing, "max_completed_syllables", 10,
            "shift_at_limit", !hardwareSmartEditing, "selection_returns_to_end", !hardwareSmartEditing,
            "candidate_selection_keys", "123456789");
    }
    private JSONObject learningOptions() {
        return object("user_phrases", true, "candidate_overrides", true, "bigrams", useBigrams, "table_learning", true);
    }
    private static JSONObject tableOptionsJSON(TableInputOptions value) {
        return object("realtime", value.composeWhileTyping, "prefix", value.prefixCandidates,
            "clear_on_error", value.clearOnError, "query_at_maximum", value.queryAtMaximum,
            "learn_selection", value.dynamicFrequency,
            "punctuation", value.punctuation == 1 ? "mixed" : value.punctuation == 2 ? "half" : "original");
    }
    private JSONObject configuration(ChineseInputMethod method) {
        return object("method", methodName(method), "profile", hardwareSmartEditing ? "desktop" : "touch",
            "layout", layoutName(layout), "user_database", userDatabasePath,
            "traditional_selection_keys", "123456789", "table_selection_keys", "123456789",
            "smart", smartOptions(), "learning", learningOptions(),
            "cangjie", tableOptionsJSON(method == ChineseInputMethod.CANGJIE ? options : new TableInputOptions(ChineseInputMethod.CANGJIE)),
            "simplex", tableOptionsJSON(method == ChineseInputMethod.SIMPLEX ? options : new TableInputOptions(ChineseInputMethod.SIMPLEX)));
    }
    private static JSONObject parseSnapshot(String json) {
        try {
            JSONObject parsed = new JSONObject(json);
            if (parsed.getInt("schema_version") != 1 || !parsed.getString("kind").equals("session")) {
                throw new IllegalStateException("Unsupported Guanyinma session snapshot");
            }
            parsed.getJSONObject("effects"); parsed.getJSONArray("candidates"); parsed.getJSONArray("readings");
            parsed.getString("visible_text"); parsed.getString("composition");
            return parsed;
        } catch (JSONException error) { throw new IllegalStateException("Invalid Guanyinma snapshot", error); }
    }
    private String text(String key) {
        try { return snapshot.getString(key); }
        catch (JSONException error) { throw new IllegalStateException("Missing Guanyinma " + key, error); }
    }
    private int number(String key) {
        try { return snapshot.getInt(key); }
        catch (JSONException error) { throw new IllegalStateException("Missing Guanyinma " + key, error); }
    }
    private JSONArray array(String key) {
        try { return snapshot.getJSONArray(key); }
        catch (JSONException error) { throw new IllegalStateException("Missing Guanyinma " + key, error); }
    }
    private static List<String> strings(JSONArray values) {
        try {
            List<String> result = new ArrayList<>(values.length());
            for (int i = 0; i < values.length(); ++i) result.add(values.getString(i));
            return List.copyOf(result);
        } catch (JSONException error) { throw new IllegalStateException("Invalid Guanyinma strings", error); }
    }
    private BopomofoEngine.Result apply(JSONObject operation) {
        JSONObject next = parseSnapshot(nativeSession.apply(operation.toString()));
        try {
            JSONObject effects = next.getJSONObject("effects");
            BopomofoEngine.Result result = new BopomofoEngine.Result(effects.getString("commit"),
                    effects.getBoolean("delete_backward"), effects.getBoolean("send_return"), effects.getBoolean("discard_composition"));
            snapshot = next; lastError = null; return result;
        } catch (JSONException error) { throw new IllegalStateException("Invalid Guanyinma effects", error); }
    }
    private BopomofoEngine.Result operate(JSONObject operation) {
        try { return apply(operation); }
        catch (RuntimeException error) { failureEpoch++; lastError = diagnostic(error); return BopomofoEngine.Result.update(); }
    }
    private static String diagnostic(Throwable error) {
        String message = error.getMessage(); return message == null || message.isEmpty() ? error.getClass().getSimpleName() : message;
    }
    String lastError() { return lastError; }
    String snapshotJSON() { return snapshot.toString(); }
    private BopomofoEngine.Result key(String value) { return operate(object("type", "key", "key", value)); }
    private void clearOverlay() { overlay = Overlay.NONE; overlayCandidates = List.of(); overlayPage = overlayHighlight = 0; }
    private List<String> visible(List<String> values) {
        List<String> result = new ArrayList<>();
        for (String value : values) if (candidateFilter.test(value)) result.add(value);
        return List.copyOf(result);
    }
    private BopomofoEngine.Result offerAssociated(BopomofoEngine.Result result) {
        if (!hasComposition() && result.committedText().codePointCount(0, result.committedText().length()) == 1) {
            List<String> values = visible(associated.candidates(result.committedText()));
            if (!values.isEmpty()) { overlay = Overlay.ASSOCIATED; overlayCandidates = values; overlayPage = overlayHighlight = 0; }
        }
        return result;
    }
    private BopomofoEngine.Result direct(String value) {
        BopomofoEngine.Result finished = finishCompositionForInputHandoff();
        if (lastError != null) return finished;
        BopomofoEngine.Result literal = operate(object("type", "direct_text", "text", value));
        return new BopomofoEngine.Result(finished.committedText() + literal.committedText(),
                literal.deleteBeforeCursor(), literal.sendEnter(), literal.discardComposingText());
    }
    private BopomofoEngine.Result width(BopomofoEngine.Result result) {
        return !hardwareFullWidth || result.committedText().isEmpty() ? result : new BopomofoEngine.Result(
                BopomofoEngine.toFullWidth(result.committedText()), result.deleteBeforeCursor(), result.sendEnter(), result.discardComposingText());
    }
    @Override public void setCandidateFilter(Predicate<String> filter) {
        if (filter == null || filter == candidateFilter) return;
        if (hasComposition() || !displayedCandidates().isEmpty()) { lastError = "請先完成組字後再更新字型服務。"; return; }
        try {
            GuanyinmaNative replacement = GuanyinmaNative.open(modelPath, configuration(chineseInputMethod()).toString(), filter);
            JSONObject state;
            try {
                state = parseSnapshot(replacement.snapshot());
                if (mode != BopomofoEngine.InputMode.BOPOMOFO) state = parseSnapshot(replacement.apply(object("type", "set_english", "enabled", true).toString()));
            } catch (RuntimeException | LinkageError error) { replacement.close(); throw error; }
            nativeSession.close(); nativeSession = replacement; snapshot = state; candidateFilter = filter; lastError = null;
        } catch (RuntimeException error) { lastError = diagnostic(error); }
    }
    @Override public void setSpaceSelectsCandidates(boolean enabled) {
        if (enabled == spaceSelects) return;
        boolean old = spaceSelects; spaceSelects = enabled;
        operate(object("type", "set_smart_options", "options", smartOptions()));
        if (lastError != null) spaceSelects = old;
    }
    @Override public boolean spaceSelectsCandidates() { return spaceSelects; }
    @Override public void setUseBigrams(boolean enabled) {
        if (enabled == useBigrams) return;
        boolean old = useBigrams; useBigrams = enabled;
        try {
            apply(object("type", "set_learning_options", "options", learningOptions()));
            apply(object("type", "set_smart_options", "options", smartOptions()));
        } catch (RuntimeException error) { useBigrams = old; lastError = diagnostic(error); }
    }
    @Override public ChineseInputMethod chineseInputMethod() { return ChineseInputMethod.valueOf(text("method").toUpperCase(Locale.ROOT)); }
    @Override public void setTableCandidateSource(TableCandidateSource source) {}
    @Override public TableInputOptions tableOptions() { return InputEngine.copyOptions(options); }
    @Override public void setTableOptions(TableInputOptions next) {
        if (hasComposition()) { lastError = "請先完成組字後再變更字表設定。"; return; }
        if (chineseInputMethod().isTable()) {
            operate(object("type", "set_table_options", "method", methodName(chineseInputMethod()), "options", tableOptionsJSON(next)));
            if (lastError != null) return;
        }
        options = InputEngine.copyOptions(next);
    }
    @Override public BopomofoEngine.Result setChineseInputMethod(ChineseInputMethod method) {
        if (method == chineseInputMethod()) return BopomofoEngine.Result.update();
        BopomofoEngine.Result result = operate(object("type", "set_method", "method", methodName(method)));
        if (lastError == null) { clearOverlay(); options = new TableInputOptions(method); }
        return result;
    }
    @Override public BopomofoEngine.Result setCompositionMode(BopomofoCompositionMode value) {
        return setChineseInputMethod(value == BopomofoCompositionMode.SMART ? ChineseInputMethod.SMART : ChineseInputMethod.TRADITIONAL);
    }
    @Override public BopomofoKeyboardLayout keyboardLayout() { return layout; }
    @Override public BopomofoEngine.Result setKeyboardLayout(BopomofoKeyboardLayout value) {
        if (layout == value) return BopomofoEngine.Result.update();
        BopomofoEngine.Result result = operate(object("type", "set_layout", "layout", layoutName(value)));
        if (lastError == null) { layout = value; clearOverlay(); }
        return result;
    }
    @Override public void setAssociatedPhraseDictionary(AssociatedPhraseDictionary value) {
        associated = value == null ? AssociatedPhraseDictionary.empty() : value;
        if (overlay == Overlay.ASSOCIATED) clearOverlay();
    }
    @Override public void setAllowedInputModes(Set<BopomofoEngine.InputMode> allowed, BopomofoEngine.InputMode preferred) { setAllowedInputModes(allowed, preferred, false); }
    @Override public void setAllowedInputModes(Set<BopomofoEngine.InputMode> allowed, BopomofoEngine.InputMode preferred, boolean selectPreferred) {
        allowedModes = allowed == null || allowed.isEmpty() ? EnumSet.allOf(BopomofoEngine.InputMode.class) : EnumSet.copyOf(allowed);
        if (temporaryEnglish && !allowedModes.contains(BopomofoEngine.InputMode.BOPOMOFO)) temporaryEnglish = false;
        if (selectPreferred || !allowedModes.contains(mode)) {
            reset(); if (lastError != null) return;
            setMode(allowedModes.contains(preferred) ? preferred : allowedModes.iterator().next()); shifted = temporaryEnglish = false;
        }
    }
    private BopomofoEngine.Result setMode(BopomofoEngine.InputMode value) {
        BopomofoEngine.Result result = operate(object("type", "set_english", "enabled", value != BopomofoEngine.InputMode.BOPOMOFO));
        if (lastError == null) { clearOverlay(); mode = value; }
        return result;
    }
    @Override public boolean restoreInputModeState(InputEngineModeState state) {
        if (hasComposition() || !displayedCandidates().isEmpty()) return false;
        setMode(allowedModes.contains(state.mode) ? state.mode : allowedModes.iterator().next());
        if (lastError != null) return false;
        temporaryEnglish = state.temporaryEnglish && mode == BopomofoEngine.InputMode.ENGLISH && allowedModes.contains(BopomofoEngine.InputMode.BOPOMOFO);
        shifted = state.shifted && !temporaryEnglish; hardwareFullWidth = state.hardwareFullWidth; return true;
    }
    private void endTemporaryEnglish() {
        setMode(allowedModes.contains(BopomofoEngine.InputMode.BOPOMOFO) ? BopomofoEngine.InputMode.BOPOMOFO : allowedModes.iterator().next());
        if (lastError == null) temporaryEnglish = shifted = false;
    }
    @Override public BopomofoEngine.Result handleSoftKey(String value) {
        boolean restore = temporaryEnglish && !value.equals("SHIFT") && !value.equals("MODE");
        BopomofoEngine.Result result;
        switch (value) {
            case "MODE" -> {
                if (temporaryEnglish) { temporaryEnglish = shifted = false; result = BopomofoEngine.Result.update(); }
                else {
                    BopomofoEngine.InputMode next = mode;
                    do { next = BopomofoEngine.InputMode.values()[(next.ordinal() + 1) % BopomofoEngine.InputMode.values().length]; } while (!allowedModes.contains(next));
                    result = setMode(next); if (lastError == null) shifted = false;
                }
            }
            case "SHIFT" -> {
                if (temporaryEnglish) { endTemporaryEnglish(); result = BopomofoEngine.Result.update(); }
                else if (mode == BopomofoEngine.InputMode.BOPOMOFO && allowedModes.contains(BopomofoEngine.InputMode.ENGLISH)) {
                    result = setMode(BopomofoEngine.InputMode.ENGLISH); if (lastError == null) { temporaryEnglish = true; shifted = false; }
                } else { shifted = !shifted; result = BopomofoEngine.Result.update(); }
            }
            case "BACKSPACE" -> result = backspace();
            case "SPACE" -> result = space();
            case "ENTER" -> result = enter();
            case "ESCAPE" -> result = escape();
            case "SYMBOL" -> result = showOverlay(BopomofoEngine.symbolCandidates());
            case "EMOJI" -> result = showOverlay(BopomofoEngine.emojiCandidates());
            default -> result = value.codePointCount(0, value.length()) == 1 ? character(value, true) : BopomofoEngine.Result.update();
        }
        if (restore && lastError == null) endTemporaryEnglish();
        return result;
    }
    private BopomofoEngine.Result character(String value, boolean touch) {
        if (mode != BopomofoEngine.InputMode.BOPOMOFO) return direct(touch && shifted ? value.toUpperCase(Locale.ROOT) : value);
        if (touch && (value.equals("，") || value.equals("。"))) return direct(value);
        if (!touch && (chineseInputMethod() == ChineseInputMethod.SMART || chineseInputMethod().isTable())
                && value.length() == 1 && value.charAt(0) >= 'A' && value.charAt(0) <= 'Z') {
            if (chineseInputMethod() == ChineseInputMethod.SMART && !text("reading").isEmpty()) return BopomofoEngine.Result.update();
            return direct(value);
        }
        clearOverlay();
        return offerAssociated(operate(object("type", "character", "text", value.toLowerCase(Locale.ROOT))));
    }
    @Override public BopomofoEngine.Result handleHardwareCharacter(char value) {
        if (!prepareHardware()) return BopomofoEngine.Result.update();
        if (overlay == Overlay.SYMBOLS && value >= '1' && value <= '9') return width(selectDisplayedCandidate(value - '1'));
        if (chineseInputMethod().isTable() && !displayedCandidates().isEmpty() && (value == '<' || value == '>')) { changePage(value == '<' ? -1 : 1); return BopomofoEngine.Result.update(); }
        return width(character(String.valueOf(value), false));
    }
    @Override public BopomofoEngine.Result commitHardwareLiteral(char value) { return prepareHardware() ? width(direct(String.valueOf(value))) : BopomofoEngine.Result.update(); }
    @Override public BopomofoEngine.Result handleHardwareSpace() { return prepareHardware() ? space(hardwareFullWidth) : BopomofoEngine.Result.update(); }
    @Override public BopomofoEngine.Result toggleHardwareLanguage() {
        if (!prepareHardware()) return BopomofoEngine.Result.update();
        BopomofoEngine.Result result = setMode(mode == BopomofoEngine.InputMode.BOPOMOFO ? BopomofoEngine.InputMode.ENGLISH : BopomofoEngine.InputMode.BOPOMOFO);
        if (lastError == null) shifted = false; return result;
    }
    @Override public BopomofoEngine.Result toggleHardwareWidth() { if (prepareHardware()) hardwareFullWidth = !hardwareFullWidth; return BopomofoEngine.Result.update(); }
    @Override public BopomofoEngine.Result commitHardwarePunctuation(String value) {
        if (!prepareHardware() || (!text("reading").isEmpty() && chineseInputMethod() != ChineseInputMethod.SMART)) return BopomofoEngine.Result.update();
        return direct(value);
    }
    @Override public BopomofoEngine.Result showHardwareSymbols() {
        if (!prepareHardware() || (!text("reading").isEmpty() && chineseInputMethod() != ChineseInputMethod.SMART)) return BopomofoEngine.Result.update();
        return showOverlay(BopomofoEngine.symbolCandidates());
    }
    private boolean prepareHardware() { long before = failureEpoch; prepareForHardwareInput(); return before == failureEpoch; }
    @Override public void prepareForHardwareInput() { if (temporaryEnglish) endTemporaryEnglish(); setHardwareSmartEditing(!hardwareTouchSmartEditing); }
    @Override public void setHardwareTouchSmartEditing(boolean enabled) { hardwareTouchSmartEditing = enabled; }
    @Override public void setHardwareSmartEditing(boolean enabled) {
        if (enabled == hardwareSmartEditing) return;
        boolean old = hardwareSmartEditing; hardwareSmartEditing = enabled;
        try {
            apply(object("type", "set_profile", "profile", enabled ? "desktop" : "touch"));
            apply(object("type", "set_smart_options", "options", smartOptions()));
        } catch (RuntimeException error) { hardwareSmartEditing = old; failureEpoch++; lastError = diagnostic(error); }
    }
    private BopomofoEngine.Result showOverlay(List<String> values) {
        BopomofoEngine.Result result = finishCompositionForInputHandoff();
        if (lastError == null) { overlay = Overlay.SYMBOLS; overlayCandidates = visible(values); overlayPage = overlayHighlight = 0; }
        return result;
    }
    @Override public BopomofoEngine.Result space() { return space(false); }
    private BopomofoEngine.Result space(boolean fullWidth) {
        if (overlay != Overlay.NONE) { changePage(1); return BopomofoEngine.Result.update(); }
        if (!hasComposition()) return BopomofoEngine.Result.commit(fullWidth ? "　" : " ");
        if (fullWidth && chineseInputMethod() == ChineseInputMethod.SMART && text("reading").isEmpty() && !spaceSelects && array("candidates").length() == 0) return operate(object("type", "direct_text", "text", "　"));
        return offerAssociated(key("space"));
    }
    @Override public BopomofoEngine.Result openSmartCandidates() {
        if (chineseInputMethod() != ChineseInputMethod.SMART || mode != BopomofoEngine.InputMode.BOPOMOFO) return BopomofoEngine.Result.update();
        if (!text("reading").isEmpty()) return key("space");
        if (array("candidates").length() > 0) { changePage(1); return BopomofoEngine.Result.update(); }
        if (array("readings").length() == 0) return BopomofoEngine.Result.update();
        int index = hardwareSmartEditing ? Math.max(0, number("reading_cursor") - 1) : array("readings").length() - 1;
        return operate(object("type", "open_candidates", "index", index));
    }
    @Override public BopomofoEngine.Result enter() {
        if (overlay == Overlay.ASSOCIATED) { clearOverlay(); return BopomofoEngine.Result.enter(); }
        if (overlay != Overlay.NONE) return selectHighlightedCandidate();
        if (isTouchSmartComposition() && hasComposition()) {
            BopomofoEngine.Result result = finishCompositionForInputHandoff();
            return new BopomofoEngine.Result(result.committedText(), result.deleteBeforeCursor(), lastError == null, result.discardComposingText());
        }
        if (!hasComposition() && displayedCandidates().isEmpty()) return BopomofoEngine.Result.enter();
        return offerAssociated(key("return"));
    }
    @Override public BopomofoEngine.Result backspace() { clearOverlay(); return !hasComposition() ? BopomofoEngine.Result.delete() : key("backspace"); }
    @Override public BopomofoEngine.Result escape() {
        if (overlay != Overlay.NONE) { clearOverlay(); return BopomofoEngine.Result.update(); }
        if (!hardwareSmartEditing) { boolean had = hasComposition(); reset(); return had && lastError == null ? BopomofoEngine.Result.discardComposition() : BopomofoEngine.Result.update(); }
        return key("escape");
    }
    @Override public BopomofoEngine.Result selectDisplayedCandidate(int index) {
        List<String> values = displayedCandidates();
        if (index < 0 || index >= values.size()) return BopomofoEngine.Result.update();
        return overlay != Overlay.NONE ? direct(values.get(index)) : offerAssociated(operate(object("type", "select", "index", index)));
    }
    @Override public BopomofoEngine.Result selectHighlightedCandidate() { return selectDisplayedCandidate(highlightedIndex()); }
    @Override public void moveHighlight(int delta) {
        if (overlay != Overlay.NONE) {
            if (!overlayCandidates.isEmpty()) { int target = Math.floorMod(overlayPage * PAGE_SIZE + overlayHighlight + delta, overlayCandidates.size()); overlayPage = target / PAGE_SIZE; overlayHighlight = target % PAGE_SIZE; }
        } else if (array("candidates").length() > 0) {
            int current = page() * PAGE_SIZE + highlightedIndex();
            int target = Math.floorMod(current + delta, array("candidates").length());
            operate(object("type", "move_highlight", "delta", target - current));
        }
    }
    @Override public void changePage(int delta) {
        if (overlay == Overlay.NONE) operate(object("type", "page", "delta", delta));
        else if (pageCount() > 0) { overlayPage = Math.floorMod(overlayPage + delta, pageCount()); overlayHighlight = 0; }
    }
    @Override public boolean moveSmartCompositionCursor(int delta) {
        if (smartCompositionCursor() < 0 || !text("reading").isEmpty()) return false;
        operate(object("type", "close_candidates"));
        if (lastError != null) return false;
        operate(object("type", "set_cursor", "index", Math.max(0, Math.min(number("reading_cursor") + delta, array("readings").length()))));
        return lastError == null;
    }
    @Override public int smartCompositionCursor() { return hardwareSmartEditing && chineseInputMethod() == ChineseInputMethod.SMART && array("readings").length() > 0 ? number("reading_cursor") : -1; }
    @Override public List<String> touchSmartCells() { return touchSmartCells(11); }
    @Override public List<String> touchSmartCells(int cellCount) {
        if (!isTouchSmartComposition() || cellCount < 1) return List.of();
        ArrayList<String> result = new ArrayList<>();
        try {
            JSONArray segments = array("segments");
            for (int i = 0; i < segments.length(); ++i) {
                JSONObject segment = segments.getJSONObject(i); int span = segment.getInt("span");
                int[] points = segment.getString("text").codePoints().toArray();
                for (int j = 0; j < span; ++j) { int start = j * points.length / span, end = (j + 1) * points.length / span; result.add(new String(points, start, end - start)); }
            }
        } catch (JSONException error) { throw new IllegalStateException("Invalid Guanyinma segments", error); }
        text("reading").codePoints().forEach(point -> {
            String value = new String(Character.toChars(point));
            if (result.size() < cellCount) result.add(value); else result.set(cellCount - 1, result.get(cellCount - 1) + value);
        });
        return List.copyOf(result);
    }
    @Override public int touchSmartEditableCount() { return array("readings").length(); }
    @Override public boolean selectTouchSmartCell(int index) {
        if (!isTouchSmartComposition() || index < 0 || index >= array("readings").length()) return false;
        try {
            JSONArray spans = array("candidate_spans");
            if (spans.length() > 0 && spans.getJSONObject(0).getInt("start") == index) operate(object("type", "close_candidates"));
            else operate(object("type", "open_candidates", "index", index));
            return lastError == null;
        } catch (JSONException error) { lastError = diagnostic(error); return false; }
    }
    @Override public int composingCaretUtf16Offset() { String value = composingText(); return value.offsetByCodePoints(0, Math.min(number("cursor"), value.codePointCount(0, value.length()))); }
    @Override public void reset() {
        operate(object("type", "reset")); if (lastError != null) return;
        clearOverlay(); if (temporaryEnglish) endTemporaryEnglish(); shifted = false;
    }
    @Override public String readingText() { return text("reading"); }
    @Override public String composingText() { return text("visible_text"); }
    @Override public String completedSmartText() { return chineseInputMethod() == ChineseInputMethod.SMART ? text("composition") : ""; }
    @Override public boolean hasComposition() { return !composingText().isEmpty(); }
    @Override public boolean isTouchSmartComposition() { return chineseInputMethod() == ChineseInputMethod.SMART && mode == BopomofoEngine.InputMode.BOPOMOFO && !hardwareSmartEditing; }
    @Override public BopomofoCompositionMode compositionMode() { return chineseInputMethod() == ChineseInputMethod.SMART ? BopomofoCompositionMode.SMART : BopomofoCompositionMode.TRADITIONAL; }
    @Override public List<String> displayedCandidates() {
        if (overlay == Overlay.NONE) return strings(array("displayed_candidates"));
        int start = overlayPage * PAGE_SIZE; return start >= overlayCandidates.size() ? List.of() : overlayCandidates.subList(start, Math.min(start + PAGE_SIZE, overlayCandidates.size()));
    }
    @Override public int page() { return overlay == Overlay.NONE ? number("page") : overlayPage; }
    @Override public int pageCount() { return overlay == Overlay.NONE ? number("page_count") : (overlayCandidates.size() + PAGE_SIZE - 1) / PAGE_SIZE; }
    @Override public int highlightedIndex() { return displayedCandidates().isEmpty() ? -1 : overlay == Overlay.NONE ? snapshot.optInt("highlight", 0) : overlayHighlight; }
    @Override public boolean isEnglishMode() { return mode == BopomofoEngine.InputMode.ENGLISH; }
    @Override public BopomofoEngine.InputMode inputMode() { return mode; }
    @Override public boolean isShifted() { return shifted; }
    @Override public boolean isTemporaryEnglish() { return temporaryEnglish; }
    @Override public boolean isHardwareFullWidth() { return hardwareFullWidth; }
    @Override public boolean isShowingAssociatedPhrases() { return overlay == Overlay.ASSOCIATED; }
    @Override public boolean isShowingSmartCandidates() { return chineseInputMethod() == ChineseInputMethod.SMART && overlay == Overlay.NONE && array("candidates").length() > 0; }
    @Override public BopomofoEngine.Result finishCompositionForModeSwitch() { return finishCompositionForInputHandoff(); }
    @Override public BopomofoEngine.Result finishCompositionForInputHandoff() {
        if (!hasComposition()) { clearOverlay(); return BopomofoEngine.Result.update(); }
        if (chineseInputMethod() != ChineseInputMethod.SMART && array("candidates").length() > 0) {
            BopomofoEngine.Result result = operate(object("type", "select", "index", highlightedIndex()));
            if (lastError != null) return result;
            operate(object("type", "reset")); if (lastError == null) clearOverlay(); return result;
        }
        BopomofoEngine.Result result = operate(object("type", "finish")); if (lastError == null) clearOverlay(); return result;
    }
    @Override public BopomofoEngine.Result refreshUserData() { return operate(object("type", "save_learning")); }
    void resetLearning() { apply(object("type", "reset_method_learning", "method", "smart")); }
    static void resetLearning(String modelPath, String userDatabasePath) {
        try (GuanyinmaInputEngine engine = new GuanyinmaInputEngine(modelPath, userDatabasePath, text -> true)) { engine.resetLearning(); }
    }
    @Override public void close() { if (nativeSession != null) { nativeSession.close(); nativeSession = null; } }
}
