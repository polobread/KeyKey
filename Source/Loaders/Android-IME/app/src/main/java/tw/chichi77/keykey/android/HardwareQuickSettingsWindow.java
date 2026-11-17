package tw.chichi77.keykey.android;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.PixelFormat;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.LinearLayout;

/** An attached, non-focusable panel above the physical keyboard's candidate strip. */
final class HardwareQuickSettingsWindow {
    interface Listener {
        void onScriptToggle();
        /** A null method switches to English while keeping the last Chinese method. */
        void onInputModeSelected(ChineseInputMethod method);
        void onWidthToggle();
        void openKeyboardSettings();
    }

    private static final int BUTTON_HEIGHT_DP = 48;
    private static final int PADDING_DP = 4;
    private static final int GAP_DP = 2;

    private final Context context;
    private final View anchor;
    private final WindowManager windowManager;
    private final WindowManager.LayoutParams window;
    private final LinearLayout content;
    private final LinearLayout methodChoices;
    private final Button scriptButton;
    private final Button modeButton;
    private final Button widthButton;
    private final Button[] methodButtons = new Button[ChineseInputMethod.values().length];
    private final Button englishButton;
    private final int[] anchorLocation = new int[2];
    private boolean attached;
    private State state;

    private record State(boolean simplified, ChineseInputMethod method, boolean english,
                         boolean fullWidth) {}

    HardwareQuickSettingsWindow(Context context, View anchor, Listener listener) {
        this.context = context;
        this.anchor = anchor;
        windowManager = context.getSystemService(WindowManager.class);
        window = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.TYPE_APPLICATION_SUB_PANEL,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        | WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                        | WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH
                        | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN, PixelFormat.TRANSLUCENT);
        // The anchor position is in absolute screen coordinates.
        window.gravity = Gravity.TOP | Gravity.getAbsoluteGravity(Gravity.START, View.LAYOUT_DIRECTION_LTR);
        window.setTitle("KeyKey hardware quick settings");

        content = new LinearLayout(context) {
            @Override public boolean dispatchTouchEvent(MotionEvent event) {
                if (event.getActionMasked() == MotionEvent.ACTION_OUTSIDE) {
                    // The trigger's touch-up toggles the panel. Leave that gesture to the anchor.
                    anchor.getLocationOnScreen(anchorLocation);
                    float x = event.getRawX() - anchorLocation[0];
                    float y = event.getRawY() - anchorLocation[1];
                    if (x < 0 || x >= anchor.getWidth() || y < 0 || y >= anchor.getHeight()) dismiss();
                    return true;
                }
                return super.dispatchTouchEvent(event);
            }
        };
        content.setOrientation(LinearLayout.VERTICAL);
        content.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
        content.setPadding(dp(PADDING_DP), dp(PADDING_DP), dp(PADDING_DP), dp(PADDING_DP));
        GradientDrawable background = new GradientDrawable();
        background.setColor(context.getColor(R.color.keykey_surface));
        background.setCornerRadius(dp(7));
        content.setBackground(background);
        content.setElevation(dp(6));

        methodChoices = new LinearLayout(context);
        methodChoices.setOrientation(LinearLayout.VERTICAL);
        methodChoices.setVisibility(View.GONE);
        content.addView(methodChoices, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        LinearLayout firstChoices = addRow(methodChoices);
        LinearLayout lastChoices = addRow(methodChoices);
        for (ChineseInputMethod method : ChineseInputMethod.values()) {
            Button choice = addButton(method.ordinal() < 3 ? firstChoices : lastChoices, () -> {
                setMethodChoicesVisible(false);
                listener.onInputModeSelected(method);
            });
            choice.setText(method.displayName);
            setupMethodChoice(choice);
            methodButtons[method.ordinal()] = choice;
        }
        englishButton = addButton(lastChoices, () -> {
            setMethodChoicesVisible(false);
            listener.onInputModeSelected(null);
        });
        englishButton.setText(R.string.hardware_quick_english);
        setupMethodChoice(englishButton);

        LinearLayout controls = addRow(content);
        scriptButton = addButton(controls, listener::onScriptToggle);
        modeButton = addButton(controls, () -> setMethodChoicesVisible(methodChoices.getVisibility() != View.VISIBLE));
        widthButton = addButton(controls, listener::onWidthToggle);
        addButton(controls, listener::openKeyboardSettings).setText(R.string.hardware_quick_settings);
    }

    void toggle(boolean simplified, ChineseInputMethod method, boolean english, boolean fullWidth) {
        if (isShowing()) {
            dismiss();
            return;
        }
        if (windowManager == null || anchor.getWindowToken() == null || anchor.getWidth() == 0) return;
        render(new State(simplified, method, english, fullWidth));
        window.token = anchor.getWindowToken();
        positionWindow();
        try {
            windowManager.addView(content, window);
            attached = true;
        } catch (WindowManager.BadTokenException | WindowManager.InvalidDisplayException
                | SecurityException | IllegalStateException ignored) {
            // The editor or the display can disappear after the anchor check.
        }
    }

    void update(boolean simplified, ChineseInputMethod method, boolean english, boolean fullWidth) {
        if (isShowing()) render(new State(simplified, method, english, fullWidth));
    }

    boolean isShowing() {
        return attached;
    }

    void dismiss() {
        if (!attached) return;
        attached = false;
        methodChoices.setVisibility(View.GONE);
        try {
            windowManager.removeViewImmediate(content);
        } catch (IllegalArgumentException ignored) {
            // The IME window may already have been detached by the system.
        }
    }

    private void render(State next) {
        if (next.equals(state)) return;
        state = next;
        scriptButton.setText(next.simplified() ? R.string.hardware_quick_simplified
                : R.string.hardware_quick_traditional);
        scriptButton.setContentDescription(context.getString(next.simplified()
                ? R.string.hardware_quick_script_simplified : R.string.hardware_quick_script_traditional));
        String methodName = next.english() ? context.getString(R.string.hardware_quick_english)
                : next.method().displayName;
        String methodSymbol = next.english() ? "英" : next.method() == ChineseInputMethod.SMART
                ? "好" : next.method().symbol;
        modeButton.setText(context.getString(R.string.hardware_quick_mode_button, methodSymbol));
        modeButton.setContentDescription(context.getString(R.string.hardware_quick_mode_description, methodName));
        widthButton.setText(next.fullWidth() ? R.string.hardware_quick_full : R.string.hardware_quick_half);
        widthButton.setContentDescription(context.getString(next.fullWidth()
                ? R.string.hardware_quick_width_full : R.string.hardware_quick_width_half));
        for (ChineseInputMethod method : ChineseInputMethod.values()) {
            methodButtons[method.ordinal()].setSelected(!next.english() && next.method() == method);
        }
        englishButton.setSelected(next.english());
    }

    private void setMethodChoicesVisible(boolean visible) {
        if (!attached) return;
        methodChoices.setVisibility(visible ? View.VISIBLE : View.GONE);
        positionWindow();
        try {
            windowManager.updateViewLayout(content, window);
        } catch (IllegalArgumentException | IllegalStateException ignored) {
            dismiss();
        }
    }

    private void positionWindow() {
        anchor.getLocationOnScreen(anchorLocation);
        int panels = methodChoices.getVisibility() == View.VISIBLE ? 3 : 1;
        window.width = anchor.getWidth();
        window.height = panels * dp(BUTTON_HEIGHT_DP) + 2 * dp(PADDING_DP);
        window.x = anchorLocation[0];
        // Keep the strip fixed while the method chooser expands upward.
        window.y = Math.max(topInset(), anchorLocation[1] - dp(GAP_DP) - window.height);
    }

    private int topInset() {
        WindowInsets insets = anchor.getRootWindowInsets();
        if (insets == null) return 0;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return insets.getInsetsIgnoringVisibility(
                    WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout()).top;
        }
        return insets.getStableInsetTop();
    }

    private LinearLayout addRow(LinearLayout parent) {
        LinearLayout row = new LinearLayout(context);
        row.setOrientation(LinearLayout.HORIZONTAL);
        parent.addView(row, ViewGroup.LayoutParams.MATCH_PARENT, dp(BUTTON_HEIGHT_DP));
        return row;
    }

    private Button addButton(LinearLayout row, Runnable action) {
        Button button = new Button(context);
        button.setAllCaps(false);
        button.setTextSize(14);
        button.setMinWidth(0);
        button.setMinimumWidth(0);
        button.setPadding(dp(2), 0, dp(2), 0);
        button.setMaxLines(1);
        button.setEllipsize(TextUtils.TruncateAt.END);
        button.setFocusable(false);
        button.setOnClickListener(view -> action.run());
        row.addView(button, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1));
        return button;
    }

    private void setupMethodChoice(Button button) {
        button.setTextColor(new ColorStateList(
                new int[][]{{android.R.attr.state_selected}, new int[0]},
                new int[]{context.getColor(R.color.keykey_blue), button.getCurrentTextColor()}));
    }

    private int dp(float value) {
        return Math.round(value * context.getResources().getDisplayMetrics().density);
    }
}
