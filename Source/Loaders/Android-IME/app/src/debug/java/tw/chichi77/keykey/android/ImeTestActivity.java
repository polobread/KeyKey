package tw.chichi77.keykey.android;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.ViewGroup;
import android.view.inputmethod.EditorInfo;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/** Debug-only host containing every editor shape supported by the IME test plan. */
public final class ImeTestActivity extends Activity {
    private TextView result;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        applyTestConfiguration();

        ScrollView scroll = new ScrollView(this);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        int padding = dp(16);
        content.setPadding(padding, padding, padding, padding);
        scroll.addView(content, new ScrollView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        TextView title = new TextView(this);
        title.setText("KeyKey IME Test Host（僅 debug）");
        title.setTextSize(22);
        title.setTextColor(Color.BLACK);
        title.setGravity(Gravity.CENTER);
        content.addView(title, matchWrap(dp(0), dp(8)));

        result = new TextView(this);
        result.setText("Action result: 尚未觸發");
        result.setTextSize(16);
        result.setTextColor(getColor(R.color.keykey_blue_dark));
        content.addView(result, matchWrap(dp(0), dp(12)));

        addSection(content, "欄位型態");
        addField(content, "一般文字", InputType.TYPE_CLASS_TEXT,
                EditorInfo.IME_ACTION_NONE, true, 0, null);
        addField(content, "Email", InputType.TYPE_CLASS_TEXT
                        | InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
                EditorInfo.IME_ACTION_NONE, true, 0, null);
        addField(content, "網址 URL", InputType.TYPE_CLASS_TEXT
                        | InputType.TYPE_TEXT_VARIATION_URI,
                EditorInfo.IME_ACTION_NONE, true, 0, null);
        addField(content, "電話", InputType.TYPE_CLASS_PHONE,
                EditorInfo.IME_ACTION_NONE, true, 0, null);
        addField(content, "整數", InputType.TYPE_CLASS_NUMBER,
                EditorInfo.IME_ACTION_NONE, true, 0, null);
        addField(content, "有號整數", InputType.TYPE_CLASS_NUMBER
                        | InputType.TYPE_NUMBER_FLAG_SIGNED,
                EditorInfo.IME_ACTION_NONE, true, 0, null);
        addField(content, "小數", InputType.TYPE_CLASS_NUMBER
                        | InputType.TYPE_NUMBER_FLAG_DECIMAL,
                EditorInfo.IME_ACTION_NONE, true, 0, null);
        addField(content, "有號小數", InputType.TYPE_CLASS_NUMBER
                        | InputType.TYPE_NUMBER_FLAG_DECIMAL
                        | InputType.TYPE_NUMBER_FLAG_SIGNED,
                EditorInfo.IME_ACTION_NONE, true, 0, null);
        addField(content, "日期", InputType.TYPE_CLASS_DATETIME
                        | InputType.TYPE_DATETIME_VARIATION_DATE,
                EditorInfo.IME_ACTION_NONE, true, 0, null);
        addField(content, "時間", InputType.TYPE_CLASS_DATETIME
                        | InputType.TYPE_DATETIME_VARIATION_TIME,
                EditorInfo.IME_ACTION_NONE, true, 0, null);
        addField(content, "日期／時間", InputType.TYPE_CLASS_DATETIME
                        | InputType.TYPE_DATETIME_VARIATION_NORMAL,
                EditorInfo.IME_ACTION_NONE, true, 0, null);
        addField(content, "密碼", InputType.TYPE_CLASS_TEXT
                        | InputType.TYPE_TEXT_VARIATION_PASSWORD,
                EditorInfo.IME_ACTION_NONE, true, 0, null);
        addField(content, "姓名", InputType.TYPE_CLASS_TEXT
                        | InputType.TYPE_TEXT_VARIATION_PERSON_NAME,
                EditorInfo.IME_ACTION_NONE, true, 0, null);
        addField(content, "地址", InputType.TYPE_CLASS_TEXT
                        | InputType.TYPE_TEXT_VARIATION_POSTAL_ADDRESS,
                EditorInfo.IME_ACTION_NONE, true, 0, null);
        addField(content, "搜尋欄", InputType.TYPE_CLASS_TEXT
                        | InputType.TYPE_TEXT_VARIATION_WEB_EDIT_TEXT,
                EditorInfo.IME_ACTION_SEARCH, true, 0, null);
        addField(content, "簡訊", InputType.TYPE_CLASS_TEXT
                        | InputType.TYPE_TEXT_VARIATION_SHORT_MESSAGE,
                EditorInfo.IME_ACTION_SEND, true, 0, null);
        addField(content, "長文字", InputType.TYPE_CLASS_TEXT
                        | InputType.TYPE_TEXT_VARIATION_LONG_MESSAGE
                        | InputType.TYPE_TEXT_FLAG_MULTI_LINE,
                EditorInfo.IME_FLAG_NO_ENTER_ACTION, false, 0, null);
        addField(content, "ASCII 限定", InputType.TYPE_CLASS_TEXT
                        | InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
                        | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS,
                EditorInfo.IME_ACTION_NONE, true, 0, null);

        addSection(content, "Enter action");
        addField(content, "完成", InputType.TYPE_CLASS_TEXT,
                EditorInfo.IME_ACTION_DONE, true, 0, null);
        addField(content, "下一個", InputType.TYPE_CLASS_TEXT,
                EditorInfo.IME_ACTION_NEXT, true, 0, null);
        addField(content, "搜尋", InputType.TYPE_CLASS_TEXT,
                EditorInfo.IME_ACTION_SEARCH, true, 0, null);
        addField(content, "傳送", InputType.TYPE_CLASS_TEXT,
                EditorInfo.IME_ACTION_SEND, true, 0, null);
        addField(content, "前往", InputType.TYPE_CLASS_TEXT,
                EditorInfo.IME_ACTION_GO, true, 0, null);
        addField(content, "上一個", InputType.TYPE_CLASS_TEXT,
                EditorInfo.IME_ACTION_PREVIOUS, true, 0, null);
        addField(content, "自訂 action", InputType.TYPE_CLASS_TEXT,
                EditorInfo.IME_ACTION_UNSPECIFIED, true, 42, "送出表單");
        addField(content, "禁止 Enter action", InputType.TYPE_CLASS_TEXT,
                EditorInfo.IME_ACTION_DONE | EditorInfo.IME_FLAG_NO_ENTER_ACTION,
                true, 0, null);

        setContentView(scroll);
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        applyTestConfiguration();
    }

    private void applyTestConfiguration() {
        String floating = getIntent().getStringExtra("floating");
        if ("off".equals(floating)) {
            CandidateWindowSettings.setFloatingEnabled(this, false);
        } else if ("vertical".equals(floating) || "horizontal".equals(floating)) {
            CandidateWindowSettings.setLayout(this, "horizontal".equals(floating)
                    ? CandidateWindowSettings.Layout.HORIZONTAL
                    : CandidateWindowSettings.Layout.VERTICAL);
            CandidateWindowSettings.setFloatingEnabled(this, true);
        }
        if (getIntent().hasExtra("keyPreview")) {
            KeyPreviewSettings.setEnabled(this,
                    getIntent().getBooleanExtra("keyPreview", true));
        }
        if (getIntent().hasExtra("hapticLevel")) {
            HapticSettings.setLevel(this, getIntent().getIntExtra("hapticLevel", 0));
        }
        String phrases = getIntent().getStringExtra("phrases");
        if ("none".equals(phrases)) {
            PhraseSettings.setEnabledCollections(this, java.util.Set.of());
        } else if ("base".equals(phrases)) {
            PhraseSettings.setEnabledCollections(this, PhraseSettings.baseCollectionOnly());
        }
    }

    private void addSection(LinearLayout content, String label) {
        TextView section = new TextView(this);
        section.setText(label);
        section.setTextSize(19);
        section.setTextColor(Color.BLACK);
        content.addView(section, matchWrap(dp(12), dp(4)));
    }

    private void addField(LinearLayout content, String label, int inputType, int imeOptions,
                          boolean singleLine, int privateActionId, String privateActionLabel) {
        TextView caption = new TextView(this);
        caption.setText(label);
        caption.setTextSize(14);
        caption.setTextColor(Color.DKGRAY);
        content.addView(caption, matchWrap(dp(4), dp(0)));

        EditText field = new EditText(this);
        field.setHint(label + "測試");
        field.setInputType(inputType);
        field.setSingleLine(singleLine);
        field.setImeOptions(imeOptions);
        if (privateActionLabel != null) {
            field.setImeActionLabel(privateActionLabel, privateActionId);
        }
        field.setOnEditorActionListener((view, actionId, event) -> {
            String eventName = event == null ? "editor action" : KeyEvent.keyCodeToString(event.getKeyCode());
            result.setText(label + ": actionId=" + actionId + ", " + eventName);
            return true;
        });
        content.addView(field, matchWrap(dp(0), dp(6)));
    }

    private LinearLayout.LayoutParams matchWrap(int top, int bottom) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        params.setMargins(0, top, 0, bottom);
        return params;
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
