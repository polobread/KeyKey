//! The public, opt-in touch phonetics contract with the shared model.
//! Copyright (c) 2026 Chui-Ping Cheng. MIT License.

mod support;

use guanyinma::bopomofo::BopomofoLayout;
use guanyinma::{
    BehaviorProfile, InputMethod, InputOperation, InputSession, Key, SessionConfig,
    SessionSnapshot, SmartOptions,
};

fn session(layout: BopomofoLayout) -> InputSession {
    InputSession::open(
        support::model_path(),
        SessionConfig {
            method: InputMethod::Smart,
            profile: BehaviorProfile::Touch,
            layout,
            smart: SmartOptions {
                shift_at_limit: true,
                selection_returns_to_end: true,
                ..SmartOptions::default()
            },
            ..SessionConfig::default()
        },
    )
    .unwrap()
}

fn type_touch(input: &mut InputSession, keys: &str) -> SessionSnapshot {
    let mut result = input.snapshot();
    for key in keys.chars() {
        result = input
            .apply(InputOperation::TouchPhonetic {
                text: key.to_string(),
            })
            .unwrap();
        assert!(result.effects.commit.is_empty());
    }
    result
}

fn key(input: &mut InputSession, key: Key) -> SessionSnapshot {
    input.apply(InputOperation::key(key)).unwrap()
}

#[test]
fn both_touch_layouts_show_nihao_live_and_select_into_the_smart_graph() {
    for (layout, keys, raw, first_syllable) in [
        (BopomofoLayout::HanyuPinyin, "nihao", "nihao", "ni"),
        (BopomofoLayout::Standard, "sucl", "ㄋㄧㄏㄠ", "su"),
    ] {
        let mut input = session(layout);
        let single = type_touch(&mut input, first_syllable);
        assert!(single.phonetic_space_first_tone);
        let live = type_touch(&mut input, &keys[first_syllable.len()..]);
        assert!(live.phonetic_pending && live.phonetic_suggestions);
        assert!(!live.phonetic_space_first_tone);
        assert_eq!(live.reading, raw);
        assert_eq!(live.visible_text, raw);
        assert_eq!(live.displayed_candidates[0], "你好");
        assert!(live.readings.is_empty());
        assert!(live.candidate_spans.is_empty());

        let selected = input.apply(InputOperation::Select { index: 0 }).unwrap();
        assert_eq!(selected.composition, "你好");
        assert_eq!(selected.readings, [r"\O", ":W"]);
        assert!(selected.effects.commit.is_empty());
        assert!(!selected.phonetic_pending && !selected.phonetic_suggestions);
        let normal = input
            .apply(InputOperation::OpenCandidates { index: 0 })
            .unwrap();
        assert!(!normal.phonetic_suggestions);
        assert!(!normal.candidate_spans.is_empty());
        input.apply(InputOperation::CloseCandidates).unwrap();
        assert_eq!(key(&mut input, Key::Return).effects.commit, "你好");
    }
}

#[test]
fn explicit_tones_and_first_tone_space_still_complete_a_reading() {
    for (layout, keys, first) in [
        (BopomofoLayout::HanyuPinyin, "ni3hao3", "ni"),
        (BopomofoLayout::Standard, "su3cl3", "su"),
    ] {
        let mut input = session(layout);
        let toned = type_touch(&mut input, keys);
        assert_eq!(toned.composition, "你好");
        assert_eq!(toned.readings, [r"\O", ":W"]);
        assert!(!toned.phonetic_pending);
        assert!(!toned.phonetic_suggestions);
        assert_eq!(key(&mut input, Key::Return).effects.commit, "你好");

        type_touch(&mut input, first);
        let first_tone = key(&mut input, Key::Space);
        assert_eq!(first_tone.readings, ["M0"]);
        assert!(!first_tone.phonetic_pending);
    }
    let mut input = session(BopomofoLayout::HanyuPinyin);
    let mixed = type_touch(&mut input, "nihao3");
    assert!(mixed.phonetic_pending);
    assert_eq!(mixed.displayed_candidates[0], "你好");
    assert_eq!(key(&mut input, Key::Return).effects.commit, "你好");
}

#[test]
fn choosing_a_prefix_leaves_the_unfinished_suffix_editable() {
    let mut input = session(BopomofoLayout::HanyuPinyin);
    let partial = type_touch(&mut input, "nihaon");
    assert_eq!(partial.reading, "nihaon");
    assert_eq!(partial.displayed_candidates[0], "你好");

    let resolved_prefix = key(&mut input, Key::Return);
    assert!(resolved_prefix.effects.commit.is_empty());
    assert_eq!(resolved_prefix.composition, "你好");
    assert_eq!(resolved_prefix.reading, "n");
    assert!(resolved_prefix.phonetic_pending && !resolved_prefix.phonetic_suggestions);
    let edited = key(&mut input, Key::Backspace);
    assert!(!edited.effects.delete_backward);
    assert_eq!(edited.visible_text, "你好");
    assert_eq!(key(&mut input, Key::Return).effects.commit, "你好");

    let mut standard = session(BopomofoLayout::Standard);
    let incomplete = type_touch(&mut standard, "s");
    assert_eq!(incomplete.reading, "ㄋ");
    assert!(!incomplete.phonetic_suggestions);
    let unconfirmed = key(&mut standard, Key::Return);
    assert_eq!(unconfirmed.reading, "ㄋ");
    assert!(unconfirmed.effects.commit.is_empty());
    assert!(!unconfirmed.effects.send_return);
    let cancelled = key(&mut standard, Key::Escape);
    assert!(!cancelled.phonetic_pending);
    assert!(cancelled.effects.discard_composition);
}

#[test]
fn opt_in_does_not_change_legacy_physical_or_unfinished_handoff_behavior() {
    let mut input = session(BopomofoLayout::HanyuPinyin);
    for ch in "nihao".chars() {
        let legacy = input.apply(InputOperation::character(ch)).unwrap();
        assert!(!legacy.phonetic_pending && !legacy.phonetic_suggestions);
        assert!(legacy.candidates.is_empty());
    }
    assert_eq!(input.snapshot().reading, "nihao");
    input.apply(InputOperation::Reset).unwrap();
    type_touch(&mut input, "ni3ha");
    let unfinished = input
        .apply(InputOperation::FinishComposition {
            complete_reading: false,
            select_highlighted_candidate: true,
            discard_table_code: true,
        })
        .unwrap();
    assert_eq!(unfinished.effects.commit, "你");
    assert!(!unfinished.phonetic_pending);
    input
        .apply(InputOperation::SetProfile {
            profile: BehaviorProfile::Desktop,
        })
        .unwrap();
    let physical = type_touch(&mut input, "nihao");
    assert_eq!(physical.reading, "nihao");
    assert!(!physical.phonetic_pending && !physical.phonetic_suggestions);
}

#[test]
fn selecting_live_words_preserves_the_nine_ten_handoff() {
    let mut input = session(BopomofoLayout::HanyuPinyin);
    let completed = type_touch(&mut input, "ni3ni3ni3ni3ni3ni3ni3ni3ni3");
    assert_eq!(completed.readings.len(), 9);
    let live = type_touch(&mut input, "nihao");
    assert_eq!(live.readings.len(), 9);
    let selected = input.apply(InputOperation::Select { index: 0 }).unwrap();
    assert_eq!(selected.readings.len(), 9);
    assert_eq!(selected.effects.commit, "你你");
    assert!(selected.composition.ends_with("你好"));
    let finished = key(&mut input, Key::Return);
    assert_eq!(
        selected.effects.commit + &finished.effects.commit,
        "你你你你你你你你你你好"
    );
}

#[test]
fn live_candidate_navigation_keeps_raw_text_until_space_confirms_the_highlight() {
    let mut input = session(BopomofoLayout::HanyuPinyin);
    let mut options = input.snapshot().smart_options;
    options.candidate_selection_keys = Some("1".into());
    input
        .apply(InputOperation::SetSmartOptions { options })
        .unwrap();

    let live = type_touch(&mut input, "nihao");
    assert_eq!(live.displayed_candidates, ["你好"]);
    assert_eq!(
        key(&mut input, Key::PageDown).displayed_candidates,
        ["妳好"]
    );
    assert_eq!(key(&mut input, Key::PageUp).displayed_candidates, ["你好"]);
    assert_eq!(key(&mut input, Key::Down).displayed_candidates, ["妳好"]);
    assert_eq!(key(&mut input, Key::Up).displayed_candidates, ["你好"]);
    assert_eq!(key(&mut input, Key::Down).displayed_candidates, ["妳好"]);

    let blocked = key(&mut input, Key::Right);
    assert!(blocked.effects.beep);
    assert_eq!(blocked.reading, "nihao");
    assert!(blocked.effects.commit.is_empty());
    assert!(blocked.phonetic_suggestions);
    let selected = key(&mut input, Key::Space);
    assert_eq!(selected.composition, "妳好");
    assert!(selected.effects.commit.is_empty());
    assert!(!selected.phonetic_pending);
    assert_eq!(key(&mut input, Key::Return).effects.commit, "妳好");
}

#[test]
fn an_incomplete_reading_does_not_become_an_ordinary_candidate_target() {
    let mut input = session(BopomofoLayout::HanyuPinyin);
    let live = type_touch(&mut input, "ni3hao");
    assert_eq!(live.composition, "你");
    assert_eq!(live.reading, "hao");
    assert!(live.phonetic_suggestions);
    let ordinary = input
        .apply(InputOperation::OpenCandidates { index: 0 })
        .unwrap();
    assert!(ordinary.effects.beep);
    assert_eq!(ordinary.candidates, live.candidates);
    assert!(ordinary.candidate_spans.is_empty());
    assert!(input.apply(InputOperation::SetCursor { index: 0 }).is_err());

    let edited = key(&mut input, Key::Backspace);
    assert_eq!(edited.reading, "ha");
    assert_eq!(edited.composition, "你");
    assert!(edited.phonetic_suggestions);
    assert!(!edited.effects.delete_backward);
    let closed = input.apply(InputOperation::CloseCandidates).unwrap();
    assert!(closed.phonetic_pending && !closed.phonetic_suggestions);
    let cancelled = key(&mut input, Key::Escape);
    assert_eq!(cancelled.composition, "你");
    assert!(!cancelled.phonetic_pending);
    assert!(!cancelled.effects.discard_composition);

    type_touch(&mut input, "qq");
    let incomplete = key(&mut input, Key::Space);
    assert_eq!(incomplete.reading, "qq");
    assert!(incomplete.effects.beep);
    assert!(incomplete.effects.commit.is_empty());
}

#[test]
fn handoff_can_resolve_a_full_suggestion_and_keeps_unmatched_spelling() {
    let mut input = session(BopomofoLayout::HanyuPinyin);
    let finish = InputOperation::FinishComposition {
        complete_reading: true,
        select_highlighted_candidate: false,
        discard_table_code: false,
    };
    type_touch(&mut input, "nihao");
    let converted = input.apply(finish.clone()).unwrap();
    assert_eq!(converted.effects.commit, "你好");
    assert!(!converted.phonetic_pending);

    type_touch(&mut input, "nihaon");
    let unconverted = input.apply(finish).unwrap();
    assert_eq!(unconverted.effects.commit, "nihaon");
    assert!(!unconverted.phonetic_pending);
}

#[test]
fn explicit_literals_and_profile_changes_leave_confirmed_smart_text_intact() {
    let mut input = session(BopomofoLayout::HanyuPinyin);
    type_touch(&mut input, "ni3ha");
    let literal = input
        .apply(InputOperation::DirectText { text: "，".into() })
        .unwrap();
    assert_eq!(literal.composition, "你，");
    assert!(literal.effects.commit.is_empty());
    assert!(!literal.phonetic_pending);

    type_touch(&mut input, "hao");
    let physical = input.apply(InputOperation::character('h')).unwrap();
    assert_eq!(physical.composition, "你，");
    assert_eq!(physical.reading, "h");
    assert!(!physical.phonetic_pending);
    key(&mut input, Key::Backspace);

    type_touch(&mut input, "hao");
    let desktop = input
        .apply(InputOperation::SetProfile {
            profile: BehaviorProfile::Desktop,
        })
        .unwrap();
    assert_eq!(desktop.composition, "你，");
    assert!(!desktop.phonetic_pending && desktop.candidates.is_empty());
    assert!(desktop.effects.commit.is_empty());
}

#[test]
fn live_input_limit_preserves_pending_text_until_it_can_be_edited() {
    let mut input = session(BopomofoLayout::HanyuPinyin);
    let pending = type_touch(&mut input, &"q".repeat(64));
    assert_eq!(pending.reading, "q".repeat(64));
    assert!(!pending.effects.beep);

    let limited = type_touch(&mut input, "n");
    assert!(limited.effects.beep);
    assert_eq!(limited.reading, pending.reading);

    let edited = key(&mut input, Key::Backspace);
    assert_eq!(edited.reading, "q".repeat(63));
    assert!(!edited.effects.delete_backward);
    assert_eq!(
        type_touch(&mut input, "n").reading,
        format!("{}n", "q".repeat(63))
    );
}
