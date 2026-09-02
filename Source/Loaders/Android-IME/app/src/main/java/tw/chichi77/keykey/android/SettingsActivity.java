package tw.chichi77.keykey.android;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.ArrayAdapter;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.Toast;

import java.io.IOException;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

public final class SettingsActivity extends Activity implements SupporterBillingManager.Listener {
    private final ArrayList<CheckBox> collectionChecks = new ArrayList<>();
    private TextView collectionStatus;
    private TextView supporterPrice;
    private Button supporterButton;
    private SupporterBillingManager supporterBillingManager;
    private boolean updatingCollections;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        int horizontalPadding = dp(24);
        int verticalPadding = dp(24);
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(getColor(R.color.keykey_surface));
        UiInsets.applySystemPadding(scroll, horizontalPadding, verticalPadding,
                horizontalPadding, verticalPadding);

        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setGravity(Gravity.CENTER_HORIZONTAL);
        content.setBackgroundColor(getColor(R.color.keykey_surface));
        scroll.addView(content, new ScrollView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        TextView title = new TextView(this);
        title.setText(R.string.settings_title);
        title.setTextSize(28);
        title.setTextColor(getColor(R.color.keykey_blue_dark));
        title.setGravity(Gravity.CENTER);
        content.addView(title, matchWrap(dp(0), dp(32)));

        TextView label = new TextView(this);
        label.setText(R.string.haptic_feedback_title);
        label.setTextSize(18);
        label.setTextColor(Color.DKGRAY);
        content.addView(label, matchWrap(dp(0), dp(8)));

        TextView value = new TextView(this);
        value.setTextSize(16);
        value.setTextColor(getColor(R.color.keykey_blue_dark));
        value.setGravity(Gravity.CENTER);
        content.addView(value, matchWrap(dp(0), dp(12)));

        SeekBar duration = new SeekBar(this);
        duration.setMax(HapticSettings.MAX_LEVEL);
        duration.setProgress(HapticSettings.level(this));
        GradientDrawable tick = new GradientDrawable();
        tick.setShape(GradientDrawable.OVAL);
        tick.setColor(getColor(R.color.keykey_blue_dark));
        tick.setSize(dp(4), dp(4));
        duration.setTickMark(tick);
        content.addView(duration, matchWrap(dp(0), dp(4)));

        LinearLayout endpoints = new LinearLayout(this);
        endpoints.setOrientation(LinearLayout.HORIZONTAL);
        TextView zero = endpointLabel(R.string.haptic_off, Gravity.START);
        TextView maximum = endpointLabel(R.string.haptic_maximum, Gravity.END);
        endpoints.addView(zero, weightedWrap());
        endpoints.addView(maximum, weightedWrap());
        content.addView(endpoints, matchWrap(dp(0), dp(24)));

        TextView description = new TextView(this);
        description.setText(R.string.haptic_feedback_description);
        description.setTextSize(14);
        description.setTextColor(Color.GRAY);
        description.setLineSpacing(0, 1.2f);
        content.addView(description, matchWrap(dp(0), dp(16)));

        CheckBox keyPreview = new CheckBox(this);
        keyPreview.setText(R.string.key_preview_enabled);
        keyPreview.setTextSize(16);
        keyPreview.setTextColor(Color.DKGRAY);
        keyPreview.setMinHeight(dp(48));
        keyPreview.setChecked(KeyPreviewSettings.enabled(this));
        keyPreview.setOnCheckedChangeListener((button, checked) ->
                KeyPreviewSettings.setEnabled(SettingsActivity.this, checked));
        content.addView(keyPreview, matchWrap(dp(0), dp(8)));

        TextView keyPreviewDescription = new TextView(this);
        keyPreviewDescription.setText(R.string.key_preview_description);
        keyPreviewDescription.setTextSize(14);
        keyPreviewDescription.setTextColor(Color.GRAY);
        keyPreviewDescription.setLineSpacing(0, 1.2f);
        content.addView(keyPreviewDescription, matchWrap(dp(0), dp(16)));

        CheckBox floatingCandidates = new CheckBox(this);
        floatingCandidates.setText(R.string.floating_candidates_enabled);
        floatingCandidates.setTextSize(16);
        floatingCandidates.setTextColor(Color.DKGRAY);
        floatingCandidates.setMinHeight(dp(48));
        floatingCandidates.setChecked(CandidateWindowSettings.floatingEnabled(this));
        content.addView(floatingCandidates, matchWrap(dp(0), dp(8)));

        TextView floatingFailure = new TextView(this);
        floatingFailure.setTextSize(14);
        floatingFailure.setTextColor(getColor(R.color.keykey_blue_dark));
        floatingFailure.setLineSpacing(0, 1.2f);
        updateFloatingFailure(floatingFailure);
        content.addView(floatingFailure, matchWrap(dp(0), dp(8)));

        TextView floatingLayoutLabel = new TextView(this);
        floatingLayoutLabel.setText(R.string.floating_candidates_layout);
        floatingLayoutLabel.setTextSize(16);
        floatingLayoutLabel.setTextColor(Color.DKGRAY);
        content.addView(floatingLayoutLabel, matchWrap(dp(0), dp(4)));

        Spinner floatingLayout = new Spinner(this);
        ArrayAdapter<CharSequence> layoutAdapter = ArrayAdapter.createFromResource(this,
                R.array.floating_candidate_layouts,
                android.R.layout.simple_spinner_item);
        layoutAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        floatingLayout.setAdapter(layoutAdapter);
        floatingLayout.setSelection(CandidateWindowSettings.layout(this)
                == CandidateWindowSettings.Layout.HORIZONTAL ? 1 : 0);
        floatingLayout.setEnabled(floatingCandidates.isChecked());
        floatingLayoutLabel.setEnabled(floatingCandidates.isChecked());
        content.addView(floatingLayout, matchWrap(dp(0), dp(36)));

        floatingCandidates.setOnCheckedChangeListener((button, checked) -> {
            CandidateWindowSettings.setFloatingEnabled(SettingsActivity.this, checked);
            floatingLayout.setEnabled(checked);
            floatingLayoutLabel.setEnabled(checked);
            updateFloatingFailure(floatingFailure);
        });
        floatingLayout.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener() {
            @Override
            public void onItemSelected(android.widget.AdapterView<?> parent, android.view.View view,
                                       int position, long id) {
                CandidateWindowSettings.setLayout(SettingsActivity.this,
                        position == 1 ? CandidateWindowSettings.Layout.HORIZONTAL
                                : CandidateWindowSettings.Layout.VERTICAL);
            }

            @Override public void onNothingSelected(android.widget.AdapterView<?> parent) {}
        });

        TextView supporterTitle = new TextView(this);
        supporterTitle.setText(R.string.supporter_section_title);
        supporterTitle.setTextSize(20);
        supporterTitle.setTextColor(getColor(R.color.keykey_blue_dark));
        content.addView(supporterTitle, matchWrap(dp(0), dp(8)));

        TextView supporterDescription = new TextView(this);
        supporterDescription.setText(R.string.supporter_description);
        supporterDescription.setTextSize(14);
        supporterDescription.setTextColor(Color.GRAY);
        supporterDescription.setLineSpacing(0, 1.2f);
        content.addView(supporterDescription, matchWrap(dp(0), dp(8)));

        supporterPrice = new TextView(this);
        supporterPrice.setTextSize(16);
        supporterPrice.setTextColor(getColor(R.color.keykey_blue_dark));
        supporterPrice.setGravity(Gravity.CENTER);
        supporterPrice.setVisibility(View.GONE);
        content.addView(supporterPrice, matchWrap(dp(0), dp(8)));

        supporterButton = new Button(this);
        supporterButton.setAllCaps(false);
        supporterButton.setOnClickListener(view ->
                supporterBillingManager.launchPurchase(SettingsActivity.this));
        content.addView(supporterButton, matchWrap(dp(0), dp(36)));
        updateSupporterButton(false, SupporterState.isSupporter(this));

        TextView phraseTitle = new TextView(this);
        phraseTitle.setTextSize(20);
        phraseTitle.setTextColor(getColor(R.color.keykey_blue_dark));
        content.addView(phraseTitle, matchWrap(dp(0), dp(8)));

        TextView phraseDescription = new TextView(this);
        phraseDescription.setText(R.string.phrase_collections_description);
        phraseDescription.setTextSize(14);
        phraseDescription.setTextColor(Color.GRAY);
        phraseDescription.setLineSpacing(0, 1.2f);
        content.addView(phraseDescription, matchWrap(dp(0), dp(12)));

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        Button selectAll = actionButton(R.string.phrase_select_all);
        Button baseOnly = actionButton(R.string.phrase_base_only);
        Button selectNone = actionButton(R.string.phrase_select_none);
        actions.addView(selectAll, weightedWrap());
        actions.addView(baseOnly, weightedWrap());
        actions.addView(selectNone, weightedWrap());
        content.addView(actions, matchWrap(dp(0), dp(8)));

        collectionStatus = new TextView(this);
        collectionStatus.setTextSize(14);
        collectionStatus.setTextColor(getColor(R.color.keykey_blue_dark));
        collectionStatus.setGravity(Gravity.CENTER);
        content.addView(collectionStatus, matchWrap(dp(0), dp(8)));

        LinearLayout collectionList = new LinearLayout(this);
        collectionList.setOrientation(LinearLayout.VERTICAL);
        content.addView(collectionList, matchWrap(dp(0), dp(12)));
        loadPhraseCollections(phraseTitle, collectionList);

        selectAll.setOnClickListener(view -> setAllCollections(true));
        baseOnly.setOnClickListener(view -> setOnlyCollections(
                PhraseSettings.baseCollectionOnly()));
        selectNone.setOnClickListener(view -> setAllCollections(false));

        updateValue(value, duration.getProgress());
        duration.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                HapticSettings.setLevel(SettingsActivity.this, progress);
                updateValue(value, progress);
            }

            @Override public void onStartTrackingTouch(SeekBar seekBar) {}
            @Override public void onStopTrackingTouch(SeekBar seekBar) {}
        });

        setContentView(scroll);

        supporterBillingManager = new SupporterBillingManager(this, this);
        supporterBillingManager.start();
    }

    private void updateFloatingFailure(TextView view) {
        CandidateWindowSettings.Failure failure = CandidateWindowSettings.failure(this);
        if (failure == null) {
            view.setVisibility(View.GONE);
            return;
        }
        view.setText(failure == CandidateWindowSettings.Failure.TOKEN
                ? R.string.floating_candidates_failure_token
                : R.string.floating_candidates_failure_attach);
        view.setVisibility(View.VISIBLE);
    }

    @Override
    protected void onDestroy() {
        if (supporterBillingManager != null) supporterBillingManager.close();
        super.onDestroy();
    }

    @Override
    public void onStateChanged(boolean billingQueryComplete, boolean supporter,
                               String formattedPrice) {
        runOnUiThread(() -> {
            updateSupporterButton(billingQueryComplete, supporter);
            if (formattedPrice == null || formattedPrice.isEmpty()) {
                supporterPrice.setVisibility(View.GONE);
            } else {
                supporterPrice.setText(getString(R.string.supporter_price, formattedPrice));
                supporterPrice.setVisibility(View.VISIBLE);
            }
        });
    }

    @Override
    public void onPurchaseError() {
        runOnUiThread(() -> Toast.makeText(this, R.string.supporter_purchase_error,
                Toast.LENGTH_SHORT).show());
    }

    private void updateSupporterButton(boolean billingQueryComplete, boolean supporter) {
        if (!billingQueryComplete) {
            supporterButton.setText(R.string.supporter_checking);
            supporterButton.setEnabled(false);
        } else if (supporter) {
            supporterButton.setText(R.string.supporter_thank_you);
            supporterButton.setEnabled(false);
        } else {
            supporterButton.setText(R.string.supporter_button);
            supporterButton.setEnabled(true);
        }
    }

    private void loadPhraseCollections(TextView title, LinearLayout list) {
        List<AssociatedPhraseDictionary.CollectionInfo> collections;
        try {
            collections = AssociatedPhraseDictionary.availableCollections(getAssets());
        } catch (IOException error) {
            title.setText(R.string.phrase_collections_title_unavailable);
            collectionStatus.setText(R.string.phrase_collections_unavailable);
            return;
        }

        title.setText(getString(R.string.phrase_collections_title, collections.size()));
        Set<String> enabled = PhraseSettings.enabledCollections(this);
        updatingCollections = true;
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
                if (!updatingCollections) savePhraseSelections();
            });
            collectionChecks.add(check);
            list.addView(check, new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        }
        updatingCollections = false;
        updateCollectionStatus();
    }

    private void setAllCollections(boolean enabled) {
        updatingCollections = true;
        for (CheckBox check : collectionChecks) check.setChecked(enabled);
        updatingCollections = false;
        savePhraseSelections();
    }

    private void setOnlyCollections(Set<String> enabled) {
        updatingCollections = true;
        for (CheckBox check : collectionChecks) {
            check.setChecked(enabled.contains((String) check.getTag()));
        }
        updatingCollections = false;
        savePhraseSelections();
    }

    private void savePhraseSelections() {
        LinkedHashSet<String> enabled = new LinkedHashSet<>();
        for (CheckBox check : collectionChecks) {
            if (check.isChecked()) enabled.add((String) check.getTag());
        }
        PhraseSettings.setEnabledCollections(this, enabled);
        updateCollectionStatus();
    }

    private void updateCollectionStatus() {
        int enabled = 0;
        for (CheckBox check : collectionChecks) if (check.isChecked()) enabled++;
        collectionStatus.setText(getString(
                enabled == 0 ? R.string.phrase_status_none : R.string.phrase_status_count,
                enabled, collectionChecks.size()));
    }

    private Button actionButton(int text) {
        Button button = new Button(this);
        button.setText(text);
        button.setTextSize(13);
        button.setAllCaps(false);
        return button;
    }

    private void updateValue(TextView view, int level) {
        int durationMs = HapticSettings.durationMsForLevel(level);
        if (durationMs == 0) {
            view.setText(R.string.haptic_value_off);
        } else {
            String format = durationMs % 100 == 0 ? "%.1f" : "%.2f";
            view.setText(getString(R.string.haptic_value_seconds,
                    String.format(Locale.TAIWAN, format, durationMs / 1000f)));
        }
    }

    private TextView endpointLabel(int text, int gravity) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextSize(13);
        view.setTextColor(Color.GRAY);
        view.setGravity(gravity);
        return view;
    }

    private LinearLayout.LayoutParams matchWrap(int top, int bottom) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        params.setMargins(0, top, 0, bottom);
        return params;
    }

    private LinearLayout.LayoutParams weightedWrap() {
        LinearLayout.LayoutParams params =
                new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        params.setMargins(dp(2), 0, dp(2), 0);
        return params;
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
