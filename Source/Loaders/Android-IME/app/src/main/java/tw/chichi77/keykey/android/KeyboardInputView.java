package tw.chichi77.keykey.android;

import android.content.Context;
import android.os.Build;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.view.WindowManager;
import android.widget.FrameLayout;

/** Keeps a touch keyboard aligned to the bottom of its window. */
class KeyboardInputView extends FrameLayout {
    final BopomofoKeyboardView keyboard;
    private final boolean managesImeWindow;
    private final int[] locationOnScreen = new int[2];
    private int lastShortWindowHeight;
    private int lastClippedKeyboardHeight;

    KeyboardInputView(Context context, BopomofoKeyboardView keyboard) {
        this(context, keyboard, true);
    }

    KeyboardInputView(Context context, BopomofoKeyboardView keyboard, boolean managesImeWindow) {
        super(context);
        this.keyboard = keyboard;
        this.managesImeWindow = managesImeWindow;
        addView(keyboard, new LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM));
    }

    @Override public WindowInsets onApplyWindowInsets(WindowInsets insets) {
        if (managesImeWindow && Build.VERSION.SDK_INT >= 30 && !updateSystemBottomOverlap()) {
            int types = WindowInsets.Type.navigationBars();
            if (Build.VERSION.SDK_INT >= 36) types |= WindowInsets.Type.captionBar();
            keyboard.setSystemBottomInset(insets.getInsets(types).bottom);
        }
        return super.onApplyWindowInsets(insets);
    }

    @Override protected void onLayout(boolean changed, int left, int top, int right, int bottom) {
        super.onLayout(changed, left, top, right, bottom);
        if (!managesImeWindow) return;
        if (Build.VERSION.SDK_INT >= 30) updateSystemBottomOverlap();
        if (!keyboard.isTouchMode() || keyboard.getTop() >= 0) {
            lastShortWindowHeight = 0;
            return;
        }
        // After a hidden rotation the platform can lay out its old window
        // height even though the keyboard has already measured taller.
        // Keep the entire keyboard inside that frame for this pass.
        keyboard.layout(keyboard.getLeft(), 0, keyboard.getRight(), keyboard.getBottom());
        int keyboardHeight = keyboard.getMeasuredHeight();
        if (getHeight() != lastShortWindowHeight || keyboardHeight != lastClippedKeyboardHeight) {
            lastShortWindowHeight = getHeight();
            lastClippedKeyboardHeight = keyboardHeight;
            post(() -> {
                if (!isShown() || !keyboard.isTouchMode()
                        || keyboard.getMeasuredHeight() <= getHeight()) return;
                // Ask the window manager to apply the fresh measurement. Keep
                // WRAP_CONTENT so later resizing can still change the height.
                requestLayout();
                if (getContext() instanceof BopomofoImeService service) {
                    var window = service.getWindow().getWindow();
                    var attrs = window.getAttributes();
                    if (attrs.height == ViewGroup.LayoutParams.WRAP_CONTENT) {
                        window.setLayout(attrs.width, attrs.height);
                    }
                }
            });
        }
    }

    @android.annotation.TargetApi(30)
    private boolean updateSystemBottomOverlap() {
        WindowInsets rootInsets = getRootWindowInsets();
        if (rootInsets == null || getHeight() == 0) return false;

        getLocationOnScreen(locationOnScreen);
        int top = locationOnScreen[1];
        int bottom = top + getHeight();
        int navigation = rootInsets.getInsets(WindowInsets.Type.navigationBars()).bottom;
        int overlap = 0;
        if (navigation > 0) {
            int displayBottom = getContext().getSystemService(WindowManager.class)
                    .getCurrentWindowMetrics().getBounds().bottom;
            overlap = bottomOverlap(top, bottom, displayBottom, navigation);
        }
        if (Build.VERSION.SDK_INT >= 36) {
            int caption = rootInsets.getInsets(WindowInsets.Type.captionBar()).bottom;
            if (caption > 0) {
                // The IME control strip is attached to the window, while the
                // system navigation bar is attached to the display.
                View decor = getRootView();
                decor.getLocationOnScreen(locationOnScreen);
                int windowBottom = locationOnScreen[1] + decor.getHeight();
                overlap = Math.max(overlap, bottomOverlap(top, bottom, windowBottom, caption));
            }
        }
        keyboard.setSystemBottomInset(overlap);
        return true;
    }

    private static int bottomOverlap(int top, int bottom, int barBottom, int barHeight) {
        return Math.max(0, Math.min(bottom, barBottom) - Math.max(top, barBottom - barHeight));
    }

    @Override protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec);
        int cappedHeight = keyboard.cappedTouchWindowHeight();
        if (cappedHeight > getMeasuredHeight()) {
            setMeasuredDimension(getMeasuredWidth(), resolveSize(cappedHeight, heightMeasureSpec));
        }
    }
}
