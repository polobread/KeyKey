package tw.chichi77.keykey.android;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.VibrationEffect;
import android.os.Vibrator;
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
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

public final class SettingsActivity extends Activity implements SupporterBillingManager.Listener {
    private final ArrayList<CheckBox> collectionChecks = new ArrayList<>();
    private TextView collectionStatus;
    private final Map<String, SettingsGroup> settingsGroups = new LinkedHashMap<>();
    private LinearLayout settingsContent;
    private LinearLayout supporterSection;
    private ScrollView settingsScroll;
    private TextView supporterTitle;
    private TextView supporterDescription;
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
        settingsScroll = scroll;
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(getColor(R.color.keykey_surface));
        UiInsets.applySystemPadding(scroll, horizontalPadding, verticalPadding,
                horizontalPadding, verticalPadding);

        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setGravity(Gravity.CENTER_HORIZONTAL);
        content.setBackgroundColor(getColor(R.color.keykey_surface));
        settingsContent = content;
        scroll.addView(content, new ScrollView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        TextView title = new TextView(this);
        title.setText(R.string.settings_title);
        title.setTextSize(28);
        title.setTextColor(getColor(R.color.keykey_blue_dark));
        title.setGravity(Gravity.CENTER);
        content.addView(title, matchWrap(dp(0), dp(32)));

        SettingsGroup compositionGroup = addSettingsGroup(content, savedInstanceState,
                "composition", R.string.settings_group_composition,
                R.string.settings_group_composition_summary, false);
        LinearLayout compositionContent = compositionGroup.body;
        updateCompositionSummary(compositionGroup.summary);
        TextView compositionModeLabel = new TextView(this);
        compositionModeLabel.setText(R.string.composition_mode_title);
        compositionModeLabel.setTextSize(18);
        compositionModeLabel.setTextColor(Color.DKGRAY);
        compositionContent.addView(compositionModeLabel, matchWrap(dp(0), dp(4)));

        Spinner compositionMode = new Spinner(this);
        compositionMode.setContentDescription(getString(R.string.composition_mode_title));
        ArrayAdapter<CharSequence> compositionAdapter = ArrayAdapter.createFromResource(this,
                R.array.composition_modes, android.R.layout.simple_spinner_item);
        compositionAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        compositionMode.setAdapter(compositionAdapter);
        compositionMode.setSelection(BopomofoCompositionModeSettings.mode(this)
                == BopomofoCompositionMode.SMART ? 0 : 1);
        compositionMode.setOnItemSelectedListener(
                new android.widget.AdapterView.OnItemSelectedListener() {
                    @Override
                    public void onItemSelected(android.widget.AdapterView<?> parent,
                                               android.view.View view, int position, long id) {
                        BopomofoCompositionModeSettings.setMode(SettingsActivity.this,
                                position == 0 ? BopomofoCompositionMode.SMART
                                        : BopomofoCompositionMode.TRADITIONAL);
                        updateCompositionSummary(compositionGroup.summary);
                    }

                    @Override public void onNothingSelected(
                            android.widget.AdapterView<?> parent) {}
                });
        compositionContent.addView(compositionMode, matchWrap(dp(0), dp(8)));

        TextView compositionModeDescription = new TextView(this);
        compositionModeDescription.setText(R.string.composition_mode_description);
        compositionModeDescription.setTextSize(14);
        compositionModeDescription.setTextColor(Color.GRAY);
        compositionModeDescription.setLineSpacing(0, 1.2f);
        compositionContent.addView(compositionModeDescription, matchWrap(dp(0), dp(24)));

        CheckBox bigramContext = new CheckBox(this);
        bigramContext.setText(R.string.smart_bigram_enabled);
        bigramContext.setTextSize(16);
        bigramContext.setTextColor(Color.DKGRAY);
        bigramContext.setMinHeight(dp(48));
        bigramContext.setChecked(BopomofoCompositionModeSettings.bigramEnabled(this));
        bigramContext.setOnCheckedChangeListener((button, checked) -> {
            BopomofoCompositionModeSettings.setBigramEnabled(SettingsActivity.this, checked);
            updateCompositionSummary(compositionGroup.summary);
        });
        compositionContent.addView(bigramContext, matchWrap(dp(0), dp(8)));
        TextView bigramDescription = new TextView(this);
        bigramDescription.setText(R.string.smart_bigram_description);
        bigramDescription.setTextSize(14);
        bigramDescription.setTextColor(Color.GRAY);
        bigramDescription.setLineSpacing(0, 1.2f);
        compositionContent.addView(bigramDescription, matchWrap(dp(0), dp(24)));

        TextView keyboardLayoutLabel = new TextView(this);
        keyboardLayoutLabel.setText(R.string.bopomofo_keyboard_layout);
        keyboardLayoutLabel.setTextSize(18);
        keyboardLayoutLabel.setTextColor(Color.DKGRAY);
        compositionContent.addView(keyboardLayoutLabel, matchWrap(dp(0), dp(4)));
        Spinner keyboardLayout = new Spinner(this);
        keyboardLayout.setContentDescription(getString(R.string.bopomofo_keyboard_layout));
        ArrayAdapter<CharSequence> keyboardLayoutAdapter = ArrayAdapter.createFromResource(this,
                R.array.bopomofo_keyboard_layouts, android.R.layout.simple_spinner_item);
        keyboardLayoutAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        keyboardLayout.setAdapter(keyboardLayoutAdapter);
        keyboardLayout.setSelection(BopomofoKeyboardLayoutSettings.layout(this)
                == BopomofoKeyboardLayout.HSU ? 1 : 0);
        keyboardLayout.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener() {
            @Override public void onItemSelected(android.widget.AdapterView<?> parent,
                    android.view.View view, int position, long id) {
                BopomofoKeyboardLayoutSettings.setLayout(SettingsActivity.this,
                        position == 1 ? BopomofoKeyboardLayout.HSU : BopomofoKeyboardLayout.STANDARD);
            }
            @Override public void onNothingSelected(android.widget.AdapterView<?> parent) {}
        });
        compositionContent.addView(keyboardLayout, matchWrap(dp(0), dp(8)));
        TextView keyboardLayoutDescription = new TextView(this);
        keyboardLayoutDescription.setText(R.string.bopomofo_keyboard_layout_description);
        keyboardLayoutDescription.setTextSize(14);
        compositionContent.addView(keyboardLayoutDescription, matchWrap(dp(0), dp(24)));

        Button userPhrases = new Button(this);
        userPhrases.setText("管理好打注音自訂詞");
        userPhrases.setContentDescription("管理好打注音自訂詞");
        userPhrases.setOnClickListener(view ->
                startActivity(new Intent(this, UserPhrasesActivity.class)));
        compositionContent.addView(userPhrases, matchWrap(dp(0), dp(8)));

        Button resetLearning = new Button(this);
        resetLearning.setText("重設好打注音學習紀錄");
        resetLearning.setOnClickListener(view -> new AlertDialog.Builder(this)
                .setTitle("重設學習紀錄？")
                .setMessage("這會清除已學習的選字和相鄰詞關係，自訂詞會保留。")
                .setNegativeButton("取消", null)
                .setPositiveButton("重設", (dialog, which) -> {
                    try (SmartMandarinUserData data = SmartMandarinUserData.open(this)) {
                        data.resetLearning();
                        Toast.makeText(this, "學習紀錄已重設", Toast.LENGTH_SHORT).show();
                    } catch (RuntimeException error) {
                        Toast.makeText(this, "無法重設學習紀錄", Toast.LENGTH_LONG).show();
                    }
                }).show());
        compositionContent.addView(resetLearning, matchWrap(dp(0), dp(24)));

        LinearLayout appearanceContent = addSettingsGroup(content, savedInstanceState,
                "appearance", R.string.settings_group_appearance,
                R.string.settings_group_appearance_summary, false).body;
        TextView label = new TextView(this);
        label.setText(R.string.haptic_feedback_title);
        label.setTextSize(18);
        label.setTextColor(Color.DKGRAY);
        appearanceContent.addView(label, matchWrap(dp(0), dp(8)));

        TextView value = new TextView(this);
        value.setTextSize(16);
        value.setTextColor(getColor(R.color.keykey_blue_dark));
        value.setGravity(Gravity.CENTER);
        appearanceContent.addView(value, matchWrap(dp(0), dp(12)));

        SeekBar duration = new SeekBar(this);
        duration.setMax(HapticSettings.maxSelectionIndex());
        duration.setProgress(HapticSettings.selectionForDurationMs(
                HapticSettings.durationMs(this)));
        appearanceContent.addView(duration, matchWrap(dp(0), dp(4)));

        LinearLayout endpoints = new LinearLayout(this);
        endpoints.setOrientation(LinearLayout.HORIZONTAL);
        TextView zero = endpointLabel(R.string.haptic_off, Gravity.START);
        TextView maximum = endpointLabel(R.string.haptic_maximum, Gravity.END);
        endpoints.addView(zero, weightedWrap());
        endpoints.addView(maximum, weightedWrap());
        appearanceContent.addView(endpoints, matchWrap(dp(0), dp(24)));

        TextView description = new TextView(this);
        description.setText(R.string.haptic_feedback_description);
        description.setTextSize(14);
        description.setTextColor(Color.GRAY);
        description.setLineSpacing(0, 1.2f);
        appearanceContent.addView(description, matchWrap(dp(0), dp(16)));

        CheckBox keyPreview = new CheckBox(this);
        keyPreview.setText(R.string.key_preview_enabled);
        keyPreview.setTextSize(16);
        keyPreview.setTextColor(Color.DKGRAY);
        keyPreview.setMinHeight(dp(48));
        keyPreview.setChecked(KeyPreviewSettings.enabled(this));
        keyPreview.setOnCheckedChangeListener((button, checked) ->
                KeyPreviewSettings.setEnabled(SettingsActivity.this, checked));
        appearanceContent.addView(keyPreview, matchWrap(dp(0), dp(8)));

        TextView keyPreviewDescription = new TextView(this);
        keyPreviewDescription.setText(R.string.key_preview_description);
        keyPreviewDescription.setTextSize(14);
        keyPreviewDescription.setTextColor(Color.GRAY);
        keyPreviewDescription.setLineSpacing(0, 1.2f);
        appearanceContent.addView(keyPreviewDescription, matchWrap(dp(0), dp(16)));

        TextView candidateColorLabel = new TextView(this);
        candidateColorLabel.setText(R.string.candidate_color_title);
        candidateColorLabel.setTextSize(16);
        candidateColorLabel.setTextColor(Color.DKGRAY);
        appearanceContent.addView(candidateColorLabel, matchWrap(dp(0), dp(4)));

        Spinner candidateColor = new Spinner(this);
        ArrayAdapter<CharSequence> colorAdapter = ArrayAdapter.createFromResource(this,
                R.array.candidate_highlight_colors,
                android.R.layout.simple_spinner_item);
        colorAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        candidateColor.setAdapter(colorAdapter);
        candidateColor.setSelection(CandidateColorSettings.selectionIndex(
                CandidateColorSettings.color(this)));
        candidateColor.setOnItemSelectedListener(
                new android.widget.AdapterView.OnItemSelectedListener() {
                    @Override
                    public void onItemSelected(android.widget.AdapterView<?> parent,
                                               android.view.View view, int position, long id) {
                        CandidateColorSettings.setColor(SettingsActivity.this,
                                CandidateColorSettings.colorAtSelectionIndex(position));
                    }

                    @Override public void onNothingSelected(
                            android.widget.AdapterView<?> parent) {}
                });
        appearanceContent.addView(candidateColor, matchWrap(dp(0), dp(20)));

        TextView keyboardSizeTitle = new TextView(this);
        keyboardSizeTitle.setText(R.string.keyboard_size_title);
        keyboardSizeTitle.setTextSize(18);
        keyboardSizeTitle.setTextColor(Color.DKGRAY);
        appearanceContent.addView(keyboardSizeTitle, matchWrap(dp(0), dp(8)));

        TextView keyboardSizeDescription = new TextView(this);
        keyboardSizeDescription.setText(R.string.keyboard_size_description);
        keyboardSizeDescription.setTextSize(14);
        keyboardSizeDescription.setTextColor(Color.GRAY);
        keyboardSizeDescription.setLineSpacing(0, 1.2f);
        appearanceContent.addView(keyboardSizeDescription, matchWrap(dp(0), dp(12)));

        addKeyboardSizeControl(appearanceContent, R.string.keyboard_size_portrait,
                KeyboardSizeSettings.portraitPercent(this), true);
        addKeyboardSizeControl(appearanceContent, R.string.keyboard_size_landscape,
                KeyboardSizeSettings.landscapePercent(this), false);

        LinearLayout hardwareContent = addSettingsGroup(content, savedInstanceState,
                "hardware", R.string.settings_group_hardware,
                R.string.settings_group_hardware_summary, false).body;
        CheckBox floatingCandidates = new CheckBox(this);
        floatingCandidates.setText(R.string.floating_candidates_enabled);
        floatingCandidates.setTextSize(16);
        floatingCandidates.setTextColor(Color.DKGRAY);
        floatingCandidates.setMinHeight(dp(48));
        floatingCandidates.setChecked(CandidateWindowSettings.floatingEnabled(this));
        hardwareContent.addView(floatingCandidates, matchWrap(dp(0), dp(8)));

        TextView floatingFailure = new TextView(this);
        floatingFailure.setTextSize(14);
        floatingFailure.setTextColor(getColor(R.color.keykey_blue_dark));
        floatingFailure.setLineSpacing(0, 1.2f);
        updateFloatingFailure(floatingFailure);
        hardwareContent.addView(floatingFailure, matchWrap(dp(0), dp(8)));

        TextView floatingLayoutLabel = new TextView(this);
        floatingLayoutLabel.setText(R.string.floating_candidates_layout);
        floatingLayoutLabel.setTextSize(16);
        floatingLayoutLabel.setTextColor(Color.DKGRAY);
        hardwareContent.addView(floatingLayoutLabel, matchWrap(dp(0), dp(4)));

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
        hardwareContent.addView(floatingLayout, matchWrap(dp(0), dp(36)));

        CheckBox hardwareNumberRow = new CheckBox(this);
        hardwareNumberRow.setText(R.string.hardware_number_row_enabled);
        hardwareNumberRow.setTextSize(16);
        hardwareNumberRow.setTextColor(Color.DKGRAY);
        hardwareNumberRow.setMinHeight(dp(48));
        hardwareNumberRow.setChecked(CandidateWindowSettings.numberRowEnabled(this));
        hardwareNumberRow.setEnabled(!floatingCandidates.isChecked());
        hardwareContent.addView(hardwareNumberRow, matchWrap(dp(0), dp(8)));
        hardwareNumberRow.setOnCheckedChangeListener((button, checked) ->
                CandidateWindowSettings.setNumberRowEnabled(SettingsActivity.this, checked));

        floatingCandidates.setOnCheckedChangeListener((button, checked) -> {
            CandidateWindowSettings.setFloatingEnabled(SettingsActivity.this, checked);
            floatingLayout.setEnabled(checked);
            floatingLayoutLabel.setEnabled(checked);
            hardwareNumberRow.setEnabled(!checked);
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

        supporterSection = new LinearLayout(this);
        supporterSection.setOrientation(LinearLayout.VERTICAL);
        supporterSection.setPadding(dp(16), dp(16), dp(16), dp(8));
        supporterSection.setBackground(sectionBackground());
        content.addView(supporterSection, matchWrap(dp(0), dp(16)));
        supporterTitle = new TextView(this);
        supporterTitle.setText(R.string.supporter_section_title);
        supporterTitle.setTextSize(20);
        supporterTitle.setTextColor(getColor(R.color.keykey_blue_dark));
        supporterSection.addView(supporterTitle, matchWrap(dp(0), dp(8)));

        supporterDescription = new TextView(this);
        supporterDescription.setText(R.string.supporter_description);
        supporterDescription.setTextSize(14);
        supporterDescription.setTextColor(Color.GRAY);
        supporterDescription.setLineSpacing(0, 1.2f);
        supporterSection.addView(supporterDescription, matchWrap(dp(0), dp(8)));

        supporterPrice = new TextView(this);
        supporterPrice.setTextSize(16);
        supporterPrice.setTextColor(getColor(R.color.keykey_blue_dark));
        supporterPrice.setGravity(Gravity.CENTER);
        supporterPrice.setVisibility(View.GONE);
        supporterSection.addView(supporterPrice, matchWrap(dp(0), dp(8)));

        supporterButton = new Button(this);
        supporterButton.setAllCaps(false);
        supporterButton.setOnClickListener(view ->
                supporterBillingManager.launchPurchase(SettingsActivity.this));
        supporterSection.addView(supporterButton, matchWrap(dp(0), dp(36)));
        updateSupporterDisplay(false, SupporterState.isSupporter(this), null);

        SettingsGroup phraseGroup = addSettingsGroup(content, savedInstanceState,
                "phrases", R.string.settings_group_phrases,
                R.string.settings_group_phrases_summary, false);
        LinearLayout phraseContent = phraseGroup.body;
        collectionStatus = phraseGroup.summary;

        TextView phraseDescription = new TextView(this);
        phraseDescription.setText(R.string.phrase_collections_description);
        phraseDescription.setTextSize(14);
        phraseDescription.setTextColor(Color.GRAY);
        phraseDescription.setLineSpacing(0, 1.2f);
        phraseContent.addView(phraseDescription, matchWrap(dp(0), dp(12)));

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        Button selectAll = actionButton(R.string.phrase_select_all);
        Button baseOnly = actionButton(R.string.phrase_base_only);
        Button selectNone = actionButton(R.string.phrase_select_none);
        actions.addView(selectAll, weightedWrap());
        actions.addView(baseOnly, weightedWrap());
        actions.addView(selectNone, weightedWrap());
        phraseContent.addView(actions, matchWrap(dp(0), dp(8)));

        LinearLayout collectionList = new LinearLayout(this);
        collectionList.setOrientation(LinearLayout.VERTICAL);
        phraseContent.addView(collectionList, matchWrap(dp(0), dp(12)));
        loadPhraseCollections(collectionList);

        selectAll.setOnClickListener(view -> setAllCollections(true));
        baseOnly.setOnClickListener(view -> setOnlyCollections(
                PhraseSettings.baseCollectionOnly()));
        selectNone.setOnClickListener(view -> setAllCollections(false));

        updateHapticValue(value, HapticSettings.durationMsForSelection(duration.getProgress()));
        duration.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                int durationMs = HapticSettings.durationMsForSelection(progress);
                HapticSettings.setDurationMs(SettingsActivity.this, durationMs);
                updateHapticValue(value, durationMs);
            }

            @Override public void onStartTrackingTouch(SeekBar seekBar) {}
            @Override public void onStopTrackingTouch(SeekBar seekBar) {
                int durationMs = HapticSettings.durationMsForSelection(seekBar.getProgress());
                Vibrator vibrator = getSystemService(Vibrator.class);
                if (durationMs > 0 && vibrator != null && vibrator.hasVibrator()) {
                    vibrator.vibrate(VibrationEffect.createOneShot(
                            durationMs, VibrationEffect.DEFAULT_AMPLITUDE));
                }
            }
        });

        placeSupporterSection(SupporterState.isSupporter(this));
        setContentView(scroll);
        if (savedInstanceState != null) {
            int scrollY = savedInstanceState.getInt("settings_scroll_y", 0);
            scroll.post(() -> scroll.scrollTo(0, scrollY));
        }

        supporterBillingManager = new SupporterBillingManager(this, this);
        supporterBillingManager.start();
    }

    @Override
    protected void onSaveInstanceState(Bundle state) {
        super.onSaveInstanceState(state);
        for (Map.Entry<String, SettingsGroup> entry : settingsGroups.entrySet()) {
            state.putBoolean("settings_group_" + entry.getKey(),
                    entry.getValue().body.getVisibility() == View.VISIBLE);
        }
        state.putInt("settings_scroll_y", settingsScroll.getScrollY());
    }

    private static final class SettingsGroup {
        final LinearLayout body;
        final TextView summary;

        SettingsGroup(LinearLayout body, TextView summary) {
            this.body = body;
            this.summary = summary;
        }
    }

    private SettingsGroup addSettingsGroup(LinearLayout root, Bundle savedState,
            String key, int titleRes, int summaryRes, boolean defaultExpanded) {
        LinearLayout section = new LinearLayout(this);
        section.setOrientation(LinearLayout.VERTICAL);
        section.setBackground(sectionBackground());
        root.addView(section, matchWrap(dp(0), dp(16)));

        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.VERTICAL);
        header.setPadding(dp(16), dp(12), dp(16), dp(12));
        header.setMinimumHeight(dp(56));
        header.setFocusable(true);
        header.setClickable(true);
        section.addView(header, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        TextView heading = new TextView(this);
        heading.setTextSize(20);
        heading.setTextColor(getColor(R.color.keykey_blue_dark));
        header.addView(heading);

        TextView summary = new TextView(this);
        summary.setText(summaryRes);
        summary.setTextSize(14);
        summary.setTextColor(Color.DKGRAY);
        summary.setPadding(0, dp(4), 0, 0);
        header.addView(summary);

        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(dp(16), 0, dp(16), dp(8));
        section.addView(body, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        boolean expanded = savedState == null ? defaultExpanded
                : savedState.getBoolean("settings_group_" + key, defaultExpanded);
        setGroupExpanded(header, heading, body, titleRes, expanded);
        header.setOnClickListener(view -> setGroupExpanded(header, heading, body, titleRes,
                body.getVisibility() != View.VISIBLE));
        SettingsGroup group = new SettingsGroup(body, summary);
        settingsGroups.put(key, group);
        return group;
    }

    private void setGroupExpanded(LinearLayout header, TextView heading, LinearLayout body,
            int titleRes, boolean expanded) {
        body.setVisibility(expanded ? View.VISIBLE : View.GONE);
        heading.setText((expanded ? "▾  " : "▸  ") + getString(titleRes));
        header.setContentDescription(getString(
                expanded ? R.string.settings_group_collapse : R.string.settings_group_expand,
                getString(titleRes)));
    }

    private GradientDrawable sectionBackground() {
        GradientDrawable background = new GradientDrawable();
        background.setColor(Color.WHITE);
        background.setCornerRadius(dp(12));
        background.setStroke(dp(1), Color.rgb(218, 226, 238));
        return background;
    }

    private void placeSupporterSection(boolean supporter) {
        if (settingsContent == null || supporterSection == null) return;
        int position = supporter ? settingsContent.getChildCount() - 1 : 1;
        if (settingsContent.indexOfChild(supporterSection) == position) return;
        settingsContent.removeView(supporterSection);
        settingsContent.addView(supporterSection,
                supporter ? settingsContent.getChildCount() : 1);
    }

    private void updateCompositionSummary(TextView view) {
        String mode = getResources().getStringArray(R.array.composition_modes)[
                BopomofoCompositionModeSettings.mode(this) == BopomofoCompositionMode.SMART
                        ? 0 : 1];
        view.setText(getString(R.string.settings_group_composition_summary, mode,
                getString(BopomofoCompositionModeSettings.bigramEnabled(this)
                        ? R.string.settings_value_on : R.string.settings_value_off)));
    }

    private void updateFloatingFailure(TextView view) {
        CandidateWindowSettings.Failure failure = CandidateWindowSettings.failure(this);
        if (failure == null) {
            view.setVisibility(View.GONE);
            return;
        }
        view.setText(switch (failure) {
            case TOKEN -> R.string.floating_candidates_failure_token;
            case ATTACH -> R.string.floating_candidates_failure_attach;
            case CURSOR_ANCHOR -> R.string.floating_candidates_failure_cursor_anchor;
        });
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
            updateSupporterDisplay(billingQueryComplete, supporter, formattedPrice);
        });
    }

    @Override
    public void onPurchaseError() {
        runOnUiThread(() -> Toast.makeText(this, R.string.supporter_purchase_error,
                Toast.LENGTH_SHORT).show());
    }

    private void updateSupporterDisplay(boolean billingQueryComplete, boolean supporter,
            String formattedPrice) {
        placeSupporterSection(supporter);
        supporterTitle.setText(supporter ? R.string.supporter_thank_you
                : R.string.supporter_section_title);
        supporterDescription.setText(supporter ? R.string.supporter_supported_description
                : R.string.supporter_description);
        if (supporter || formattedPrice == null || formattedPrice.isEmpty()) {
            supporterPrice.setVisibility(View.GONE);
        } else {
            supporterPrice.setText(getString(R.string.supporter_price, formattedPrice));
            supporterPrice.setVisibility(View.VISIBLE);
        }
        if (supporter) {
            supporterButton.setText(R.string.supporter_thank_you);
            supporterButton.setEnabled(false);
        } else if (!billingQueryComplete) {
            supporterButton.setText(R.string.supporter_checking);
            supporterButton.setEnabled(false);
        } else {
            supporterButton.setText(R.string.supporter_button);
            supporterButton.setEnabled(true);
        }
    }

    private void loadPhraseCollections(LinearLayout list) {
        List<AssociatedPhraseDictionary.CollectionInfo> collections;
        try {
            collections = AssociatedPhraseDictionary.availableCollections(getAssets());
        } catch (IOException error) {
            collectionStatus.setText(R.string.phrase_collections_unavailable);
            return;
        }

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

    private void addKeyboardSizeControl(LinearLayout content, int labelResource,
                                        int currentPercent, boolean portrait) {
        TextView label = new TextView(this);
        label.setText(labelResource);
        label.setTextSize(16);
        label.setTextColor(Color.DKGRAY);
        content.addView(label, matchWrap(dp(0), dp(4)));

        TextView value = new TextView(this);
        value.setTextSize(16);
        value.setTextColor(getColor(R.color.keykey_blue_dark));
        value.setGravity(Gravity.CENTER);
        updateKeyboardSizeValue(value, currentPercent);
        content.addView(value, matchWrap(dp(0), dp(4)));

        SeekBar size = new SeekBar(this);
        size.setMax(KeyboardSizeSettings.maxSelectionIndex());
        size.setProgress(KeyboardSizeSettings.selectionForPercent(currentPercent));
        content.addView(size, matchWrap(dp(0), dp(2)));

        LinearLayout endpoints = new LinearLayout(this);
        endpoints.setOrientation(LinearLayout.HORIZONTAL);
        TextView minimum = endpointLabel(R.string.keyboard_size_minimum, Gravity.START);
        TextView maximum = endpointLabel(R.string.keyboard_size_maximum, Gravity.END);
        endpoints.addView(minimum, weightedWrap());
        endpoints.addView(maximum, weightedWrap());
        content.addView(endpoints, matchWrap(dp(0), dp(12)));

        size.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                int percent = KeyboardSizeSettings.percentForSelection(progress);
                if (portrait) {
                    KeyboardSizeSettings.setPortraitPercent(SettingsActivity.this, percent);
                } else {
                    KeyboardSizeSettings.setLandscapePercent(SettingsActivity.this, percent);
                }
                updateKeyboardSizeValue(value, percent);
            }

            @Override public void onStartTrackingTouch(SeekBar seekBar) {}
            @Override public void onStopTrackingTouch(SeekBar seekBar) {}
        });
    }

    private void updateKeyboardSizeValue(TextView view, int percent) {
        view.setText(getString(R.string.keyboard_size_value, percent));
    }

    private void updateHapticValue(TextView view, int durationMs) {
        if (durationMs == 0) {
            view.setText(R.string.haptic_value_off);
        } else {
            view.setText(getString(R.string.haptic_value_seconds,
                    String.format(Locale.TAIWAN, "%.3f", durationMs / 1000f), durationMs));
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
