package tw.chichi77.keykey.android;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.os.Bundle;
import android.provider.Settings;
import android.view.Gravity;
import android.view.ViewGroup;
import android.view.inputmethod.InputMethodManager;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

public final class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        int padding = dp(24);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setGravity(Gravity.CENTER_HORIZONTAL);
        content.setPadding(padding, padding, padding, padding);
        content.setBackgroundColor(getColor(R.color.keykey_surface));

        TextView title = new TextView(this);
        title.setText(R.string.setup_title);
        title.setTextSize(28);
        title.setTextColor(getColor(R.color.keykey_blue_dark));
        title.setGravity(Gravity.CENTER);
        content.addView(title, matchWrap(dp(0), dp(20)));

        TextView description = new TextView(this);
        description.setText(R.string.setup_description);
        description.setTextSize(17);
        description.setTextColor(Color.DKGRAY);
        description.setGravity(Gravity.CENTER);
        description.setLineSpacing(0, 1.2f);
        content.addView(description, matchWrap(dp(0), dp(32)));

        Button enable = new Button(this);
        enable.setText(R.string.enable_ime);
        enable.setAllCaps(false);
        enable.setOnClickListener(view -> startActivity(new Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)));
        content.addView(enable, matchWrap(dp(0), dp(12)));

        Button choose = new Button(this);
        choose.setText(R.string.choose_ime);
        choose.setAllCaps(false);
        choose.setOnClickListener(view -> {
            InputMethodManager manager = getSystemService(InputMethodManager.class);
            if (manager != null) manager.showInputMethodPicker();
        });
        content.addView(choose, matchWrap(dp(0), dp(24)));

        TextView privacy = new TextView(this);
        privacy.setText(R.string.privacy_note);
        privacy.setTextSize(14);
        privacy.setTextColor(Color.GRAY);
        privacy.setGravity(Gravity.CENTER);
        content.addView(privacy, matchWrap(dp(0), dp(12)));

        setContentView(content);
    }

    private LinearLayout.LayoutParams matchWrap(int top, int bottom) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        params.setMargins(0, top, 0, bottom);
        return params;
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
