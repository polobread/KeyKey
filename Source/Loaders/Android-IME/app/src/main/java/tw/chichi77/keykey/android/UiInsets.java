package tw.chichi77.keykey.android;

import android.os.Build;
import android.view.DisplayCutout;
import android.view.View;
import android.view.WindowInsets;

final class UiInsets {
    private UiInsets() {}

    @SuppressWarnings("deprecation")
    static void applySystemPadding(View view, int left, int top, int right, int bottom) {
        view.setPadding(left, top, right, bottom);
        view.setOnApplyWindowInsetsListener((target, insets) -> {
            int insetLeft;
            int insetTop;
            int insetRight;
            int insetBottom;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                android.graphics.Insets safeInsets = insets.getInsets(
                        WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
                insetLeft = safeInsets.left;
                insetTop = safeInsets.top;
                insetRight = safeInsets.right;
                insetBottom = safeInsets.bottom;
            } else {
                insetLeft = insets.getSystemWindowInsetLeft();
                insetTop = insets.getSystemWindowInsetTop();
                insetRight = insets.getSystemWindowInsetRight();
                insetBottom = insets.getSystemWindowInsetBottom();
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                    && Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                DisplayCutout cutout = insets.getDisplayCutout();
                if (cutout != null) {
                    insetLeft = Math.max(insetLeft, cutout.getSafeInsetLeft());
                    insetTop = Math.max(insetTop, cutout.getSafeInsetTop());
                    insetRight = Math.max(insetRight, cutout.getSafeInsetRight());
                    insetBottom = Math.max(insetBottom, cutout.getSafeInsetBottom());
                }
            }
            target.setPadding(left + insetLeft, top + insetTop,
                    right + insetRight, bottom + insetBottom);
            return insets;
        });
        view.requestApplyInsets();
    }
}
