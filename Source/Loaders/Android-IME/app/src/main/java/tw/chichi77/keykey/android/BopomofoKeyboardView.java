package tw.chichi77.keykey.android;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Rect;
import android.graphics.RectF;
import android.view.MotionEvent;
import android.view.View;

import java.util.ArrayList;
import java.util.List;

final class BopomofoKeyboardView extends View {
    enum Mode { PORTRAIT, LANDSCAPE, HARDWARE, HARDWARE_FLOATING }

    interface Listener {
        void onPress();
        void onKey(String key);
        void onCandidate(int displayedIndex);
        void onPage(int delta);
    }

    private enum HitKind { KEY, CANDIDATE, PAGE }

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

    private static final String[][] BOPOMOFO_AND_ENGLISH_ROWS = {
            {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-"},
            {"q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "@"},
            {"a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "EMOJI"},
            {"z", "x", "c", "v", "b", "n", "m", ",", ".", "/", "SHIFT"}
    };
    private static final String[][] SHIFTED_ENGLISH_ROWS = {
            {"!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_"},
            {"Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "@"},
            {"A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "EMOJI"},
            {"Z", "X", "C", "V", "B", "N", "M", ",", ".", "/", "SHIFT"}
    };
    private static final String[][] NUMBER_ROWS = {
            {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-"},
            {"!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_"},
            {"+", "=", "[", "]", "{", "}", "<", ">", "/", "\\", "|"},
            {"~", "`", "\"", "'", ":", ";", "?", ",", ".", "…", "SHIFT"}
    };
    private static final String[][] SHIFTED_NUMBER_ROWS = {
            {"$", "€", "£", "¥", "₩", "₹", "₽", "¢", "₫", "₱", "฿"},
            {"＋", "－", "×", "÷", "=", "≠", "≈", "±", "<", ">", "∞"},
            {"←", "→", "↑", "↓", "↔", "↕", "↖", "↗", "↘", "↙", "⇒"},
            {"★", "☆", "●", "○", "■", "□", "▲", "△", "▼", "▽", "SHIFT"}
    };
    private static final String[] FUNCTION_ROW = {
            "MODE", "SYMBOL", "SETTINGS", "，", "SPACE", "。", "BACKSPACE", "ENTER"
    };
    private static final int PORTRAIT_CONTENT_HEIGHT_DP = 330;
    private static final int PORTRAIT_SYSTEM_AREA_HEIGHT_DP = 40;
    private static final int LANDSCAPE_CONTENT_HEIGHT_DP = 155;
    private static final int LANDSCAPE_SYSTEM_AREA_HEIGHT_DP = 35;
    private static final int HARDWARE_CONTENT_HEIGHT_DP = 58;
    private static final int HARDWARE_PORTRAIT_SYSTEM_AREA_HEIGHT_DP = 40;
    private static final int HARDWARE_LANDSCAPE_SYSTEM_AREA_HEIGHT_DP = 35;
    private static final float TONE_SYMBOL_SCALE = 1.8f;
    private static final String BOPOMOFO_HEIGHT_REFERENCE = "ㄅ";

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

    private Listener listener;
    private Mode mode = Mode.PORTRAIT;
    private List<String> candidates = List.of();
    private String reading = "";
    private BopomofoEngine.InputMode inputMode = BopomofoEngine.InputMode.BOPOMOFO;
    private boolean shifted;
    private boolean temporaryEnglish;
    private boolean hardwareFullWidth;
    private boolean supportPromptVisible;
    private InputFieldPolicy fieldPolicy = InputFieldPolicy.DEFAULT;
    private int page;
    private int pageCount;
    private int highlightedIndex = -1;
    private int candidateHighlightTextColor = Color.WHITE;
    private float downX;
    private float downY;
    private boolean downOnCandidate;
    private boolean keyPreviewEnabled = true;
    private Hit previewHit;

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

    void setMode(Mode mode) {
        if (this.mode == mode) return;
        this.mode = mode;
        previewHit = null;
        requestLayout();
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

    void setState(List<String> candidates, String reading, BopomofoEngine.InputMode inputMode,
                  boolean shifted, boolean temporaryEnglish, boolean hardwareFullWidth,
                  boolean supportPromptVisible, int page, int pageCount,
                  int highlightedIndex, InputFieldPolicy fieldPolicy) {
        this.candidates = List.copyOf(candidates);
        this.reading = reading;
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

    static String[][] shiftedEnglishRows() { return SHIFTED_ENGLISH_ROWS; }
    static String[][] shiftedNumberRows() { return SHIFTED_NUMBER_ROWS; }

    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        int desiredHeight = switch (mode) {
            case HARDWARE_FLOATING -> dp(1);
            case HARDWARE -> dp(HARDWARE_CONTENT_HEIGHT_DP) + hardwareSystemAreaHeight();
            case LANDSCAPE -> dp(LANDSCAPE_CONTENT_HEIGHT_DP + LANDSCAPE_SYSTEM_AREA_HEIGHT_DP);
            case PORTRAIT -> dp(PORTRAIT_CONTENT_HEIGHT_DP + PORTRAIT_SYSTEM_AREA_HEIGHT_DP);
        };
        int width = MeasureSpec.getSize(widthMeasureSpec);
        setMeasuredDimension(resolveSize(width, widthMeasureSpec),
                resolveSize(desiredHeight, heightMeasureSpec));
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        hits.clear();
        canvas.drawRect(0, 0, getWidth(), getHeight(), backgroundPaint);
        switch (mode) {
            case HARDWARE_FLOATING -> { }
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
        float candidateHeight = landscape ? contentHeight / 6f
                : Math.max(dp(46), contentHeight * 0.15f);
        drawCandidateStrip(canvas, new RectF(0, 0, getWidth(), candidateHeight));

        String[][] rows = inputRows();
        float top = candidateHeight;
        float rowHeight = (contentHeight - top) / 5f;
        for (int row = 0; row < rows.length; row++) {
            drawEqualKeyRow(canvas, rows[row], 0, getWidth(), top + row * rowHeight,
                    top + (row + 1) * rowHeight);
        }
        drawWeightedKeyRow(canvas, FUNCTION_ROW, 0, getWidth(), top + 4 * rowHeight,
                contentHeight);
    }

    private void drawHardware(Canvas canvas) {
        RectF area = new RectF(0, 0, getWidth(), contentHeight());
        float gap = dp(2);
        int cellCount = BopomofoEngine.CANDIDATES_PER_PAGE + 3;
        float cellWidth = area.width() / cellCount;
        for (int i = 0; i < BopomofoEngine.CANDIDATES_PER_PAGE; i++) {
            RectF cell = new RectF(area.left + i * cellWidth + gap,
                    area.top + gap, area.left + (i + 1) * cellWidth - gap,
                    area.bottom - gap);
            drawCandidate(canvas, cell, i);
        }
        drawHardwareEmojiButton(canvas, new RectF(
                area.left + BopomofoEngine.CANDIDATES_PER_PAGE * cellWidth,
                area.top, area.left + (BopomofoEngine.CANDIDATES_PER_PAGE + 1) * cellWidth,
                area.bottom));
        drawHardwareStatusButton(canvas, new RectF(
                area.left + (BopomofoEngine.CANDIDATES_PER_PAGE + 1) * cellWidth,
                area.top, area.left + (BopomofoEngine.CANDIDATES_PER_PAGE + 2) * cellWidth,
                area.bottom), inputMode == BopomofoEngine.InputMode.BOPOMOFO ? "ㄅ" : "英",
                "HARDWARE_LANGUAGE");
        drawHardwareStatusButton(canvas, new RectF(
                area.left + (BopomofoEngine.CANDIDATES_PER_PAGE + 2) * cellWidth,
                area.top, area.right, area.bottom), hardwareFullWidth ? "全" : "半",
                "HARDWARE_WIDTH");
    }

    private void drawHardwareStatusButton(Canvas canvas, RectF bounds, String label,
                                          String key) {
        RectF inset = inset(bounds, dp(2));
        canvas.drawRoundRect(inset, dp(6), dp(6), specialKeyPaint);

        textPaint.setTextSize(dp(18));
        textPaint.setFakeBoldText(true);
        canvas.drawText(label, inset.centerX(), textBaseline(inset, textPaint), textPaint);
        hits.add(new Hit(new RectF(inset), HitKind.KEY, key, -1));
    }

    private void drawHardwareEmojiButton(Canvas canvas, RectF bounds) {
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
        if (candidates.isEmpty()) {
            drawEmptyCandidateMessage(canvas, area);
            return;
        }

        float gap = dp(2);
        int cellCount = BopomofoEngine.CANDIDATES_PER_PAGE + 2;
        float cellWidth = area.width() / cellCount;
        drawPageButton(canvas, new RectF(area.left, area.top,
                area.left + cellWidth, area.bottom), -1, "▲");
        for (int i = 0; i < BopomofoEngine.CANDIDATES_PER_PAGE; i++) {
            RectF cell = new RectF(area.left + (i + 1) * cellWidth + gap,
                    area.top + gap, area.left + (i + 2) * cellWidth - gap, area.bottom - gap);
            drawCandidate(canvas, cell, i);
        }
        drawPageButton(canvas, new RectF(area.right - cellWidth, area.top,
                area.right, area.bottom), 1, "▼");
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
        String message;
        if (!reading.isEmpty()) message = reading + "　按空白選字";
        else if (inputMode == BopomofoEngine.InputMode.ENGLISH) {
            message = temporaryEnglish ? "暫時英文小寫" : shifted ? "英文大寫" : "英文小寫";
        }
        else if (inputMode == BopomofoEngine.InputMode.NUMBER) {
            message = shifted ? "數字與符號（二）" : "數字與符號（一）";
        }
        else {
            if (supportPromptVisible && inputMode == BopomofoEngine.InputMode.BOPOMOFO
                    && (mode == Mode.PORTRAIT || mode == Mode.LANDSCAPE)) {
                drawSupportPrompt(canvas, area);
                return;
            }
            message = mode == Mode.HARDWARE
                    ? "標準注音・候選 1–9・關聯詞 Shift+1–9" : "標準注音";
        }
        hintPaint.setTextSize(standardHintTextSize());
        canvas.drawText(message, area.centerX(), textBaseline(area, hintPaint), hintPaint);
    }

    private void drawSupportPrompt(Canvas canvas, RectF area) {
        String primary = "標準注音";
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

    private float standardHintTextSize() {
        return mode == Mode.LANDSCAPE ? dp(11) : dp(14);
    }

    private void drawEqualKeyRow(Canvas canvas, String[] keys, float left, float right,
                                 float top, float bottom) {
        if (keys.length == 0) return;
        float width = (right - left) / keys.length;
        for (int index = 0; index < keys.length; index++) {
            RectF bounds = new RectF(left + index * width + dp(2), top + dp(2),
                    left + (index + 1) * width - dp(2), bottom - dp(2));
            drawKey(canvas, bounds, keys[index]);
        }
    }

    private void drawWeightedKeyRow(Canvas canvas, String[] keys, float left, float right,
                                    float top, float bottom) {
        float totalWeight = 0;
        for (String key : keys) totalWeight += keyWeight(key);
        float unit = (right - left) / totalWeight;
        float cursor = left;
        for (String key : keys) {
            float width = unit * keyWeight(key);
            RectF bounds = new RectF(cursor + dp(2), top + dp(2),
                    cursor + width - dp(2), bottom - dp(2));
            drawKey(canvas, bounds, key);
            cursor += width;
        }
    }

    private void drawKey(Canvas canvas, RectF bounds, String key) {
        boolean special = isSpecialKey(key);
        boolean enabled = fieldPolicy.isKeyEnabled(key, inputMode, shifted);
        int savedAlpha = canvas.saveLayerAlpha(bounds, enabled ? 255 : 92);
        canvas.drawRoundRect(bounds, dp(6), dp(6), special ? specialKeyPaint : keyPaint);

        String symbol = bopomofoSymbol(key);
        if (!symbol.isEmpty()) {
            drawBopomofoKey(canvas, bounds, symbol, key, temporaryEnglish);
            canvas.restoreToCount(savedAlpha);
            if (enabled) hits.add(new Hit(new RectF(bounds), HitKind.KEY, key, -1));
            return;
        }

        if (key.equals("ENTER")) {
            if (fieldPolicy.enterLabel().isEmpty()) drawEnterKey(canvas, bounds);
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
        textPaint.setFakeBoldText(key.equals("SPACE")
                || (inputMode == BopomofoEngine.InputMode.BOPOMOFO && !special));
        canvas.drawText(label, bounds.centerX(), textBaseline(bounds, textPaint), textPaint);
        canvas.restoreToCount(savedAlpha);
        if (enabled) hits.add(new Hit(new RectF(bounds), HitKind.KEY, key, -1));
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

        float normalPrimarySize = dp(18);
        float primarySize = isToneSymbol(primary)
                ? normalPrimarySize * TONE_SYMBOL_SCALE : normalPrimarySize;
        float primaryBaseline = bounds.centerY() - dp(4);
        if (isToneSymbol(primary)) {
            primaryBaseline = topAlignedBaseline(textPaint, primary, primarySize,
                    BOPOMOFO_HEIGHT_REFERENCE, normalPrimarySize, primaryBaseline);
        }
        textPaint.setTextSize(primarySize);
        canvas.drawText(primary, bounds.centerX(), primaryBaseline, textPaint);

        float normalSecondarySize = dp(10);
        float secondarySize = isToneSymbol(secondary)
                ? normalSecondarySize * TONE_SYMBOL_SCALE : normalSecondarySize;
        float secondaryBaseline = bounds.centerY() + dp(17);
        if (isToneSymbol(secondary)) {
            secondaryBaseline = topAlignedBaseline(hintPaint, secondary, secondarySize,
                    "1", normalSecondarySize, secondaryBaseline);
        }
        hintPaint.setTextSize(secondarySize);
        canvas.drawText(secondary, bounds.centerX(), secondaryBaseline, hintPaint);
    }

    private void drawLandscapeBopomofoKey(Canvas canvas, RectF bounds, String primary,
                                           String secondary) {
        float normalSize = dp(11);
        float primarySize = isToneSymbol(primary) ? normalSize * TONE_SYMBOL_SCALE : normalSize;
        float secondarySize = isToneSymbol(secondary) ? normalSize * TONE_SYMBOL_SCALE : normalSize;
        float gap = dp(3);

        textPaint.setTextSize(primarySize);
        float primaryWidth = textPaint.measureText(primary);
        textPaint.setTextSize(secondarySize);
        float secondaryWidth = textPaint.measureText(secondary);
        float left = bounds.centerX() - (primaryWidth + gap + secondaryWidth) / 2f;
        textPaint.setTextSize(normalSize);
        float normalBaseline = textBaseline(bounds, textPaint);

        textPaint.setTextSize(primarySize);
        float primaryBaseline = isToneSymbol(primary)
                ? topAlignedBaseline(textPaint, primary, primarySize,
                        BOPOMOFO_HEIGHT_REFERENCE, normalSize, normalBaseline)
                : normalBaseline;
        canvas.drawText(primary, left + primaryWidth / 2f,
                primaryBaseline, textPaint);
        textPaint.setTextSize(secondarySize);
        float secondaryBaseline = isToneSymbol(secondary)
                ? topAlignedBaseline(textPaint, secondary, secondarySize,
                        BOPOMOFO_HEIGHT_REFERENCE, normalSize, normalBaseline)
                : normalBaseline;
        canvas.drawText(secondary, left + primaryWidth + gap + secondaryWidth / 2f,
                secondaryBaseline, textPaint);
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
                    "MODE", "，", "。" -> true;
            default -> false;
        };
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN -> {
                downX = event.getX();
                downY = event.getY();
                Hit hit = findHit(downX, downY);
                if (hit != null && listener != null) listener.onPress();
                downOnCandidate = hit != null && hit.kind() == HitKind.CANDIDATE;
                previewHit = canPreview(hit) ? hit : null;
                if (previewHit != null) invalidate();
                return true;
            }
            case MotionEvent.ACTION_MOVE -> {
                if (previewHit != null
                        && !previewHit.bounds().contains(event.getX(), event.getY())) {
                    previewHit = null;
                    invalidate();
                }
                return true;
            }
            case MotionEvent.ACTION_UP -> {
                clearKeyPreview();
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
                    } else if (hit.kind() == HitKind.PAGE) {
                        listener.onPage(hit.candidateIndex());
                    } else {
                        listener.onKey(hit.key());
                    }
                }
                performClick();
                return true;
            }
            case MotionEvent.ACTION_CANCEL -> {
                downOnCandidate = false;
                clearKeyPreview();
                return true;
            }
            default -> { return true; }
        }
    }

    @Override
    public boolean performClick() {
        super.performClick();
        return true;
    }

    private Hit findHit(float x, float y) {
        for (Hit hit : hits) if (hit.bounds().contains(x, y)) return hit;
        return null;
    }

    private boolean canPreview(Hit hit) {
        return keyPreviewEnabled && isTouchMode() && hit != null
                && hit.kind() == HitKind.KEY && !previewLabel(hit.key()).isEmpty();
    }

    private boolean isTouchMode() {
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
            case "MODE" -> fieldPolicy.modeCaption(inputMode);
            case "SHIFT" -> shifted ? "⇧" : "⇧";
            case "BACKSPACE" -> "⌫";
            case "SPACE" -> "空白";
            case "SYMBOL" -> "符";
            case "SETTINGS" -> "設";
            case "EMOJI" -> "☺";
            default -> key;
        };
    }

    private String bopomofoSymbol(String key) {
        if (inputMode != BopomofoEngine.InputMode.BOPOMOFO && !temporaryEnglish
                || key.length() != 1) return "";
        String symbol = BopomofoReading.symbolForKey(Character.toLowerCase(key.charAt(0)));
        return symbol;
    }

    private String[][] inputRows() {
        if (inputMode == BopomofoEngine.InputMode.NUMBER) {
            return shifted ? SHIFTED_NUMBER_ROWS : NUMBER_ROWS;
        }
        if (inputMode == BopomofoEngine.InputMode.ENGLISH && shifted) {
            return SHIFTED_ENGLISH_ROWS;
        }
        return BOPOMOFO_AND_ENGLISH_ROWS;
    }

    private float keyWeight(String key) {
        return switch (key) {
            case "SPACE" -> 3.8f;
            case "BACKSPACE", "ENTER" -> 1.4f;
            case "MODE" -> 1.65f;
            default -> 1f;
        };
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
        int systemAreaHeight = switch (mode) {
            case HARDWARE_FLOATING -> 0;
            case PORTRAIT -> dp(PORTRAIT_SYSTEM_AREA_HEIGHT_DP);
            case LANDSCAPE -> dp(LANDSCAPE_SYSTEM_AREA_HEIGHT_DP);
            case HARDWARE -> hardwareSystemAreaHeight();
        };
        return Math.max(0, getHeight() - systemAreaHeight);
    }

    private int hardwareSystemAreaHeight() {
        boolean landscape = getResources().getConfiguration().orientation
                == android.content.res.Configuration.ORIENTATION_LANDSCAPE;
        return dp(landscape ? HARDWARE_LANDSCAPE_SYSTEM_AREA_HEIGHT_DP
                : HARDWARE_PORTRAIT_SYSTEM_AREA_HEIGHT_DP);
    }
}
