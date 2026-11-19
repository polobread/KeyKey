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
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;

public final class SettingsActivity extends Activity implements SupporterBillingManager.Listener {
    static Intent intent(android.content.Context context, boolean virtual) {
        return new Intent(context, SettingsActivity.class).putExtra(KeyboardSettingsProfile.EXTRA_PROFILE,
                virtual ? KeyboardSettingsProfile.VIRTUAL : KeyboardSettingsProfile.PHYSICAL);
    }
    private boolean virtualKeyboard = true;
    private final java.util.List<View> hardwareAdvancedControls = new java.util.ArrayList<>();
    private final Map<String, LinearLayout> settingsGroups = new LinkedHashMap<>();
    private LinearLayout settingsContent;
    private LinearLayout supporterSection;
    private ScrollView settingsScroll;
    private TextView supporterTitle;
    private TextView supporterDescription;
    private TextView supporterPrice;
    private Button supporterButton;
    private SupporterBillingManager supporterBillingManager;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        KeyboardSettingsProfile.migrate(this);
        String profile = getIntent().getStringExtra(KeyboardSettingsProfile.EXTRA_PROFILE);
        if (profile == null) {
            startActivity(new Intent(this, MainActivity.class)
                    .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP));
            finish();
            return;
        }
        virtualKeyboard = !KeyboardSettingsProfile.PHYSICAL.equals(profile);

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
        title.setText(virtualKeyboard ? R.string.virtual_keyboard_settings : R.string.physical_keyboard_settings);
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
        compositionMode.setSelection(ChineseInputMethodSettings.method(this, virtualKeyboard).ordinal());
        compositionMode.setOnItemSelectedListener(
                new android.widget.AdapterView.OnItemSelectedListener() {
                    @Override
                    public void onItemSelected(android.widget.AdapterView<?> parent,
                                               android.view.View view, int position, long id) {
                        ChineseInputMethodSettings.setMethod(SettingsActivity.this,
                                ChineseInputMethod.values()[position], virtualKeyboard);
                    }

                    @Override public void onNothingSelected(
                            android.widget.AdapterView<?> parent) {}
                });
        methodContent.addView(compositionMode, matchWrap(dp(0), dp(8)));

        Switch simplifiedChineseOutput = new Switch(this);
        simplifiedChineseOutput.setText(R.string.simplified_chinese_output);
        simplifiedChineseOutput.setTextSize(16);
        simplifiedChineseOutput.setTextColor(Color.DKGRAY);
        simplifiedChineseOutput.setMinHeight(dp(48));
        simplifiedChineseOutput.setChecked(ChineseInputMethodSettings.simplifiedChineseOutput(this, virtualKeyboard));
        simplifiedChineseOutput.setOnCheckedChangeListener((button, checked) ->
                ChineseInputMethodSettings.setSimplifiedChineseOutput(this, checked, virtualKeyboard));
        addHelpRow(methodContent, simplifiedChineseOutput, R.string.simplified_chinese_output_description);

        LinearLayout compositionContent = addSettingsGroup(content, savedInstanceState,
                "composition", R.string.settings_group_composition, 0, false);
        addHelpLabel(compositionContent, R.string.composition_mode_help,
                virtualKeyboard ? R.string.composition_mode_description : R.string.hardware_composition_mode_description);

        CheckBox omitTone = settingsCheckBox(R.string.smart_omit_tone,
                BopomofoCompositionModeSettings.omitTone(this, virtualKeyboard));
        omitTone.setOnCheckedChangeListener((button, checked) ->
                BopomofoCompositionModeSettings.setOmitTone(SettingsActivity.this, checked, virtualKeyboard));
        if (virtualKeyboard) addHelpRow(compositionContent, omitTone, R.string.smart_omit_tone_description);
        else addHardwareHelpRow(compositionContent, omitTone, R.string.hardware_omit_tone_description);
        if (!virtualKeyboard) hardwareAdvancedControls.add(omitTone);

        CheckBox spaceSelectsCandidates = settingsCheckBox(R.string.smart_space_selects_candidates,
                BopomofoCompositionModeSettings.spaceSelectsCandidates(this, virtualKeyboard));
        spaceSelectsCandidates.setOnCheckedChangeListener((button, checked) ->
                BopomofoCompositionModeSettings.setSpaceSelectsCandidates(SettingsActivity.this, checked, virtualKeyboard));
        addHelpRow(compositionContent, spaceSelectsCandidates,
                virtualKeyboard ? R.string.smart_space_selects_candidates_description : R.string.hardware_space_selects_candidates_description);

        CheckBox bigramContext = settingsCheckBox(R.string.smart_bigram_enabled,
                BopomofoCompositionModeSettings.bigramEnabled(this, virtualKeyboard));
        bigramContext.setOnCheckedChangeListener((button, checked) ->
                BopomofoCompositionModeSettings.setBigramEnabled(SettingsActivity.this, checked, virtualKeyboard));
        addHelpRow(compositionContent, bigramContext, R.string.smart_bigram_description);

        addHelpLabel(compositionContent, R.string.bopomofo_keyboard_layout,
                R.string.bopomofo_keyboard_layout_description);
        Spinner keyboardLayout = new Spinner(this);
        keyboardLayout.setContentDescription(getString(R.string.bopomofo_keyboard_layout));
        ArrayAdapter<CharSequence> keyboardLayoutAdapter = ArrayAdapter.createFromResource(this,
                R.array.bopomofo_keyboard_layouts, android.R.layout.simple_spinner_item);
        keyboardLayoutAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        keyboardLayout.setAdapter(keyboardLayoutAdapter);
        keyboardLayout.setSelection(BopomofoKeyboardLayoutSettings.layout(this, virtualKeyboard).ordinal());
        keyboardLayout.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener() {
            @Override public void onItemSelected(android.widget.AdapterView<?> parent,
                    android.view.View view, int position, long id) {
                BopomofoKeyboardLayoutSettings.setLayout(SettingsActivity.this,
                        BopomofoKeyboardLayout.values()[position], virtualKeyboard);
            }
            @Override public void onNothingSelected(android.widget.AdapterView<?> parent) {}
        });
        compositionContent.addView(keyboardLayout, matchWrap(dp(0), dp(8)));

        if (!virtualKeyboard) addHardwareAdvancedSettings(compositionContent);

        LinearLayout tableContent = addSettingsGroup(content, savedInstanceState,
                "table", R.string.settings_group_table,
                R.string.settings_group_table_summary, false);
        addHelpLabel(tableContent, R.string.table_settings_help,
                R.string.settings_group_table_description);
        addTableSettings(tableContent, ChineseInputMethod.CANGJIE);
        addTableSettings(tableContent, ChineseInputMethod.SIMPLEX);

        if (virtualKeyboard) {
        LinearLayout appearanceContent = addSettingsGroup(content, savedInstanceState,
                "appearance", R.string.settings_group_appearance,
                R.string.settings_group_appearance_summary, false);
        addFeedbackSettings(appearanceContent);
        addCandidateColorSettings(appearanceContent);

        CheckBox keyPreview = settingsCheckBox(R.string.key_preview_enabled, KeyPreviewSettings.enabled(this));
        keyPreview.setOnCheckedChangeListener((button, checked) ->
                KeyPreviewSettings.setEnabled(SettingsActivity.this, checked));
        addHelpRow(appearanceContent, keyPreview, R.string.key_preview_description);

        addKeyboardLayoutSettings(appearanceContent);

        Button resizeKeyboard = new Button(this);
        resizeKeyboard.setText(R.string.keyboard_resize_title);
        resizeKeyboard.setOnClickListener(view ->
                startActivity(new Intent(this, KeyboardResizeActivity.class)));
        appearanceContent.addView(resizeKeyboard, matchWrap(dp(0), dp(16)));



        }

        if (!virtualKeyboard) {
        LinearLayout hardwareContent = addSettingsGroup(content, savedInstanceState,
                "hardware", R.string.settings_group_hardware,
                R.string.settings_group_hardware_summary, false);
        addFeedbackSettings(hardwareContent);
        addCandidateColorSettings(hardwareContent);
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
                { CandidateWindowSettings.setSmartTwoRowsEnabled(SettingsActivity.this, checked);
                    updateHardwareAdvancedControls(); });

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
            updateHardwareAdvancedControls();
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

        updateHardwareAdvancedControls();
        }

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

        placeSupporterSection(SupporterState.isSupporter(this));
        setContentView(scroll);
        if (savedInstanceState != null) {
            int scrollY = savedInstanceState.getInt("settings_scroll_y", 0);
            scroll.post(() -> scroll.scrollTo(0, scrollY));
        }

        supporterBillingManager = new SupporterBillingManager(this, this);
        supporterBillingManager.start();
    }

    @Override protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        String previous = getIntent().getStringExtra(KeyboardSettingsProfile.EXTRA_PROFILE);
        String requested = intent.getStringExtra(KeyboardSettingsProfile.EXTRA_PROFILE);
        setIntent(intent);
        if (!java.util.Objects.equals(previous, requested)) recreate();
    }

    @Override
    protected void onSaveInstanceState(Bundle state) {
        super.onSaveInstanceState(state);
        for (Map.Entry<String, LinearLayout> entry : settingsGroups.entrySet()) {
            state.putBoolean("settings_group_" + entry.getKey(),
                    entry.getValue().getVisibility() == View.VISIBLE);
        }
        if (settingsScroll != null) state.putInt("settings_scroll_y", settingsScroll.getScrollY());
    }

    private void addFeedbackSettings(LinearLayout parent) {
        int title = virtualKeyboard ? R.string.haptic_feedback_title : R.string.hardware_haptic_feedback_title;
        addHelpLabel(parent, title, virtualKeyboard
                ? R.string.haptic_feedback_description : R.string.hardware_haptic_feedback_description);
        TextView value = new TextView(this);
        value.setTextSize(16);
        value.setTextColor(getColor(R.color.keykey_blue_dark));
        value.setGravity(Gravity.CENTER);
        parent.addView(value, matchWrap(dp(0), dp(12)));
        SeekBar duration = new SeekBar(this);
        duration.setContentDescription(getString(title));
        duration.setMax(HapticSettings.maxSelectionIndex());
        duration.setProgress(HapticSettings.selectionForDurationMs(HapticSettings.durationMs(this, virtualKeyboard)));
        parent.addView(duration, matchWrap(dp(0), dp(4)));
        LinearLayout endpoints = new LinearLayout(this);
        endpoints.setOrientation(LinearLayout.HORIZONTAL);
        endpoints.addView(endpointLabel(R.string.haptic_off, Gravity.START), weightedWrap());
        endpoints.addView(endpointLabel(R.string.haptic_maximum, Gravity.END), weightedWrap());
        parent.addView(endpoints, matchWrap(dp(0), dp(8)));
        updateHapticValue(value, HapticSettings.durationMsForSelection(duration.getProgress()));
        duration.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                int durationMs = HapticSettings.durationMsForSelection(progress);
                HapticSettings.setDurationMs(SettingsActivity.this, durationMs, virtualKeyboard);
                updateHapticValue(value, durationMs);
            }
            @Override public void onStartTrackingTouch(SeekBar seekBar) {}
            @Override public void onStopTrackingTouch(SeekBar seekBar) {
                int durationMs = HapticSettings.durationMsForSelection(seekBar.getProgress());
                Vibrator vibrator = getSystemService(Vibrator.class);
                if (durationMs > 0 && vibrator != null && vibrator.hasVibrator()) {
                    vibrator.vibrate(VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE));
                }
            }
        });
    }

    private void addCandidateColorSettings(LinearLayout parent) {
        addHelpLabel(parent, R.string.candidate_color_title, R.string.candidate_color_description);
        Spinner candidateColor = new Spinner(this);
        candidateColor.setContentDescription(getString(R.string.candidate_color_title));
        ArrayAdapter<CharSequence> colorAdapter = ArrayAdapter.createFromResource(this,
                R.array.candidate_highlight_colors, android.R.layout.simple_spinner_item);
        colorAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        candidateColor.setAdapter(colorAdapter);
        candidateColor.setSelection(CandidateColorSettings.selectionIndex(CandidateColorSettings.color(this, virtualKeyboard)));
        candidateColor.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener() {
            @Override public void onItemSelected(android.widget.AdapterView<?> parent, View view, int position, long id) {
                CandidateColorSettings.setColor(SettingsActivity.this,
                        CandidateColorSettings.colorAtSelectionIndex(position), virtualKeyboard);
            }
            @Override public void onNothingSelected(android.widget.AdapterView<?> parent) {}
        });
        parent.addView(candidateColor, matchWrap(dp(0), dp(20)));
    }

    private void addHardwareHelpRow(LinearLayout parent, TextView option, int description) {
        addHelpRow(parent, option, getString(description) + "\n\n" + getString(R.string.hardware_advanced_description));
    }

    private void addHardwareAdvancedSettings(LinearLayout parent) {
        String[] names = {HardwareSmartSettings.CURSOR_AT_END, HardwareSmartSettings.RETURNS_TO_END,
                HardwareSmartSettings.CLEAR_ESCAPE, HardwareSmartSettings.IGNORE_CAPS, HardwareSmartSettings.SHIFT_UPPER};
        int[] labels = {R.string.hardware_candidate_before_cursor, R.string.hardware_selection_returns_to_end,
                R.string.hardware_escape_clears_composition, R.string.hardware_ignore_caps, R.string.hardware_shift_upper};
        int[] descriptions = {R.string.hardware_candidate_before_cursor_description,
                R.string.hardware_selection_returns_to_end_description, R.string.hardware_escape_clears_composition_description,
                R.string.hardware_ignore_caps_description, R.string.hardware_shift_upper_description};
        for (int index = 0; index < names.length; index++) {
            String name = names[index];
            CheckBox control = settingsCheckBox(labels[index], HardwareSmartSettings.enabled(this, name));
            control.setOnCheckedChangeListener((button, checked) -> HardwareSmartSettings.setEnabled(this, name, checked));
            addHardwareHelpRow(parent, control, descriptions[index]);
            hardwareAdvancedControls.add(control);
        }
        TextView maximumLabel = new TextView(this);
        maximumLabel.setText(R.string.hardware_max_syllables);
        maximumLabel.setTextSize(16);
        maximumLabel.setTextColor(Color.DKGRAY);
        addHardwareHelpRow(parent, maximumLabel, R.string.hardware_max_syllables_description);
        Spinner maximum = new Spinner(this);
        String[] counts = new String[11];
        for (int index = 0; index < counts.length; index++) counts[index] = Integer.toString(index + 10);
        ArrayAdapter<String> adapter = new ArrayAdapter<>(this, android.R.layout.simple_spinner_item, counts);
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        maximum.setAdapter(adapter);
        maximum.setContentDescription(getString(R.string.hardware_max_syllables));
        maximum.setSelection(HardwareSmartSettings.maxSyllables(this) - 10);
        maximum.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener() {
            public void onItemSelected(android.widget.AdapterView<?> parent, View view, int position, long id) {
                HardwareSmartSettings.setMaxSyllables(SettingsActivity.this, position + 10);
            }
            public void onNothingSelected(android.widget.AdapterView<?> parent) {}
        });
        hardwareAdvancedControls.add(maximum);
        parent.addView(maximum, matchWrap(0, dp(8)));
    }
    private void updateHardwareAdvancedControls() {
        boolean desktop = CandidateWindowSettings.floatingEnabled(this) || !CandidateWindowSettings.smartTwoRowsEnabled(this);
        for (View control : hardwareAdvancedControls) setDependentControlEnabled(control, desktop);
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
        addHelpLabel(parent, R.string.keyboard_font_size, R.string.keyboard_font_size_description);
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
        integrated.setOnCheckedChangeListener((button, checked) ->
                KeyboardBottomControlsSettings.setEnabled(this, checked));
        addHelpRow(parent, integrated, R.string.integrated_bottom_controls_description);
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
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(16), dp(8), dp(8), dp(8));
        header.setMinimumHeight(dp(56));
        header.setFocusable(true);
        header.setClickable(true);
        section.addView(header, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        TextView heading = new TextView(this);
        heading.setTextSize(20);
        heading.setTextColor(getColor(R.color.keykey_blue_dark));
        header.addView(heading, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        if (summaryRes != 0) header.addView(helpButton(getString(titleRes), getString(summaryRes)),
                new LinearLayout.LayoutParams(dp(48), dp(48)));

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
        addTableSettings(parent, method, virtualKeyboard);
    }

    private void addTableSettings(LinearLayout parent, ChineseInputMethod method, boolean virtualKeyboard) {
        boolean cangjie = method == ChineseInputMethod.CANGJIE;
        TextView heading = new TextView(this);
        heading.setText(method.displayName + "設定");
        heading.setTextSize(18);
        parent.addView(heading, matchWrap(dp(0), dp(4)));
        TableInputOptions initial = ChineseInputMethodSettings.options(this, method, virtualKeyboard);
        String[] keys = cangjie
                ? new String[]{"realtime", "prefix", "clear", "maximum", "learning"}
                : new String[]{"realtime", "clear", "learning"};
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
            control.setText(title);
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
            } : switch (key) {
                case "realtime", "clear" -> R.string.cangjie_candidate_mode_description;
                default -> 0;
            };
            if (help != 0) {
                addHelpRow(parent, control, help);
            } else {
                parent.addView(control, matchWrap(dp(0), dp(0)));
            }
        }
        refresh.run();
        if (cangjie) {
            Spinner punctuation = new Spinner(this);
            punctuation.setContentDescription("倉頡標點");
            ArrayAdapter<String> adapter = new ArrayAdapter<>(this,
                    android.R.layout.simple_spinner_item, new String[]{"標點：原字表", "標點：中英混合", "標點：半形"});
            adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
            punctuation.setAdapter(adapter);
            punctuation.setSelection(initial.punctuation);
            punctuation.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener() {
                public void onItemSelected(android.widget.AdapterView<?> view, View item, int position, long id) {
                    TableInputOptions next = ChineseInputMethodSettings.options(SettingsActivity.this, method, virtualKeyboard);
                    if (next.punctuation == position) return;
                    next.punctuation = position;
                    ChineseInputMethodSettings.setOptions(SettingsActivity.this, method, next, virtualKeyboard);
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
        addHelpRow(parent, option, getString(message));
    }

    private void addHelpRow(LinearLayout parent, TextView option, CharSequence message) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.addView(option, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        row.addView(helpButton(option.getText(), message), new LinearLayout.LayoutParams(dp(48), dp(48)));
        parent.addView(row, matchWrap(dp(0), dp(4)));
    }

    private ImageButton helpButton(CharSequence title, CharSequence message) {
        ImageButton info = new ImageButton(this);
        info.setImageResource(R.drawable.ic_settings_info);
        info.setContentDescription(getString(R.string.settings_show_help, title));
        int iconPadding = dp(12);
        info.setPadding(iconPadding, iconPadding, iconPadding, iconPadding);
        TypedValue background = new TypedValue();
        getTheme().resolveAttribute(android.R.attr.selectableItemBackgroundBorderless, background, true);
        info.setBackgroundResource(background.resourceId);
        info.setOnClickListener(view -> new AlertDialog.Builder(this)
                .setTitle(title).setMessage(message)
                .setPositiveButton(R.string.settings_close_help, null).show());
        return info;
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
