package tw.chichi77.keykey.android;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.graphics.Color;
import android.os.Bundle;
import android.net.Uri;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.IOException;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

/** A local phrase editor backed by the same user table as macOS Manjusri. */
public final class UserPhrasesActivity extends Activity {
    private static final int IMPORT_PHRASES = 1;
    private static final int EXPORT_PHRASES = 2;
    private SmartMandarinUserData userData;
    private LinearLayout phraseList;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        setTitle("好打注音自訂詞");

        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(getColor(R.color.keykey_surface));
        UiInsets.applySystemPadding(scroll, dp(20), dp(20), dp(20), dp(20));
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(0, 0, 0, dp(12));
        scroll.addView(content);
        setContentView(scroll);

        TextView heading = new TextView(this);
        heading.setText("好打注音自訂詞");
        heading.setTextSize(24);
        heading.setTextColor(getColor(R.color.keykey_blue_dark));
        content.addView(heading);

        TextView hint = new TextView(this);
        hint.setText("每個字輸入一組注音，以空格分隔。例如：你好／ㄋㄧˇ ㄏㄠˇ。"
                + "也可以用標準鍵位輸入 su3 cl3。");
        hint.setTextSize(14);
        hint.setTextColor(Color.DKGRAY);
        LinearLayout.LayoutParams hintLayout = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        hintLayout.topMargin = dp(12);
        content.addView(hint, hintLayout);

        Button add = new Button(this);
        add.setText("新增自訂詞");
        add.setOnClickListener(view -> edit(null));
        content.addView(add);

        LinearLayout fileActions = new LinearLayout(this);
        fileActions.setOrientation(LinearLayout.HORIZONTAL);
        Button importButton = new Button(this);
        importButton.setText("匯入自訂詞");
        importButton.setOnClickListener(view -> {
            Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.setType("*/*");
            startActivityForResult(intent, IMPORT_PHRASES);
        });
        fileActions.addView(importButton, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        Button exportButton = new Button(this);
        exportButton.setText("匯出自訂詞");
        exportButton.setOnClickListener(view -> {
            Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.setType("text/plain");
            intent.putExtra(Intent.EXTRA_TITLE, "KeyKey-UserPhrases.mjsr");
            startActivityForResult(intent, EXPORT_PHRASES);
        });
        fileActions.addView(exportButton, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        content.addView(fileActions);

        phraseList = new LinearLayout(this);
        phraseList.setOrientation(LinearLayout.VERTICAL);
        content.addView(phraseList);

        try {
            userData = SmartMandarinUserData.open(this);
            reload();
        } catch (RuntimeException error) {
            add.setEnabled(false);
            importButton.setEnabled(false);
            exportButton.setEnabled(false);
            TextView failure = new TextView(this);
            failure.setText("無法開啟自訂詞資料庫：" + error.getMessage());
            phraseList.addView(failure);
        }
    }

    private void reload() {
        phraseList.removeAllViews();
        if (userData == null) return;
        for (SmartMandarinUserData.Phrase phrase : userData.phrases()) {
            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.HORIZONTAL);
            row.setGravity(Gravity.CENTER_VERTICAL);
            Button edit = new Button(this);
            edit.setText(phrase.text() + "\n" + phrase.reading());
            edit.setAllCaps(false);
            edit.setGravity(Gravity.START | Gravity.CENTER_VERTICAL);
            edit.setOnClickListener(view -> edit(phrase));
            row.addView(edit, new LinearLayout.LayoutParams(0,
                    ViewGroup.LayoutParams.WRAP_CONTENT, 1));
            Button delete = new Button(this);
            delete.setText("刪除");
            delete.setContentDescription("刪除 " + phrase.text());
            delete.setOnClickListener(view -> confirmDelete(phrase));
            row.addView(delete);
            phraseList.addView(row);
        }
    }

    private void edit(SmartMandarinUserData.Phrase phrase) {
        if (userData == null) return;
        LinearLayout fields = new LinearLayout(this);
        fields.setOrientation(LinearLayout.VERTICAL);
        fields.setPadding(dp(20), 0, dp(20), 0);
        EditText text = new EditText(this);
        text.setHint("詞句，例如 你好");
        text.setSingleLine(true);
        text.setText(phrase == null ? "" : phrase.text());
        fields.addView(text);
        EditText reading = new EditText(this);
        reading.setHint("注音或鍵位，例如 su3 cl3");
        reading.setSingleLine(true);
        reading.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        reading.setText(phrase == null ? "" : phrase.reading());
        fields.addView(reading);

        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle(phrase == null ? "新增自訂詞" : "編輯自訂詞")
                .setView(fields)
                .setNegativeButton("取消", null)
                .setPositiveButton("儲存", null)
                .create();
        dialog.setOnShowListener(ignored -> dialog.getButton(AlertDialog.BUTTON_POSITIVE)
                .setOnClickListener(view -> {
                    try {
                        userData.savePhrase(phrase == null ? null : phrase.id(),
                                text.getText().toString(), reading.getText().toString());
                        dialog.dismiss();
                        reload();
                    } catch (RuntimeException error) {
                        Toast.makeText(this, error.getMessage(), Toast.LENGTH_LONG).show();
                    }
                }));
        dialog.show();
    }

    private void confirmDelete(SmartMandarinUserData.Phrase phrase) {
        new AlertDialog.Builder(this)
                .setTitle("刪除「" + phrase.text() + "」？")
                .setNegativeButton("取消", null)
                .setPositiveButton("刪除", (dialog, which) -> {
                    try {
                        userData.deletePhrase(phrase.id());
                        reload();
                    } catch (RuntimeException error) {
                        Toast.makeText(this, "無法刪除自訂詞", Toast.LENGTH_LONG).show();
                    }
                }).show();
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (resultCode != RESULT_OK || data == null || userData == null) return;
        Uri uri = data.getData();
        if (uri == null) return;
        try {
            if (requestCode == IMPORT_PHRASES) {
                try (InputStream input = getContentResolver().openInputStream(uri)) {
                    if (input == null) throw new IOException("無法讀取檔案");
                    ByteArrayOutputStream bytes = new ByteArrayOutputStream();
                    byte[] buffer = new byte[8192];
                    int count;
                    while ((count = input.read(buffer)) >= 0) bytes.write(buffer, 0, count);
                    SmartMandarinUserData.ImportResult result = userData.importPhrases(
                            new String(bytes.toByteArray(), StandardCharsets.UTF_8));
                    reload();
                    Toast.makeText(this, "已匯入 " + result.imported() + " 筆，略過 "
                            + result.skipped() + " 筆", Toast.LENGTH_LONG).show();
                }
            } else if (requestCode == EXPORT_PHRASES) {
                try (OutputStream output = getContentResolver().openOutputStream(uri, "wt")) {
                    if (output == null) throw new IOException("無法寫入檔案");
                    output.write(userData.exportPhrases().getBytes(StandardCharsets.UTF_8));
                    output.flush();
                    Toast.makeText(this, "自訂詞已匯出", Toast.LENGTH_SHORT).show();
                }
            }
        } catch (IOException | RuntimeException error) {
            Toast.makeText(this, "詞庫匯入／匯出失敗：" + error.getMessage(),
                    Toast.LENGTH_LONG).show();
        }
    }

    @Override
    protected void onDestroy() {
        if (userData != null) userData.close();
        super.onDestroy();
    }
}
