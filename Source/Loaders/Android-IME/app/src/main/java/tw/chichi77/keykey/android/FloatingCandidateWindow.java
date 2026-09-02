package tw.chichi77.keykey.android;

import android.content.Context;
import android.graphics.Color;
import android.graphics.Insets;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.util.DisplayMetrics;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.view.WindowManager;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.text.TextUtils;

import java.util.List;

final class FloatingCandidateWindow {
    interface Listener {
        void onPress();
        void onCandidate(int displayedIndex);
        void onWindowUnavailable(CandidateWindowSettings.Failure failure);
    }

    private static final int VERTICAL_WIDTH_DP = 96;
    private static final int VERTICAL_ROW_HEIGHT_DP = 40;
    private static final int HORIZONTAL_CELL_WIDTH_DP = 68;
    private static final int HORIZONTAL_HEIGHT_DP = 48;
    private static final int MAX_TOKEN_RETRIES = 15;
    private static final long TOKEN_RETRY_DELAY_MS = 100;

    private final Context context;
    private final View tokenView;
    private final WindowManager windowManager;
    private final LinearLayout content;
    private final Listener listener;
    private final WindowManager.LayoutParams windowParameters;

    private boolean added;
    private RectF cursorAnchor;
    private List<String> candidates = List.of();
    private int highlightedIndex = -1;
    private int tokenRetryCount;
    private CandidateWindowSettings.Layout layout = CandidateWindowSettings.Layout.VERTICAL;

    FloatingCandidateWindow(Context context, View tokenView, Listener listener) {
        this.context = context;
        this.tokenView = tokenView;
        this.listener = listener;
        windowManager = context.getSystemService(WindowManager.class);

        content = new LinearLayout(context);
        content.setElevation(dp(8));
        content.setClipToOutline(true);

        windowParameters = new WindowManager.LayoutParams();
        windowParameters.type = WindowManager.LayoutParams.TYPE_APPLICATION_SUB_PANEL;
        windowParameters.format = PixelFormat.TRANSLUCENT;
        windowParameters.gravity = Gravity.TOP | Gravity.START;
        windowParameters.flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                | WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN;
        windowParameters.setTitle("KeyKey candidate window");
    }

    void update(List<String> candidates, int highlightedIndex,
                CandidateWindowSettings.Layout layout, RectF cursorAnchor) {
        this.candidates = List.copyOf(candidates);
        this.highlightedIndex = highlightedIndex;
        this.layout = layout;
        this.cursorAnchor = cursorAnchor == null ? null : new RectF(cursorAnchor);
        if (candidates.isEmpty()) {
            tokenRetryCount = 0;
            hide();
            return;
        }
        rebuildContent();
        showOrMove();
    }

    void updateCursorAnchor(RectF cursorAnchor) {
        this.cursorAnchor = cursorAnchor == null ? null : new RectF(cursorAnchor);
        if (added) showOrMove();
    }

    void hide() {
        if (!added || windowManager == null) return;
        try {
            windowManager.removeViewImmediate(content);
        } catch (IllegalArgumentException ignored) {
            // The IME window may already have been detached by the system.
        }
        added = false;
    }

    private void rebuildContent() {
        content.removeAllViews();
        boolean horizontal = layout == CandidateWindowSettings.Layout.HORIZONTAL;
        content.setOrientation(horizontal ? LinearLayout.HORIZONTAL : LinearLayout.VERTICAL);
        content.setBackground(windowBackground());

        Rect safeBounds = safeBounds();
        int horizontalWidth = Math.min(safeBounds.width(),
                dp(HORIZONTAL_CELL_WIDTH_DP) * candidates.size());
        int cellWidth = candidates.isEmpty() ? 0 : horizontalWidth / candidates.size();
        float horizontalTextSize = cellWidth < dp(46) ? 10 : cellWidth < dp(58) ? 12 : 15;
        int verticalRowHeight = Math.min(dp(VERTICAL_ROW_HEIGHT_DP),
                safeBounds.height() / candidates.size());

        for (int index = 0; index < candidates.size(); index++) {
            String candidate = candidates.get(index);
            TextView item = new TextView(context);
            int itemText = horizontal ? R.string.floating_candidate_item_horizontal
                    : R.string.floating_candidate_item_vertical;
            item.setText(context.getString(itemText, index + 1,
                    CandidateDisplayText.elide(candidate)));
            item.setContentDescription(context.getString(
                    R.string.floating_candidate_description, index + 1, candidate));
            item.setSingleLine(true);
            item.setEllipsize(TextUtils.TruncateAt.END);
            item.setGravity(horizontal ? Gravity.CENTER : Gravity.CENTER_VERTICAL | Gravity.START);
            item.setTextSize(TypedValue.COMPLEX_UNIT_DIP,
                    horizontal ? horizontalTextSize : 18);
            item.setPadding(horizontal ? dp(2) : dp(4), 0,
                    horizontal ? dp(2) : dp(4), 0);
            boolean highlighted = index == highlightedIndex;
            item.setTextColor(highlighted ? Color.WHITE : Color.rgb(24, 31, 44));
            item.setBackgroundColor(highlighted
                    ? context.getColor(R.color.keykey_blue) : Color.TRANSPARENT);
            final int selectedIndex = index;
            item.setOnClickListener(view -> {
                listener.onPress();
                listener.onCandidate(selectedIndex);
            });

            LinearLayout.LayoutParams itemParameters;
            if (horizontal) {
                itemParameters = new LinearLayout.LayoutParams(
                        0, dp(HORIZONTAL_HEIGHT_DP), 1f);
            } else {
                itemParameters = new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, verticalRowHeight);
            }
            content.addView(item, itemParameters);
        }

        windowParameters.width = horizontal ? horizontalWidth : dp(VERTICAL_WIDTH_DP);
        windowParameters.height = horizontal ? dp(HORIZONTAL_HEIGHT_DP)
                : verticalRowHeight * candidates.size();
    }

    private void showOrMove() {
        if (windowManager == null || candidates.isEmpty()) return;
        if (tokenView.getWindowToken() == null) {
            retryOrFallback(CandidateWindowSettings.Failure.TOKEN);
            return;
        }
        tokenRetryCount = 0;

        Rect safeBounds = safeBounds();
        int gap = dp(4);
        int width = windowParameters.width;
        int height = windowParameters.height;
        int x;
        int y;
        if (cursorAnchor != null) {
            x = Math.round(cursorAnchor.left);
            int below = Math.round(cursorAnchor.bottom) + gap;
            int above = Math.round(cursorAnchor.top) - height - gap;
            y = below + height <= safeBounds.bottom ? below : above;
        } else {
            x = safeBounds.centerX() - width / 2;
            y = safeBounds.bottom - height - dp(12);
        }
        windowParameters.x = clamp(x, safeBounds.left, safeBounds.right - width);
        windowParameters.y = clamp(y, safeBounds.top, safeBounds.bottom - height);
        windowParameters.token = tokenView.getWindowToken();

        try {
            if (added) windowManager.updateViewLayout(content, windowParameters);
            else {
                windowManager.addView(content, windowParameters);
                added = true;
            }
        } catch (WindowManager.BadTokenException | WindowManager.InvalidDisplayException
                | SecurityException | IllegalStateException error) {
            if (added) {
                try {
                    windowManager.removeViewImmediate(content);
                } catch (IllegalArgumentException ignored) {
                    // The IME window may already have been detached by the system.
                }
            }
            added = false;
            retryOrFallback(CandidateWindowSettings.Failure.ATTACH);
        }
    }

    private void retryOrFallback(CandidateWindowSettings.Failure failure) {
        if (++tokenRetryCount <= MAX_TOKEN_RETRIES) {
            tokenView.postDelayed(() -> showOrMove(), TOKEN_RETRY_DELAY_MS);
        } else {
            tokenRetryCount = 0;
            listener.onWindowUnavailable(failure);
        }
    }

    private Rect safeBounds() {
        Rect bounds;
        WindowInsets windowInsets;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            android.view.WindowMetrics metrics = windowManager.getCurrentWindowMetrics();
            bounds = new Rect(metrics.getBounds());
            windowInsets = metrics.getWindowInsets();
        } else {
            DisplayMetrics metrics = new DisplayMetrics();
            windowManager.getDefaultDisplay().getRealMetrics(metrics);
            bounds = new Rect(0, 0, metrics.widthPixels, metrics.heightPixels);
            windowInsets = tokenView.getRootWindowInsets();
        }

        if (windowInsets == null) return bounds;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Insets insets = windowInsets.getInsetsIgnoringVisibility(
                    WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            bounds.left += insets.left;
            bounds.top += insets.top;
            bounds.right -= insets.right;
            bounds.bottom -= insets.bottom;
        } else {
            bounds.left += windowInsets.getStableInsetLeft();
            bounds.top += windowInsets.getStableInsetTop();
            bounds.right -= windowInsets.getStableInsetRight();
            bounds.bottom -= windowInsets.getStableInsetBottom();
        }
        return bounds;
    }

    private GradientDrawable windowBackground() {
        GradientDrawable background = new GradientDrawable();
        background.setColor(Color.rgb(244, 247, 252));
        background.setCornerRadius(dp(7));
        background.setStroke(dp(1), Color.rgb(92, 102, 119));
        return background;
    }

    private int clamp(int value, int minimum, int maximum) {
        if (maximum < minimum) return minimum;
        return Math.max(minimum, Math.min(maximum, value));
    }

    private int dp(float value) {
        return Math.round(value * context.getResources().getDisplayMetrics().density);
    }
}
