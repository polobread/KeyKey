//! Public Smart Mandarin behavior with the unchanged shared KeyKey database.
//!
//! Expected text, candidate prefixes/counts and the long composition checkpoints
//! were independently observed using the macOS OVIMSmartMandarin + Manjusri
//! source. These ordinary tests never load frozen migration-baseline fixtures.

mod support;

use guanyinma::{
    BehaviorOptions, BehaviorProfile, Effects, InputMethod, InputOperation, InputSession, Key,
    Modifiers, SessionConfig, SessionSnapshot, SmartOptions,
};
use std::path::PathBuf;

fn model() -> PathBuf {
    support::model_path()
}

fn session(options: SmartOptions) -> InputSession {
    InputSession::open(
        model(),
        SessionConfig {
            method: InputMethod::Smart,
            smart: options,
            ..SessionConfig::default()
        },
    )
    .unwrap()
}

fn options() -> SmartOptions {
    SmartOptions {
        // Controlled page size matches the independently executed Mac oracle.
        candidate_selection_keys: Some("12345678".into()),
        space_opens_candidates: false,
        ..SmartOptions::default()
    }
}

fn type_keys(input: &mut InputSession, text: &str, committed: &mut String) -> SessionSnapshot {
    let mut snapshot = input.snapshot();
    for character in text.chars() {
        snapshot = input.apply(InputOperation::character(character)).unwrap();
        committed.push_str(&snapshot.effects.commit);
    }
    snapshot
}

fn key(input: &mut InputSession, key: Key) -> SessionSnapshot {
    input.apply(InputOperation::key(key)).unwrap()
}

fn open(input: &mut InputSession, index: usize) -> SessionSnapshot {
    input
        .apply(InputOperation::OpenCandidates { index })
        .unwrap()
}

fn select_text(input: &mut InputSession, text: &str) -> SessionSnapshot {
    let snapshot = input.snapshot();
    let index = snapshot
        .candidates
        .iter()
        .position(|candidate| candidate == text)
        .unwrap_or_else(|| panic!("missing candidate {text}"));
    let target_page = index / snapshot.page_size;
    if target_page != snapshot.page {
        input
            .apply(InputOperation::Page {
                delta: target_page as i32 - snapshot.page as i32,
            })
            .unwrap();
    }
    input
        .apply(InputOperation::Select {
            index: index % snapshot.page_size,
        })
        .unwrap()
}

#[test]
fn macos_single_reading_keeps_the_full_candidate_order_and_page_views() {
    let mut input = session(options());
    let typed = type_keys(&mut input, "g4", &mut String::new());
    assert_eq!(typed.composition, "是");
    assert_eq!(typed.cursor, 1);
    assert!(typed.reading.is_empty());
    assert!(typed.candidates.is_empty());
    let candidates = open(&mut input, 0);
    assert_eq!(candidates.candidates.len(), 368);
    assert_eq!(
        &candidates.candidates[..20],
        [
            "是", "事", "市", "式", "視", "世", "示", "士", "試", "識", "勢", "適", "室", "釋",
            "使", "飾", "氏", "始", "逝", "誓",
        ]
    );
    assert_eq!(candidates.page_size, 8);
    assert_eq!(candidates.displayed_candidates, candidates.candidates[..8]);
    let next = key(&mut input, Key::PageDown);
    assert_eq!(next.page, 1);
    assert_eq!(next.candidates, candidates.candidates);
    assert_eq!(next.displayed_candidates, candidates.candidates[8..16]);
    let selected = input.apply(InputOperation::Select { index: 0 }).unwrap();
    assert_eq!(selected.composition, "試");
    assert!(selected.effects.commit.is_empty());
    assert!(selected.candidates.is_empty());
    assert_eq!(key(&mut input, Key::Return).effects.commit, "試");
}

#[test]
fn longer_spans_precede_single_character_candidates_and_selection_keeps_the_tail() {
    let mut input = session(options());
    assert_eq!(
        type_keys(&mut input, "su3cl3", &mut String::new()).composition,
        "你好"
    );
    let candidates = open(&mut input, 0);
    assert_eq!(candidates.candidates.len(), 87);
    assert_eq!(
        &candidates.candidates[..7],
        ["你好", "妳好", "你", "妳", "擬", "旎", "薿"]
    );
    let selected = select_text(&mut input, "妳");
    assert_eq!(selected.composition, "妳好");
    assert_eq!(selected.cursor, 1);
    assert_eq!(selected.reading_cursor, 1);
    assert_eq!(selected.readings.len(), 2);
    assert!(selected.effects.commit.is_empty());
    assert!(selected.candidates.is_empty());
    key(&mut input, Key::End);
    assert_eq!(key(&mut input, Key::Return).effects.commit, "妳好");

    type_keys(&mut input, "su3cl3", &mut String::new());
    open(&mut input, 0);
    let selected_word = select_text(&mut input, "妳好");
    assert_eq!(selected_word.composition, "妳好");
    assert_eq!(selected_word.cursor, 2);
    assert_eq!(selected_word.readings.len(), 2);
    assert!(selected_word.effects.commit.is_empty());
}

#[test]
fn phrase_candidates_follow_the_manjusri_span_order() {
    let mut input = session(options());
    assert_eq!(
        type_keys(&mut input, "fu/3ru84", &mut String::new()).composition,
        "請假"
    );
    let snapshot = open(&mut input, 0);
    assert_eq!(snapshot.candidates.len(), 29);
    assert_eq!(&snapshot.candidates[..5], ["請假", "請", "頃", "廎", "苘"]);
    let selected = select_text(&mut input, "請假");
    assert_eq!(selected.composition, "請假");
    assert_eq!(selected.cursor, 2);
    assert!(selected.effects.commit.is_empty());
}

#[test]
fn insertion_and_deletion_use_the_reading_cursor_and_rebuild_the_sentence() {
    let mut input = session(options());
    type_keys(&mut input, "su3cl3", &mut String::new());
    assert_eq!(key(&mut input, Key::Left).cursor, 1);
    let inserted = type_keys(&mut input, "su3", &mut String::new());
    assert_eq!(inserted.composition, "你你好");
    assert_eq!(inserted.cursor, 2);
    assert_eq!(inserted.readings.len(), 3);
    key(&mut input, Key::End);
    assert_eq!(key(&mut input, Key::Return).effects.commit, "你你好");

    type_keys(&mut input, "su3cl3", &mut String::new());
    key(&mut input, Key::Left);
    let deleted = key(&mut input, Key::Backspace);
    assert_eq!(deleted.composition, "好");
    assert_eq!(deleted.cursor, 0);
    assert_eq!(deleted.readings.len(), 1);
    assert!(deleted.effects.commit.is_empty());
    key(&mut input, Key::End);
    assert_eq!(key(&mut input, Key::Return).effects.commit, "好");
}

#[test]
fn return_to_end_selection_is_a_behavior_choice_for_subsequent_input() {
    let mut input = session(SmartOptions {
        selection_returns_to_end: true,
        ..options()
    });
    type_keys(&mut input, "su3cl3", &mut String::new());
    open(&mut input, 0);
    let selected = select_text(&mut input, "妳");
    assert_eq!(selected.composition, "妳好");
    assert_eq!(selected.cursor, 2);
    assert_eq!(selected.reading_cursor, 2);
    let next = type_keys(&mut input, "su3", &mut String::new());
    assert_eq!(next.composition, "妳好你");
    assert_eq!(next.cursor, 3);
}

const LONG_SENTENCE: &str = "請假要去哪裡玩呢去海邊因為那裡有比基尼";
const SYLLABLES: [&str; 19] = [
    "fu/3", "ru84", "ul4", "fm4", "s83", "xu3", "j06", "sk7", "fm4", "c93", "1u0 ", "up ", "jo4",
    "s84", "xu3", "u.3", "1u3", "ru ", "su6",
];

fn select_wan(input: &mut InputSession) {
    let candidates = open(input, 6);
    // Native Manjusri includes a phrase overlapping the selected reading.
    assert_eq!(&candidates.candidates[..3], ["理完", "完", "玩"]);
    assert_eq!(candidates.candidates.len(), 76);
    let chosen = select_text(input, "玩");
    assert_eq!(chosen.composition, "請假要去哪裡玩");
    assert!(chosen.effects.commit.is_empty());
    key(input, Key::End);
}

#[test]
fn ten_completed_readings_shift_a_whole_phrase_at_eleven_without_losing_text() {
    let mut input = session(options());
    let mut committed = String::new();
    let mut result = input.snapshot();
    for (index, syllable) in SYLLABLES.iter().enumerate() {
        result = type_keys(&mut input, syllable, &mut committed);
        if index == 6 {
            select_wan(&mut input);
            result = input.snapshot();
        }
        if index == 9 {
            assert!(committed.is_empty());
            assert_eq!(result.composition, "請假要去哪裡玩呢去海");
            assert_eq!(result.readings.len(), 10);
        }
        if index == 10 {
            assert_eq!(committed, "請假");
            assert_eq!(result.composition, "要去哪裡玩呢去海邊");
            assert_eq!(result.readings.len(), 9);
        }
        assert!(result.readings.len() <= 10);
    }
    assert_eq!(committed, "請假要去哪裡玩呢去");
    assert_eq!(result.composition, "海邊因為那裡有比基尼");
    assert_eq!(committed.clone() + &result.composition, LONG_SENTENCE);
    committed.push_str(&key(&mut input, Key::Return).effects.commit);
    assert_eq!(committed, LONG_SENTENCE);
    assert_eq!(input.snapshot().effects, Effects::default());
    assert!(key(&mut input, Key::Return).effects.commit.is_empty());
}

#[test]
fn inclusive_ten_reading_limit_shifts_on_tenth_using_the_same_phrase_rule() {
    let mut input = session(SmartOptions {
        max_completed_syllables: 10,
        shift_at_limit: true,
        ..options()
    });
    let mut committed = String::new();
    let mut result = input.snapshot();
    for (index, syllable) in SYLLABLES.iter().enumerate() {
        result = type_keys(&mut input, syllable, &mut committed);
        if index == 6 {
            select_wan(&mut input);
            result = input.snapshot();
        }
        if index == 8 {
            assert!(committed.is_empty());
            assert_eq!(result.readings.len(), 9);
        }
        if index == 9 {
            assert_eq!(committed, "請假");
            assert_eq!(result.composition, "要去哪裡玩呢去海");
            assert_eq!(result.readings.len(), 8);
        }
        assert!(result.readings.len() <= 9);
    }
    assert_eq!(committed.clone() + &result.composition, LONG_SENTENCE);
    committed.push_str(&key(&mut input, Key::Return).effects.commit);
    assert_eq!(committed, LONG_SENTENCE);
}

#[test]
fn pending_reading_edits_and_mode_switches_preserve_exact_visible_text_once() {
    let mut input = session(options());
    type_keys(&mut input, "su3cl", &mut String::new());
    let before = input.snapshot();
    assert_eq!(before.composition, "你");
    assert_eq!(before.reading, "ㄏㄠ");
    assert_eq!(before.visible_text, "你ㄏㄠ");
    let erased = key(&mut input, Key::Backspace);
    assert_eq!(erased.composition, "你");
    assert_eq!(erased.reading, "ㄏ");
    let switched = input.apply(InputOperation::ToggleEnglish).unwrap();
    assert!(switched.english);
    assert_eq!(switched.effects.commit, "你ㄏ");
    assert!(switched.composition.is_empty());
    assert!(switched.reading.is_empty());
    assert!(switched.visible_text.is_empty());
    let repeated = input
        .apply(InputOperation::SetEnglish { enabled: true })
        .unwrap();
    assert!(repeated.effects.commit.is_empty());
    assert_eq!(input.snapshot().effects, Effects::default());
}

#[test]
fn common_caps_and_keypad_behaviors_apply_to_smart_mandarin_too() {
    let mut input = InputSession::open(
        model(),
        SessionConfig {
            method: InputMethod::Smart,
            smart: options(),
            behaviors: BehaviorOptions {
                ignore_caps_lock_in_chinese: true,
                ..BehaviorOptions::default()
            },
            ..SessionConfig::default()
        },
    )
    .unwrap();
    for character in "SU3CL3".chars() {
        input
            .apply(InputOperation::Character {
                text: character.to_string(),
                modifiers: Modifiers {
                    caps_lock: true,
                    num_lock: true,
                    ..Modifiers::default()
                },
            })
            .unwrap();
    }
    assert_eq!(input.snapshot().composition, "你好");
    open(&mut input, 0);
    let number = input
        .apply(InputOperation::Character {
            text: "2".into(),
            modifiers: Modifiers {
                keypad: true,
                num_lock: true,
                ..Modifiers::default()
            },
        })
        .unwrap();
    assert_eq!(number.effects.commit, "你好2");
    assert!(number.candidates.is_empty());
    assert!(number.visible_text.is_empty());
}

#[test]
fn invalid_candidate_and_cursor_operations_leave_smart_state_unchanged() {
    let mut input = session(options());
    type_keys(&mut input, "su3cl3", &mut String::new());
    open(&mut input, 0);
    let before = serde_json::to_value(input.snapshot()).unwrap();
    for operation in [
        InputOperation::Select { index: usize::MAX },
        InputOperation::SetCursor { index: usize::MAX },
        InputOperation::OpenCandidates { index: usize::MAX },
    ] {
        assert!(input.apply(operation).is_err());
        assert_eq!(serde_json::to_value(input.snapshot()).unwrap(), before);
    }
}

#[test]
fn space_and_punctuation_follow_mac_key_priority_and_runtime_options() {
    let mut input = session(options());
    type_keys(&mut input, "su3", &mut String::new());
    let space = key(&mut input, Key::Space);
    assert_eq!(space.composition, "你 ");
    assert!(space.effects.commit.is_empty());
    let next = type_keys(&mut input, "cl3", &mut String::new());
    assert_eq!(next.composition, "你 好");
    assert_eq!(key(&mut input, Key::Return).effects.commit, "你 好");

    type_keys(&mut input, "su3cl3:", &mut String::new());
    assert_eq!(input.snapshot().composition, "你好：");
    assert_eq!(
        type_keys(&mut input, "g4", &mut String::new()).composition,
        "你好：是"
    );
    assert_eq!(key(&mut input, Key::Return).effects.commit, "你好：是");

    type_keys(&mut input, "su3cl3,", &mut String::new());
    let phonetic_comma = input.snapshot();
    // An unshifted comma is the Standard-layout ㄝ reading key.
    assert_eq!(phonetic_comma.composition, "你好");
    assert_eq!(phonetic_comma.reading, "ㄝ");
    input.apply(InputOperation::Reset).unwrap();
    type_keys(&mut input, "su3", &mut String::new());
    let changed = input
        .apply(InputOperation::SetSmartOptions {
            options: SmartOptions {
                space_opens_candidates: true,
                ..options()
            },
        })
        .unwrap();
    assert_eq!(changed.composition, "你");
    assert!(changed.effects.commit.is_empty());
    let panel = key(&mut input, Key::Space);
    assert_eq!(panel.candidates.len(), 85);
    assert_eq!(&panel.candidates[..3], ["你", "妳", "擬"]);
    let confirmed = key(&mut input, Key::Return);
    assert_eq!(confirmed.composition, "你");
    assert!(confirmed.effects.commit.is_empty());
    assert!(confirmed.candidates.is_empty());
    assert_eq!(key(&mut input, Key::Return).effects.commit, "你");
}

#[test]
fn candidate_end_targeting_uses_only_nodes_ending_at_the_target() {
    let mut input = session(SmartOptions {
        candidate_cursor_at_end: true,
        ..options()
    });
    type_keys(&mut input, "su3cl3", &mut String::new());
    let candidates = open(&mut input, 0);
    assert_eq!(candidates.cursor, 1);
    assert_eq!(candidates.candidates.len(), 85);
    assert_eq!(&candidates.candidates[..3], ["你", "妳", "擬"]);
    assert!(!candidates.candidates.iter().any(|text| text == "你好"));
    let selected = select_text(&mut input, "妳");
    assert_eq!(selected.composition, "妳好");
    assert_eq!(selected.cursor, 1);
    assert!(selected.effects.commit.is_empty());
}

#[test]
fn closing_and_reopening_candidates_does_not_rewrite_or_commit_composition() {
    let mut input = session(options());
    type_keys(&mut input, "su3cl3", &mut String::new());
    let panel = open(&mut input, 0);
    let closed = input.apply(InputOperation::CloseCandidates).unwrap();
    assert_eq!(closed.composition, panel.composition);
    assert_eq!(closed.readings, panel.readings);
    assert_eq!(closed.cursor, panel.cursor);
    assert!(closed.candidates.is_empty());
    assert!(closed.candidate_spans.is_empty());
    assert!(closed.effects.commit.is_empty());
    let repeated = input.apply(InputOperation::CloseCandidates).unwrap();
    assert_eq!(repeated.composition, "你好");
    assert!(repeated.effects.commit.is_empty());
    let reopened = open(&mut input, 0);
    assert_eq!(reopened.candidates, panel.candidates);
    assert_eq!(reopened.candidate_spans, panel.candidate_spans);
    assert_eq!(reopened.composition, panel.composition);
    assert!(reopened.effects.commit.is_empty());
}

#[test]
fn touch_host_effects_and_desktop_pass_through_are_explicit_interaction_choices() {
    for profile in [BehaviorProfile::Desktop, BehaviorProfile::Touch] {
        let mut input = InputSession::open(
            model(),
            SessionConfig {
                method: InputMethod::Smart,
                profile,
                smart: options(),
                ..SessionConfig::default()
            },
        )
        .unwrap();
        let touch = profile == BehaviorProfile::Touch;
        let backspace = key(&mut input, Key::Backspace);
        assert_eq!(backspace.effects.handled, touch);
        assert_eq!(backspace.effects.delete_backward, touch);
        assert!(!backspace.effects.send_return);
        assert!(backspace.effects.commit.is_empty());
        assert_eq!(input.snapshot().effects, Effects::default());
        let enter = key(&mut input, Key::Return);
        assert_eq!(enter.effects.handled, touch);
        assert_eq!(enter.effects.send_return, touch);
        assert!(!enter.effects.delete_backward);
        assert!(enter.effects.commit.is_empty());
        assert_eq!(input.snapshot().effects, Effects::default());
    }
}

#[test]
fn unsupported_composition_limits_fail_without_changing_active_state() {
    for limit in [0, 9, 21, usize::MAX] {
        assert!(InputSession::open(
            model(),
            SessionConfig {
                method: InputMethod::Smart,
                smart: SmartOptions {
                    max_completed_syllables: limit,
                    ..options()
                },
                ..SessionConfig::default()
            },
        )
        .is_err());
    }
    let mut input = session(options());
    type_keys(&mut input, "su3cl3", &mut String::new());
    open(&mut input, 0);
    let before = serde_json::to_value(input.snapshot()).unwrap();
    let invalid = input.apply(InputOperation::SetSmartOptions {
        options: SmartOptions {
            max_completed_syllables: 21,
            ..options()
        },
    });
    assert!(invalid.is_err());
    assert_eq!(serde_json::to_value(input.snapshot()).unwrap(), before);
}

#[test]
fn a_twenty_reading_limit_retains_twenty_and_shifts_only_after_the_next_completion() {
    let mut input = session(SmartOptions {
        max_completed_syllables: 20,
        ..options()
    });
    let mut committed = String::new();
    for index in 0..20 {
        let current = type_keys(&mut input, "su3", &mut committed);
        assert_eq!(current.readings.len(), index + 1);
        assert!(committed.is_empty());
    }
    let before = input.snapshot();
    assert_eq!(before.composition, "你".repeat(20));
    let next = type_keys(&mut input, "su3", &mut committed);
    assert!(!committed.is_empty());
    assert!(next.readings.len() <= 20);
    assert_eq!(committed + &next.composition, "你".repeat(21));
}

#[test]
fn modified_alphabetic_candidate_keys_preserve_the_active_panel() {
    let mut input = session(SmartOptions {
        candidate_selection_keys: Some("asdfghjk".into()),
        ..options()
    });
    type_keys(&mut input, "g4", &mut String::new());
    open(&mut input, 0);
    key(&mut input, Key::PageDown);
    input
        .apply(InputOperation::MoveHighlight { delta: 3 })
        .unwrap();
    let active = input.snapshot();
    assert_eq!(active.page, 1);
    assert_eq!(active.highlight, Some(3));
    let before = serde_json::to_value(&active).unwrap();

    // Caps Lock + Shift can deliver a lowercase selection letter. Its Shift
    // modifier must still distinguish it from the configured bare key.
    let shifted_letter = input
        .apply(InputOperation::Character {
            text: "a".into(),
            modifiers: Modifiers {
                shift: true,
                caps_lock: true,
                ..Modifiers::default()
            },
        })
        .unwrap();
    assert!(shifted_letter.effects.handled);
    assert!(shifted_letter.effects.beep);
    assert!(shifted_letter.effects.commit.is_empty());
    assert_eq!(serde_json::to_value(input.snapshot()).unwrap(), before);

    let shifted_escape = input
        .apply(InputOperation::Key {
            key: Key::Escape,
            modifiers: Modifiers {
                shift: true,
                ..Modifiers::default()
            },
        })
        .unwrap();
    assert!(shifted_escape.effects.handled);
    assert!(shifted_escape.effects.beep);
    assert!(shifted_escape.effects.commit.is_empty());
    assert_eq!(serde_json::to_value(input.snapshot()).unwrap(), before);

    let selected = input.apply(InputOperation::character('a')).unwrap();
    assert_eq!(
        selected.composition,
        active.candidates[active.page * active.page_size]
    );
    assert!(selected.candidates.is_empty());
    assert!(!selected.effects.beep);
    assert!(selected.effects.commit.is_empty());

    let reopened = open(&mut input, 0);
    assert!(!reopened.candidates.is_empty());
    let canceled = key(&mut input, Key::Escape);
    assert_eq!(canceled.composition, selected.composition);
    assert!(canceled.candidates.is_empty());
    assert!(!canceled.effects.beep);
    assert!(canceled.effects.commit.is_empty());
}

#[test]
fn full_width_smart_commits_chinese_and_ascii_once_across_mode_flushes() {
    let mut input = session(options());
    // The frontend recognizes its physical shortcut and sends semantic state.
    let wide = input.apply(InputOperation::ToggleFullWidth).unwrap();
    assert!(wide.full_width);
    assert!(wide.effects.commit.is_empty());

    type_keys(&mut input, "su3", &mut String::new());
    let literal = input
        .apply(InputOperation::Character {
            text: "A".into(),
            modifiers: Modifiers {
                shift: true,
                ..Modifiers::default()
            },
        })
        .unwrap();
    assert_eq!(literal.composition, "你A");
    assert!(literal.effects.commit.is_empty());

    let english = input.apply(InputOperation::ToggleEnglish).unwrap();
    assert!(english.english);
    assert!(english.full_width);
    assert_eq!(english.effects.commit, "你Ａ");
    assert!(english.visible_text.is_empty());
    assert_eq!(input.snapshot().effects, Effects::default());

    let repeated_mode = input
        .apply(InputOperation::SetEnglish { enabled: true })
        .unwrap();
    assert!(repeated_mode.effects.commit.is_empty());
    assert_eq!(
        input
            .apply(InputOperation::character('b'))
            .unwrap()
            .effects
            .commit,
        "ｂ"
    );
    assert_eq!(input.snapshot().effects, Effects::default());

    let chinese = input
        .apply(InputOperation::SetEnglish { enabled: false })
        .unwrap();
    assert!(chinese.effects.commit.is_empty());
    assert!(chinese.full_width);
    type_keys(&mut input, "cl3", &mut String::new());
    assert_eq!(key(&mut input, Key::Return).effects.commit, "好");
    assert!(key(&mut input, Key::Return).effects.commit.is_empty());
    assert_eq!(input.snapshot().effects, Effects::default());

    let empty_literal = input
        .apply(InputOperation::Character {
            text: "Z".into(),
            modifiers: Modifiers {
                shift: true,
                ..Modifiers::default()
            },
        })
        .unwrap();
    assert_eq!(empty_literal.effects.commit, "Ｚ");
    assert!(empty_literal.visible_text.is_empty());
    assert_eq!(input.snapshot().effects, Effects::default());
}

#[test]
fn bigram_behavior_rewalks_active_text_without_flushing_reading_or_manual_selection() {
    // Independently checked real-model witness: context disambiguates 哪/那.
    let keys = "fu/3ru84ul4fm4s83";
    let mut input = session(options());
    let original = type_keys(&mut input, keys, &mut String::new());
    assert_eq!(original.composition, "請假要去哪");
    input.apply(InputOperation::SetCursor { index: 2 }).unwrap();
    type_keys(&mut input, "su", &mut String::new());
    let pending = input.snapshot();
    assert_eq!(pending.visible_text, "請假ㄋㄧ要去哪");
    assert_eq!(pending.reading_cursor, 2);

    let disabled = SmartOptions {
        use_bigrams: false,
        ..options()
    };
    let without_context = input
        .apply(InputOperation::SetSmartOptions {
            options: disabled.clone(),
        })
        .unwrap();
    assert_eq!(without_context.composition, "請假要去那");
    assert_eq!(without_context.visible_text, "請假ㄋㄧ要去那");
    assert_eq!(without_context.reading, pending.reading);
    assert_eq!(without_context.readings, pending.readings);
    assert_eq!(without_context.reading_cursor, pending.reading_cursor);
    assert!(without_context.effects.commit.is_empty());

    let restored = input
        .apply(InputOperation::SetSmartOptions { options: options() })
        .unwrap();
    assert_eq!(restored.visible_text, pending.visible_text);
    assert_eq!(restored.reading_cursor, pending.reading_cursor);
    assert!(restored.effects.commit.is_empty());
    assert_eq!(input.snapshot().effects, Effects::default());

    let mut initially_disabled = session(disabled.clone());
    assert_eq!(
        type_keys(&mut initially_disabled, keys, &mut String::new()).composition,
        "請假要去那"
    );
    open(&mut initially_disabled, 4);
    let chosen = select_text(&mut initially_disabled, "哪");
    assert_eq!(chosen.composition, "請假要去哪");
    assert!(chosen.effects.commit.is_empty());
    for next_options in [options(), disabled] {
        let changed = initially_disabled
            .apply(InputOperation::SetSmartOptions {
                options: next_options,
            })
            .unwrap();
        assert_eq!(changed.composition, "請假要去哪");
        assert_eq!(changed.readings, chosen.readings);
        assert_eq!(changed.reading_cursor, chosen.reading_cursor);
        assert!(changed.effects.commit.is_empty());
    }
}
