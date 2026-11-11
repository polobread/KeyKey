package tw.chichi77.keykey.android;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Rect;
import android.graphics.RectF;
import android.os.Handler;
import android.os.Looper;
import android.os.Build;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.WindowManager;
import android.view.WindowInsets;

import java.util.ArrayList;
import java.util.List;

final class BopomofoKeyboardView extends View {
    enum Mode { PORTRAIT, LANDSCAPE, HARDWARE, HARDWARE_FLOATING }

    interface Listener {
        void onPress();
        void onKey(String key);
        void onCandidate(int displayedIndex);
        void onSmartCell(int index);
        void onPage(int delta);
        default void onInputMethodPicker() {}
    }

    private enum HitKind { KEY, CANDIDATE, PAGE, SMART_CELL, CANDIDATE_BLOCK }

    private static final class Hit {
        private final RectF bounds;
        private final HitKind kind;
        private final String key;
        private final int candidateIndex;

        Hit(RectF bounds, HitKind kind, String key, int candidateIndex) {
            this.bounds = bounds;
            this.kind = kind;
            this.key = key;
            this.candidateIndex = candidateIndex;
        }

        RectF bounds() { return bounds; }
        HitKind kind() { return kind; }
        String key() { return key; }
        int candidateIndex() { return candidateIndex; }
    }

    private static final String[] HARDWARE_NUMBER_DIGITS = {
            "1", "2", "3", "4", "5", "6", "7", "8", "9", "0"
    };
    private static final String[] HARDWARE_NUMBER_SYMBOLS = {
            "!", "@", "#", "$", "%", "^", "&", "*", "(", ")"
    };
    private static final String[] HARDWARE_PUNCTUATION_KEYS = {
            "-", "=", "[", "]", ";", "'", ",", ".", "/", "\\", "`"
    };
    private static final String[] HARDWARE_PUNCTUATION_SYMBOLS = {
            "_", "+", "{", "}", ":", "\"", "<", ">", "?", "|", "~"
    };
    static final String HARDWARE_LITERAL_PREFIX = "HARDWARE_LITERAL:";
    private static final int PORTRAIT_SYSTEM_AREA_HEIGHT_DP = 40;
    private static final int LANDSCAPE_SYSTEM_AREA_HEIGHT_DP = 35;
    private static final int HARDWARE_CONTENT_HEIGHT_DP = 58;
    private static final int HARDWARE_NUMBER_ROW_HEIGHT_DP = 48;
    private static final int HARDWARE_PORTRAIT_SYSTEM_AREA_HEIGHT_DP = 40;
    private static final int HARDWARE_LANDSCAPE_SYSTEM_AREA_HEIGHT_DP = 35;
    private static final int PHONETIC_GRID_CELL_COUNT = 11;
    private static final float TONE_SYMBOL_SCALE = 1.8f;
    private static final String BOPOMOFO_HEIGHT_REFERENCE = "ㄅ";
    private static final String KEY_FONT_REFERENCE = "ㄖ";
    private static final float KEY_HINT_SCALE = 10f / 18;

    private final Paint backgroundPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint keyPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint specialKeyPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint candidatePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint candidateHighlightPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint textPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint hintPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint enterPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path enterPath = new Path();
    private final Rect referenceGlyphBounds = new Rect();
    private final Rect glyphBounds = new Rect();
    private final ArrayList<Hit> hits = new ArrayList<>();
    private float touchKeyTextSize;

    private Listener listener;
    private Mode mode = Mode.PORTRAIT;
    private KeyboardLayoutProfile layoutProfile = KeyboardLayoutProfile.ALIGNED;
    private KeyboardLayoutProfile.KeycapArea keycapArea = KeyboardLayoutProfile.KeycapArea.SMALL;
    private KeyboardLayoutProfile.FontSize fontSize = KeyboardLayoutProfile.FontSize.NORMAL;
    private KeyboardLayoutProfile.DeletePosition deletePosition = KeyboardLayoutProfile.DeletePosition.LEFT_OF_ENTER;
    private List<String> candidates = List.of();
    private String reading = "";
    private boolean smartMode;
    private boolean touchPhoneticGrid, phoneticPending, phoneticSpaceFirstTone;
    private List<String> smartCells = List.of();
    private int smartEditableCount;
    private ChineseInputMethod chineseInputMethod = ChineseInputMethod.SMART;
    private InputEngine.InputMode inputMode = InputEngine.InputMode.BOPOMOFO;
    private BopomofoKeyboardLayout keyboardLayout = BopomofoKeyboardLayout.STANDARD;
    private boolean shifted;
    private boolean temporaryEnglish;
    private boolean hardwareFullWidth;
    private int measuredContentHeight;
    private Mode lastMeasuredMode;
    private int lastDesiredContentHeight = -1;
    private int lastReservedHeight = -1;
    private int lastDesiredBottomGap = -1;
    private int measuredBottomGap;
    private int measuredHeightBudget;
    private Rect lastWindowBounds;
    private boolean touchBottomSpaceEnabled = true;
    private boolean hardwareBottomSpaceEnabled = true;
    private boolean integratedBottomControls;
    private int navigationBarBottomInset;
    private boolean showGlobe;
    private String pickerPressKey;
    private boolean pickerPressConsumed;
    private final Runnable pickerLongPress = () -> {
        if (pickerPressKey != null && listener != null) {
            pickerPressConsumed = true;
            listener.onInputMethodPicker();
        }
    };
    private boolean hardwareNumberRowEnabled;
    private boolean hardwareSmartTwoRowsEnabled;
    private boolean hardwareNumberShifted;
    private boolean supportPromptVisible;
    private boolean associatedPhrasesVisible;
    private InputFieldPolicy fieldPolicy = InputFieldPolicy.DEFAULT;
    private int page;
    private int pageCount;
    private int highlightedIndex = -1;
    private int candidateHighlightTextColor = Color.WHITE;
    private float downX;
    private float downY;
    private boolean downOnCandidate;
    private boolean backspaceTouchStarted;
    private final BackspaceRepeater backspaceRepeater =
            new BackspaceRepeater(new Handler(Looper.getMainLooper()));
    private boolean keyPreviewEnabled = true;
    private Hit previewHit;
    private KeyboardSizeSettings.Size portraitSize = KeyboardSizeSettings.DEFAULT_SIZE;
    private KeyboardSizeSettings.Size landscapeSize = KeyboardSizeSettings.DEFAULT_SIZE;
    private KeyboardEdgeGeometry resizePreview;
    private boolean resizeDragActive;

    BopomofoKeyboardView(Context context) {
        super(context);
        setBackgroundColor(Color.rgb(218, 223, 232));
        setFocusable(false);

        backgroundPaint.setColor(Color.rgb(218, 223, 232));
        keyPaint.setColor(Color.WHITE);
        specialKeyPaint.setColor(Color.rgb(198, 207, 222));
        candidatePaint.setColor(Color.rgb(244, 247, 252));
        candidateHighlightPaint.setColor(Color.rgb(128, 0, 128));
        textPaint.setColor(Color.rgb(24, 31, 44));
        textPaint.setTextAlign(Paint.Align.CENTER);
        hintPaint.setColor(Color.rgb(92, 102, 119));
        hintPaint.setTextAlign(Paint.Align.CENTER);
        enterPaint.setColor(Color.rgb(24, 31, 44));
        enterPaint.setStyle(Paint.Style.STROKE);
        enterPaint.setStrokeCap(Paint.Cap.ROUND);
        enterPaint.setStrokeJoin(Paint.Join.ROUND);
    }

    void setListener(Listener listener) {
        this.listener = listener;
    }

    void setLayoutProfile(KeyboardLayoutProfile profile) {
        if (layoutProfile == profile) return;
        layoutProfile = profile;
        backspaceRepeater.stop();
        backspaceTouchStarted = false;
        clearKeyPreview();
        hits.clear();
        requestLayout();
        invalidate();
    }

    void setLayoutOptions(KeyboardLayoutProfile.KeycapArea area,
            KeyboardLayoutProfile.FontSize size,
            KeyboardLayoutProfile.DeletePosition position) {
        if (keycapArea == area && fontSize == size && deletePosition == position) return;
        keycapArea = area;
        fontSize = size;
        deletePosition = position;
        backspaceRepeater.stop();
        backspaceTouchStarted = false;
        clearKeyPreview();
        hits.clear();
        invalidate();
    }

    void setKeyboardLayout(BopomofoKeyboardLayout layout) {
        if (keyboardLayout == layout) return;
        keyboardLayout = layout;
        previewHit = null;
        invalidate();
    }

    void setMode(Mode mode) {
        if (this.mode == mode) return;
        backspaceRepeater.stop();
        backspaceTouchStarted = false;
        this.mode = mode;
        previewHit = null;
        requestLayout();
        invalidate();
    }

    void setHardwareNumberRowEnabled(boolean enabled) {
        if (hardwareNumberRowEnabled == enabled) return;
        hardwareNumberRowEnabled = enabled;
        hardwareNumberShifted = false;
        if (mode == Mode.HARDWARE) requestLayout();
        invalidate();
    }

    void setHardwareSmartTwoRowsEnabled(boolean enabled) {
        if (hardwareSmartTwoRowsEnabled == enabled) return;
        hardwareSmartTwoRowsEnabled = enabled;
        if (mode == Mode.HARDWARE) requestLayout();
        invalidate();
    }

    private boolean usesHardwareSmartTwoRows() {
        return mode == Mode.HARDWARE && hardwareSmartTwoRowsEnabled && smartMode;
    }

    private boolean showsHardwareSmartCandidateRow() {
        return usesHardwareSmartTwoRows() && !candidates.isEmpty();
    }

    private int hardwareNumberRowCount() {
        return hardwareNumberRowEnabled ? 2 : hardwareSmartTwoRowsEnabled ? 1 : 0;
    }

    void setBottomSpaceEnabled(boolean touchEnabled, boolean hardwareEnabled) {
        if (touchBottomSpaceEnabled == touchEnabled
                && hardwareBottomSpaceEnabled == hardwareEnabled) return;
        touchBottomSpaceEnabled = touchEnabled;
        hardwareBottomSpaceEnabled = hardwareEnabled;
        requestLayout();
        invalidate();
    }

    void setIntegratedBottomControls(boolean integrated, boolean showGlobe) {
        if (integratedBottomControls == integrated && this.showGlobe == showGlobe) return;
        integratedBottomControls = integrated;
        this.showGlobe = showGlobe;
        cancelPickerPress();
        hits.clear();
        requestLayout();
        invalidate();
    }

    void toggleHardwareNumberShift() {
        hardwareNumberShifted = !hardwareNumberShifted;
        invalidate();
    }

    void setChineseInputMethod(ChineseInputMethod method) {
        if (chineseInputMethod == method) return;
        chineseInputMethod = method;
        previewHit = null;
        invalidate();
    }

    void setKeyPreviewEnabled(boolean enabled) {
        if (keyPreviewEnabled == enabled) return;
        keyPreviewEnabled = enabled;
        if (!enabled) previewHit = null;
        invalidate();
    }

    void setCandidateHighlightColors(int backgroundColor, int textColor) {
        candidateHighlightPaint.setColor(backgroundColor);
        candidateHighlightTextColor = textColor;
        invalidate();
    }

    void setTouchKeyboardHeightPercents(int portraitPercent, int landscapePercent) {
        setTouchKeyboardSizes(new KeyboardSizeSettings.Size(portraitPercent / 100f, portraitSize.bottomGapDp()),
                new KeyboardSizeSettings.Size(landscapePercent / 100f, landscapeSize.bottomGapDp()));
    }

    void setTouchKeyboardSizes(KeyboardSizeSettings.Size portrait, KeyboardSizeSettings.Size landscape) {
        if (portraitSize.equals(portrait) && landscapeSize.equals(landscape)) return;
        portraitSize = portrait;
        landscapeSize = landscape;
        if (isTouchMode()) requestLayout();
    }

    void setResizePreview(KeyboardEdgeGeometry edges) {
        if (java.util.Objects.equals(resizePreview, edges)) return;
        resizePreview = edges;
        requestLayout();
        invalidate();
    }

    void setResizeDragActive(boolean active) {
        if (resizeDragActive == active) return;
        resizeDragActive = active;
        if (active) {
            resetPickerPress();
            backspaceRepeater.stop();
            backspaceTouchStarted = false;
            downOnCandidate = false;
            // A key touch interrupted by resizing must not fire when it lifts.
            downX = Float.NaN;
            previewHit = null;
            hits.clear();
        }
        invalidate();
    }

    Mode mode() {
        return mode;
    }

    int defaultTouchHeight() {
        return dp(layoutProfile.layout(touchOrientation()).contentHeightDp);
    }

    int minimumTouchHeight() {
        return Math.round(defaultTouchHeight() * (KeyboardSizeSettings.MIN_PERCENT / 100f));
    }

    int maximumTouchHeight() {
        return Math.round(defaultTouchHeight() * (KeyboardSizeSettings.MAX_PERCENT / 100f));
    }

    int maximumResizeExtent(int availableHeight) {
        int reserved = Math.max(reservedSystemAreaHeight(), systemAreaHeight());
        return Math.max(visibleTouchEdges().top(), availableHeight - reserved);
    }

    KeyboardEdgeGeometry visibleTouchEdges() {
        int visibleContent = Math.round(contentHeight());
        int gap = Math.min(measuredBottomGap, Math.max(0, getHeight() - systemAreaHeight() - visibleContent));
        return new KeyboardEdgeGeometry(visibleContent + gap, gap);
    }

    void setState(List<String> candidates, String reading, boolean smartMode,
                  List<String> smartCells, int smartEditableCount,
                  InputEngine.InputMode inputMode,
                  boolean shifted, boolean temporaryEnglish, boolean hardwareFullWidth,
                  boolean supportPromptVisible, int page, int pageCount,
                  int highlightedIndex, InputFieldPolicy fieldPolicy) {
        this.candidates = List.copyOf(candidates);
        this.reading = reading;
        this.smartMode = smartMode;
        this.smartCells = List.copyOf(smartCells);
        this.smartEditableCount = smartEditableCount;
        this.inputMode = inputMode;
        this.shifted = shifted;
        this.temporaryEnglish = temporaryEnglish;
        this.hardwareFullWidth = hardwareFullWidth;
        this.supportPromptVisible = supportPromptVisible;
        this.page = page;
        this.pageCount = pageCount;
        this.highlightedIndex = highlightedIndex;
        this.fieldPolicy = fieldPolicy == null ? InputFieldPolicy.DEFAULT : fieldPolicy;
        invalidate();
    }

    void setPhoneticState(boolean grid, boolean pending, boolean spaceFirstTone) {
        if (touchPhoneticGrid == grid && phoneticPending == pending
                && phoneticSpaceFirstTone == spaceFirstTone) return;
        touchPhoneticGrid = grid;
        phoneticPending = pending;
        phoneticSpaceFirstTone = spaceFirstTone;
        invalidate();
    }

    void setAssociatedPhrasesVisible(boolean visible) {
        if (associatedPhrasesVisible == visible) return;
        associatedPhrasesVisible = visible;
        invalidate();
    }

    static String[][] shiftedEnglishRows() {
        return KeyboardLayoutProfile.ALIGNED.layout(KeyboardLayoutProfile.Orientation.PORTRAIT)
                .rows(KeyboardLayoutProfile.Plane.ENGLISH, true)
                .stream().map(row -> row.toArray(new String[0])).toArray(String[][]::new);
    }
    static String[][] shiftedNumberRows() {
        return KeyboardLayoutProfile.ALIGNED.layout(KeyboardLayoutProfile.Orientation.PORTRAIT)
                .rows(KeyboardLayoutProfile.Plane.NUMBER_SYMBOLS, true)
                .stream().map(row -> row.toArray(new String[0])).toArray(String[][]::new);
    }

    @Override
    public WindowInsets onApplyWindowInsets(WindowInsets insets) {
        if (Build.VERSION.SDK_INT >= 30) {
            // Parents may already have consumed this area. Only reserve what
            // reaches this view, rather than reading the root's original insets.
            int bottom = insets.getInsets(WindowInsets.Type.navigationBars()).bottom;
            if (navigationBarBottomInset != bottom) {
                navigationBarBottomInset = bottom;
                requestLayout();
                invalidate();
            }
        }
        return super.onApplyWindowInsets(insets);
    }

    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        int desiredContentHeight = switch (mode) {
            case HARDWARE_FLOATING -> dp(showGlobe ? HARDWARE_CONTENT_HEIGHT_DP : 1);
            case HARDWARE -> dp(HARDWARE_CONTENT_HEIGHT_DP
                    + hardwareNumberRowCount() * HARDWARE_NUMBER_ROW_HEIGHT_DP);
            case LANDSCAPE -> Math.round(defaultTouchHeight() * landscapeSize.heightScale());
            case PORTRAIT -> Math.round(defaultTouchHeight() * portraitSize.heightScale());
        };
        int desiredBottomGap = 0;
        if (isTouchMode()) {
            KeyboardSizeSettings.Size size = mode == Mode.LANDSCAPE ? landscapeSize : portraitSize;
            desiredBottomGap = dp(size.bottomGapDp());
            if (resizePreview != null) {
                desiredContentHeight = resizePreview.contentHeight();
                desiredBottomGap = resizePreview.bottom();
            }
        }
        // Budget the reserved area before clamping the keyboard content, even
        // when that area is disabled. Otherwise a capped IME keeps its height
        // and gives the removed padding to the keys instead of the host app.
        int systemAreaHeight = systemAreaHeight();
        int reservedHeight = Math.max(reservedSystemAreaHeight(), systemAreaHeight);
        int width = MeasureSpec.getSize(widthMeasureSpec);
        Rect windowBounds = Build.VERSION.SDK_INT >= 30
                ? getContext().getSystemService(WindowManager.class).getCurrentWindowMetrics().getBounds() : null;
        // Once the IME window has been sized, the framework measures its child
        // again within that window (including AT_MOST for a WRAP_CONTENT child).
        // Its old height is not a new screen cap when the reservation changes.
        // A cutout can change only the client width after WM allocates that height.
        boolean withinRequestedWindow = MeasureSpec.getMode(heightMeasureSpec) != MeasureSpec.UNSPECIFIED
                && MeasureSpec.getSize(heightMeasureSpec) == getMeasuredHeight()
                && mode == lastMeasuredMode
                && desiredContentHeight == lastDesiredContentHeight
                && reservedHeight == lastReservedHeight
                && desiredBottomGap == lastDesiredBottomGap
                && (windowBounds == null ? lastWindowBounds == null : windowBounds.equals(lastWindowBounds));
        if (!withinRequestedWindow) {
            measuredHeightBudget = resolveSize(desiredContentHeight + desiredBottomGap + reservedHeight,
                    heightMeasureSpec);
            int availableHeight = Math.max(0, measuredHeightBudget - reservedHeight);
            // A small host window may require reducing the optional gap before shrinking the keys.
            int minimumContent = isTouchMode() ? Math.min(desiredContentHeight, minimumTouchHeight()) : 0;
            measuredBottomGap = Math.min(desiredBottomGap, Math.max(0, availableHeight - minimumContent));
            measuredContentHeight = Math.min(desiredContentHeight, availableHeight - measuredBottomGap);
        }
        // Keep the content through old-window feedback, while obeying the
        // current parent spec. A WRAP_CONTENT root layout restores the total
        // height when it measures again against its upstream window budget.
        int desiredHeight = resolveSize(Math.min(measuredHeightBudget,
                measuredContentHeight + measuredBottomGap + systemAreaHeight), heightMeasureSpec);
        setMeasuredDimension(resolveSize(width, widthMeasureSpec), desiredHeight);
        lastMeasuredMode = mode;
        lastDesiredContentHeight = desiredContentHeight;
        lastReservedHeight = reservedHeight;
        lastDesiredBottomGap = desiredBottomGap;
        lastWindowBounds = windowBounds == null ? null : new Rect(windowBounds);
    }

    int cappedIntegratedWindowHeight() {
        return isTouchMode() && integratedBottomControls
                && (measuredContentHeight < lastDesiredContentHeight || measuredBottomGap < lastDesiredBottomGap)
                ? measuredHeightBudget : 0;
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        canvas.drawRect(0, 0, getWidth(), getHeight(), backgroundPaint);
        if (resizeDragActive) return;
        hits.clear();
        switch (mode) {
            case HARDWARE_FLOATING -> {
                if (showGlobe) drawHardwareStatusButton(canvas,
                        new RectF(Math.max(0, getWidth() - dp(HARDWARE_CONTENT_HEIGHT_DP)), 0,
                                getWidth(), dp(HARDWARE_CONTENT_HEIGHT_DP)), "🌐", "GLOBE");
            }
            case HARDWARE -> drawHardware(canvas);
            case LANDSCAPE -> drawLandscape(canvas);
            case PORTRAIT -> drawPortrait(canvas);
        }
        drawKeyPreview(canvas);
    }

    private void drawPortrait(Canvas canvas) {
        drawTouchKeyboard(canvas, false);
    }

    private void drawLandscape(Canvas canvas) {
        drawTouchKeyboard(canvas, true);
    }

    private void drawTouchKeyboard(Canvas canvas, boolean landscape) {
        float contentHeight = contentHeight();
        float top = landscape ? contentHeight / 6f : Math.max(dp(46), contentHeight * 0.15f);
        if (smartMode) {
            drawSmartCellStrip(canvas, new RectF(0, 0, getWidth(), top));
        } else {
            drawCandidateStrip(canvas, new RectF(0, 0, getWidth(), top));
        }

        var orientation = touchOrientation();
        var plane = inputPlane();
        var layout = layoutProfile.layout(orientation);
        float rowHeight = (contentHeight - top) / (layout.rows(plane, shifted).size() + 1);
        touchKeyTextSize = sharedTouchKeyTextSize(rowHeight);
        for (var key : KeyboardLayoutGeometry.keys(layoutProfile, orientation, plane, shifted, deletePosition,
                getWidth() / getResources().getDisplayMetrics().density, integratedBottomControls, showGlobe)) {
            RectF bounds = new RectF(key.left() * getWidth() + dp(2),
                    top + key.top() * (contentHeight - top) + dp(2),
                    key.right() * getWidth() - dp(2),
                    top + key.bottom() * (contentHeight - top) - dp(2));
            drawKey(canvas, bounds, key.action());
        }
        if (smartMode && !candidates.isEmpty()) {
            RectF overlay = new RectF(0, top, getWidth(), top + rowHeight);
            canvas.drawRect(overlay, backgroundPaint);
            hits.add(new Hit(new RectF(overlay), HitKind.CANDIDATE_BLOCK, "", -1));
            drawCandidateStrip(canvas, overlay);
        }
    }

    private void drawSmartCellStrip(Canvas canvas, RectF area) {
        int cellCount = compositionCellCount();
        if (isTouchMode() && layoutProfile.split) {
            var slots = KeyboardLayoutGeometry.splitStripSlots(cellCount + 1, widthDp(area));
            for (int index = 0; index < cellCount; index++) {
                drawSmartCell(canvas, inset(stripSlotBounds(area, slots.get(index)), dp(2)), index, cellCount);
            }
            drawStripControl(canvas, stripSlotBounds(area, slots.get(cellCount)), "▼", "DISMISS");
        } else {
            drawSmartCellStrip(canvas, area, cellCount);
        }
    }

    private void drawSmartCellStrip(Canvas canvas, RectF area, int cellCount) {
        float cellWidth = area.width() / cellCount;
        for (int index = 0; index < cellCount; index++) {
            RectF cell = new RectF(area.left + index * cellWidth + dp(2),
                    area.top + dp(2), area.left + (index + 1) * cellWidth - dp(2),
                    area.bottom - dp(2));
            drawSmartCell(canvas, cell, index, cellCount);
        }
    }

    private void drawSmartCell(Canvas canvas, RectF cell, int index, int cellCount) {
        boolean showSupport = supportPromptEligible() && reading.isEmpty()
                && smartCells.isEmpty() && candidates.isEmpty() && !associatedPhrasesVisible;
        canvas.drawRoundRect(cell, dp(6), dp(6), candidatePaint);
        if (showSupport && index >= cellCount - 3) {
            drawSupportPromptWord(canvas, cell, index - (cellCount - 3));
            return;
        }
        if (index >= smartCells.size()) return;
        String value = smartCells.get(index);
        textPaint.setTextSize(mode == Mode.LANDSCAPE ? dp(12) : dp(18));
        textPaint.setFakeBoldText(index < smartEditableCount);
        boolean splitTouch = isTouchMode() && layoutProfile.split;
        if (isTouchMode() && (!fontSize.showsHints() || splitTouch)) {
            fitStripText(textPaint, value, cell, textPaint.getTextSize());
        }
        float availableWidth = Math.max(1, cell.width() - dp(4));
        float measuredWidth = textPaint.measureText(value);
        if (measuredWidth > availableWidth) {
            float fittedSize = textPaint.getTextSize() * availableWidth / measuredWidth;
            // Split touch cells and hardware reading tails must fit their own slot.
            textPaint.setTextSize(usesHardwareSmartTwoRows() || splitTouch
                    ? fittedSize : Math.max(dp(8), fittedSize));
        }
        canvas.drawText(value, cell.centerX(), textBaseline(cell, textPaint), textPaint);
        if (index < smartEditableCount && !value.isEmpty()) {
            hits.add(new Hit(new RectF(cell), HitKind.SMART_CELL, "", index));
        }
    }

    private float widthDp(RectF area) {
        return area.width() / getResources().getDisplayMetrics().density;
    }

    private RectF stripSlotBounds(RectF area, KeyboardLayoutGeometry.StripSlot slot) {
        return new RectF(area.left + slot.left() * area.width(), area.top,
                area.left + slot.right() * area.width(), area.bottom);
    }

    private void drawStripControl(Canvas canvas, RectF bounds, String label, String action) {
        RectF cell = inset(bounds, dp(2));
        canvas.drawRoundRect(cell, dp(6), dp(6), specialKeyPaint);
        textPaint.setFakeBoldText(true);
        fitStripText(textPaint, label, cell, mode == Mode.LANDSCAPE ? dp(14) : dp(16));
        canvas.drawText(label, cell.centerX(), textBaseline(cell, textPaint), textPaint);
        hits.add(new Hit(new RectF(cell), HitKind.KEY, action, -1));
    }

    private void drawHardware(Canvas canvas) {
        RectF area = new RectF(0, 0, getWidth(), dp(HARDWARE_CONTENT_HEIGHT_DP));
        float gap = dp(2);
        int cellCount = InputEngine.CANDIDATES_PER_PAGE + 3;
        float cellWidth = area.width() / cellCount;
        boolean showSupport = supportPromptEligible() && candidates.isEmpty();
        if (usesHardwareSmartTwoRows()) {
            drawSmartCellStrip(canvas, new RectF(area.left, area.top,
                    area.left + InputEngine.CANDIDATES_PER_PAGE * cellWidth, area.bottom),
                    InputEngine.CANDIDATES_PER_PAGE);
        } else {
            for (int i = 0; i < InputEngine.CANDIDATES_PER_PAGE; i++) {
                RectF cell = new RectF(area.left + i * cellWidth + gap,
                        area.top + gap, area.left + (i + 1) * cellWidth - gap,
                        area.bottom - gap);
                if (showSupport && i >= 6) {
                    canvas.drawRoundRect(cell, dp(6), dp(6), candidatePaint);
                    drawSupportPromptWord(canvas, cell, i - 6);
                } else {
                    drawCandidate(canvas, cell, i);
                }
            }
        }
        drawHardwareEmojiButton(canvas, new RectF(
                area.left + InputEngine.CANDIDATES_PER_PAGE * cellWidth,
                area.top, area.left + (InputEngine.CANDIDATES_PER_PAGE + 1) * cellWidth,
                area.bottom));
        drawHardwareStatusButton(canvas, new RectF(
                area.left + (InputEngine.CANDIDATES_PER_PAGE + 1) * cellWidth,
                area.top, area.left + (InputEngine.CANDIDATES_PER_PAGE + 2) * cellWidth,
                area.bottom), inputMode == InputEngine.InputMode.BOPOMOFO ? chineseModeSymbol() : "英",
                "HARDWARE_LANGUAGE");
        drawHardwareStatusButton(canvas, new RectF(
                area.left + (InputEngine.CANDIDATES_PER_PAGE + 2) * cellWidth,
                area.top, area.right, area.bottom), "▼", "HARDWARE_COLLAPSE");
        if (hardwareNumberRowCount() > 0) {
            RectF numberArea = new RectF(0, area.bottom, getWidth(),
                    area.bottom + dp(HARDWARE_NUMBER_ROW_HEIGHT_DP));
            // Candidates occupy the existing number row without resizing the IME.
            // Draw only the active row so covered number/settings keys have no hits.
            if (showsHardwareSmartCandidateRow()) {
                drawCandidateStrip(canvas, numberArea);
            } else {
                drawHardwareNumberRow(canvas, numberArea);
            }
        }
        if (hardwareNumberRowEnabled) {
            drawHardwarePunctuationRow(canvas, new RectF(0,
                    area.bottom + dp(HARDWARE_NUMBER_ROW_HEIGHT_DP), getWidth(),
                    area.bottom + dp(2 * HARDWARE_NUMBER_ROW_HEIGHT_DP)));
        }
    }

    private void drawHardwareNumberRow(Canvas canvas, RectF area) {
        float cellWidth = area.width() / 12f;
        for (int index = 0; index < 12; index++) {
            RectF cell = new RectF(area.left + index * cellWidth, area.top,
                    area.left + (index + 1) * cellWidth, area.bottom);
            if (index < 10) {
                drawHardwareLiteralKey(canvas, inset(cell, dp(2)), HARDWARE_NUMBER_DIGITS[index],
                        HARDWARE_NUMBER_SYMBOLS[index]);
            } else if (index == 10) {
                drawHardwareStatusButton(canvas, cell, "符", "HARDWARE_SYMBOL");
            } else {
                drawHardwareStatusButton(canvas, cell, "設", "SETTINGS");
            }
        }
    }

    private void drawHardwarePunctuationRow(Canvas canvas, RectF area) {
        float cellWidth = area.width() / 12f;
        for (int index = 0; index < 11; index++) {
            RectF cell = inset(new RectF(area.left + index * cellWidth, area.top,
                    area.left + (index + 1) * cellWidth, area.bottom), dp(2));
            drawHardwareLiteralKey(canvas, cell, HARDWARE_PUNCTUATION_KEYS[index],
                    HARDWARE_PUNCTUATION_SYMBOLS[index]);
        }
        RectF shift = inset(new RectF(area.right - cellWidth, area.top,
                area.right, area.bottom), dp(2));
        canvas.drawRoundRect(shift, dp(6), dp(6), specialKeyPaint);
        textPaint.setTextSize(dp(18));
        textPaint.setFakeBoldText(hardwareNumberShifted);
        canvas.drawText("⇧", shift.centerX(), textBaseline(shift, textPaint), textPaint);
        hits.add(new Hit(new RectF(shift), HitKind.KEY, "HARDWARE_NUMBER_SHIFT", -1));
    }

    private void drawHardwareLiteralKey(Canvas canvas, RectF cell,
                                        String unshifted, String shiftedValue) {
        String primary = hardwareNumberShifted ? shiftedValue : unshifted;
        String secondary = hardwareNumberShifted ? unshifted : shiftedValue;
        canvas.drawRoundRect(cell, dp(6), dp(6), keyPaint);
        textPaint.setTextSize(dp(17));
        textPaint.setFakeBoldText(true);
        canvas.drawText(primary, cell.centerX(), cell.centerY() + dp(1), textPaint);
        hintPaint.setTextSize(dp(10));
        canvas.drawText(secondary, cell.centerX(), cell.bottom - dp(5), hintPaint);
        hits.add(new Hit(new RectF(cell), HitKind.KEY,
                HARDWARE_LITERAL_PREFIX + primary, -1));
    }

    private void drawHardwareStatusButton(Canvas canvas, RectF bounds, String label,
                                          String key) {
        RectF inset = inset(bounds, dp(2));
        canvas.drawRoundRect(inset, dp(6), dp(6), specialKeyPaint);

        boolean collapse = key.equals("HARDWARE_COLLAPSE");
        textPaint.setTextSize(dp(collapse ? 14 : 18));
        textPaint.setFakeBoldText(!collapse);
        canvas.drawText(label, inset.centerX(), textBaseline(inset, textPaint), textPaint);
        hits.add(new Hit(new RectF(inset), HitKind.KEY, key, -1));
    }

    private void drawHardwareEmojiButton(Canvas canvas, RectF bounds) {
        if (showGlobe) {
            drawHardwareStatusButton(canvas, bounds, "🌐", "GLOBE");
            return;
        }
        RectF inset = inset(bounds, dp(2));
        boolean enabled = fieldPolicy.isKeyEnabled("EMOJI", inputMode, shifted);
        int savedAlpha = canvas.saveLayerAlpha(inset, enabled ? 255 : 92);
        canvas.drawRoundRect(inset, dp(6), dp(6), specialKeyPaint);
        textPaint.setTextSize(dp(18));
        textPaint.setFakeBoldText(false);
        canvas.drawText("☺", inset.centerX(), textBaseline(inset, textPaint), textPaint);
        canvas.restoreToCount(savedAlpha);
        if (enabled) hits.add(new Hit(new RectF(inset), HitKind.KEY, "EMOJI", -1));
    }

    private void drawCandidateStrip(Canvas canvas, RectF area) {
        if (isTouchMode() && layoutProfile.split) {
            drawSplitCandidateStrip(canvas, area);
            return;
        }
        if (candidates.isEmpty()) {
            drawEmptyCandidateMessage(canvas, area);
            return;
        }

        float gap = dp(2);
        int cellCount = InputEngine.CANDIDATES_PER_PAGE + 2;
        float cellWidth = area.width() / cellCount;
        drawPageButton(canvas, new RectF(area.left, area.top,
                area.left + cellWidth, area.bottom), -1, "▲");
        for (int i = 0; i < InputEngine.CANDIDATES_PER_PAGE; i++) {
            RectF cell = new RectF(area.left + (i + 1) * cellWidth + gap,
                    area.top + gap, area.left + (i + 2) * cellWidth - gap, area.bottom - gap);
            drawCandidate(canvas, cell, i);
        }
        drawPageButton(canvas, new RectF(area.right - cellWidth, area.top,
                area.right, area.bottom), 1, "▼");
    }

    private void drawSplitCandidateStrip(Canvas canvas, RectF area) {
        int candidateCount = InputEngine.CANDIDATES_PER_PAGE;
        var slots = KeyboardLayoutGeometry.splitStripSlots(candidateCount + 3, widthDp(area));
        var last = stripSlotBounds(area, slots.get(slots.size() - 1));
        if (candidates.isEmpty()) {
            int half = slots.size() / 2;
            RectF left = new RectF(area.left, area.top,
                    stripSlotBounds(area, slots.get(half - 1)).right, area.bottom);
            RectF right = new RectF(stripSlotBounds(area, slots.get(half)).left,
                    area.top, last.left, area.bottom);
            if (!reading.isEmpty()) {
                drawStripMessage(canvas, left, reading, true);
                drawStripMessage(canvas, right, readingInstruction(), false);
            } else if (supportPromptVisible && inputMode == InputEngine.InputMode.BOPOMOFO) {
                drawStripMessage(canvas, left, bopomofoLayoutName(), false);
                drawStripMessage(canvas, right, getResources().getString(R.string.supporter_prompt), false);
            } else {
                drawStripMessage(canvas, left, emptyCandidateMessage(), false);
            }
        } else {
            drawPageButton(canvas, stripSlotBounds(area, slots.get(0)), -1, "▲");
            for (int index = 0; index < candidateCount; index++) {
                drawCandidate(canvas, inset(stripSlotBounds(area, slots.get(index + 1)), dp(2)), index);
            }
            drawPageButton(canvas, stripSlotBounds(area, slots.get(candidateCount + 1)), 1, "▼");
        }
        boolean canCloseCandidates = smartMode && !candidates.isEmpty();
        drawStripControl(canvas, last, canCloseCandidates ? "×" : "▼",
                canCloseCandidates ? "CLOSE_CANDIDATES" : "DISMISS");
    }

    private void drawStripMessage(Canvas canvas, RectF bounds, String message, boolean primary) {
        RectF content = inset(bounds, dp(2));
        Paint paint = primary ? textPaint : hintPaint;
        paint.setFakeBoldText(false);
        fitStripText(paint, message, content, standardHintTextSize());
        int save = canvas.save();
        canvas.clipRect(content);
        canvas.drawText(message, content.centerX(), textBaseline(content, paint), paint);
        canvas.restoreToCount(save);
    }

    private void drawCandidate(Canvas canvas, RectF bounds, int index) {
        boolean highlighted = index == highlightedIndex && index < candidates.size();
        canvas.drawRoundRect(bounds, dp(6), dp(6),
                highlighted ? candidateHighlightPaint : candidatePaint);
        int previousHintColor = hintPaint.getColor();
        int previousTextColor = textPaint.getColor();
        if (highlighted) {
            hintPaint.setColor(candidateHighlightTextColor);
            textPaint.setColor(candidateHighlightTextColor);
        }
        String number = Integer.toString(index + 1);
        hintPaint.setTextAlign(Paint.Align.LEFT);
        hintPaint.setTextSize(mode == Mode.LANDSCAPE ? dp(7) : dp(10));
        canvas.drawText(number, bounds.left + dp(5),
                bounds.top + (mode == Mode.LANDSCAPE ? dp(8) : dp(12)), hintPaint);
        hintPaint.setTextAlign(Paint.Align.CENTER);
        if (index < candidates.size()) {
            String value = candidates.get(index);
            textPaint.setTextSize(mode == Mode.LANDSCAPE ? dp(12) : dp(18));
            textPaint.setFakeBoldText(true);
            if (isTouchMode() && (!fontSize.showsHints() || layoutProfile.split)) {
                fitStripText(textPaint, value, bounds, textPaint.getTextSize());
            }
            canvas.drawText(value, bounds.centerX(), textBaseline(bounds, textPaint), textPaint);
            hits.add(new Hit(new RectF(bounds), HitKind.CANDIDATE, "", index));
        }
        hintPaint.setColor(previousHintColor);
        textPaint.setColor(previousTextColor);
    }

    private void drawPageButton(Canvas canvas, RectF bounds, int delta, String label) {
        RectF inset = inset(bounds, dp(2));
        canvas.drawRoundRect(inset, dp(6), dp(6), specialKeyPaint);
        textPaint.setTextSize(mode == Mode.LANDSCAPE ? dp(14) : dp(16));
        textPaint.setFakeBoldText(true);
        canvas.drawText(label, inset.centerX(), textBaseline(inset, textPaint), textPaint);
        hits.add(new Hit(new RectF(inset), HitKind.PAGE, "", delta));
    }

    private void drawEmptyCandidateMessage(Canvas canvas, RectF area) {
        if (!reading.isEmpty() && isTouchMode() && !fontSize.showsHints()) {
            drawReadingMessage(canvas, area);
            return;
        }
        if (reading.isEmpty() && supportPromptVisible && inputMode == InputEngine.InputMode.BOPOMOFO
                && (mode == Mode.PORTRAIT || mode == Mode.LANDSCAPE)) {
            drawSupportPrompt(canvas, area);
            return;
        }
        hintPaint.setTextSize(standardHintTextSize());
        canvas.drawText(emptyCandidateMessage(), area.centerX(), textBaseline(area, hintPaint), hintPaint);
    }

    private String emptyCandidateMessage() {
        if (!reading.isEmpty()) return reading + "　" + readingInstruction();
        if (inputMode == InputEngine.InputMode.ENGLISH) {
            return temporaryEnglish ? "暫時英文小寫" : shifted ? "英文大寫" : "英文小寫";
        }
        if (inputMode == InputEngine.InputMode.NUMBER) return shifted ? "數字與符號（二）" : "數字與符號（一）";
        return bopomofoLayoutName()
                + (mode == Mode.HARDWARE ? "・候選 1–9・關聯詞 Shift+1–9" : "");
    }

    private void fitStripText(Paint paint, String label, RectF bounds, float normalSize) {
        paint.setTextSize(normalSize * fontSize.stripScale);
        paint.getTextBounds(label, 0, label.length(), glyphBounds);
        Paint.FontMetrics metrics = paint.getFontMetrics();
        float width = Math.max(glyphBounds.width(), paint.measureText(label));
        float height = Math.max(glyphBounds.height(), metrics.descent - metrics.ascent);
        float scale = Math.min(1f, Math.min(Math.max(1, bounds.width() - dp(4)) / Math.max(1, width),
                Math.max(1, bounds.height() - dp(4)) / Math.max(1, height)));
        paint.setTextSize(paint.getTextSize() * scale);
    }

    private void drawReadingMessage(Canvas canvas, RectF area) {
        String instruction = readingInstruction();
        hintPaint.setTextSize(standardHintTextSize());
        float instructionWidth = hintPaint.measureText(instruction);
        float gap = standardHintTextSize();
        RectF readingBounds = new RectF(area);
        readingBounds.right -= instructionWidth + gap;
        textPaint.setFakeBoldText(false);
        fitStripText(textPaint, reading, readingBounds, standardHintTextSize());
        float readingWidth = textPaint.measureText(reading);
        float left = area.centerX() - (readingWidth + gap + instructionWidth) / 2f;
        canvas.drawText(reading, left + readingWidth / 2f, textBaseline(area, textPaint), textPaint);
        canvas.drawText(instruction, left + readingWidth + gap + instructionWidth / 2f,
                textBaseline(area, hintPaint), hintPaint);
    }

    private boolean usesPinyin() {
        return !chineseInputMethod.isTable() && keyboardLayout == BopomofoKeyboardLayout.HANYU_PINYIN;
    }

    private String readingInstruction() {
        return usesPinyin() ? "按空白輸入一聲" : "按空白選字";
    }

    private String chineseModeSymbol() {
        return usesPinyin() ? "拼" : chineseInputMethod.symbol;
    }

    private String bopomofoLayoutName() {
        if (chineseInputMethod.isTable()) return chineseInputMethod.displayName;
        return keyboardLayout == BopomofoKeyboardLayout.STANDARD
                ? keyboardLayout.displayName + "注音" : keyboardLayout.displayName;
    }

    private void drawSupportPrompt(Canvas canvas, RectF area) {
        String primary = bopomofoLayoutName();
        String secondary = getResources().getString(R.string.supporter_prompt);
        float primarySize = standardHintTextSize();
        float secondarySize = primarySize * 0.70f;
        float gap = dp(8);

        hintPaint.setTextSize(primarySize);
        float primaryWidth = hintPaint.measureText(primary);
        float baseline = textBaseline(area, hintPaint);
        hintPaint.setTextSize(secondarySize);
        float secondaryWidth = hintPaint.measureText(secondary);
        float startX = area.centerX() - (primaryWidth + gap + secondaryWidth) / 2f;

        hintPaint.setTextAlign(Paint.Align.LEFT);
        hintPaint.setTextSize(primarySize);
        canvas.drawText(primary, startX, baseline, hintPaint);
        hintPaint.setTextSize(secondarySize);
        canvas.drawText(secondary, startX + primaryWidth + gap, baseline, hintPaint);
        hintPaint.setTextAlign(Paint.Align.CENTER);
    }

    private boolean supportPromptEligible() {
        return supportPromptVisible && smartMode && chineseInputMethod == ChineseInputMethod.SMART
                && inputMode == InputEngine.InputMode.BOPOMOFO;
    }

    private void drawSupportPromptWord(Canvas canvas, RectF cell, int wordIndex) {
        int[] words = {R.string.supporter_prompt_welcome, R.string.supporter_prompt_paid,
                R.string.supporter_prompt_support};
        String word = getResources().getString(words[wordIndex]);
        hintPaint.setTextSize(standardHintTextSize());
        hintPaint.setFakeBoldText(false);
        float availableWidth = Math.max(1, cell.width() - dp(4));
        float measuredWidth = hintPaint.measureText(word);
        if (measuredWidth > availableWidth) {
            hintPaint.setTextSize(hintPaint.getTextSize() * availableWidth / measuredWidth);
        }
        canvas.drawText(word, cell.centerX(), textBaseline(cell, hintPaint), hintPaint);
    }

    private float standardHintTextSize() {
        return mode == Mode.LANDSCAPE ? dp(11) : dp(14);
    }

    private void drawKey(Canvas canvas, RectF bounds, String key) {
        boolean special = isSpecialKey(key);
        boolean enabled = fieldPolicy.isKeyEnabled(key, inputMode, shifted);
        int savedAlpha = canvas.saveLayerAlpha(bounds, enabled ? 255 : 92);
        RectF cap = new RectF(bounds);
        if (isTouchMode() && layoutProfile.staggered) cap.inset(dp(1), dp(1));
        RectF labelBounds = new RectF(cap);
        if (isTouchMode()) {
            float scale = (float) Math.sqrt(keycapArea.fraction);
            cap.inset(cap.width() * (1 - scale) / 2, cap.height() * (1 - scale) / 2);
        }
        canvas.drawRoundRect(cap, dp(6), dp(6), special ? specialKeyPaint : keyPaint);

        if (isTouchMode() && showGlobe && key.equals("MODE")) {
            drawCompactModeLabel(canvas, labelBounds);
            canvas.restoreToCount(savedAlpha);
            if (enabled) hits.add(new Hit(new RectF(bounds), HitKind.KEY, key, -1));
            return;
        }

        String symbol = bopomofoSymbol(key);
        if (isTouchMode() && !fontSize.showsHints() && !key.equals("ENTER")) {
            String label = !symbol.isEmpty() ? (temporaryEnglish ? key : symbol) : keyLabel(key);
            drawSizedKeyLabel(canvas, labelBounds, label,
                    touchKeyTextSize * (isToneSymbol(label) ? TONE_SYMBOL_SCALE : 1f));
            canvas.restoreToCount(savedAlpha);
            if (enabled) hits.add(new Hit(new RectF(bounds), HitKind.KEY, key, -1));
            return;
        }
        if (!symbol.isEmpty()) {
            drawBopomofoKey(canvas, bounds, symbol, key, temporaryEnglish);
            canvas.restoreToCount(savedAlpha);
            if (enabled) hits.add(new Hit(new RectF(bounds), HitKind.KEY, key, -1));
            return;
        }

        if (key.equals("ENTER")) {
            if (fieldPolicy.enterLabel().isEmpty()) drawEnterKey(canvas,
                    isTouchMode() && !fontSize.showsHints() ? labelBounds : bounds);
            else if (isTouchMode() && !fontSize.showsHints()) drawSizedKeyLabel(canvas, labelBounds,
                    fieldPolicy.enterLabel(), touchKeyTextSize);
            else drawEnterLabel(canvas, bounds, fieldPolicy.enterLabel());
            canvas.restoreToCount(savedAlpha);
            if (enabled) hits.add(new Hit(new RectF(bounds), HitKind.KEY, key, -1));
            return;
        }

        String label = keyLabel(key);
        textPaint.setFakeBoldText(false);
        int textSize = mode == Mode.LANDSCAPE ? (label.length() > 3 ? 9 : 12)
                : (label.length() > 3 ? 12 : 18);
        textPaint.setTextSize(dp(textSize));
        textPaint.setFakeBoldText(isTouchMode() || key.equals("SPACE")
                || (inputMode == InputEngine.InputMode.BOPOMOFO && !special));
        if (isTouchMode()) {
            float fittedSize = fittedKeyTextSize(labelBounds, label, dp(4));
            boolean control = isSpecialKey(key) && !List.of("SPACE", "，", "。", "、", "？", "SYMBOL", "SETTINGS").contains(key);
            textPaint.setTextSize(control ? Math.min(touchKeyTextSize, fittedSize) : touchKeyTextSize);
        }
        if (isTouchMode() && layoutProfile.split && special) {
            float availableWidth = Math.max(1, bounds.width() - dp(4));
            float labelWidth = textPaint.measureText(label);
            if (labelWidth > availableWidth) textPaint.setTextSize(textPaint.getTextSize() * availableWidth / labelWidth);
        }
        canvas.drawText(label, bounds.centerX(), textBaseline(bounds, textPaint), textPaint);
        canvas.restoreToCount(savedAlpha);
        if (enabled) hits.add(new Hit(new RectF(bounds), HitKind.KEY, key, -1));
    }

    private void drawSizedKeyLabel(Canvas canvas, RectF bounds, String label, float size) {
        textPaint.setFakeBoldText(true);
        boolean control = List.of("☺", "🌐", "⌫", "⇧", "▼").contains(label);
        boolean longCaption = label.codePointCount(0, label.length()) > 1 && !label.equals("空白");
        textPaint.setTextSize(control || longCaption
                ? Math.min(size, fittedKeyTextSize(bounds, label, dp(4))) : size);
        textPaint.getTextBounds(label, 0, label.length(), glyphBounds);
        float baseline = bounds.centerY() - (glyphBounds.top + glyphBounds.bottom) / 2f;
        float x = bounds.centerX() + textPaint.measureText(label) / 2f
                - (glyphBounds.left + glyphBounds.right) / 2f;
        canvas.drawText(label, x, baseline, textPaint);
    }

    private float sharedTouchKeyTextSize(float rowHeight) {
        // The ㄖ key is the reference for every input plane. Its real slot
        // follows the current view width, layout, direction and available height.
        var reference = KeyboardLayoutGeometry.keys(layoutProfile, touchOrientation(),
                KeyboardLayoutProfile.Plane.BOPOMOFO, false, deletePosition,
                getWidth() / getResources().getDisplayMetrics().density,
                integratedBottomControls, showGlobe).stream()
                .filter(key -> key.action().equals("b")).findFirst().orElseThrow();
        float stagger = layoutProfile.staggered ? 2 * dp(1) : 0;
        float width = Math.max(1, (reference.right() - reference.left()) * getWidth()
                - 2 * dp(2) - stagger - dp(4));
        float height = Math.max(1, rowHeight - 2 * dp(2) - stagger - dp(4));
        textPaint.setFakeBoldText(true);
        textPaint.setTextSize(100);
        textPaint.getTextBounds(KEY_FONT_REFERENCE, 0, KEY_FONT_REFERENCE.length(), referenceGlyphBounds);
        float referenceWidth = Math.max(referenceGlyphBounds.width(), textPaint.measureText(KEY_FONT_REFERENCE));
        Paint.FontMetrics primary = textPaint.getFontMetrics();
        float referenceHeight = Math.max(referenceGlyphBounds.height(), primary.descent - primary.ascent);
        float fullFit = 100 * Math.min(width / referenceWidth, height / referenceHeight);

        // Reserve the hint's own font box and spacing before maximizing the
        // standard caption. Both boxes scale with the computed main text size.
        hintPaint.setTextSize(100 * KEY_HINT_SCALE);
        Paint.FontMetrics secondary = hintPaint.getFontMetrics();
        float hintWidth = hintPaint.measureText(KEY_FONT_REFERENCE);
        String hints = "1234567890qwertyuiopasdfghjklzxcvbnm@";
        for (int index = 0; index < hints.length(); index++) {
            hintWidth = Math.max(hintWidth, hintPaint.measureText(hints, index, index + 1));
        }
        float hintHeight = secondary.descent - secondary.ascent;
        float gap = dp(2);
        float standardFit = 100 * Math.min(Math.max(1, width - gap) / (referenceWidth + hintWidth),
                Math.max(1, height - gap) / (referenceHeight + hintHeight));
        return KeyboardTypography.keyTextSize(fontSize, standardFit, fullFit);
    }

    private void drawCompactModeLabel(Canvas canvas, RectF bounds) {
        String[] labels = keyLabel("MODE").split("/", 2);
        if (labels.length != 2) {
            drawSizedKeyLabel(canvas, bounds, keyLabel("MODE"), touchKeyTextSize);
            return;
        }
        RectF upper = new RectF(bounds.left, bounds.top, bounds.centerX(), bounds.centerY());
        RectF lower = new RectF(bounds.centerX(), bounds.centerY(), bounds.right, bounds.bottom);
        float normalSize = touchKeyTextSize;
        drawSizedKeyLabel(canvas, upper, labels[0], Math.min(normalSize, fittedKeyTextSize(upper, labels[0], dp(4))));
        drawSizedKeyLabel(canvas, lower, labels[1], Math.min(normalSize, fittedKeyTextSize(lower, labels[1], dp(4))));
    }

    private float fittedKeyTextSize(RectF bounds, String label, float padding) {
        textPaint.setTextSize(100);
        textPaint.getTextBounds(label, 0, label.length(), glyphBounds);
        float availableWidth = Math.max(1, bounds.width() - padding);
        float availableHeight = Math.max(1, bounds.height() - padding);
        float scale = Math.min(availableWidth / Math.max(1, Math.max(glyphBounds.width(), textPaint.measureText(label))),
                availableHeight / Math.max(1, glyphBounds.height()));
        return 100 * scale;
    }

    private void drawEnterLabel(Canvas canvas, RectF bounds, String label) {
        textPaint.setFakeBoldText(true);
        float textSize = dp(mode == Mode.LANDSCAPE || label.length() > 2 ? 10 : 14);
        textPaint.setTextSize(textSize);
        float availableWidth = Math.max(1, bounds.width() - dp(6));
        float measuredWidth = textPaint.measureText(label);
        if (measuredWidth > availableWidth) {
            textPaint.setTextSize(Math.max(dp(7), textSize * availableWidth / measuredWidth));
        }
        float size = textPaint.getTextSize();
        textPaint.setTextSize(Math.min(size, fittedKeyTextSize(bounds, label, dp(4))));
        canvas.drawText(label, bounds.centerX(), textBaseline(bounds, textPaint), textPaint);
    }

    private void drawKeyPreview(Canvas canvas) {
        if (previewHit == null || !isTouchMode()) return;
        String label = previewLabel(previewHit.key());
        if (label.isEmpty()) return;

        RectF source = previewHit.bounds();
        float scale = 1.4f;
        float width = source.width() * scale;
        float height = source.height() * scale;
        float margin = dp(2);
        float left = Math.max(margin, Math.min(source.centerX() - width / 2f,
                getWidth() - margin - width));
        float bottom = source.top - dp(4);
        float top = bottom - height;
        if (top < margin) {
            top = margin;
            bottom = top + height;
        }
        RectF bounds = new RectF(left, top, left + width, bottom);
        canvas.drawRoundRect(bounds, dp(8), dp(8),
                isSpecialKey(previewHit.key()) ? specialKeyPaint : keyPaint);

        textPaint.setFakeBoldText(true);
        float normalSize = dp(mode == Mode.LANDSCAPE ? 17 : 25);
        float textSize = isToneSymbol(label) ? normalSize * TONE_SYMBOL_SCALE : normalSize;
        textPaint.setTextSize(textSize);
        Paint.FontMetrics metrics = textPaint.getFontMetrics();
        float availableHeight = Math.max(1, bounds.height() - dp(8));
        float measuredHeight = metrics.descent - metrics.ascent;
        if (measuredHeight > availableHeight) {
            textPaint.setTextSize(textSize * availableHeight / measuredHeight);
        }
        canvas.drawText(label, bounds.centerX(), textBaseline(bounds, textPaint), textPaint);
    }

    private void drawEnterKey(Canvas canvas, RectF bounds) {
        float side = dp(mode == Mode.LANDSCAPE ? 14 : 20);
        if (isTouchMode()) {
            side = touchKeyTextSize * (mode == Mode.LANDSCAPE ? 14f / 11 : 20f / 18);
        }
        float unit = side / 24f;
        float left = bounds.centerX() - side / 2f;
        float top = bounds.centerY() - side / 2f;
        enterPath.reset();
        enterPath.moveTo(left + 18 * unit, top + 6 * unit);
        enterPath.lineTo(left + 18 * unit, top + 13 * unit);
        enterPath.lineTo(left + 6 * unit, top + 13 * unit);
        enterPath.moveTo(left + 11 * unit, top + 9 * unit);
        enterPath.lineTo(left + 6 * unit, top + 13 * unit);
        enterPath.lineTo(left + 11 * unit, top + 17 * unit);
        enterPaint.setStrokeWidth(2 * unit);
        canvas.drawPath(enterPath, enterPaint);
    }

    private void drawBopomofoKey(Canvas canvas, RectF bounds, String symbol, String key,
                                 boolean keyFirst) {
        String primary = keyFirst ? key : symbol;
        String secondary = keyFirst ? symbol : key;
        textPaint.setFakeBoldText(true);
        if (mode == Mode.LANDSCAPE) {
            drawLandscapeBopomofoKey(canvas, bounds, primary, secondary);
            return;
        }

        float normalPrimarySize = touchKeyTextSize;
        float normalSecondarySize = touchKeyTextSize * KEY_HINT_SCALE;
        textPaint.setTextSize(normalPrimarySize);
        Paint.FontMetrics primaryMetrics = textPaint.getFontMetrics();
        hintPaint.setTextSize(normalSecondarySize);
        Paint.FontMetrics secondaryMetrics = hintPaint.getFontMetrics();
        float primaryHeight = primaryMetrics.descent - primaryMetrics.ascent;
        float secondaryHeight = secondaryMetrics.descent - secondaryMetrics.ascent;
        float top = bounds.centerY() - (primaryHeight + dp(2) + secondaryHeight) / 2f;
        float primarySize = isToneSymbol(primary)
                ? normalPrimarySize * TONE_SYMBOL_SCALE : normalPrimarySize;
        float primaryBaseline = top - primaryMetrics.ascent;
        if (isToneSymbol(primary)) {
            primaryBaseline = topAlignedBaseline(textPaint, primary, primarySize,
                    BOPOMOFO_HEIGHT_REFERENCE, normalPrimarySize, primaryBaseline);
        }
        textPaint.setTextSize(primarySize);
        canvas.drawText(primary, bounds.centerX(), primaryBaseline, textPaint);

        float secondarySize = isToneSymbol(secondary)
                ? normalSecondarySize * TONE_SYMBOL_SCALE : normalSecondarySize;
        float secondaryBaseline = top + primaryHeight + dp(2) - secondaryMetrics.ascent;
        if (isToneSymbol(secondary)) {
            secondaryBaseline = topAlignedBaseline(hintPaint, secondary, secondarySize,
                    "1", normalSecondarySize, secondaryBaseline);
        }
        hintPaint.setTextSize(secondarySize);
        canvas.drawText(secondary, bounds.centerX(), secondaryBaseline, hintPaint);
    }

    private void drawLandscapeBopomofoKey(Canvas canvas, RectF bounds, String primary,
                                           String secondary) {
        float normalSize = touchKeyTextSize;
        float hintSize = touchKeyTextSize * KEY_HINT_SCALE;
        textPaint.setTextSize(normalSize);
        float primaryWidth = textPaint.measureText(KEY_FONT_REFERENCE);
        hintPaint.setTextSize(hintSize);
        float secondaryWidth = Math.max(hintPaint.measureText(KEY_FONT_REFERENCE), hintPaint.measureText(secondary));
        float left = bounds.centerX() - (primaryWidth + dp(2) + secondaryWidth) / 2f;
        float normalBaseline = textBaseline(bounds, textPaint);
        float primarySize = isToneSymbol(primary) ? normalSize * TONE_SYMBOL_SCALE : normalSize;
        float primaryBaseline = isToneSymbol(primary)
                ? topAlignedBaseline(textPaint, primary, primarySize,
                        BOPOMOFO_HEIGHT_REFERENCE, normalSize, normalBaseline) : normalBaseline;
        textPaint.setTextSize(primarySize);
        canvas.drawText(primary, left + primaryWidth / 2f, primaryBaseline, textPaint);
        float secondarySize = isToneSymbol(secondary) ? hintSize * TONE_SYMBOL_SCALE : hintSize;
        float secondaryBaseline = textBaseline(bounds, hintPaint);
        if (isToneSymbol(secondary)) {
            secondaryBaseline = topAlignedBaseline(hintPaint, secondary, secondarySize,
                    KEY_FONT_REFERENCE, hintSize, secondaryBaseline);
        }
        hintPaint.setTextSize(secondarySize);
        canvas.drawText(secondary, left + primaryWidth + dp(2) + secondaryWidth / 2f,
                secondaryBaseline, hintPaint);
    }

    private boolean isToneSymbol(String value) {
        return value.equals("ˊ") || value.equals("ˇ") || value.equals("ˋ")
                || value.equals("˙");
    }

    private float topAlignedBaseline(Paint paint, String value, float textSize,
                                     String reference, float referenceSize,
                                     float referenceBaseline) {
        paint.setTextSize(referenceSize);
        paint.getTextBounds(reference, 0, reference.length(), referenceGlyphBounds);
        paint.setTextSize(textSize);
        paint.getTextBounds(value, 0, value.length(), glyphBounds);
        return referenceBaseline + referenceGlyphBounds.top - glyphBounds.top;
    }

    private boolean isSpecialKey(String key) {
        return switch (key) {
            case "SHIFT", "BACKSPACE", "ENTER", "SPACE", "SYMBOL", "SETTINGS", "EMOJI",
                    "MODE", "GLOBE", "DISMISS", "CLOSE_CANDIDATES", "，", "。", "、", "？" -> true;
            default -> false;
        };
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        if (resizeDragActive) return true;
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN -> {
                backspaceRepeater.stop();
                downX = event.getX();
                downY = event.getY();
                Hit hit = findHit(downX, downY);
                resetPickerPress();
                if (hit != null && hit.kind() == HitKind.KEY
                        && (hit.key().equals("GLOBE") || hit.key().equals("SETTINGS"))) {
                    pickerPressKey = hit.key();
                    postDelayed(pickerLongPress, ViewConfiguration.getLongPressTimeout());
                }
                if (hit != null && listener != null) listener.onPress();
                backspaceTouchStarted = hit != null && hit.kind() == HitKind.KEY
                        && "BACKSPACE".equals(hit.key());
                if (backspaceTouchStarted && listener != null) {
                    listener.onKey("BACKSPACE");
                    backspaceRepeater.start(() -> {
                        if (listener != null) listener.onKey("BACKSPACE");
                    });
                }
                downOnCandidate = hit != null && hit.kind() == HitKind.CANDIDATE;
                previewHit = canPreview(hit) ? hit : null;
                if (previewHit != null) invalidate();
                return true;
            }
            case MotionEvent.ACTION_MOVE -> {
                if (pickerPressKey != null) {
                    Hit hit = findHit(event.getX(), event.getY());
                    if (hit == null || hit.kind() != HitKind.KEY || !hit.key().equals(pickerPressKey)) {
                        // Moving out cancels this press even if the finger returns;
                        // an opened picker must never become a settings tap or switch.
                        cancelPickerPress();
                    }
                }
                if (backspaceTouchStarted) {
                    Hit hit = findHit(event.getX(), event.getY());
                    if (hit == null || hit.kind() != HitKind.KEY
                            || !"BACKSPACE".equals(hit.key())) backspaceRepeater.stop();
                }
                if (previewHit != null
                        && !previewHit.bounds().contains(event.getX(), event.getY())) {
                    previewHit = null;
                    invalidate();
                }
                return true;
            }
            case MotionEvent.ACTION_UP -> {
                boolean pickerHandled = pickerPressConsumed;
                resetPickerPress();
                backspaceRepeater.stop();
                clearKeyPreview();
                if (pickerHandled) {
                    performClick();
                    return true;
                }
                if (backspaceTouchStarted) {
                    backspaceTouchStarted = false;
                    performClick();
                    return true;
                }
                float distance = event.getX() - downX;
                if (downOnCandidate && Math.abs(distance) > dp(38)) {
                    if (listener != null) listener.onPage(distance < 0 ? 1 : -1);
                    performClick();
                    return true;
                }
                Hit hit = findHit(event.getX(), event.getY());
                if (hit != null && hit.bounds().contains(downX, downY) && listener != null) {
                    if (hit.kind() == HitKind.CANDIDATE) {
                        listener.onCandidate(hit.candidateIndex());
                    } else if (hit.kind() == HitKind.SMART_CELL) {
                        listener.onSmartCell(hit.candidateIndex());
                    } else if (hit.kind() == HitKind.PAGE) {
                        listener.onPage(hit.candidateIndex());
                    } else if (hit.kind() == HitKind.KEY) {
                        listener.onKey(hit.key());
                    }
                }
                performClick();
                return true;
            }
            case MotionEvent.ACTION_CANCEL -> {
                resetPickerPress();
                backspaceRepeater.stop();
                backspaceTouchStarted = false;
                downOnCandidate = false;
                clearKeyPreview();
                return true;
            }
            default -> { return true; }
        }
    }

    @Override
    protected void onDetachedFromWindow() {
        resetPickerPress();
        backspaceRepeater.stop();
        backspaceTouchStarted = false;
        super.onDetachedFromWindow();
    }

    private void cancelPickerPress() {
        removeCallbacks(pickerLongPress);
        pickerPressConsumed |= pickerPressKey != null;
        pickerPressKey = null;
    }

    private void resetPickerPress() {
        cancelPickerPress();
        pickerPressConsumed = false;
    }

    @Override
    public boolean performClick() {
        super.performClick();
        return true;
    }

    private Hit findHit(float x, float y) {
        for (int index = hits.size() - 1; index >= 0; index--) {
            Hit hit = hits.get(index);
            if (hit.bounds().contains(x, y)) return hit;
        }
        return null;
    }

    private boolean canPreview(Hit hit) {
        return keyPreviewEnabled && isTouchMode() && hit != null
                && hit.kind() == HitKind.KEY && !previewLabel(hit.key()).isEmpty();
    }

    boolean isTouchMode() {
        return mode == Mode.PORTRAIT || mode == Mode.LANDSCAPE;
    }

    private void clearKeyPreview() {
        if (previewHit == null) return;
        previewHit = null;
        invalidate();
    }

    private String previewLabel(String key) {
        if (key == null || key.length() != 1) return "";
        String symbol = bopomofoSymbol(key);
        return !symbol.isEmpty() && !temporaryEnglish ? symbol : key;
    }

    private String keyLabel(String key) {
        return switch (key) {
            case "MODE" -> fieldPolicy.modeCaption(inputMode).replace("ㄅ", chineseModeSymbol());
            case "SHIFT" -> shifted ? "⇧" : "⇧";
            case "BACKSPACE" -> "⌫";
            case "SPACE" -> usesPinyin() && inputMode == InputEngine.InputMode.BOPOMOFO
                    && (phoneticPending ? phoneticSpaceFirstTone
                            : !reading.isEmpty() && candidates.isEmpty()) ? "一聲" : "空白";
            case "SYMBOL" -> "符";
            case "SETTINGS" -> "設";
            case "EMOJI" -> "☺";
            case "GLOBE" -> "🌐";
            case "DISMISS" -> "▼";
            default -> key;
        };
    }

    private String bopomofoSymbol(String key) {
        if (chineseInputMethod.isTable())
            return inputMode == InputEngine.InputMode.BOPOMOFO && !temporaryEnglish
                    ? ChineseInputMethod.root(key) : "";
        if (keyboardLayout != BopomofoKeyboardLayout.STANDARD) return "";
        if (inputMode != InputEngine.InputMode.BOPOMOFO && !temporaryEnglish
                || key.length() != 1) return "";
        String symbol = BopomofoKeyboardLayout.symbolForKey(Character.toLowerCase(key.charAt(0)));
        return symbol;
    }

    private KeyboardLayoutProfile.Orientation touchOrientation() {
        return mode == Mode.LANDSCAPE ? KeyboardLayoutProfile.Orientation.LANDSCAPE
                : KeyboardLayoutProfile.Orientation.PORTRAIT;
    }

    int compositionCellCount() {
        if (isTouchMode() && touchPhoneticGrid) return PHONETIC_GRID_CELL_COUNT;
        KeyboardLayoutProfile profile = isTouchMode() ? layoutProfile : KeyboardLayoutProfile.ALIGNED;
        return profile.layout(touchOrientation()).compositionCellCount;
    }

    private KeyboardLayoutProfile.Plane inputPlane() {
        if (inputMode == InputEngine.InputMode.NUMBER) {
            return KeyboardLayoutProfile.Plane.NUMBER_SYMBOLS;
        } else if (inputMode == InputEngine.InputMode.ENGLISH) {
            return KeyboardLayoutProfile.Plane.ENGLISH;
        } else if (chineseInputMethod == ChineseInputMethod.CANGJIE) {
            return KeyboardLayoutProfile.Plane.CANGJIE;
        } else if (chineseInputMethod == ChineseInputMethod.SIMPLEX) {
            return KeyboardLayoutProfile.Plane.SIMPLEX;
        } else {
            return KeyboardLayoutProfile.Plane.BOPOMOFO;
        }
    }

    private float textBaseline(RectF bounds, Paint paint) {
        Paint.FontMetrics metrics = paint.getFontMetrics();
        return bounds.centerY() - (metrics.ascent + metrics.descent) / 2f;
    }

    private RectF inset(RectF source, float amount) {
        return new RectF(source.left + amount, source.top + amount,
                source.right - amount, source.bottom - amount);
    }

    private int dp(float value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private float contentHeight() {
        if (isTouchMode() && (integratedBottomControls || measuredBottomGap > 0 || resizePreview != null)) {
            // The old allocated window can cap a transient pass before the new
            // WRAP_CONTENT budget arrives. Drawing and hits must still stay safe.
            return Math.min(measuredContentHeight,
                    Math.max(0, getHeight() - systemAreaHeight() - measuredBottomGap));
        }
        return measuredContentHeight;
    }

    private int systemAreaHeight() {
        if (isTouchMode() && integratedBottomControls) return navigationBarBottomInset;
        boolean enabled = mode == Mode.HARDWARE ? hardwareBottomSpaceEnabled : touchBottomSpaceEnabled;
        return enabled ? reservedSystemAreaHeight() : 0;
    }

    private int reservedSystemAreaHeight() {
        return switch (mode) {
            case HARDWARE_FLOATING -> 0;
            case PORTRAIT -> dp(PORTRAIT_SYSTEM_AREA_HEIGHT_DP);
            case LANDSCAPE -> dp(LANDSCAPE_SYSTEM_AREA_HEIGHT_DP);
            case HARDWARE -> hardwareSystemAreaHeight();
        };
    }

    private int hardwareSystemAreaHeight() {
        boolean landscape = getResources().getConfiguration().orientation
                == android.content.res.Configuration.ORIENTATION_LANDSCAPE;
        return dp(landscape ? HARDWARE_LANDSCAPE_SYSTEM_AREA_HEIGHT_DP
                : HARDWARE_PORTRAIT_SYSTEM_AREA_HEIGHT_DP);
    }

}
