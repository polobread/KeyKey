//! Focused contracts derived from macOS OVIMSmartMandarin, without migration fixtures.
//! Copyright (c) 2026 Chui-Ping Cheng. MIT License.
mod support;

use guanyinma::bopomofo::BopomofoLayout;
use guanyinma::smart::{SmartOptions, SmartState};
use guanyinma::{Effects, Key, ModelDatabase, Modifiers};

fn database() -> ModelDatabase {
    ModelDatabase::open(support::model_path()).unwrap()
}
fn effects() -> Effects {
    Effects {
        handled: true,
        ..Effects::default()
    }
}
fn type_keys(state: &mut SmartState, db: &ModelDatabase, keys: &str, options: &SmartOptions) {
    for character in keys.chars() {
        state
            .character(db, character, Modifiers::default(), options, &mut effects())
            .unwrap();
    }
}
fn press(
    state: &mut SmartState,
    db: &ModelDatabase,
    key: Key,
    shift: bool,
    options: &SmartOptions,
) -> Effects {
    let mut result = effects();
    state
        .key(
            db,
            key,
            Modifiers {
                shift,
                ..Modifiers::default()
            },
            options,
            &mut result,
        )
        .unwrap();
    result
}

#[test]
fn shift_phrase_marking_uses_native_confirmation_and_cancel_rules() {
    let db = database();
    let options = SmartOptions::default();
    let mut state = SmartState::new(BopomofoLayout::Standard);
    type_keys(&mut state, &db, "su3cl3", &options);
    assert_eq!(state.composition(), "你好");
    press(&mut state, &db, Key::Left, true, &options);
    let marked = state.marked_phrase().unwrap();
    assert_eq!((marked.reading_start, marked.reading_span), (1, 1));
    assert_eq!((marked.text_start, marked.text_length), (1, 1));
    assert_eq!(marked.text, "好");
    press(&mut state, &db, Key::Home, true, &options);
    assert_eq!(state.marked_phrase().unwrap().text, "你好");
    assert_eq!(state.reading_cursor(), 0);
    let canceled = press(&mut state, &db, Key::Escape, false, &options);
    assert!(canceled.commit.is_empty() && !canceled.beep);
    assert!(state.marked_phrase().is_none());
    assert_eq!(state.composition(), "你好");
    press(&mut state, &db, Key::Right, true, &options);
    assert_eq!(state.marked_phrase().unwrap().text, "你");
    press(&mut state, &db, Key::Right, false, &options);
    assert_eq!(
        state.reading_cursor(),
        1,
        "first plain arrow cancels without moving again"
    );
    press(&mut state, &db, Key::Right, false, &options);
    assert_eq!(state.reading_cursor(), 2);
    press(&mut state, &db, Key::Left, true, &options);
    let confirmed = press(&mut state, &db, Key::Return, false, &options);
    assert!(confirmed.commit.is_empty() && !confirmed.beep);
    assert!(state.marked_phrase().is_none());
    let request = state.take_marked_phrase_request().unwrap();
    assert_eq!(request.text, "好");
    assert_eq!(request.qstring, state.completed_readings()[1]);
    assert!(state.take_marked_phrase_request().is_none());
    assert_eq!(state.composition(), "你好");
}

#[test]
fn marking_is_bounded_to_six_completed_readings_and_other_keys_restore_anchor() {
    let db = database();
    let options = SmartOptions::default();
    let mut state = SmartState::new(BopomofoLayout::Standard);
    type_keys(&mut state, &db, &"g4".repeat(10), &options);
    press(&mut state, &db, Key::Home, true, &options);
    assert_eq!(state.reading_cursor(), 4);
    assert_eq!(state.marked_phrase().unwrap().reading_span, 6);
    let canceled = press(&mut state, &db, Key::End, true, &options);
    assert!(canceled.beep && state.marked_phrase().is_none());
    assert_eq!(state.reading_cursor(), 10);
    let edge = press(&mut state, &db, Key::Right, true, &options);
    assert!(edge.beep && state.marked_phrase().is_none());
    press(&mut state, &db, Key::Left, true, &options);
    let before = state.completed_readings().len();
    let deleted = press(&mut state, &db, Key::Backspace, false, &options);
    assert!(deleted.beep && state.marked_phrase().is_none());
    assert_eq!(state.completed_readings().len(), before - 1);
    assert_eq!(
        state.reading_cursor(),
        before - 1,
        "delete uses original mark anchor"
    );
}

#[test]
fn shift_ascii_uppercase_is_an_explicit_core_choice_and_caps_space_is_literal() {
    let db = database();
    for enabled in [false, true] {
        let options = SmartOptions {
            shift_always_uppercase: enabled,
            ..SmartOptions::default()
        };
        let mut state = SmartState::new(BopomofoLayout::Standard);
        let mut empty = effects();
        state
            .character(
                &db,
                'a',
                Modifiers {
                    shift: true,
                    ..Modifiers::default()
                },
                &options,
                &mut empty,
            )
            .unwrap();
        assert_eq!(empty.commit, if enabled { "A" } else { "a" });
        type_keys(&mut state, &db, "su3", &options);
        state
            .character(
                &db,
                'a',
                Modifiers {
                    shift: true,
                    ..Modifiers::default()
                },
                &options,
                &mut effects(),
            )
            .unwrap();
        assert_eq!(state.composition(), if enabled { "你A" } else { "你a" });
    }
    let options = SmartOptions::default();
    let mut state = SmartState::new(BopomofoLayout::Standard);
    type_keys(&mut state, &db, "su3", &options);
    let mut literal = effects();
    state
        .key(
            &db,
            Key::Space,
            Modifiers {
                caps_lock: true,
                ..Modifiers::default()
            },
            &options,
            &mut literal,
        )
        .unwrap();
    assert_eq!(state.composition(), "你 ");
    assert!(state.candidates().is_empty() && literal.commit.is_empty() && !literal.beep);
}

#[test]
fn direct_text_replaces_unfinished_reading_and_is_one_native_graph_block() {
    let db = database();
    let options = SmartOptions::default();
    let mut state = SmartState::new(BopomofoLayout::Standard);
    type_keys(&mut state, &db, "su3cl3", &options);
    press(&mut state, &db, Key::Left, false, &options);
    type_keys(&mut state, &db, "g", &options);
    assert!(!state.reading().is_empty());
    let mut inserted = effects();
    state
        .direct_text(&db, "Ａ🙂", &options, &mut inserted)
        .unwrap();
    assert!(inserted.commit.is_empty() && !inserted.beep);
    assert!(state.reading().is_empty());
    assert_eq!(state.composition(), "你Ａ🙂好");
    assert_eq!(
        state.completed_readings().len(),
        3,
        "multi-scalar direct key is a single block"
    );
    assert_eq!(state.reading_cursor(), 2);
    assert_eq!(state.cursor(), 3);
    press(&mut state, &db, Key::Left, true, &options);
    let marked = state.marked_phrase().unwrap();
    assert_eq!((marked.text_start, marked.text_length), (1, 2));
    assert_eq!(marked.text, "Ａ🙂");
    assert_eq!(marked.reading_span, 1);
    assert_eq!(marked.qstring, "_passthru_Ａ🙂 ");
    let confirm = press(&mut state, &db, Key::Return, false, &options);
    assert!(confirm.commit.is_empty());
    let requested = state.take_marked_phrase_request().unwrap();
    assert_eq!(
        requested, marked,
        "trusted internal marks retain actual graph query blocks"
    );
    let before = state.composition();
    let mut rejected = effects();
    state
        .direct_text(&db, "A B", &options, &mut rejected)
        .unwrap();
    assert!(rejected.beep && rejected.commit.is_empty());
    assert_eq!(
        state.composition(),
        before,
        "canonical invalid direct block does not replace composition"
    );
    state.clear();
    type_keys(&mut state, &db, "g", &options);
    let mut empty = effects();
    state.direct_text(&db, "AB", &options, &mut empty).unwrap();
    assert_eq!(empty.commit, "AB");
    assert!(state.is_empty());
}

#[test]
fn marking_confirmation_does_not_complete_or_drop_a_new_unfinished_reading() {
    let db = database();
    let options = SmartOptions::default();
    let mut state = SmartState::new(BopomofoLayout::Standard);
    let empty = press(&mut state, &db, Key::Left, true, &options);
    assert!(!empty.handled && !empty.beep);
    type_keys(&mut state, &db, "su3cl3", &options);
    press(&mut state, &db, Key::Left, true, &options);
    type_keys(&mut state, &db, "g", &options);
    assert_eq!(state.visible_text(), "你ㄕ好");
    let confirmation = press(&mut state, &db, Key::Return, false, &options);
    assert!(confirmation.commit.is_empty());
    assert_eq!(state.take_marked_phrase_request().unwrap().text, "好");
    assert_eq!(state.visible_text(), "你ㄕ好");
    assert_eq!(state.completed_readings().len(), 2);
    state.cancel_phrase_mark();
    assert!(state.marked_phrase().is_none());
    assert_eq!(state.visible_text(), "你ㄕ好");
}

#[test]
fn ctrl_punctuation_uses_native_keyboard_target_without_relocating_the_caret() {
    let db = database();
    for end in [false, true] {
        let options = SmartOptions {
            candidate_cursor_at_end: end,
            ..SmartOptions::default()
        };
        let mut state = SmartState::new(BopomofoLayout::Standard);
        type_keys(&mut state, &db, "su3cl3", &options);
        let mut result = effects();
        state
            .character(
                &db,
                '1',
                Modifiers {
                    control: true,
                    ..Modifiers::default()
                },
                &options,
                &mut result,
            )
            .unwrap();
        assert_eq!(
            state.reading_cursor(),
            3,
            "Ctrl long jump keeps the inserted-reading caret"
        );
        assert!(state.candidates().len() > 1);
        assert!(state
            .candidates()
            .iter()
            .all(|row| row.query == "_punctuation_list"));
        state.cancel_candidates();
        assert_eq!(state.reading_cursor(), 3);
        state.clear();
        type_keys(&mut state, &db, "su3cl3", &options);
        press(&mut state, &db, Key::Home, false, &options);
        state
            .character(
                &db,
                '1',
                Modifiers {
                    control: true,
                    ..Modifiers::default()
                },
                &options,
                &mut effects(),
            )
            .unwrap();
        assert_eq!(state.reading_cursor(), 1);
        assert!(!state.candidates().is_empty());
        assert_eq!(
            state
                .candidates()
                .iter()
                .all(|row| row.query == "_punctuation_list"),
            end,
            "middle insertion follows native end-target setting"
        );
        state.clear();
        type_keys(&mut state, &db, "su3cl3", &options);
        press(&mut state, &db, Key::Home, false, &options);
        let mut single = effects();
        state
            .character(
                &db,
                ',',
                Modifiers {
                    control: true,
                    ..Modifiers::default()
                },
                &options,
                &mut single,
            )
            .unwrap();
        assert_eq!(state.reading_cursor(), 1);
        assert!(
            state.candidates().is_empty(),
            "one Ctrl punctuation must not open a following word's panel"
        );
        assert!(!single.beep && single.commit.is_empty());
    }
}

#[test]
fn empty_space_candidate_binding_passes_through_but_literal_policy_commits() {
    let db = database();
    for opens in [false, true] {
        for caps_lock in [false, true] {
            for shift in [false, true] {
                let options = SmartOptions {
                    space_opens_candidates: opens,
                    ..SmartOptions::default()
                };
                let mut state = SmartState::new(BopomofoLayout::Standard);
                let mut result = effects();
                state
                    .key(
                        &db,
                        Key::Space,
                        Modifiers {
                            caps_lock,
                            shift,
                            ..Modifiers::default()
                        },
                        &options,
                        &mut result,
                    )
                    .unwrap();
                let literal = !opens || caps_lock;
                assert_eq!(result.handled, literal);
                assert_eq!(result.commit, if literal { " " } else { "" });
                assert!(!result.beep && state.is_empty());
            }
        }
    }
}
