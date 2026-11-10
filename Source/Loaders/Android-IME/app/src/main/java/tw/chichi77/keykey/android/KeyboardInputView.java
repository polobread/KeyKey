package tw.chichi77.keykey.android;

import android.content.Context;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.FrameLayout;

/** Keeps a touch keyboard aligned to the bottom of its window. */
class KeyboardInputView extends FrameLayout {
    final BopomofoKeyboardView keyboard;

    KeyboardInputView(Context context, BopomofoKeyboardView keyboard) {
        super(context);
        this.keyboard = keyboard;
        addView(keyboard, new LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
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
