package tw.chichi77.keykey.android;

import static org.junit.Assert.*;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.WebView;
import android.widget.Button;
import android.widget.ListView;
import android.widget.TextView;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry;
import androidx.test.runner.lifecycle.Stage;
import org.junit.Test;
import org.junit.runner.RunWith;
import java.io.File;
import java.io.FileOutputStream;

@RunWith(AndroidJUnit4.class)
public final class AcknowledgementsInstrumentedTest {
    @Test public void unnumberedEntryOpensBundledNoticeAndReturns() throws Exception {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        var monitor = instrumentation.addMonitor(AcknowledgementsActivity.class.getName(), null, false);
        Activity main = null;
        Activity directory = null;
        Activity detail = null;
        try {
            main = instrumentation.startActivitySync(new Intent(context, MainActivity.class)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            Activity home = main;
            instrumentation.waitForIdleSync();
            saveScreenshot(context, "main-entry.png");
            instrumentation.runOnMainSync(() -> {
                Button entry = (Button) findText(home.findViewById(android.R.id.content), "授權與致謝");
                assertNotNull(entry);
                View settings = findText(home.findViewById(android.R.id.content), "3. 調整設定");
                assertNotNull(settings);
                assertTrue(entry.getTop() > settings.getTop());
                entry.performClick();
            });
            directory = instrumentation.waitForMonitorWithTimeout(monitor, 5000);
            assertNotNull(directory);
            Activity listPage = directory;
            ListView[] list = new ListView[1];
            long deadline = System.currentTimeMillis() + 5000;
            while (list[0] == null && System.currentTimeMillis() < deadline) {
                instrumentation.runOnMainSync(() -> list[0] = listPage.findViewById(android.R.id.content)
                        .findViewWithTag("acknowledgements.directory"));
                Thread.sleep(50);
            }
            assertNotNull(list[0]);
            saveScreenshot(context, "notice-directory.png");
            instrumentation.runOnMainSync(() -> {
                int position = -1;
                for (int i = 0; i < list[0].getAdapter().getCount(); i++) {
                    if ("Yahoo! KeyKey".equals(list[0].getAdapter().getItem(i))) position = i;
                }
                assertTrue(position >= 0);
                list[0].performItemClick(null, position, position);
            });
            Activity[] openedDetail = new Activity[1];
            deadline = System.currentTimeMillis() + 5000;
            while (openedDetail[0] == null && System.currentTimeMillis() < deadline) {
                instrumentation.runOnMainSync(() -> {
                    for (Activity candidate : ActivityLifecycleMonitorRegistry.getInstance()
                            .getActivitiesInStage(Stage.RESUMED)) {
                        if (candidate instanceof AcknowledgementsActivity && candidate != listPage) {
                            openedDetail[0] = candidate;
                        }
                    }
                });
                Thread.sleep(50);
            }
            detail = openedDetail[0];
            assertNotNull(detail);
            Activity documentPage = detail;
            WebView[] web = new WebView[1];
            deadline = System.currentTimeMillis() + 10000;
            while (web[0] == null && System.currentTimeMillis() < deadline) {
                instrumentation.runOnMainSync(() -> web[0] = documentPage.findViewById(android.R.id.content)
                        .findViewWithTag("acknowledgements.document.loaded"));
                Thread.sleep(50);
            }
            assertNotNull("Bundled notice must finish rendering", web[0]);
            instrumentation.runOnMainSync(() -> {
                assertFalse(web[0].getSettings().getJavaScriptEnabled());
                assertTrue(web[0].getSettings().getBlockNetworkLoads());
                assertFalse(web[0].getSettings().getAllowFileAccess());
            });
            java.util.concurrent.CountDownLatch rendered = new java.util.concurrent.CountDownLatch(1);
            instrumentation.runOnMainSync(() -> web[0].postVisualStateCallback(0,
                    new WebView.VisualStateCallback() {
                        @Override public void onComplete(long requestId) { rendered.countDown(); }
                    }));
            assertTrue("Notice must be ready to draw", rendered.await(5, java.util.concurrent.TimeUnit.SECONDS));
            instrumentation.getUiAutomation().waitForIdle(500, 5000);
            saveScreenshot(context, "yahoo-notice.png");
            java.util.concurrent.CountDownLatch searched = new java.util.concurrent.CountDownLatch(1);
            int[] matches = new int[1];
            instrumentation.runOnMainSync(() -> {
                web[0].setFindListener((active, count, done) -> {
                    if (done) { matches[0] = count; searched.countDown(); }
                });
                web[0].findAllAsync("Redistribution and use");
            });
            assertTrue("Reader search must complete", searched.await(5, java.util.concurrent.TimeUnit.SECONDS));
            assertTrue("Actual license terms must be rendered in the document", matches[0] > 0);
            instrumentation.runOnMainSync(web[0]::clearMatches);
            instrumentation.runOnMainSync(() -> ((Button) findText(
                    documentPage.findViewById(android.R.id.content), "返回")).performClick());
            instrumentation.waitForIdleSync();
            assertTrue(detail.isFinishing());
            instrumentation.runOnMainSync(() -> assertNotNull(listPage.findViewById(android.R.id.content)
                    .findViewWithTag("acknowledgements.directory")));
        } finally {
            for (Activity activity : new Activity[]{detail, directory, main}) {
                if (activity != null) instrumentation.runOnMainSync(activity::finish);
            }
            instrumentation.removeMonitor(monitor);
        }
    }

    @Test public void rustComponentRetainsAttributionAndFullTerms() throws Exception {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        Activity directory = instrumentation.startActivitySync(new Intent(context, AcknowledgementsActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        Activity detail = null;
        try {
            ListView[] list = new ListView[1];
            long deadline = System.currentTimeMillis() + 5000;
            while (list[0] == null && System.currentTimeMillis() < deadline) {
                instrumentation.runOnMainSync(() -> list[0] = directory.findViewById(android.R.id.content)
                        .findViewWithTag("acknowledgements.directory"));
                Thread.sleep(50);
            }
            assertNotNull(list[0]);
            instrumentation.runOnMainSync(() -> {
                int rust = -1;
                for (int i = 0; i < list[0].getAdapter().getCount(); i++) {
                    String name = list[0].getAdapter().getItem(i).toString();
                    assertFalse(name.contains("COPYRIGHT-library.html"));
                    assertFalse(name.contains("licenses/GPL"));
                    if (name.startsWith("Rust 標準函式庫 ")) rust = i;
                }
                assertTrue(rust >= 0);
                list[0].performItemClick(null, rust, rust);
            });
            Activity[] foreground = new Activity[1];
            deadline = System.currentTimeMillis() + 5000;
            while (foreground[0] == null && System.currentTimeMillis() < deadline) {
                instrumentation.runOnMainSync(() -> {
                    for (Activity activity : ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(Stage.RESUMED)) {
                        if (activity instanceof AcknowledgementsActivity && activity != directory) foreground[0] = activity;
                    }
                });
                Thread.sleep(50);
            }
            detail = foreground[0];
            assertNotNull(detail);
            Activity page = detail;
            WebView[] web = new WebView[1];
            deadline = System.currentTimeMillis() + 10000;
            while (web[0] == null && System.currentTimeMillis() < deadline) {
                instrumentation.runOnMainSync(() -> web[0] = page.findViewById(android.R.id.content)
                        .findViewWithTag("acknowledgements.document.loaded"));
                Thread.sleep(50);
            }
            assertNotNull(web[0]);
            java.util.concurrent.CountDownLatch searched = new java.util.concurrent.CountDownLatch(1);
            int[] matches = new int[1];
            instrumentation.runOnMainSync(() -> {
                web[0].setFindListener((active, count, done) -> {
                    if (done) { matches[0] = count; searched.countDown(); }
                });
                web[0].findAllAsync("The Crossbeam Project Developers");
            });
            assertTrue(searched.await(5, java.util.concurrent.TimeUnit.SECONDS));
            assertTrue("Rust attribution must be readable", matches[0] > 0);
            saveScreenshot(context, "rust-component.png");
            instrumentation.runOnMainSync(() -> ((Button) findText(page.findViewById(android.R.id.content), "返回")).performClick());
            instrumentation.waitForIdleSync();
            assertTrue(detail.isFinishing());
        } finally {
            if (detail != null) instrumentation.runOnMainSync(detail::finish);
            instrumentation.runOnMainSync(directory::finish);
        }
    }

    private static View findText(View root, String expected) {
        if (root instanceof TextView text && expected.contentEquals(text.getText())) return root;
        if (root instanceof ViewGroup group) {
            for (int i = 0; i < group.getChildCount(); i++) {
                View found = findText(group.getChildAt(i), expected);
                if (found != null) return found;
            }
        }
        return null;
    }

    private static void saveScreenshot(Context context, String name) throws Exception {
        var automation = InstrumentationRegistry.getInstrumentation().getUiAutomation();
        automation.waitForIdle(500, 5000);
        Bitmap screenshot = automation.takeScreenshot();
        assertNotNull(screenshot);
        try (FileOutputStream output = new FileOutputStream(new File(context.getExternalFilesDir(null), name))) {
            assertTrue(screenshot.compress(Bitmap.CompressFormat.PNG, 100, output));
        }
    }
}
