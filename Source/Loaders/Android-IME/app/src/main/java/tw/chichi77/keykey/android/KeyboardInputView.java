package tw.chichi77.keykey.android;

import android.content.Context;
import android.os.Build;
import android.os.Bundle;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;

/** Keeps the keyboard at the bottom of the IME and hosts its local size controls. */
final class KeyboardInputView extends FrameLayout {
    private static final int CONTROL_HEIGHT_DP = 44;

    private final BopomofoKeyboardView keyboard;
    private final LinearLayout settingsMenu;
    private final LinearLayout resizeToolbar;
    private final Button bottomHandle;
    private Runnable openSettings;
    private KeyboardEdgeGeometry startingEdges;
    private KeyboardEdgeGeometry previewEdges;
    private boolean landscape;
    private boolean restoreDefaults;
    private Drag drag;

    private record Drag(int pointer, float startY, boolean top, KeyboardEdgeGeometry visible,
                        KeyboardEdgeGeometry before, int minContent, int maxContent,
                        int maxExtent, int maxGap) {
        KeyboardEdgeGeometry at(float screenY) {
            return visible.drag(top, Math.round(startY - screenY), minContent, maxContent,
                    maxExtent, maxGap);
        }
    }

    KeyboardInputView(Context context, BopomofoKeyboardView keyboard) {
        super(context);
        this.keyboard = keyboard;
        addView(keyboard, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM));

        settingsMenu = toolbar();
        addAction(settingsMenu, R.string.keyboard_resize_title, this::beginResize, 1);
        addAction(settingsMenu, R.string.keyboard_resize_open_settings, () -> {
            settingsMenu.setVisibility(GONE);
            if (openSettings != null) openSettings.run();
        }, 1);
        addAction(settingsMenu, R.string.keyboard_resize_cancel, () -> settingsMenu.setVisibility(GONE), 1);

        resizeToolbar = toolbar();
        addAction(resizeToolbar, R.string.keyboard_resize_reset, this::resetResize, 1);
        Button topHandle = button(R.string.keyboard_resize_top_label);
        topHandle.setContentDescription(context.getString(R.string.keyboard_resize_top));
        configureHandle(topHandle, true);
        resizeToolbar.addView(topHandle, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.MATCH_PARENT, 1.4f));
        addAction(resizeToolbar, R.string.keyboard_resize_cancel, this::cancelResize, 1);
        addAction(resizeToolbar, R.string.keyboard_resize_done, this::finishResize, 1);

        bottomHandle = button(R.string.keyboard_resize_bottom_up);
        bottomHandle.setContentDescription(context.getString(R.string.keyboard_resize_bottom));
        configureHandle(bottomHandle, false);
        bottomHandle.setVisibility(GONE);
        addView(bottomHandle, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT,
                dp(CONTROL_HEIGHT_DP), Gravity.TOP | Gravity.CENTER_HORIZONTAL));
    }

    void showSettingsMenu(Runnable openSettings) {
        if (!keyboard.isTouchMode() || isResizing()) return;
        this.openSettings = openSettings;
        settingsMenu.setVisibility(VISIBLE);
    }

    void beginResize() {
        if (!keyboard.isTouchMode() || isResizing()) return;
        KeyboardEdgeGeometry edges = keyboard.visibleTouchEdges();
        if (edges.contentHeight() <= 0) return;
        settingsMenu.setVisibility(GONE);
        landscape = keyboard.mode() == BopomofoKeyboardView.Mode.LANDSCAPE;
        startingEdges = edges;
        previewEdges = edges;
        restoreDefaults = false;
        updateBottomHandle();
        resizeToolbar.setVisibility(VISIBLE);
        bottomHandle.setVisibility(VISIBLE);
    }

    boolean isResizing() {
        return previewEdges != null;
    }

    boolean hasSizeControls() {
        return isResizing() || settingsMenu.getVisibility() == VISIBLE;
    }

    void cancelResize() {
        settingsMenu.setVisibility(GONE);
        if (!isResizing()) return;
        endResizeDrag();
        previewEdges = null;
        keyboard.setResizePreview(null);
        resizeToolbar.setVisibility(GONE);
        bottomHandle.setVisibility(GONE);
    }

    private void resetResize() {
        restoreDefaults = true;
        preview(new KeyboardEdgeGeometry(keyboard.defaultTouchHeight(), 0));
    }

    private void finishResize() {
        if (restoreDefaults || !previewEdges.equals(startingEdges)) {
            var size = new KeyboardSizeSettings.Size(
                    previewEdges.contentHeight() / (float) keyboard.defaultTouchHeight(),
                    previewEdges.bottom() / density());
            KeyboardSizeSettings.setSize(getContext(), landscape, size);
            keyboard.setTouchKeyboardSizes(KeyboardSizeSettings.size(getContext(), false),
                    KeyboardSizeSettings.size(getContext(), true));
        }
        cancelResize();
    }

    private void preview(KeyboardEdgeGeometry edges) {
        if (edges.equals(previewEdges)) return;
        previewEdges = edges;
        keyboard.setResizePreview(edges);
        updateBottomHandle();
    }

    private void updateBottomHandle() {
        bottomHandle.setText(previewEdges.bottom() == 0
                ? R.string.keyboard_resize_bottom_up : R.string.keyboard_resize_bottom_label);
    }

    private LinearLayout toolbar() {
        LinearLayout bar = new LinearLayout(getContext());
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setVisibility(GONE);
        addView(bar, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                dp(CONTROL_HEIGHT_DP), Gravity.TOP));
        return bar;
    }

    private void addAction(LinearLayout bar, int label, Runnable action, float weight) {
        Button button = button(label);
        button.setOnClickListener(view -> action.run());
        bar.addView(button, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, weight));
    }

    private Button button(int label) {
        Button button = new Button(getContext());
        button.setText(label);
        button.setAllCaps(false);
        button.setTextSize(13);
        button.setMinWidth(0);
        button.setMinimumWidth(0);
        button.setPadding(dp(2), 0, dp(2), 0);
        button.setFocusable(false);
        return button;
    }

    private void configureHandle(Button handle, boolean top) {
        handle.setOnTouchListener((view, event) -> onResizeTouch(event, top));
        handle.setAccessibilityDelegate(new View.AccessibilityDelegate() {
            @Override public void onInitializeAccessibilityNodeInfo(View host, AccessibilityNodeInfo info) {
                super.onInitializeAccessibilityNodeInfo(host, info);
                if (!isResizing()) return;
                info.removeAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_CLICK);
                info.setScrollable(true);
                if (!step(top, 1).equals(previewEdges)) {
                    info.addAction(new AccessibilityNodeInfo.AccessibilityAction(
                            AccessibilityNodeInfo.ACTION_SCROLL_FORWARD,
                            getContext().getString(R.string.keyboard_resize_step_up)));
                }
                if (!step(top, -1).equals(previewEdges)) {
                    info.addAction(new AccessibilityNodeInfo.AccessibilityAction(
                            AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD,
                            getContext().getString(R.string.keyboard_resize_step_down)));
                }
            }

            @Override public boolean performAccessibilityAction(View host, int action, Bundle args) {
                if (isResizing() && (action == AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
                        || action == AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD)) {
                    preview(step(top, action == AccessibilityNodeInfo.ACTION_SCROLL_FORWARD ? 1 : -1));
                    return true;
                }
                return super.performAccessibilityAction(host, action, args);
            }
        });
    }

    private KeyboardEdgeGeometry step(boolean top, int direction) {
        return dragFrom(top, -1, 0).at(-direction * dp(4));
    }

    private Drag dragFrom(boolean top, int pointer, float screenY) {
        KeyboardEdgeGeometry visible = keyboard.visibleTouchEdges();
        return new Drag(pointer, screenY, top, visible, previewEdges,
                Math.min(visible.contentHeight(), keyboard.minimumTouchHeight()),
                keyboard.maximumTouchHeight(), keyboard.maximumResizeExtent(),
                dp(KeyboardSizeSettings.MAX_BOTTOM_GAP_DP));
    }

    private boolean onResizeTouch(MotionEvent event, boolean top) {
        if (!isResizing()) return true;
        int action = event.getActionMasked();
        if (action == MotionEvent.ACTION_DOWN) {
            if (drag == null) {
                drag = dragFrom(top, event.getPointerId(0), screenY(event, 0));
                keyboard.setResizeDragActive(true);
                requestDisallowInterceptTouchEvent(true);
            }
            return true;
        }
        if (drag == null || drag.top() != top) return true;
        if (action == MotionEvent.ACTION_CANCEL) {
            preview(drag.before());
            endResizeDrag();
        } else if (action == MotionEvent.ACTION_MOVE || action == MotionEvent.ACTION_UP
                || action == MotionEvent.ACTION_POINTER_UP) {
            int index = event.findPointerIndex(drag.pointer());
            if (action == MotionEvent.ACTION_POINTER_UP && index != event.getActionIndex()) return true;
            if (index >= 0) {
                KeyboardEdgeGeometry next = drag.at(screenY(event, index));
                if (!next.equals(drag.visible()) || !previewEdges.equals(drag.before())) preview(next);
            }
            if (action != MotionEvent.ACTION_MOVE) endResizeDrag();
        }
        return true;
    }

    private void endResizeDrag() {
        drag = null;
        keyboard.setResizeDragActive(false);
    }

    private static float screenY(MotionEvent event, int pointer) {
        // The IME's top moves during a resize, so its local coordinates drift.
        return Build.VERSION.SDK_INT >= 29 ? event.getRawY(pointer)
                : event.getRawY() + event.getY(pointer) - event.getY(0);
    }

    private int dp(float value) {
        return Math.round(value * density());
    }

    private float density() {
        return getResources().getDisplayMetrics().density;
    }

    @Override public boolean onInterceptTouchEvent(MotionEvent event) {
        if (event.getActionMasked() == MotionEvent.ACTION_DOWN && settingsMenu.getVisibility() == VISIBLE
                && (event.getY() < settingsMenu.getTop() || event.getY() >= settingsMenu.getBottom())) {
            settingsMenu.setVisibility(GONE);
        }
        return super.onInterceptTouchEvent(event);
    }

    @Override protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec);
        int cappedHeight = keyboard.cappedIntegratedWindowHeight();
        if (cappedHeight > getMeasuredHeight()) {
            setMeasuredDimension(getMeasuredWidth(), resolveSize(cappedHeight, heightMeasureSpec));
        }
    }

    @Override protected void onLayout(boolean changed, int left, int top, int right, int bottom) {
        super.onLayout(changed, left, top, right, bottom);
        int keyboardTop = keyboard.getTop();
        if (settingsMenu.getVisibility() == VISIBLE) layoutAt(settingsMenu, 0, keyboardTop);
        if (isResizing()) {
            layoutAt(resizeToolbar, 0, keyboardTop);
            KeyboardEdgeGeometry edges = keyboard.visibleTouchEdges();
            int handleHeight = bottomHandle.getMeasuredHeight();
            int handleTop = Math.max(keyboardTop, keyboardTop + edges.contentHeight()
                    - handleHeight);
            layoutAt(bottomHandle, (getWidth() - bottomHandle.getMeasuredWidth()) / 2, handleTop);
        }
    }

    private static void layoutAt(View view, int left, int top) {
        view.layout(left, top, left + view.getMeasuredWidth(), top + view.getMeasuredHeight());
    }

    @Override protected void onDetachedFromWindow() {
        cancelResize();
        super.onDetachedFromWindow();
    }
}
