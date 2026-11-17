package tw.chichi77.keykey.android;

import android.content.Context;
import android.os.Build;
import android.view.Gravity;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.view.WindowManager;
import android.widget.FrameLayout;

/** Keeps a touch keyboard aligned to the bottom of its window. */
class KeyboardInputView extends FrameLayout {
    final BopomofoKeyboardView keyboard;
    private final boolean managesImeWindow;
    private int dispatchedNavigationBottom;
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
        if (managesImeWindow && Build.VERSION.SDK_INT >= 30) {
            dispatchedNavigationBottom = insets.getInsets(WindowInsets.Type.navigationBars()).bottom;
            updateNavigationBottom();
        }
        return super.onApplyWindowInsets(insets);
    }

    @Override protected void onLayout(boolean changed, int left, int top, int right, int bottom) {
        super.onLayout(changed, left, top, right, bottom);
        if (!managesImeWindow) return;
        if (Build.VERSION.SDK_INT >= 30 && dispatchedNavigationBottom == 0) {
            updateNavigationBottom();
        }
        if (!keyboard.hasIntegratedTouchControls() || keyboard.getTop() >= 0) {
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
                if (!isShown() || !keyboard.hasIntegratedTouchControls()
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
    private void updateNavigationBottom() {
        int bottom = dispatchedNavigationBottom;
        if (bottom == 0 && getHeight() > 0) {
            WindowInsets rootInsets = getRootWindowInsets();
            int rootBottom = rootInsets == null ? 0
                    : rootInsets.getInsets(WindowInsets.Type.navigationBars()).bottom;
            if (rootBottom > 0) {
                // A zero dispatch can also mean that an ancestor already moved
                // the content above the bar. Reserve only the part we overlap.
                int displayBottom = getContext().getSystemService(WindowManager.class)
                        .getCurrentWindowMetrics().getBounds().bottom;
                int[] location = new int[2];
                getLocationOnScreen(location);
                int navigationTop = displayBottom - rootBottom;
                bottom = Math.max(0, Math.min(rootBottom, location[1] + getHeight() - navigationTop));
            }
        }
        keyboard.setNavigationBarBottomInset(bottom);
    }

    @Override protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec);
        int cappedHeight = keyboard.cappedIntegratedWindowHeight();
        if (cappedHeight > getMeasuredHeight()) {
            setMeasuredDimension(getMeasuredWidth(), resolveSize(cappedHeight, heightMeasureSpec));
        }
    }
}
