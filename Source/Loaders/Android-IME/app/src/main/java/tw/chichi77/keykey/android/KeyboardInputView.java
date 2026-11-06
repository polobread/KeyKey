package tw.chichi77.keykey.android;

import android.content.Context;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.FrameLayout;

/** Keeps capped content at the bottom of the IME's allocated window. */
final class KeyboardInputView extends FrameLayout {
    private final BopomofoKeyboardView keyboard;

    KeyboardInputView(Context context, BopomofoKeyboardView keyboard) {
        super(context);
        this.keyboard = keyboard;
        addView(keyboard, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM));
    }

    @Override protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec);
        int cappedHeight = keyboard.cappedIntegratedWindowHeight();
        if (cappedHeight > getMeasuredHeight()) {
            setMeasuredDimension(getMeasuredWidth(), resolveSize(cappedHeight, heightMeasureSpec));
        }
    }
}
