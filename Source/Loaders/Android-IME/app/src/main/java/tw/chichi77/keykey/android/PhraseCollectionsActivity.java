package tw.chichi77.keykey.android;

import android.app.Activity;
import android.graphics.Color;
import android.os.Build;
import android.os.Bundle;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.IOException;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.function.Predicate;

public final class PhraseCollectionsActivity extends Activity {
    private final List<CheckBox> collectionChecks = new ArrayList<>();
    private ScrollView scroll;
    private TextView status;
    private boolean updatingCollections;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setTitle(R.string.phrase_collections_title);

        int padding = dp(24);
        scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(getColor(R.color.keykey_surface));
        UiInsets.applySystemPadding(scroll, padding, padding, padding, padding);

        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(content);
        setContentView(scroll);

        TextView title = new TextView(this);
        title.setText(R.string.phrase_collections_title);
        title.setTextSize(28);
        title.setTextColor(getColor(R.color.keykey_blue_dark));
        title.setGravity(Gravity.CENTER);
        if (Build.VERSION.SDK_INT >= 28) title.setAccessibilityHeading(true);
        content.addView(title, matchWrap(dp(12)));

        TextView description = new TextView(this);
        description.setText(R.string.phrase_collections_description);
        description.setTextSize(14);
        description.setTextColor(Color.DKGRAY);
        description.setLineSpacing(0, 1.2f);
        content.addView(description, matchWrap(dp(12)));

        status = new TextView(this);
        status.setTextSize(14);
        status.setTextColor(getColor(R.color.keykey_blue_dark));
        status.setAccessibilityLiveRegion(TextView.ACCESSIBILITY_LIVE_REGION_POLITE);
        content.addView(status, matchWrap(dp(8)));

        List<AssociatedPhraseDictionary.CollectionInfo> collections;
        try {
            collections = AssociatedPhraseDictionary.availableCollections(getAssets());
        } catch (IOException error) {
            status.setText(R.string.phrase_collections_unavailable);
            return;
        }

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        addAction(actions, R.string.phrase_select_all, source -> true);
        addAction(actions, R.string.phrase_base_only, PhraseSettings.baseCollectionOnly()::contains);
        addAction(actions, R.string.phrase_select_none, source -> false);
        content.addView(actions, matchWrap(dp(8)));

        var enabled = PhraseSettings.enabledCollections(this);
        for (AssociatedPhraseDictionary.CollectionInfo collection : collections) {
            CheckBox check = new CheckBox(this);
            check.setText(getString(R.string.phrase_collection_item,
                    collection.displayName(), collection.source()));
            check.setTextSize(16);
            check.setTextColor(Color.DKGRAY);
            check.setMinHeight(dp(48));
            check.setTag(collection.source());
            check.setChecked(enabled.contains(collection.source()));
            check.setOnCheckedChangeListener((button, checked) -> {
                if (!updatingCollections) saveSelections();
            });
            collectionChecks.add(check);
            content.addView(check, matchWrap(0));
        }
        updateStatus();
        if (savedInstanceState != null) {
            scroll.post(() -> scroll.scrollTo(0, savedInstanceState.getInt("scroll_y")));
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle state) {
        super.onSaveInstanceState(state);
        state.putInt("scroll_y", scroll.getScrollY());
    }

    private void addAction(LinearLayout actions, int label, Predicate<String> selected) {
        Button button = new Button(this);
        button.setText(label);
        button.setTextSize(13);
        button.setAllCaps(false);
        button.setOnClickListener(view -> {
            updatingCollections = true;
            for (CheckBox check : collectionChecks) {
                check.setChecked(selected.test((String) check.getTag()));
            }
            updatingCollections = false;
            saveSelections();
        });
        actions.addView(button, new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
    }

    private void saveSelections() {
        var enabled = new LinkedHashSet<String>();
        for (CheckBox check : collectionChecks) {
            if (check.isChecked()) enabled.add((String) check.getTag());
        }
        PhraseSettings.setEnabledCollections(this, enabled);
        updateStatus();
    }

    private void updateStatus() {
        int enabled = 0;
        for (CheckBox check : collectionChecks) if (check.isChecked()) enabled++;
        status.setText(getString(enabled == 0 ? R.string.phrase_status_none : R.string.phrase_status_count,
                enabled, collectionChecks.size()));
    }

    private LinearLayout.LayoutParams matchWrap(int bottomMargin) {
        var params = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        params.bottomMargin = bottomMargin;
        return params;
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
