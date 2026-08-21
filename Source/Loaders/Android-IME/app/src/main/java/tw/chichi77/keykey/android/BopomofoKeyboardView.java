package tw.chichi77.keykey.android;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.view.MotionEvent;
import android.view.View;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

final class BopomofoKeyboardView extends View {
    enum Mode { PORTRAIT, LANDSCAPE, HARDWARE }

    interface Listener {
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

    private static final String[][] KEY_ROWS = {
            {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "BACKSPACE"},
            {"q", "w", "e", "r", "t", "y", "u", "i", "o", "p"},
            {"a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "ENTER"},
            {"SHIFT", "z", "x", "c", "v", "b", "n", "m", ",", ".", "/", "SHIFT"},
            {"MODE", "SYMBOL", "，", "SPACE", "。", "EMOJI"}
    };
    private static final int PORTRAIT_CONTENT_HEIGHT_DP = 330;
    private static final int PORTRAIT_SYSTEM_AREA_HEIGHT_DP = 46;
    private static final int LANDSCAPE_CONTENT_HEIGHT_DP = 155;
    private static final int LANDSCAPE_SYSTEM_AREA_HEIGHT_DP = 35;
    private static final int HARDWARE_CONTENT_HEIGHT_DP = 58;

    private final Paint backgroundPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint keyPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint specialKeyPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint candidatePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint textPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint hintPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final ArrayList<Hit> hits = new ArrayList<>();

    private Listener listener;
    private Mode mode = Mode.PORTRAIT;
    private List<String> candidates = List.of();
    private String reading = "";
    private boolean englishMode;
    private boolean shifted;
    private int page;
    private int pageCount;
    private float downX;
    private float downY;
    private boolean downOnCandidate;

    BopomofoKeyboardView(Context context) {
        super(context);
        setBackgroundColor(Color.rgb(218, 223, 232));
        setFocusable(false);

        backgroundPaint.setColor(Color.rgb(218, 223, 232));
        keyPaint.setColor(Color.WHITE);
        specialKeyPaint.setColor(Color.rgb(198, 207, 222));
        candidatePaint.setColor(Color.rgb(244, 247, 252));
        textPaint.setColor(Color.rgb(24, 31, 44));
        textPaint.setTextAlign(Paint.Align.CENTER);
        hintPaint.setColor(Color.rgb(92, 102, 119));
        hintPaint.setTextAlign(Paint.Align.CENTER);
    }

    void setListener(Listener listener) {
        this.listener = listener;
    }

    void setMode(Mode mode) {
        if (this.mode == mode) return;
        this.mode = mode;
        requestLayout();
        invalidate();
    }

    void setState(List<String> candidates, String reading, boolean englishMode,
                  boolean shifted, int page, int pageCount) {
        this.candidates = List.copyOf(candidates);
        this.reading = reading;
        this.englishMode = englishMode;
        this.shifted = shifted;
        this.page = page;
        this.pageCount = pageCount;
        invalidate();
    }

    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        int desiredHeight = switch (mode) {
            case HARDWARE -> dp(HARDWARE_CONTENT_HEIGHT_DP);
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
            case HARDWARE -> drawHardware(canvas);
            case LANDSCAPE -> drawLandscape(canvas);
            case PORTRAIT -> drawPortrait(canvas);
        }
    }

    private void drawPortrait(Canvas canvas) {
        float contentHeight = contentHeight();
        float candidateHeight = Math.max(dp(46), contentHeight * 0.15f);
        drawCandidateStrip(canvas, new RectF(0, 0, getWidth(), candidateHeight));

        float top = candidateHeight;
        float rowHeight = (contentHeight - top) / KEY_ROWS.length;
        for (int row = 0; row < KEY_ROWS.length; row++) {
            drawKeyRow(canvas, KEY_ROWS[row], 0, getWidth(), top + row * rowHeight,
                    top + (row + 1) * rowHeight);
        }
    }

    private void drawLandscape(Canvas canvas) {
        float contentHeight = contentHeight();
        float rowHeight = contentHeight / KEY_ROWS.length;
        float centerWidth = Math.min(getWidth() * 0.36f, dp(390));
        float sideWidth = (getWidth() - centerWidth) / 2f;
        float centerLeft = sideWidth;
        float centerRight = sideWidth + centerWidth;
        float pageButtonWidth = Math.min(dp(38), centerWidth * 0.12f);
        float candidateLeft = centerLeft + pageButtonWidth;
        float candidateRight = centerRight - pageButtonWidth;

        if (!candidates.isEmpty()) {
            drawPageButton(canvas, new RectF(centerLeft, 0, candidateLeft, contentHeight), -1, "▲");
            drawPageButton(canvas, new RectF(candidateRight, 0, centerRight, contentHeight), 1, "▼");
        }

        for (int row = 0; row < KEY_ROWS.length; row++) {
            String[] keys = KEY_ROWS[row];
            int split = (keys.length + 1) / 2;
            String[] left = slice(keys, 0, split);
            String[] right = slice(keys, split, keys.length);
            float top = row * rowHeight;
            float bottom = (row + 1) * rowHeight;
            drawKeyRow(canvas, left, 0, centerLeft, top, bottom);
            drawKeyRow(canvas, right, centerRight, getWidth(), top, bottom);
            float candidateMiddle = (candidateLeft + candidateRight) / 2f;
            drawLandscapeCandidate(canvas, new RectF(candidateLeft, top,
                    candidateMiddle, bottom), row);
            drawLandscapeCandidate(canvas, new RectF(candidateMiddle, top,
                    candidateRight, bottom), row + 5);
        }
    }

    private void drawHardware(Canvas canvas) {
        drawCandidateStrip(canvas, new RectF(0, 0, getWidth(), contentHeight()));
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

    private void drawLandscapeCandidate(Canvas canvas, RectF bounds, int index) {
        RectF inset = inset(bounds, dp(2));
        drawCandidate(canvas, inset, index);
        if (candidates.isEmpty() && index == 2) {
            String message = reading.isEmpty() ? "候選字" : reading;
            hintPaint.setTextSize(dp(12));
            canvas.drawText(message, bounds.centerX(), textBaseline(bounds, hintPaint), hintPaint);
        }
    }

    private void drawCandidate(Canvas canvas, RectF bounds, int index) {
        canvas.drawRoundRect(bounds, dp(6), dp(6), candidatePaint);
        if (index >= candidates.size()) return;
        String number = Integer.toString(index + 1);
        String value = candidates.get(index);
        textPaint.setTextSize(mode == Mode.LANDSCAPE ? dp(15) : dp(18));
        textPaint.setFakeBoldText(true);
        canvas.drawText(value, bounds.centerX(), textBaseline(bounds, textPaint), textPaint);
        hintPaint.setTextAlign(Paint.Align.LEFT);
        hintPaint.setTextSize(mode == Mode.LANDSCAPE ? dp(9) : dp(10));
        canvas.drawText(number, bounds.left + dp(5),
                bounds.top + (mode == Mode.LANDSCAPE ? dp(10) : dp(12)), hintPaint);
        hintPaint.setTextAlign(Paint.Align.CENTER);
        hits.add(new Hit(new RectF(bounds), HitKind.CANDIDATE, "", index));
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
        else if (englishMode) message = "英文模式";
        else message = mode == Mode.HARDWARE ? "標準注音・數字鍵選字・PgUp/PgDn 換頁" : "標準注音";
        hintPaint.setTextSize(dp(14));
        canvas.drawText(message, area.centerX(), textBaseline(area, hintPaint), hintPaint);
    }

    private void drawKeyRow(Canvas canvas, String[] keys, float left, float right,
                            float top, float bottom) {
        if (keys.length == 0) return;
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
        boolean special = key.length() > 1 || key.equals("，") || key.equals("。");
        canvas.drawRoundRect(bounds, dp(6), dp(6), special ? specialKeyPaint : keyPaint);

        String label = keyLabel(key);
        String symbol = key.length() == 1 ? BopomofoReading.symbolForKey(key.charAt(0)) : "";
        textPaint.setFakeBoldText(false);
        if (!englishMode && !symbol.isEmpty()) {
            if (mode == Mode.LANDSCAPE) {
                textPaint.setTextSize(dp(13));
                textPaint.setFakeBoldText(true);
                canvas.drawText(label + " " + symbol, bounds.centerX(),
                        textBaseline(bounds, textPaint), textPaint);
            } else {
                textPaint.setTextSize(dp(13));
                canvas.drawText(label, bounds.centerX(), bounds.centerY() - dp(4), textPaint);
                textPaint.setTextSize(dp(15));
                textPaint.setFakeBoldText(true);
                canvas.drawText(symbol, bounds.centerX(), bounds.centerY() + dp(14), textPaint);
            }
        } else {
            int textSize = mode == Mode.LANDSCAPE ? (label.length() > 3 ? 11 : 13)
                    : (label.length() > 3 ? 13 : 17);
            textPaint.setTextSize(dp(textSize));
            textPaint.setFakeBoldText(key.equals("SPACE"));
            canvas.drawText(label, bounds.centerX(), textBaseline(bounds, textPaint), textPaint);
        }
        hits.add(new Hit(new RectF(bounds), HitKind.KEY, key, -1));
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN -> {
                downX = event.getX();
                downY = event.getY();
                Hit hit = findHit(downX, downY);
                downOnCandidate = hit != null && hit.kind() == HitKind.CANDIDATE;
                return true;
            }
            case MotionEvent.ACTION_UP -> {
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

    private String keyLabel(String key) {
        return switch (key) {
            case "MODE" -> englishMode ? "Alt/中" : "Alt/英";
            case "SHIFT" -> shifted ? "⇧" : "⇧";
            case "BACKSPACE" -> "⌫";
            case "ENTER" -> "↵";
            case "SPACE" -> "空白";
            case "SYMBOL" -> "符";
            case "EMOJI" -> "☺";
            default -> englishMode && shifted && key.length() == 1
                    ? key.toUpperCase(Locale.ROOT) : key;
        };
    }

    private float keyWeight(String key) {
        return switch (key) {
            case "SPACE" -> 4.2f;
            case "SHIFT", "BACKSPACE", "ENTER", "EMOJI", "MODE" -> 1.45f;
            case "SYMBOL" -> 1.2f;
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

    private String[] slice(String[] source, int start, int end) {
        String[] result = new String[end - start];
        System.arraycopy(source, start, result, 0, result.length);
        return result;
    }

    private int dp(float value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private float contentHeight() {
        int systemAreaHeight = switch (mode) {
            case PORTRAIT -> dp(PORTRAIT_SYSTEM_AREA_HEIGHT_DP);
            case LANDSCAPE -> dp(LANDSCAPE_SYSTEM_AREA_HEIGHT_DP);
            case HARDWARE -> 0;
        };
        return Math.max(0, getHeight() - systemAreaHeight);
    }
}
