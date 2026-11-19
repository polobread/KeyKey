package tw.chichi77.keykey.android;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

/** The shared settings navigation and user-data actions embedded in the app home. */
final class KeyboardSettingsSection {
    private KeyboardSettingsSection() {}
    static void addTo(Activity activity, LinearLayout page) {
        KeyboardSettingsProfile.migrate(activity);
        TextView title = new TextView(activity);
        title.setText(R.string.settings_title);
        title.setTextSize(28);
        page.addView(title, margins(activity, 0, 20));
        for (boolean virtual : new boolean[]{true, false}) {
            Button button = new Button(activity);
            button.setAllCaps(false);
            button.setText(virtual ? R.string.virtual_keyboard_settings : R.string.physical_keyboard_settings);
            button.setOnClickListener(view -> activity.startActivity(SettingsActivity.intent(activity, virtual)));
            page.addView(button, margins(activity, 0, 12));
        }
        TextView shared = new TextView(activity);
        shared.setText(R.string.keyboard_profiles_shared_data);
        page.addView(shared, margins(activity, 0, 16));
        Button phrases = new Button(activity);
        phrases.setAllCaps(false);
        phrases.setText("管理好打注音自訂詞");
        phrases.setOnClickListener(view -> activity.startActivity(new Intent(activity, UserPhrasesActivity.class)));
        page.addView(phrases, margins(activity, 0, 8));
        Button collections = new Button(activity);
        collections.setAllCaps(false);
        collections.setText(R.string.phrase_collections_title);
        collections.setOnClickListener(view -> activity.startActivity(new Intent(activity, PhraseCollectionsActivity.class)));
        page.addView(collections, margins(activity, 0, 8));
        Button reset = new Button(activity);
        reset.setAllCaps(false);
        reset.setText("重設好打注音學習紀錄");
        reset.setOnClickListener(view -> new AlertDialog.Builder(activity)
                .setTitle("重設好打注音學習紀錄？")
                .setMessage("這會清除已學習的選字和相鄰詞關係，自訂詞會保留。")
                .setNegativeButton("取消", null).setPositiveButton("重設", (dialog, which) -> {
                    CandidateGlyphSupport.shared().reset();
                    try (UserPhraseRepository data = UserPhraseRepository.open(activity)) {
                        data.resetSmartLearning();
                        Toast.makeText(activity, "好打注音學習紀錄已重設", Toast.LENGTH_SHORT).show();
                    } catch (RuntimeException error) {
                        Toast.makeText(activity, "無法重設學習紀錄：" + error.getMessage(), Toast.LENGTH_LONG).show();
                    }
                }).show());
        page.addView(reset, margins(activity, 0, 8));
    }
    private static LinearLayout.LayoutParams margins(Activity activity, int top, int bottom) {
        float density = activity.getResources().getDisplayMetrics().density;
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                android.view.ViewGroup.LayoutParams.MATCH_PARENT, android.view.ViewGroup.LayoutParams.WRAP_CONTENT);
        params.setMargins(0, Math.round(top * density), 0, Math.round(bottom * density));
        return params;
    }
}
