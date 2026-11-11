package tw.chichi77.keykey.android;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.ImageButton;
import android.widget.ArrayAdapter;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.Toast;

import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;

public final class SettingsActivity extends Activity implements SupporterBillingManager.Listener {
    private final Map<String, LinearLayout> settingsGroups = new LinkedHashMap<>();
    private LinearLayout settingsContent;
    private LinearLayout supporterSection;
    private ScrollView settingsScroll;
    private TextView supporterTitle;
    private TextView supporterDescription;
    private TextView supporterPrice;
    private Button supporterButton;
    private SupporterBillingManager supporterBillingManager;
    private CheckBox touchBottomSpace;

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

        LinearLayout methodContent = new LinearLayout(this);
        methodContent.setOrientation(LinearLayout.VERTICAL);
        methodContent.setPadding(dp(16), dp(12), dp(16), dp(8));
        methodContent.setBackground(sectionBackground());
        content.addView(methodContent, matchWrap(dp(0), dp(16)));
        TextView compositionModeLabel = new TextView(this);
        compositionModeLabel.setText(R.string.composition_mode_title);
        compositionModeLabel.setTextSize(18);
        compositionModeLabel.setTextColor(Color.DKGRAY);
        methodContent.addView(compositionModeLabel, matchWrap(dp(0), dp(4)));

        Spinner compositionMode = new Spinner(this);
        compositionMode.setContentDescription(getString(R.string.composition_mode_title));
        ArrayAdapter<CharSequence> compositionAdapter = ArrayAdapter.createFromResource(this,
                R.array.composition_modes, android.R.layout.simple_spinner_item);
        compositionAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        compositionMode.setAdapter(compositionAdapter);
        compositionMode.setSelection(ChineseInputMethodSettings.method(this).ordinal());
        compositionMode.setOnItemSelectedListener(
                new android.widget.AdapterView.OnItemSelectedListener() {
                    @Override
                    public void onItemSelected(android.widget.AdapterView<?> parent,
                                               android.view.View view, int position, long id) {
                        ChineseInputMethodSettings.setMethod(SettingsActivity.this,
                                ChineseInputMethod.values()[position]);
                    }

                    @Override public void onNothingSelected(
                            android.widget.AdapterView<?> parent) {}
                });
        methodContent.addView(compositionMode, matchWrap(dp(0), dp(8)));

        LinearLayout compositionContent = addSettingsGroup(content, savedInstanceState,
                "composition", R.string.settings_group_composition, 0, false);
        addHelpLabel(compositionContent, R.string.composition_mode_help,
                R.string.composition_mode_description);

        CheckBox omitTone = settingsCheckBox(R.string.smart_omit_tone,
                BopomofoCompositionModeSettings.omitTone(this));
        omitTone.setOnCheckedChangeListener((button, checked) ->
                BopomofoCompositionModeSettings.setOmitTone(SettingsActivity.this, checked));
        addHelpRow(compositionContent, omitTone, R.string.smart_omit_tone_description);

        CheckBox spaceSelectsCandidates = settingsCheckBox(R.string.smart_space_selects_candidates,
                BopomofoCompositionModeSettings.spaceSelectsCandidates(this));
        spaceSelectsCandidates.setOnCheckedChangeListener((button, checked) ->
                BopomofoCompositionModeSettings.setSpaceSelectsCandidates(SettingsActivity.this, checked));
        addHelpRow(compositionContent, spaceSelectsCandidates,
                R.string.smart_space_selects_candidates_description);

        CheckBox bigramContext = settingsCheckBox(R.string.smart_bigram_enabled,
                BopomofoCompositionModeSettings.bigramEnabled(this));
        bigramContext.setOnCheckedChangeListener((button, checked) ->
                BopomofoCompositionModeSettings.setBigramEnabled(SettingsActivity.this, checked));
        addHelpRow(compositionContent, bigramContext, R.string.smart_bigram_description);

        addHelpLabel(compositionContent, R.string.bopomofo_keyboard_layout,
                R.string.bopomofo_keyboard_layout_description);
        Spinner keyboardLayout = new Spinner(this);
        keyboardLayout.setContentDescription(getString(R.string.bopomofo_keyboard_layout));
        ArrayAdapter<CharSequence> keyboardLayoutAdapter = ArrayAdapter.createFromResource(this,
                R.array.bopomofo_keyboard_layouts, android.R.layout.simple_spinner_item);
        keyboardLayoutAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        keyboardLayout.setAdapter(keyboardLayoutAdapter);
        keyboardLayout.setSelection(BopomofoKeyboardLayoutSettings.layout(this).ordinal());
        keyboardLayout.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener() {
            @Override public void onItemSelected(android.widget.AdapterView<?> parent,
                    android.view.View view, int position, long id) {
                BopomofoKeyboardLayoutSettings.setLayout(SettingsActivity.this,
                        BopomofoKeyboardLayout.values()[position]);
            }
            @Override public void onNothingSelected(android.widget.AdapterView<?> parent) {}
        });
        compositionContent.addView(keyboardLayout, matchWrap(dp(0), dp(8)));

        Button userPhrases = new Button(this);
        userPhrases.setText("管理好打注音自訂詞");
        userPhrases.setContentDescription("管理好打注音自訂詞");
        userPhrases.setOnClickListener(view -> startActivity(new Intent(this, UserPhrasesActivity.class)));
        compositionContent.addView(userPhrases, matchWrap(dp(0), dp(8)));

        Button resetLearning = new Button(this);
        resetLearning.setText("重設好打注音學習紀錄");
        resetLearning.setOnClickListener(view -> {
            new AlertDialog.Builder(this)
                    .setTitle("重設好打注音學習紀錄？")
                    .setMessage("這會清除已學習的選字和相鄰詞關係，自訂詞會保留。")
                    .setNegativeButton("取消", null)
                    .setPositiveButton("重設", (dialog, which) -> {
                        CandidateGlyphSupport.shared().reset();
                        try (UserPhraseRepository data = UserPhraseRepository.open(this)) {
                            data.resetSmartLearning();
                            Toast.makeText(this, "好打注音學習紀錄已重設", Toast.LENGTH_SHORT).show();
                        } catch (RuntimeException error) {
                            Toast.makeText(this, "無法重設學習紀錄：" + error.getMessage(), Toast.LENGTH_LONG).show();
                        }
                    }).show();
        });
        compositionContent.addView(resetLearning, matchWrap(dp(0), dp(24)));

        LinearLayout tableContent = addSettingsGroup(content, savedInstanceState,
                "table", R.string.settings_group_table,
                R.string.settings_group_table_summary, false);
        addHelpLabel(tableContent, R.string.table_settings_help,
                R.string.settings_group_table_description);
        addTableSettings(tableContent, ChineseInputMethod.CANGJIE);
        addTableSettings(tableContent, ChineseInputMethod.SIMPLEX);

        LinearLayout appearanceContent = addSettingsGroup(content, savedInstanceState,
                "appearance", R.string.settings_group_appearance,
                R.string.settings_group_appearance_summary, false);
        addHelpLabel(appearanceContent, R.string.haptic_feedback_title,
                R.string.haptic_feedback_description);

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
        appearanceContent.addView(endpoints, matchWrap(dp(0), dp(8)));

        CheckBox keyPreview = settingsCheckBox(R.string.key_preview_enabled, KeyPreviewSettings.enabled(this));
        keyPreview.setOnCheckedChangeListener((button, checked) ->
                KeyPreviewSettings.setEnabled(SettingsActivity.this, checked));
        addHelpRow(appearanceContent, keyPreview, R.string.key_preview_description);

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
        addKeyboardLayoutSettings(appearanceContent);

        Button resizeKeyboard = new Button(this);
        resizeKeyboard.setText(R.string.keyboard_resize_title);
        resizeKeyboard.setOnClickListener(view ->
                startActivity(new Intent(this, KeyboardResizeActivity.class)));
        appearanceContent.addView(resizeKeyboard, matchWrap(dp(0), dp(16)));

        touchBottomSpace = settingsCheckBox(R.string.bottom_language_space_enabled,
                KeyboardBottomSpaceSettings.touchEnabled(this));
        touchBottomSpace.setOnCheckedChangeListener((button, checked) ->
                KeyboardBottomSpaceSettings.setTouchEnabled(SettingsActivity.this, checked));
        addHelpRow(appearanceContent, touchBottomSpace, R.string.touch_bottom_space_description);
        updateTouchBottomSpaceAvailability();

        LinearLayout hardwareContent = addSettingsGroup(content, savedInstanceState,
                "hardware", R.string.settings_group_hardware,
                R.string.settings_group_hardware_summary, false);
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

        CheckBox hardwareSmartTwoRows = settingsCheckBox(R.string.hardware_smart_two_rows_enabled,
                CandidateWindowSettings.smartTwoRowsEnabled(this));
        setDependentControlEnabled(hardwareSmartTwoRows, !floatingCandidates.isChecked());
        addHelpRow(hardwareContent, hardwareSmartTwoRows, R.string.hardware_smart_two_rows_description);
        hardwareSmartTwoRows.setOnCheckedChangeListener((button, checked) ->
                CandidateWindowSettings.setSmartTwoRowsEnabled(SettingsActivity.this, checked));

        CheckBox hardwareNumberRow = settingsCheckBox(R.string.hardware_number_row_enabled,
                CandidateWindowSettings.numberRowEnabled(this));
        setDependentControlEnabled(hardwareNumberRow, !floatingCandidates.isChecked());
        addHelpRow(hardwareContent, hardwareNumberRow, R.string.hardware_collapse_description);
        hardwareNumberRow.setOnCheckedChangeListener((button, checked) ->
                CandidateWindowSettings.setNumberRowEnabled(SettingsActivity.this, checked));

        CheckBox hardwareBottomSpace = settingsCheckBox(R.string.bottom_language_space_enabled,
                KeyboardBottomSpaceSettings.hardwareEnabled(this));
        setDependentControlEnabled(hardwareBottomSpace, !floatingCandidates.isChecked());
        hardwareBottomSpace.setOnCheckedChangeListener((button, checked) ->
                KeyboardBottomSpaceSettings.setHardwareEnabled(SettingsActivity.this, checked));
        addHelpRow(hardwareContent, hardwareBottomSpace, R.string.hardware_bottom_space_description);

        floatingCandidates.setOnCheckedChangeListener((button, checked) -> {
            CandidateWindowSettings.setFloatingEnabled(SettingsActivity.this, checked);
            floatingLayout.setEnabled(checked);
            floatingLayoutLabel.setEnabled(checked);
            setDependentControlEnabled(hardwareSmartTwoRows, !checked);
            setDependentControlEnabled(hardwareNumberRow, !checked);
            setDependentControlEnabled(hardwareBottomSpace, !checked);
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
        for (Map.Entry<String, LinearLayout> entry : settingsGroups.entrySet()) {
            state.putBoolean("settings_group_" + entry.getKey(),
                    entry.getValue().getVisibility() == View.VISIBLE);
        }
        state.putInt("settings_scroll_y", settingsScroll.getScrollY());
    }

    private void addKeyboardLayoutSettings(LinearLayout parent) {
        var profiles = KeyboardLayoutProfile.available();
        var areas = KeyboardLayoutProfile.KeycapArea.values();
        var fonts = KeyboardLayoutProfile.FontSize.values();
        var positions = KeyboardLayoutProfile.DeletePosition.values();
        addHelpLabel(parent, R.string.keyboard_layout_profile,
                R.string.keyboard_layout_profile_description);
        Spinner profile = layoutOptionSpinner(parent, R.string.keyboard_layout_profile,
                profiles.stream().map(item -> item.displayName).toArray(String[]::new));
        profile.setSelection(profiles.indexOf(KeyboardLayoutProfileSettings.profile(this)));
        addLayoutOptionLabel(parent, R.string.keyboard_keycap_area);
        Spinner area = layoutOptionSpinner(parent, R.string.keyboard_keycap_area,
                new String[] {getString(R.string.keyboard_spacing_small), getString(R.string.keyboard_spacing_medium),
                        getString(R.string.keyboard_spacing_large)});
        area.setSelection(java.util.Arrays.asList(areas).indexOf(KeyboardLayoutProfileSettings.keycapArea(this)));
        addLayoutOptionLabel(parent, R.string.keyboard_font_size);
        Spinner font = layoutOptionSpinner(parent, R.string.keyboard_font_size,
                new String[] {getString(R.string.keyboard_font_normal), getString(R.string.keyboard_font_medium),
                        getString(R.string.keyboard_font_large), getString(R.string.keyboard_font_extra_large)});
        font.setSelection(java.util.Arrays.asList(fonts).indexOf(KeyboardLayoutProfileSettings.fontSize(this)));
        addLayoutOptionLabel(parent, R.string.keyboard_delete_position);
        Spinner position = layoutOptionSpinner(parent, R.string.keyboard_delete_position,
                new String[] {getString(R.string.keyboard_delete_above), getString(R.string.keyboard_delete_left)});
        position.setSelection(java.util.Arrays.asList(positions).indexOf(KeyboardLayoutProfileSettings.deletePosition(this)));
        profile.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener() {
            @Override public void onItemSelected(android.widget.AdapterView<?> adapter, View view, int index, long id) {
                KeyboardLayoutProfile selected = profiles.get(index);
                KeyboardLayoutProfileSettings.setProfile(SettingsActivity.this, selected);
            }
            @Override public void onNothingSelected(android.widget.AdapterView<?> adapter) {}
        });
        area.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener() {
            @Override public void onItemSelected(android.widget.AdapterView<?> adapter, View view, int index, long id) {
                KeyboardLayoutProfileSettings.setKeycapArea(SettingsActivity.this, areas[index]);
            }
            @Override public void onNothingSelected(android.widget.AdapterView<?> adapter) {}
        });
        font.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener() {
            @Override public void onItemSelected(android.widget.AdapterView<?> adapter, View view, int index, long id) {
                KeyboardLayoutProfileSettings.setFontSize(SettingsActivity.this, fonts[index]);
            }
            @Override public void onNothingSelected(android.widget.AdapterView<?> adapter) {}
        });
        position.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener() {
            @Override public void onItemSelected(android.widget.AdapterView<?> adapter, View view, int index, long id) {
                KeyboardLayoutProfileSettings.setDeletePosition(SettingsActivity.this, positions[index]);
            }
            @Override public void onNothingSelected(android.widget.AdapterView<?> adapter) {}
        });
        CheckBox integrated = settingsCheckBox(R.string.integrated_bottom_controls_enabled,
                KeyboardBottomControlsSettings.enabled(this));
        integrated.setOnCheckedChangeListener((button, checked) -> {
            KeyboardBottomControlsSettings.setEnabled(this, checked);
            updateTouchBottomSpaceAvailability();
        });
        addHelpRow(parent, integrated, R.string.integrated_bottom_controls_description);
    }

    private void updateTouchBottomSpaceAvailability() {
        if (touchBottomSpace == null) return;
        boolean enabled = !KeyboardBottomControlsSettings.enabled(this);
        setDependentControlEnabled(touchBottomSpace, enabled);
    }

    private void addLayoutOptionLabel(LinearLayout parent, int text) {
        TextView label = new TextView(this);
        label.setText(text);
        label.setTextSize(16);
        label.setTextColor(Color.DKGRAY);
        parent.addView(label, matchWrap(dp(0), dp(4)));
    }

    private Spinner layoutOptionSpinner(LinearLayout parent, int label, String[] entries) {
        Spinner spinner = new Spinner(this);
        spinner.setContentDescription(getString(label));
        ArrayAdapter<String> adapter = new ArrayAdapter<>(this, android.R.layout.simple_spinner_item, entries);
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        spinner.setAdapter(adapter);
        parent.addView(spinner, matchWrap(dp(0), dp(12)));
        return spinner;
    }

    private LinearLayout addSettingsGroup(LinearLayout root, Bundle savedState,
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

        if (summaryRes != 0) {
            TextView summary = new TextView(this);
            summary.setText(summaryRes);
            summary.setTextSize(14);
            summary.setTextColor(Color.DKGRAY);
            summary.setPadding(0, dp(4), 0, 0);
            header.addView(summary);
        }

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
        settingsGroups.put(key, body);
        return body;
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

    private void addTableSettings(LinearLayout parent, ChineseInputMethod method) {
        addTableSettings(parent, method, true);
        if (method == ChineseInputMethod.CANGJIE) addTableSettings(parent, method, false);
    }

    private void addTableSettings(LinearLayout parent, ChineseInputMethod method, boolean virtualKeyboard) {
        boolean cangjie = method == ChineseInputMethod.CANGJIE;
        TextView heading = new TextView(this);
        heading.setText(method.displayName + (cangjie
                ? (virtualKeyboard ? "設定（虛擬鍵盤）" : "設定（實體鍵盤）") : "設定"));
        heading.setTextSize(18);
        parent.addView(heading, matchWrap(dp(0), dp(4)));
        TableInputOptions initial = ChineseInputMethodSettings.options(this, method, virtualKeyboard);
        String[] keys = cangjie
                ? (virtualKeyboard ? new String[]{"realtime", "prefix", "clear", "maximum", "learning"}
                                   : new String[]{"realtime", "prefix", "clear"})
                : new String[]{"realtime", "clear"};
        CheckBox[] controls = new CheckBox[keys.length];
        boolean[] updating = {false};
        Runnable refresh = () -> {
            TableInputOptions saved = ChineseInputMethodSettings.options(this, method, virtualKeyboard);
            updating[0] = true;
            for (int i = 0; i < keys.length; i++) {
                if (controls[i] == null) continue;
                controls[i].setChecked(switch (keys[i]) {
                    case "realtime" -> saved.composeWhileTyping;
                    case "prefix" -> saved.prefixCandidates;
                    case "clear" -> saved.clearOnError;
                    case "maximum" -> saved.queryAtMaximum;
                    default -> saved.dynamicFrequency;
                });
                controls[i].setEnabled(!keys[i].equals("prefix") || saved.composeWhileTyping);
            }
            updating[0] = false;
        };
        for (int i = 0; i < keys.length; i++) {
            String key = keys[i];
            CheckBox control = new CheckBox(this);
            controls[i] = control;
            String title = switch (key) {
                case "realtime" -> "即時候選";
                case "prefix" -> "未打完也能選字";
                case "clear" -> "錯碼清除";
                case "maximum" -> "滿五碼查詢";
                default -> "依選字紀錄排序";
            };
            control.setText(virtualKeyboard ? title : "實體鍵盤：" + title);
            control.setMinHeight(dp(44));
            control.setOnCheckedChangeListener((button, checked) -> {
                if (updating[0]) return;
                TableInputOptions next = ChineseInputMethodSettings.options(this, method, virtualKeyboard);
                switch (key) {
                    case "realtime" -> { next.composeWhileTyping = checked; if (checked) next.clearOnError = false; }
                    case "prefix" -> { if (next.composeWhileTyping) next.prefixCandidates = checked; }
                    case "clear" -> { next.clearOnError = checked; if (checked) next.composeWhileTyping = false; }
                    case "maximum" -> next.queryAtMaximum = checked;
                    default -> next.dynamicFrequency = checked;
                }
                ChineseInputMethodSettings.setOptions(this, method, next, virtualKeyboard);
                refresh.run();
            });
            int help = cangjie ? switch (key) {
                case "realtime", "clear" -> R.string.cangjie_candidate_mode_description;
                case "prefix" -> R.string.cangjie_prefix_candidates_description;
                default -> 0;
            } : 0;
            if (help != 0) {
                addHelpRow(parent, control, help);
            } else {
                parent.addView(control, matchWrap(dp(0), dp(0)));
            }
        }
        refresh.run();
        if (cangjie && virtualKeyboard) {
            Spinner punctuation = new Spinner(this);
            punctuation.setContentDescription("倉頡標點");
            ArrayAdapter<String> adapter = new ArrayAdapter<>(this,
                    android.R.layout.simple_spinner_item, new String[]{"標點：原字表", "標點：中英混合", "標點：半形"});
            adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
            punctuation.setAdapter(adapter);
            punctuation.setSelection(initial.punctuation);
            punctuation.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener() {
                public void onItemSelected(android.widget.AdapterView<?> view, View item, int position, long id) {
                    TableInputOptions next = ChineseInputMethodSettings.options(SettingsActivity.this, method, true);
                    if (next.punctuation == position) return;
                    next.punctuation = position;
                    ChineseInputMethodSettings.setOptions(SettingsActivity.this, method, next, true);
                }
                public void onNothingSelected(android.widget.AdapterView<?> view) {}
            });
            parent.addView(punctuation, matchWrap(dp(0), dp(8)));
        }
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

    private void updateHapticValue(TextView view, int durationMs) {
        if (durationMs == 0) {
            view.setText(R.string.haptic_value_off);
        } else {
            view.setText(getString(R.string.haptic_value_seconds,
                    String.format(Locale.TAIWAN, "%.3f", durationMs / 1000f), durationMs));
        }
    }

    private CheckBox settingsCheckBox(int title, boolean checked) {
        CheckBox check = new CheckBox(this);
        check.setText(title);
        check.setTextSize(16);
        check.setTextColor(Color.DKGRAY);
        check.setMinHeight(dp(48));
        check.setChecked(checked);
        return check;
    }

    private void addHelpLabel(LinearLayout parent, int title, int message) {
        TextView label = new TextView(this);
        label.setText(title);
        label.setTextSize(16);
        label.setTextColor(Color.DKGRAY);
        addHelpRow(parent, label, message);
    }

    private void addHelpRow(LinearLayout parent, TextView option, int message) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.addView(option, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        CharSequence title = option.getText();
        ImageButton info = new ImageButton(this);
        info.setImageResource(R.drawable.ic_settings_info);
        info.setContentDescription(getString(R.string.settings_show_help, title));
        int iconPadding = dp(12);
        info.setPadding(iconPadding, iconPadding, iconPadding, iconPadding);
        TypedValue background = new TypedValue();
        getTheme().resolveAttribute(android.R.attr.selectableItemBackgroundBorderless, background, true);
        info.setBackgroundResource(background.resourceId);
        info.setOnClickListener(view -> new AlertDialog.Builder(this)
                .setTitle(title)
                .setMessage(message)
                .setPositiveButton(R.string.settings_close_help, null)
                .show());
        row.addView(info, new LinearLayout.LayoutParams(dp(48), dp(48)));
        parent.addView(row, matchWrap(dp(0), dp(4)));
    }

    private static void setDependentControlEnabled(View control, boolean enabled) {
        control.setEnabled(enabled);
        control.setAlpha(enabled ? 1f : 0.45f);
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
