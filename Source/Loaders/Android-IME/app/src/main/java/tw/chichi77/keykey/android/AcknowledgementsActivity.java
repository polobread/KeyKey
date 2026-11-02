package tw.chichi77.keykey.android;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.view.Gravity;
import android.view.ViewGroup;
import android.webkit.WebResourceRequest;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.TextView;

import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.List;

/** Offline access to the complete notices already distributed in the APK. */
public final class AcknowledgementsActivity extends Activity {
    private static final String DOCUMENT = "document";
    private LinearLayout content;
    private TextView title;
    private TextView status;
    private WebView documentView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setBackgroundColor(getColor(R.color.keykey_surface));
        int padding = dp(16);
        UiInsets.applySystemPadding(content, padding, padding, padding, padding);

        Button back = new Button(this);
        back.setText(R.string.acknowledgements_back);
        back.setAllCaps(false);
        back.setOnClickListener(view -> finish());
        content.addView(back, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        title = new TextView(this);
        title.setText(R.string.acknowledgements_title);
        title.setTextSize(23);
        title.setTextColor(getColor(R.color.keykey_blue_dark));
        title.setGravity(Gravity.CENTER);
        content.addView(title, matchWrap());
        status = new TextView(this);
        status.setText(R.string.acknowledgements_loading);
        status.setTextSize(16);
        status.setPadding(0, dp(12), 0, dp(12));
        content.addView(status, matchWrap());
        setContentView(content);

        new Thread(() -> {
            try (InputStreamReader reader = new InputStreamReader(
                    getAssets().open(LicenseNotices.ASSET), StandardCharsets.UTF_8)) {
                StringBuilder text = new StringBuilder();
                char[] buffer = new char[8192];
                int count;
                while ((count = reader.read(buffer)) != -1) text.append(buffer, 0, count);
                List<LicenseNotices.Document> documents = LicenseNotices.parse(text.toString());
                runOnUiThread(() -> {
                    if (!isFinishing() && !isDestroyed()) show(documents);
                });
            } catch (IOException error) {
                runOnUiThread(() -> {
                    if (!isFinishing() && !isDestroyed()) status.setText(R.string.acknowledgements_error);
                });
            }
        }, "keykey-notices").start();
    }

    private void show(List<LicenseNotices.Document> documents) {
        int selected = getIntent().getIntExtra(DOCUMENT, -1);
        if (selected >= 0) {
            if (selected >= documents.size()) {
                status.setText(R.string.acknowledgements_error);
                return;
            }
            LicenseNotices.Document document = documents.get(selected);
            title.setText(document.title());
            content.removeView(status);
            documentView = new WebView(this);
            documentView.setTag("acknowledgements.document");
            documentView.getSettings().setJavaScriptEnabled(false);
            documentView.getSettings().setAllowFileAccess(false);
            documentView.getSettings().setAllowContentAccess(false);
            documentView.getSettings().setBlockNetworkLoads(true);
            documentView.getSettings().setDefaultTextEncodingName("UTF-8");
            documentView.setWebViewClient(new WebViewClient() {
                @Override
                public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                    // Notices are self-contained; no external page is loaded.
                    return true;
                }
                @Override
                public void onPageFinished(WebView view, String url) {
                    view.setTag("acknowledgements.document.loaded");
                }
            });
            content.addView(documentView, new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
            String style = "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
                    + "<style>body{margin:12px;font:16px sans-serif;overflow-wrap:anywhere}"
                    + "pre{white-space:pre-wrap;font:14px monospace}summary{padding:8px}</style>";
            String html = "<!doctype html><html><head>" + style + "</head><body><pre>"
                        + escape(document.source()) + "\n\n" + escape(document.text()) + "</pre></body></html>";
            documentView.loadDataWithBaseURL(null, html, "text/html", "UTF-8", null);
            return;
        }
        status.setText(R.string.acknowledgements_description);
        ListView directory = new ListView(this);
        directory.setTag("acknowledgements.directory");
        java.util.ArrayList<String> names = new java.util.ArrayList<>();
        for (LicenseNotices.Document document : documents) names.add(document.title());
        directory.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_list_item_1, names));
        directory.setOnItemClickListener((parent, view, position, id) -> startActivity(
                new Intent(this, AcknowledgementsActivity.class).putExtra(DOCUMENT, position)));
        content.addView(directory, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
    }

    private static String escape(String value) {
        return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
    }

    @Override
    protected void onDestroy() {
        if (documentView != null) {
            content.removeView(documentView);
            documentView.destroy();
        }
        super.onDestroy();
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
