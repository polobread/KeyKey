//! Desktop Smart Mandarin's opt-in continuous phonetic input contract.
//! Copyright (c) 2026 Chui-Ping Cheng. MIT License.

mod support;

use guanyinma::bopomofo::BopomofoLayout;
use guanyinma::{
    BehaviorProfile, InputMethod, InputOperation, InputSession, Key, Modifiers, SessionConfig,
    SessionSnapshot, SmartOptions,
};

fn session(layout: BopomofoLayout, omit_tone: bool) -> InputSession {
    InputSession::open(
        support::model_path(),
        SessionConfig {
            method: InputMethod::Smart,
            profile: BehaviorProfile::Desktop,
            layout,
            smart: SmartOptions {
                omit_tone,
                ..SmartOptions::default()
            },
            ..SessionConfig::default()
        },
    )
    .unwrap()
}

fn type_keys(session: &mut InputSession, text: &str) -> SessionSnapshot {
    for character in text.chars() {
        let response = session.apply(InputOperation::character(character)).unwrap();
        assert!(response.effects.commit.is_empty(), "{character}: {text}");
    }
    session.snapshot()
}

fn key(session: &mut InputSession, key: Key) -> SessionSnapshot {
    session.apply(InputOperation::key(key)).unwrap()
}

#[test]
fn opted_in_desktop_accepts_omitted_and_explicit_tones_on_all_layouts() {
    for (layout, plain, toned) in [
        (BopomofoLayout::Standard, "sucl", "su3cl3"),
        (BopomofoLayout::Hsu, "nehw", "nefhwf"),
        (BopomofoLayout::ETen, "nehz", "ne3hz3"),
        (BopomofoLayout::ETen26, "nehz", "nejhzj"),
        (BopomofoLayout::HanyuPinyin, "nihao", "ni3hao3"),
    ] {
        let mut session = session(layout, true);
        for keys in [plain, toned] {
            let shown = type_keys(&mut session, keys);
            assert_eq!(shown.visible_text, "你好", "{layout:?} {keys}");
            assert_eq!(shown.cursor, 2, "{layout:?} {keys}");
            assert!(shown.displayed_candidates.is_empty(), "{layout:?} {keys}");
            assert_eq!(
                key(&mut session, Key::Return).effects.commit,
                "你好",
                "{layout:?} {keys}"
            );
        }
    }
}

#[test]
fn desktop_uses_native_selection_and_inserts_at_the_edited_caret() {
    let mut session = session(BopomofoLayout::Standard, true);
    type_keys(&mut session, "sucl");
    let opened = key(&mut session, Key::Space);
    assert!(!opened.displayed_candidates.is_empty());
    assert!(!opened.candidate_spans.is_empty());
    assert!(!opened.phonetic_pending);
    key(&mut session, Key::Escape);

    assert_eq!(key(&mut session, Key::Home).cursor, 0);
    let shown = type_keys(&mut session, "5j/");
    assert_eq!(shown.visible_text, "中你好");
    assert_eq!(shown.cursor, 1);
    let explicit = key(&mut session, Key::Space);
    assert_eq!(explicit.visible_text, "中你好");
    assert!(!explicit.phonetic_pending);
    assert_eq!(key(&mut session, Key::Return).effects.commit, "中你好");
}

#[test]
fn pending_desktop_reading_respects_backspace_escape_and_setting_changes() {
    let mut session = session(BopomofoLayout::Standard, true);
    type_keys(&mut session, "sucls");
    let rejected = key(&mut session, Key::Return);
    assert!(rejected.effects.beep);
    assert!(rejected.effects.commit.is_empty());
    assert!(rejected.visible_text.ends_with('ㄋ'));
    assert_eq!(key(&mut session, Key::Backspace).visible_text, "你好");

    type_keys(&mut session, "sucl");
    let toggled = session
        .apply(InputOperation::SetSmartOptions {
            options: SmartOptions::default(),
        })
        .unwrap();
    assert!(!toggled.smart_options.omit_tone);
    assert!(!toggled.effects.commit.is_empty());
    assert!(toggled.visible_text.is_empty());
    assert_eq!(type_keys(&mut session, "su").visible_text, "ㄋㄧ");

    let mut cleared = session;
    cleared.apply(InputOperation::Reset).unwrap();
    cleared
        .apply(InputOperation::SetSmartOptions {
            options: SmartOptions {
                omit_tone: true,
                clear_composing_with_escape: true,
                ..SmartOptions::default()
            },
        })
        .unwrap();
    type_keys(&mut cleared, "su3cl");
    let escaped = key(&mut cleared, Key::Escape);
    assert!(escaped.effects.discard_composition);
    assert!(escaped.visible_text.is_empty());
}

#[test]
fn opt_in_preserves_shortcuts_and_delegates_a_tone_without_pending_readings() {
    let mut session = session(BopomofoLayout::Standard, true);
    let lone = session.apply(InputOperation::character('3')).unwrap();
    assert!(!lone.phonetic_pending);
    session.apply(InputOperation::Reset).unwrap();
    type_keys(&mut session, "sucl");
    let shortcut = session
        .apply(InputOperation::Character {
            text: "c".into(),
            modifiers: Modifiers {
                command: true,
                ..Modifiers::default()
            },
        })
        .unwrap();
    assert!(shortcut.effects.commit.is_empty());
    assert_eq!(shortcut.visible_text, "你好");
    assert!(shortcut.phonetic_pending);
    assert_eq!(key(&mut session, Key::Return).effects.commit, "你好");
}

#[test]
fn default_desktop_keeps_explicit_tone_entry_and_normal_smart_composition() {
    let mut session = session(BopomofoLayout::Standard, false);
    let pending = type_keys(&mut session, "su");
    assert_eq!(pending.visible_text, "ㄋㄧ");
    assert!(!pending.phonetic_pending);
    let shown = type_keys(&mut session, "3cl3");
    assert_eq!(shown.composition, "你好");
    assert_eq!(key(&mut session, Key::Return).effects.commit, "你好");
}

#[test]
fn compact_layout_at_the_maximum_buffer_size_keeps_the_entire_sentence() {
    let mut session = session(BopomofoLayout::ETen26, true);
    let options = SmartOptions {
        omit_tone: true,
        max_completed_syllables: 20,
        ..SmartOptions::default()
    };
    session
        .apply(InputOperation::SetSmartOptions { options })
        .unwrap();
    let mut committed = String::new();
    for character in "gxlk".repeat(21).chars() {
        let result = session.apply(InputOperation::character(character)).unwrap();
        assert!(!result.effects.beep, "{character}: {}", result.phonetic);
        committed.push_str(&result.effects.commit);
    }
    assert!(!committed.is_empty());
    committed.push_str(&key(&mut session, Key::Return).effects.commit);
    assert_eq!(committed.chars().count(), 21);
    assert!(committed.chars().all(|c| ('一'..='龯').contains(&c)));
}

#[test]
fn inferred_desktop_text_can_open_native_ctrl_punctuation() {
    let mut input = session(BopomofoLayout::Standard, true);
    let ctrl_one = InputOperation::Character {
        text: "1".into(),
        modifiers: Modifiers {
            control: true,
            ..Modifiers::default()
        },
    };
    type_keys(&mut input, "sucls");
    let incomplete = input.apply(ctrl_one.clone()).unwrap();
    assert!(incomplete.effects.beep);
    assert!(incomplete.visible_text.ends_with('ㄋ'));
    assert!(incomplete.displayed_candidates.is_empty());
    key(&mut input, Key::Backspace);

    let opened = input.apply(ctrl_one).unwrap();
    assert!(!opened.effects.beep);
    assert!(opened.visible_text.starts_with("你好"));
    assert!(!opened.phonetic_pending);
    assert!(opened
        .candidate_spans
        .iter()
        .any(|candidate| candidate.query == "_punctuation_list"));
}

#[test]
fn omitted_tones_offer_other_tones_and_selection_keeps_their_readings() {
    for chosen in ["完", "玩"] {
        let mut input = session(BopomofoLayout::Standard, true);
        type_keys(&mut input, "fu/ru8ulfms8xuj0");
        let opened = key(&mut input, Key::Down);
        let index = opened
            .candidates
            .iter()
            .position(|text| text == chosen)
            .unwrap_or_else(|| {
                panic!(
                    "{chosen} missing from omitted-tone candidates: {:?}",
                    opened.candidates
                )
            });
        let query = opened.candidate_spans[index].query.clone();
        assert!(opened.candidates.iter().any(|text| text == "完"));
        assert!(opened.candidates.iter().any(|text| text == "玩"));
        input
            .apply(InputOperation::Page {
                delta: (index / opened.page_size) as i32,
            })
            .unwrap();
        let selected = input
            .apply(InputOperation::Select {
                index: index % opened.page_size,
            })
            .unwrap();
        assert_eq!(selected.visible_text, format!("請假要去哪裡{chosen}"));
        assert_eq!(selected.readings[6], query);
        assert!(selected.displayed_candidates.is_empty());
        key(&mut input, Key::End);
        type_keys(&mut input, "sk");
        assert_eq!(
            key(&mut input, Key::Return).effects.commit,
            format!("請假要去哪裡{chosen}呢")
        );
    }
}

#[test]
fn omitted_tone_choices_survive_native_navigation_but_explicit_tones_stay_constrained() {
    let mut input = session(BopomofoLayout::HanyuPinyin, true);
    type_keys(&mut input, "wan");
    key(&mut input, Key::Left);
    let opened = input
        .apply(InputOperation::OpenCandidates { index: 0 })
        .unwrap();
    assert!(opened.candidates.iter().any(|text| text == "完"));
    assert!(opened.candidates.iter().any(|text| text == "玩"));
    key(&mut input, Key::Escape);
    key(&mut input, Key::End);
    key(&mut input, Key::Backspace);
    type_keys(&mut input, "wan1");
    let explicit = key(&mut input, Key::Down);
    assert!(!explicit
        .candidates
        .iter()
        .any(|text| text == "完" || text == "玩"));
}

#[test]
fn omitted_tone_choices_follow_whole_word_shifts_and_mid_sentence_targets() {
    let mut input = session(BopomofoLayout::Standard, true);
    let mut committed = String::new();
    for character in "fu/ru8ulfms8xuj0skfmc91u0".chars() {
        let shown = input.apply(InputOperation::character(character)).unwrap();
        committed.push_str(&shown.effects.commit);
    }
    assert_eq!(committed, "請假");
    // The seventh syllable becomes index four after the two-syllable shift.
    let opened = input
        .apply(InputOperation::OpenCandidates { index: 4 })
        .unwrap();
    let index = opened
        .candidates
        .iter()
        .position(|text| text == "完" || text == "玩")
        .unwrap();
    let chosen = opened.candidates[index].clone();
    input
        .apply(InputOperation::Page {
            delta: (index / opened.page_size) as i32,
        })
        .unwrap();
    let selected = input
        .apply(InputOperation::Select {
            index: index % opened.page_size,
        })
        .unwrap();
    assert_eq!(
        selected.visible_text.chars().nth(4).unwrap().to_string(),
        chosen
    );
    assert_eq!(selected.visible_text.chars().count(), 9);
    key(&mut input, Key::End);
    committed.push_str(&key(&mut input, Key::Return).effects.commit);
    assert_eq!(committed.chars().count(), 11);
}

#[test]
fn cross_tone_candidates_respect_font_filters_and_disabled_omission() {
    let mut input = InputSession::open_with_candidate_filter(
        support::model_path(),
        SessionConfig {
            method: InputMethod::Smart,
            smart: SmartOptions {
                omit_tone: true,
                ..SmartOptions::default()
            },
            ..SessionConfig::default()
        },
        guanyinma::CandidateFilter::new(|text| text != "玩"),
    )
    .unwrap();
    type_keys(&mut input, "j0");
    let opened = key(&mut input, Key::Down);
    assert!(opened.candidates.iter().any(|text| text == "完"));
    assert!(!opened.candidates.iter().any(|text| text == "玩"));

    let mut explicit = session(BopomofoLayout::Standard, false);
    type_keys(&mut explicit, "j0");
    key(&mut explicit, Key::Space);
    let opened = key(&mut explicit, Key::Down);
    assert!(!opened
        .candidates
        .iter()
        .any(|text| text == "完" || text == "玩"));
}

#[test]
fn cross_tone_selection_preserves_a_chosen_neighbor_and_learns_the_new_reading() {
    let mut input = session(BopomofoLayout::Standard, true);
    input
        .apply(InputOperation::SetLearningOptions {
            options: guanyinma::LearningOptions {
                candidate_overrides: true,
                bigrams: true,
                ..guanyinma::LearningOptions::default()
            },
        })
        .unwrap();
    type_keys(&mut input, "sucl");
    let opened = key(&mut input, Key::Down);
    let first = opened
        .candidates
        .iter()
        .position(|text| text == "你好")
        .unwrap();
    input
        .apply(InputOperation::Select { index: first })
        .unwrap();
    key(&mut input, Key::End);
    type_keys(&mut input, "j0");
    let opened = key(&mut input, Key::Down);
    let index = opened
        .candidates
        .iter()
        .position(|text| text == "玩")
        .unwrap();
    let query = opened.candidate_spans[index].query.clone();
    input
        .apply(InputOperation::Page {
            delta: (index / opened.page_size) as i32,
        })
        .unwrap();
    let selected = input
        .apply(InputOperation::Select {
            index: index % opened.page_size,
        })
        .unwrap();
    assert_eq!(selected.visible_text, "你好玩");
    let data = input.user_data().unwrap();
    assert!(data
        .bigrams
        .iter()
        .any(|row| row.current == "玩" && row.qstring.ends_with(&query)));
    let reopened = key(&mut input, Key::Down);
    assert_eq!(
        reopened
            .candidate_spans
            .iter()
            .find(|candidate| candidate.span == 1)
            .unwrap()
            .text,
        "玩"
    );
    key(&mut input, Key::Escape);
    key(&mut input, Key::End);
    assert_eq!(key(&mut input, Key::Return).effects.commit, "你好玩");
}
