//! Public-session behavior with the shared, read-only KeyKey database.
//!
//! These targeted tests exercise Guanyinma's API. They never load or refresh
//! the manual Rust migration functional-baseline fixtures.
//! Character.text is the actual text delivered by the frontend; physical
//! keycode translation belongs to the frontend. The Chinese Caps Lock option
//! may normalize unshifted ASCII letters; English receives the original text.

mod support;

use guanyinma::bopomofo::{BopomofoLayout, BopomofoReading};
use guanyinma::table::{self, PunctuationStyle, TableQueryOptions};
use guanyinma::{
    BehaviorOptions, BehaviorProfile, Effects, InputMethod, InputOperation, InputSession, Key,
    ModelDatabase, Modifiers, SessionConfig, SessionSnapshot, Table, TableOptions,
};
use rusqlite::Connection;
use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

fn shared_database() -> PathBuf {
    support::model_path()
}

fn session(config: SessionConfig) -> InputSession {
    InputSession::open(shared_database(), config).unwrap()
}

fn traditional() -> InputSession {
    session(SessionConfig {
        // An explicit controlled page size; the macOS Standard default is nine.
        traditional_selection_keys: Some("12345678".into()),
        ..SessionConfig::default()
    })
}

fn table_session(method: InputMethod, options: TableOptions) -> InputSession {
    session(SessionConfig {
        method,
        cangjie: Some(options),
        simplex: Some(options),
        ..SessionConfig::default()
    })
}

fn type_keys(session: &mut InputSession, keys: &str) -> SessionSnapshot {
    let mut result = session.snapshot();
    for key in keys.chars() {
        result = session.apply(InputOperation::character(key)).unwrap();
    }
    result
}

fn key(session: &mut InputSession, key: Key) -> SessionSnapshot {
    session.apply(InputOperation::key(key)).unwrap()
}

fn state_json(session: &InputSession) -> serde_json::Value {
    serde_json::to_value(session.snapshot()).unwrap()
}

#[test]
fn five_desktop_layouts_query_the_same_complete_traditional_candidate_order() {
    let database = ModelDatabase::open(shared_database()).unwrap();
    let mut reading = BopomofoReading::new(BopomofoLayout::Standard);
    for key in "5j/".chars() {
        assert!(reading.combine(key));
    }
    let expected = database
        .lookup_table(Table::Traditional, &reading.query_key())
        .unwrap();
    assert!(expected.len() > 9);
    assert_eq!(expected.first().unwrap(), "中");

    for (layout, keys, page_size) in [
        (BopomofoLayout::Standard, "5j/", 9),
        (BopomofoLayout::Hsu, "jxl", 8),
        (BopomofoLayout::ETen, ",x-", 9),
        (BopomofoLayout::ETen26, "gxl", 8),
        (BopomofoLayout::HanyuPinyin, "zhong", 9),
    ] {
        let mut input = session(SessionConfig {
            layout,
            ..SessionConfig::default()
        });
        let partial = type_keys(&mut input, keys);
        assert!(partial.effects.commit.is_empty(), "{layout:?}");
        assert!(partial.candidates.is_empty(), "{layout:?}");
        let queried = key(&mut input, Key::Space);
        assert_eq!(queried.candidates, expected, "{layout:?}");
        assert_eq!(queried.code, reading.query_key(), "{layout:?}");
        assert_eq!(queried.composition, "中", "{layout:?}");
        assert_eq!(queried.page_size, page_size, "{layout:?}");
        assert_eq!(
            queried.displayed_candidates,
            expected[..page_size],
            "{layout:?}"
        );
        assert!(queried.effects.commit.is_empty());
    }
}

#[test]
fn traditional_pages_are_views_of_the_full_order_and_selection_is_page_local() {
    let expected = ModelDatabase::open(shared_database())
        .unwrap()
        .lookup_table(Table::Traditional, r"\O")
        .unwrap();
    assert_eq!(&expected[..3], ["你", "妳", "擬"]);
    assert!(expected.len() > 8);

    let mut input = traditional();
    let queried = type_keys(&mut input, "su3");
    assert_eq!(queried.phonetic, "ㄋㄧˇ");
    assert_eq!(queried.candidates, expected);
    assert_eq!(queried.page, 0);
    assert_eq!(queried.highlight, Some(0));
    let next = input.apply(InputOperation::Page { delta: 1 }).unwrap();
    assert_eq!(next.candidates, expected);
    assert_eq!(
        next.displayed_candidates,
        expected[8..expected.len().min(16)]
    );
    assert_eq!(next.highlight, Some(0));
    assert!(next.effects.commit.is_empty());
    let selected = input.apply(InputOperation::Select { index: 0 }).unwrap();
    assert_eq!(selected.effects.commit, expected[8]);
    assert!(selected.composition.is_empty());
    assert!(selected.candidates.is_empty());
    assert_eq!(input.snapshot().effects, Effects::default());

    // Phase two performs no learning writes; choosing a later candidate does not
    // silently change subsequent source ordering in this or another session.
    assert_eq!(type_keys(&mut input, "su3").candidates, expected);
    assert_eq!(type_keys(&mut traditional(), "su3").candidates, expected);
}

#[test]
fn traditional_editing_cancels_candidates_then_removes_one_phonetic_component() {
    let mut input = traditional();
    type_keys(&mut input, "su3");
    let edited = key(&mut input, Key::Backspace);
    assert_eq!(edited.composition, "ㄋㄧ");
    assert_eq!(edited.phonetic, "ㄋㄧ");
    assert!(edited.candidates.is_empty());
    assert!(!edited.effects.discard_composition);
    assert!(edited.effects.commit.is_empty());
    assert_eq!(key(&mut input, Key::Backspace).composition, "ㄋ");
    let empty = key(&mut input, Key::Backspace);
    assert!(empty.composition.is_empty());
    assert!(empty.effects.discard_composition);
    let host_delete = key(&mut input, Key::Backspace);
    assert!(!host_delete.effects.handled);
    assert!(!host_delete.effects.delete_backward);
}

#[test]
fn a_new_traditional_reading_commits_the_highlighted_candidate() {
    let mut input = traditional();
    type_keys(&mut input, "su3");
    let moved = input
        .apply(InputOperation::MoveHighlight { delta: 1 })
        .unwrap();
    assert_eq!(moved.highlight, Some(1));
    assert!(moved.effects.commit.is_empty());
    let next = type_keys(&mut input, "a");
    assert_eq!(next.effects.commit, "妳");
    assert_eq!(next.composition, "ㄇ");
    assert!(next.candidates.is_empty());

    // A shortcut chord while candidates are open must neither select nor add a
    // phonetic component, including punctuation keys that double as phonetics.
    input.apply(InputOperation::Reset).unwrap();
    type_keys(&mut input, "su3");
    let before = state_json(&input);
    let shortcut = input
        .apply(InputOperation::Character {
            text: ",".into(),
            modifiers: Modifiers {
                control: true,
                ..Modifiers::default()
            },
        })
        .unwrap();
    assert!(shortcut.effects.handled && shortcut.effects.beep);
    assert!(shortcut.effects.commit.is_empty());
    assert_eq!(state_json(&input), before);
}

#[test]
fn global_num_lock_does_not_change_normal_chinese_keyboard_input() {
    for method in [
        InputMethod::Traditional,
        InputMethod::Cangjie,
        InputMethod::Simplex,
    ] {
        let mut plain = session(SessionConfig {
            method,
            ..SessionConfig::default()
        });
        let expected = plain.apply(InputOperation::character('s')).unwrap();
        let mut locked = session(SessionConfig {
            method,
            ..SessionConfig::default()
        });
        let actual = locked
            .apply(InputOperation::Character {
                text: "s".into(),
                modifiers: Modifiers {
                    num_lock: true,
                    ..Modifiers::default()
                },
            })
            .unwrap();
        assert_eq!(
            serde_json::to_value(&actual).unwrap(),
            serde_json::to_value(&expected).unwrap(),
            "{method:?}"
        );
        assert_eq!(
            actual.composition,
            if method == InputMethod::Traditional {
                "ㄋ"
            } else {
                "尸"
            }
        );
        assert!(actual.effects.commit.is_empty());
        assert!(!actual.effects.beep);
    }
}

#[test]
fn actual_keypad_digits_and_operators_are_literal_in_all_three_methods() {
    for method in [
        InputMethod::Traditional,
        InputMethod::Cangjie,
        InputMethod::Simplex,
    ] {
        let mut input = session(SessionConfig {
            method,
            ..SessionConfig::default()
        });
        // Keypad origin is independent of the global NumLock toggle. Navigation
        // from a non-printing keypad key is supplied as a Key operation instead.
        for num_lock in [false, true] {
            for character in "0123456789.+-*/".chars() {
                let result = input
                    .apply(InputOperation::Character {
                        text: character.to_string(),
                        modifiers: Modifiers {
                            keypad: true,
                            num_lock,
                            ..Modifiers::default()
                        },
                    })
                    .unwrap();
                assert_eq!(
                    result.effects.commit,
                    character.to_string(),
                    "{method:?} {character}"
                );
                assert!(result.effects.handled);
                assert!(!result.effects.beep);
                assert!(result.composition.is_empty());
                assert!(result.candidates.is_empty());
                assert_eq!(input.snapshot().effects, Effects::default());
            }
        }
    }
}

fn active_input(method: InputMethod, with_candidates: bool) -> InputSession {
    let mut input = session(SessionConfig {
        method,
        ..SessionConfig::default()
    });
    match (method, with_candidates) {
        (InputMethod::Smart, _) => unreachable!("phase-two helper excludes Smart Mandarin"),
        (InputMethod::Traditional, false) => {
            type_keys(&mut input, "su");
        }
        (InputMethod::Traditional, true) => {
            type_keys(&mut input, "su3");
        }
        (InputMethod::Cangjie, false) => {
            type_keys(&mut input, "ab");
        }
        (InputMethod::Cangjie, true) => {
            type_keys(&mut input, "a");
            key(&mut input, Key::Space);
        }
        (InputMethod::Simplex, false) => {
            type_keys(&mut input, "a");
        }
        (InputMethod::Simplex, true) => {
            type_keys(&mut input, "ab");
        }
    }
    input
}

#[test]
fn keypad_preserves_visible_roots_or_reading_and_bypasses_candidate_selection() {
    for method in [
        InputMethod::Traditional,
        InputMethod::Cangjie,
        InputMethod::Simplex,
    ] {
        for with_candidates in [false, true] {
            let mut input = active_input(method, with_candidates);
            let visible = match (method, with_candidates) {
                (InputMethod::Smart, _) => unreachable!("phase-two matrix excludes Smart Mandarin"),
                (InputMethod::Traditional, false) => "ㄋㄧ",
                (InputMethod::Traditional, true) => "你",
                (InputMethod::Cangjie, false) | (InputMethod::Simplex, true) => "日月",
                (InputMethod::Cangjie, true) | (InputMethod::Simplex, false) => "日",
            };
            assert_eq!(input.snapshot().composition, visible);
            if with_candidates {
                assert!(input.snapshot().candidates.len() > 1);
                input
                    .apply(InputOperation::MoveHighlight { delta: 1 })
                    .unwrap();
            }
            let result = input
                .apply(InputOperation::Character {
                    text: "1".into(),
                    modifiers: Modifiers {
                        keypad: true,
                        num_lock: true,
                        ..Modifiers::default()
                    },
                })
                .unwrap();
            assert_eq!(result.effects.commit, format!("{visible}1"), "{method:?}");
            assert!(result.effects.handled);
            assert!(!result.effects.beep);
            assert!(result.composition.is_empty());
            assert!(result.candidates.is_empty());
            let next = type_keys(&mut input, "s");
            assert_eq!(
                next.composition,
                if method == InputMethod::Traditional {
                    "ㄋ"
                } else {
                    "尸"
                }
            );
            assert!(next.effects.commit.is_empty());
        }
    }
}

#[test]
fn keypad_shortcuts_and_release_preserve_session_state() {
    for method in [
        InputMethod::Traditional,
        InputMethod::Cangjie,
        InputMethod::Simplex,
    ] {
        for active in [false, true] {
            for literal_keypad in [false, true] {
                let mut input = if active {
                    active_input(method, true)
                } else {
                    session(SessionConfig {
                        method,
                        ..SessionConfig::default()
                    })
                };
                input
                    .apply(InputOperation::SetBehaviors {
                        behaviors: BehaviorOptions {
                            literal_keypad,
                            ..BehaviorOptions::default()
                        },
                    })
                    .unwrap();
                let before = state_json(&input);
                for extra in [
                    Modifiers {
                        control: true,
                        ..Modifiers::default()
                    },
                    Modifiers {
                        alt: true,
                        ..Modifiers::default()
                    },
                    Modifiers {
                        command: true,
                        ..Modifiers::default()
                    },
                    Modifiers {
                        release: true,
                        ..Modifiers::default()
                    },
                ] {
                    let result = input
                        .apply(InputOperation::Character {
                            text: "1".into(),
                            modifiers: Modifiers {
                                keypad: true,
                                num_lock: true,
                                ..extra
                            },
                        })
                        .unwrap();
                    assert!(!result.effects.handled, "{method:?}");
                    assert!(!result.effects.beep);
                    assert!(result.effects.commit.is_empty());
                    assert_eq!(state_json(&input), before);
                }
            }
        }
    }
}

#[test]
fn literal_keypad_option_changes_routing_without_dismissing_candidates() {
    for method in [
        InputMethod::Traditional,
        InputMethod::Cangjie,
        InputMethod::Simplex,
    ] {
        for literal_keypad in [false, true] {
            let mut input = active_input(method, true);
            input
                .apply(InputOperation::MoveHighlight { delta: 1 })
                .unwrap();
            let before = input.snapshot();
            let changed = input
                .apply(InputOperation::SetBehaviors {
                    behaviors: BehaviorOptions {
                        literal_keypad,
                        ..BehaviorOptions::default()
                    },
                })
                .unwrap();
            assert_eq!(changed.composition, before.composition);
            assert_eq!(changed.phonetic, before.phonetic);
            assert_eq!(changed.code, before.code);
            assert_eq!(changed.candidates, before.candidates);
            assert_eq!(changed.displayed_candidates, before.displayed_candidates);
            assert_eq!(changed.page, before.page);
            assert_eq!(changed.highlight, before.highlight);
            assert!(changed.effects.commit.is_empty());
            let result = input
                .apply(InputOperation::Character {
                    text: "1".into(),
                    modifiers: Modifiers {
                        keypad: true,
                        num_lock: true,
                        ..Modifiers::default()
                    },
                })
                .unwrap();
            assert_eq!(
                result.effects.commit,
                if literal_keypad {
                    format!("{}1", before.composition)
                } else {
                    before.candidates[0].clone()
                },
                "{method:?} literal_keypad={literal_keypad}"
            );
            assert!(result.effects.handled);
            assert!(!result.effects.beep);
            assert!(result.composition.is_empty());
            assert!(result.candidates.is_empty());
        }
    }
}

#[test]
fn behavior_updates_apply_to_future_keys_without_flushing_pending_roots() {
    for method in [
        InputMethod::Traditional,
        InputMethod::Cangjie,
        InputMethod::Simplex,
    ] {
        for ignore_caps in [false, true] {
            for literal_keypad in [false, true] {
                let mut input = active_input(method, false);
                let before = input.snapshot();
                let changed = input
                    .apply(InputOperation::SetBehaviors {
                        behaviors: BehaviorOptions {
                            ignore_caps_lock_in_chinese: ignore_caps,
                            literal_keypad,
                        },
                    })
                    .unwrap();
                assert_eq!(changed.composition, before.composition);
                assert_eq!(changed.phonetic, before.phonetic);
                assert_eq!(changed.code, before.code);
                assert_eq!(changed.candidates, before.candidates);
                assert!(changed.effects.commit.is_empty());
                let result = input
                    .apply(InputOperation::Character {
                        text: "S".into(),
                        modifiers: Modifiers {
                            caps_lock: true,
                            ..Modifiers::default()
                        },
                    })
                    .unwrap();
                if ignore_caps {
                    let mut ordinary = active_input(method, false);
                    let expected = type_keys(&mut ordinary, "s");
                    assert_eq!(result.composition, expected.composition);
                    assert_eq!(result.code, expected.code);
                    assert_eq!(result.candidates, expected.candidates);
                    assert_eq!(result.effects.commit, expected.effects.commit);
                } else {
                    assert_eq!(result.effects.commit, "S");
                    assert!(result.composition.is_empty());
                }
            }
        }
    }
}

#[test]
fn configured_caps_preference_normalizes_unshifted_chinese_letters_only() {
    for method in [
        InputMethod::Traditional,
        InputMethod::Cangjie,
        InputMethod::Simplex,
    ] {
        for ignore_caps in [false, true] {
            for caps_lock in [false, true] {
                for character in ['s', 'S'] {
                    let mut input = session(SessionConfig {
                        method,
                        behaviors: BehaviorOptions {
                            ignore_caps_lock_in_chinese: ignore_caps,
                            ..BehaviorOptions::default()
                        },
                        ..SessionConfig::default()
                    });
                    let result = input
                        .apply(InputOperation::Character {
                            text: character.to_string(),
                            modifiers: Modifiers {
                                caps_lock,
                                ..Modifiers::default()
                            },
                        })
                        .unwrap();
                    if ignore_caps || (!caps_lock && character == 's') {
                        assert_eq!(
                            result.composition,
                            if method == InputMethod::Traditional {
                                "ㄋ"
                            } else {
                                "尸"
                            },
                            "{method:?} ignore={ignore_caps} caps={caps_lock} {character}"
                        );
                        assert!(result.effects.commit.is_empty());
                    } else {
                        assert_eq!(result.effects.commit, character.to_string());
                        assert!(result.composition.is_empty());
                    }
                    assert!(!result.effects.beep);
                }
            }
        }
    }
}

#[test]
fn caps_preference_preserves_received_shift_literals_and_english_case() {
    for method in [
        InputMethod::Traditional,
        InputMethod::Cangjie,
        InputMethod::Simplex,
    ] {
        for ignore_caps in [false, true] {
            for caps_lock in [false, true] {
                for character in ['s', 'S'] {
                    let mut input = session(SessionConfig {
                        method,
                        behaviors: BehaviorOptions {
                            ignore_caps_lock_in_chinese: ignore_caps,
                            ..BehaviorOptions::default()
                        },
                        ..SessionConfig::default()
                    });
                    let result = input
                        .apply(InputOperation::Character {
                            text: character.to_string(),
                            modifiers: Modifiers {
                                shift: true,
                                caps_lock,
                                ..Modifiers::default()
                            },
                        })
                        .unwrap();
                    assert_eq!(result.effects.commit, character.to_string());
                    assert!(result.composition.is_empty());
                }
                for shift in [false, true] {
                    let mut input = session(SessionConfig {
                        method,
                        behaviors: BehaviorOptions {
                            ignore_caps_lock_in_chinese: ignore_caps,
                            ..BehaviorOptions::default()
                        },
                        ..SessionConfig::default()
                    });
                    input
                        .apply(InputOperation::SetEnglish { enabled: true })
                        .unwrap();
                    // The frontend already resolved Caps XOR Shift into text.
                    let received = if caps_lock != shift { "S" } else { "s" };
                    let result = input
                        .apply(InputOperation::Character {
                            text: received.into(),
                            modifiers: Modifiers {
                                shift,
                                caps_lock,
                                ..Modifiers::default()
                            },
                        })
                        .unwrap();
                    assert_eq!(result.effects.commit, received);
                    assert!(result.composition.is_empty());
                }
            }
        }
    }
}

#[test]
fn english_traditional_control_punctuation_remains_a_host_shortcut() {
    let mut input = traditional();
    input
        .apply(InputOperation::SetEnglish { enabled: true })
        .unwrap();
    let before = state_json(&input);
    // These keys have Chinese control-punctuation entries, including the
    // Ctrl+0/1 punctuation list. English mode must not query any of them.
    for character in ['0', '1', ',', '.', ':', ';', '\'', '"'] {
        for shift in [false, true] {
            let result = input
                .apply(InputOperation::Character {
                    text: character.to_string(),
                    modifiers: Modifiers {
                        control: true,
                        shift,
                        ..Modifiers::default()
                    },
                })
                .unwrap();
            assert!(!result.effects.handled);
            assert!(!result.effects.beep);
            assert!(result.effects.commit.is_empty());
            assert!(result.candidates.is_empty());
            assert!(result.composition.is_empty());
            assert_eq!(state_json(&input), before);
        }
    }
    let shifted = input
        .apply(InputOperation::Character {
            text: "S".into(),
            modifiers: Modifiers {
                shift: true,
                ..Modifiers::default()
            },
        })
        .unwrap();
    assert_eq!(shifted.effects.commit, "S");
    assert!(shifted.english);
    assert!(shifted.candidates.is_empty());
}

#[test]
fn candidate_navigation_single_page_clamps_arrows_and_explicit_highlight_moves() {
    let mut input = active_input(InputMethod::Cangjie, true);
    assert_eq!(input.snapshot().candidates, ["日", "曰"]);
    for operation in [
        InputOperation::key(Key::Up),
        InputOperation::MoveHighlight { delta: -1 },
    ] {
        let result = input.apply(operation).unwrap();
        assert_eq!(result.highlight, Some(0));
        assert_eq!(result.page, 0);
        assert!(result.effects.beep);
        assert!(result.effects.commit.is_empty());
    }
    let moved = key(&mut input, Key::Down);
    assert_eq!(moved.highlight, Some(1));
    assert!(!moved.effects.beep);
    for operation in [
        InputOperation::key(Key::Down),
        InputOperation::MoveHighlight { delta: 1 },
    ] {
        let result = input.apply(operation).unwrap();
        assert_eq!(result.highlight, Some(1));
        assert_eq!(result.page, 0);
        assert!(result.effects.beep);
        assert!(result.effects.commit.is_empty());
    }
    assert_eq!(key(&mut input, Key::Return).effects.commit, "曰");
}

#[test]
fn candidate_navigation_single_page_paging_resets_highlight_and_beeps() {
    for operation in [
        InputOperation::key(Key::PageUp),
        InputOperation::key(Key::PageDown),
        InputOperation::Page { delta: -1 },
        InputOperation::Page { delta: 1 },
    ] {
        let mut input = active_input(InputMethod::Cangjie, true);
        input
            .apply(InputOperation::MoveHighlight { delta: 1 })
            .unwrap();
        let result = input.apply(operation).unwrap();
        assert_eq!(result.page_count, 1);
        assert_eq!(result.page, 0);
        assert_eq!(result.highlight, Some(0));
        assert_eq!(result.candidates, ["日", "曰"]);
        assert!(result.effects.beep);
        assert!(result.effects.commit.is_empty());
    }
}

#[test]
fn candidate_navigation_multiple_pages_wrap_at_the_complete_list_boundary() {
    let mut input = active_input(InputMethod::Simplex, true);
    let before = input.snapshot();
    assert_eq!(before.candidates.len(), 42);
    assert_eq!(before.page_count, 5);
    let last = key(&mut input, Key::Up);
    assert_eq!(last.page, 4);
    assert_eq!(last.highlight, Some(5));
    assert_eq!(last.candidates, before.candidates);
    assert_eq!(last.displayed_candidates, before.candidates[36..42]);
    assert!(!last.effects.beep);
    assert!(last.effects.commit.is_empty());
    let first = key(&mut input, Key::Down);
    assert_eq!(first.page, 0);
    assert_eq!(first.highlight, Some(0));
    assert_eq!(first.candidates, before.candidates);
    assert_eq!(first.displayed_candidates, before.candidates[..9]);
    assert!(!first.effects.beep);
    assert!(first.effects.commit.is_empty());
}

#[test]
fn candidate_navigation_with_shift_preserves_the_panel_and_beeps() {
    let mut input = active_input(InputMethod::Simplex, true);
    input.apply(InputOperation::Page { delta: 1 }).unwrap();
    input
        .apply(InputOperation::MoveHighlight { delta: 2 })
        .unwrap();
    let before = state_json(&input);
    for key in [
        Key::Home,
        Key::End,
        Key::Left,
        Key::Right,
        Key::Up,
        Key::Down,
        Key::PageUp,
        Key::PageDown,
    ] {
        let result = input
            .apply(InputOperation::Key {
                key,
                modifiers: Modifiers {
                    shift: true,
                    ..Modifiers::default()
                },
            })
            .unwrap();
        assert!(result.effects.handled);
        assert!(result.effects.beep);
        assert!(result.effects.commit.is_empty());
        assert_eq!(state_json(&input), before);
    }
}

#[test]
fn semantic_shift_toggle_flushes_visible_composition_once() {
    for method in [
        InputMethod::Traditional,
        InputMethod::Cangjie,
        InputMethod::Simplex,
    ] {
        for with_candidates in [false, true] {
            let mut input = active_input(method, with_candidates);
            let visible = input.snapshot().composition;
            assert!(!visible.is_empty());
            if with_candidates {
                input
                    .apply(InputOperation::MoveHighlight { delta: 1 })
                    .unwrap();
            }
            // Native frontends recognize a completed Shift tap and send one
            // semantic operation; hardware timing is not part of this API.
            let toggled = input.apply(InputOperation::ToggleEnglish).unwrap();
            assert!(toggled.english);
            assert_eq!(toggled.effects.commit, visible);
            assert!(toggled.composition.is_empty());
            assert!(toggled.candidates.is_empty());
            assert_eq!(input.snapshot().effects, Effects::default());
            let unchanged = input
                .apply(InputOperation::SetEnglish { enabled: true })
                .unwrap();
            assert!(unchanged.english);
            assert!(unchanged.effects.commit.is_empty());
            assert_eq!(type_keys(&mut input, "S").effects.commit, "S");
            let back = input.apply(InputOperation::ToggleEnglish).unwrap();
            assert!(!back.english);
            assert!(back.effects.commit.is_empty());
            let unchanged = input
                .apply(InputOperation::SetEnglish { enabled: false })
                .unwrap();
            assert!(!unchanged.english);
            assert!(unchanged.effects.commit.is_empty());
            assert!(!type_keys(&mut input, "s").composition.is_empty());
        }
    }
}

#[test]
fn invalid_operations_leave_active_composition_and_paging_unchanged() {
    let mut input = traditional();
    type_keys(&mut input, "su3");
    input.apply(InputOperation::Page { delta: 1 }).unwrap();
    let before = state_json(&input);
    for operation in [
        InputOperation::Select { index: 8 },
        InputOperation::Select { index: usize::MAX },
        InputOperation::Character {
            text: "ab".into(),
            modifiers: Modifiers::default(),
        },
        InputOperation::Character {
            text: "\n".into(),
            modifiers: Modifiers::default(),
        },
        InputOperation::SetTableOptions {
            method: InputMethod::Traditional,
            options: TableOptions::default(),
        },
    ] {
        assert!(input.apply(operation).is_err());
        assert_eq!(state_json(&input), before);
    }
}

#[test]
fn cangjie_one_page_space_selects_first_while_return_selects_highlighted() {
    let mut input = table_session(InputMethod::Cangjie, TableOptions::default());
    assert_eq!(type_keys(&mut input, "a").composition, "日");
    let queried = key(&mut input, Key::Space);
    assert_eq!(queried.candidates, ["日", "曰"]);
    assert_eq!(queried.page_count, 1);
    input
        .apply(InputOperation::MoveHighlight { delta: 1 })
        .unwrap();
    // OVIMGeneric's one-page Space behavior explicitly chooses index zero.
    assert_eq!(key(&mut input, Key::Space).effects.commit, "日");

    type_keys(&mut input, "a");
    key(&mut input, Key::Space);
    input
        .apply(InputOperation::MoveHighlight { delta: 1 })
        .unwrap();
    assert_eq!(key(&mut input, Key::Return).effects.commit, "曰");
    assert_eq!(input.snapshot().effects, Effects::default());
}

#[test]
fn cangjie_new_root_commits_highlight_but_prefix_preview_continues_the_code() {
    let mut input = table_session(InputMethod::Cangjie, TableOptions::default());
    type_keys(&mut input, "a");
    key(&mut input, Key::Space);
    input
        .apply(InputOperation::MoveHighlight { delta: 1 })
        .unwrap();
    let next = type_keys(&mut input, "b");
    assert_eq!(next.effects.commit, "曰");
    assert_eq!(next.code, "b");
    assert_eq!(next.composition, "月");

    let options = TableOptions {
        realtime: true,
        prefix: true,
        query_at_maximum: true,
        ..TableOptions::default()
    };
    let mut input = table_session(InputMethod::Cangjie, options);
    let database = ModelDatabase::open(shared_database()).unwrap();
    for (code, typed, count) in [
        ("h", 'h', 38),
        ("hk", 'k', 40),
        ("hkr", 'r', 11),
        ("hkrb", 'b', 2),
        ("hkrbr", 'r', 1),
    ] {
        let snapshot = input.apply(InputOperation::character(typed)).unwrap();
        assert_eq!(snapshot.code, code);
        assert_eq!(snapshot.page, 0);
        assert_eq!(snapshot.highlight, Some(0));
        assert_eq!(snapshot.candidates.len(), count);
        assert!(snapshot.effects.commit.is_empty(), "{code}");
        let expected = table::candidates(
            &database,
            Table::Cangjie,
            code,
            TableQueryOptions {
                prefix: true,
                ..TableQueryOptions::default()
            },
        )
        .unwrap();
        assert_eq!(snapshot.candidates, expected.values, "{code}");
    }
    let fifth = input.snapshot();
    assert_eq!(fifth.candidates, ["喬"]);
    assert_eq!(fifth.composition, "竹大口月口");
    // The full five-root preview stays available; the next root starts a code.
    let sixth = type_keys(&mut input, "a");
    assert_eq!(sixth.effects.commit, "喬");
    assert_eq!(sixth.code, "a");
    assert_eq!(&sixth.candidates[..2], ["日", "曰"]);
}

#[test]
fn cangjie_preview_backspace_requeries_and_space_confirms_a_unique_code() {
    let mut input = table_session(
        InputMethod::Cangjie,
        TableOptions {
            realtime: true,
            prefix: true,
            ..TableOptions::default()
        },
    );
    type_keys(&mut input, "hkrbr");
    let edited = key(&mut input, Key::Backspace);
    assert_eq!(edited.code, "hkrb");
    assert_eq!(edited.candidates.len(), 2);
    assert!(edited.effects.commit.is_empty());
    type_keys(&mut input, "r");
    let confirmed = key(&mut input, Key::Space);
    assert_eq!(confirmed.effects.commit, "喬");
    assert!(confirmed.code.is_empty());
    assert!(confirmed.candidates.is_empty());
}

#[test]
fn table_error_options_preserve_realtime_roots_and_clear_final_invalid_codes() {
    let mut input = table_session(InputMethod::Cangjie, TableOptions::default());
    type_keys(&mut input, "zzzzz");
    let full = type_keys(&mut input, "a");
    assert_eq!(full.code, "zzzzz");
    assert!(full.effects.beep);
    let failed = key(&mut input, Key::Space);
    assert!(failed.effects.beep);
    assert!(failed.code.is_empty());
    assert!(failed.composition.is_empty());

    for options in [
        TableOptions {
            clear_on_error: false,
            ..TableOptions::default()
        },
        TableOptions {
            realtime: true,
            clear_on_error: true,
            ..TableOptions::default()
        },
    ] {
        let mut input = table_session(InputMethod::Cangjie, options);
        let typed = type_keys(&mut input, "zzzzz");
        assert!(typed.effects.commit.is_empty());
        let failed = key(&mut input, Key::Space);
        assert!(failed.effects.beep);
        assert_eq!(failed.code, "zzzzz");
        assert_eq!(failed.composition, "重重重重重");
        if options.realtime {
            assert!(!failed.table_options.clear_on_error);
        }
    }
}

#[test]
fn simplex_queries_at_two_roots_with_all_candidates_and_cycles_pages_on_space() {
    let expected = ModelDatabase::open(shared_database())
        .unwrap()
        .lookup_table(Table::Simplex, "ab")
        .unwrap();
    assert_eq!(expected.len(), 42);
    let mut input = table_session(InputMethod::Simplex, TableOptions::simplex());
    assert!(type_keys(&mut input, "a").candidates.is_empty());
    let queried = type_keys(&mut input, "b");
    assert_eq!(queried.candidates, expected);
    assert_eq!(queried.composition, "日月");
    assert_eq!(queried.page_count, 5);
    let paged = key(&mut input, Key::Space);
    assert_eq!(paged.page, 1);
    assert_eq!(paged.displayed_candidates, expected[9..18]);
    let selected = input.apply(InputOperation::Select { index: 1 }).unwrap();
    assert_eq!(selected.effects.commit, expected[10]);
    assert!(selected.code.is_empty());
    assert!(selected.candidates.is_empty());

    // A one-page Simplex list retains the panel's paging behavior.
    type_keys(&mut input, "a");
    key(&mut input, Key::Space);
    let paged = key(&mut input, Key::Space);
    assert_eq!(paged.page, 0);
    assert_eq!(paged.candidates, ["日", "曰"]);
    assert!(paged.effects.commit.is_empty());
}

#[test]
fn table_punctuation_and_wildcards_use_the_desktop_source_order() {
    let mut input = table_session(InputMethod::Cangjie, TableOptions::default());
    let wildcard = type_keys(&mut input, "hk?");
    assert_eq!(wildcard.code, "hk?");
    assert!(wildcard.candidates.is_empty());
    let queried = key(&mut input, Key::Space);
    let database = ModelDatabase::open(shared_database()).unwrap();
    assert_eq!(
        queried.candidates,
        database
            .lookup_table_pattern(Table::Cangjie, "hk?")
            .unwrap()
    );
    assert!(queried.candidates.len() > 36);
    assert!(!queried.candidates.iter().any(|value| value == "喬"));

    for (punctuation, expected) in [
        (PunctuationStyle::Mixed, "，"),
        (PunctuationStyle::Half, ","),
    ] {
        let mut input = table_session(
            InputMethod::Cangjie,
            TableOptions {
                punctuation,
                ..TableOptions::default()
            },
        );
        let typed = type_keys(&mut input, ",");
        assert_eq!(typed.effects.commit, expected);
        assert!(typed.code.is_empty());
    }
}

#[test]
fn switching_method_layout_and_english_flushes_the_visible_composition_once() {
    let mut input = traditional();
    type_keys(&mut input, "su3");
    let changed = input
        .apply(InputOperation::SetMethod {
            method: InputMethod::Cangjie,
        })
        .unwrap();
    assert_eq!(changed.effects.commit, "你");
    assert!(changed.composition.is_empty());
    assert_eq!(changed.method, InputMethod::Cangjie);
    assert!(input
        .apply(InputOperation::SetMethod {
            method: InputMethod::Cangjie,
        })
        .unwrap()
        .effects
        .commit
        .is_empty());
    type_keys(&mut input, "ab");
    let layout = input
        .apply(InputOperation::SetLayout {
            layout: BopomofoLayout::Hsu,
        })
        .unwrap();
    assert_eq!(layout.effects.commit, "日月");
    assert!(layout.code.is_empty());
    type_keys(&mut input, "a");
    let english = input
        .apply(InputOperation::SetEnglish { enabled: true })
        .unwrap();
    assert_eq!(english.effects.commit, "日");
    assert!(english.english);
    assert_eq!(type_keys(&mut input, "a").effects.commit, "a");
    assert_eq!(input.snapshot().effects, Effects::default());

    input
        .apply(InputOperation::SetEnglish { enabled: false })
        .unwrap();
    type_keys(&mut input, "b");
    let finished = input.apply(InputOperation::Finish).unwrap();
    assert_eq!(finished.effects.commit, "月");
    assert!(input
        .apply(InputOperation::Finish)
        .unwrap()
        .effects
        .commit
        .is_empty());
    type_keys(&mut input, "a");
    let reset = input.apply(InputOperation::Reset).unwrap();
    assert!(reset.effects.commit.is_empty());
    assert!(reset.composition.is_empty());
}

#[test]
fn touch_reports_host_delete_and_return_without_replaying_effects_in_snapshots() {
    let mut input = session(SessionConfig {
        profile: BehaviorProfile::Touch,
        ..SessionConfig::default()
    });
    let deleted = key(&mut input, Key::Backspace);
    assert!(deleted.effects.handled && deleted.effects.delete_backward);
    assert_eq!(input.snapshot().effects, Effects::default());
    let returned = key(&mut input, Key::Return);
    assert!(returned.effects.handled && returned.effects.send_return);
    assert_eq!(input.snapshot().effects, Effects::default());
}

#[test]
fn database_failure_rolls_back_new_reading_and_method_changes_atomically() {
    let fixture = FailingModel::new();
    let mut input = InputSession::open(&fixture.path, SessionConfig::default()).unwrap();
    type_keys(&mut input, "su");
    let before = state_json(&input);
    // The tone mutates reading before the malformed dictionary value is read.
    assert!(input.apply(InputOperation::character('3')).is_err());
    assert_eq!(state_json(&input), before);

    // A method change flushes the old composition before reading selection
    // metadata; its failure must restore both state and configuration.
    assert!(input
        .apply(InputOperation::SetMethod {
            method: InputMethod::Cangjie,
        })
        .is_err());
    assert_eq!(state_json(&input), before);
    assert_eq!(
        input.apply(InputOperation::Finish).unwrap().effects.commit,
        "ㄋㄧ"
    );
}

struct FailingModel {
    path: PathBuf,
    directory: PathBuf,
}
impl FailingModel {
    fn new() -> Self {
        static NEXT: AtomicU64 = AtomicU64::new(0);
        let directory = loop {
            let id = NEXT.fetch_add(1, Ordering::Relaxed);
            let path = std::env::temp_dir().join(format!(
                "guanyinma-session-failure-{}-{id}",
                std::process::id()
            ));
            match fs::create_dir(&path) {
                Ok(()) => break path,
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(error) => panic!("create isolated test directory: {error}"),
            }
        };
        let path = directory.join("model.db");
        Connection::open(&path)
            .unwrap()
            .execute_batch(
                r#"
                CREATE TABLE unigrams (qstring, current, probability, backoff);
                CREATE TABLE bigrams (qstring, previous, current, probability);
                CREATE TABLE "Mandarin-bpmf-cin" (key, value);
                CREATE TABLE "Generic-cj-cin" (key, value);
                CREATE TABLE "Generic-simplex-cin" (key, value);
                INSERT INTO "Mandarin-bpmf-cin" VALUES ('\O', x'ff');
                INSERT INTO "Generic-cj-cin" VALUES ('__property_selkey', x'ff');
                "#,
            )
            .unwrap();
        Self { path, directory }
    }
}
impl Drop for FailingModel {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.directory);
    }
}

#[test]
fn semantic_profile_switch_preserves_active_reading_and_candidate_transaction() {
    let mut input = session(SessionConfig {
        profile: BehaviorProfile::Touch,
        traditional_selection_keys: Some("123456789".into()),
        ..SessionConfig::default()
    });
    type_keys(&mut input, "su3");
    let before = input.snapshot();
    assert!(!before.candidates.is_empty());
    for profile in [
        BehaviorProfile::Desktop,
        BehaviorProfile::Desktop,
        BehaviorProfile::Touch,
    ] {
        let after = input.apply(InputOperation::SetProfile { profile }).unwrap();
        assert_eq!(after.profile, profile);
        assert_eq!(after.reading, before.reading);
        assert_eq!(after.visible_text, before.visible_text);
        assert_eq!(after.candidates, before.candidates);
        assert_eq!(after.page, before.page);
        assert_eq!(after.highlight, before.highlight);
        assert_eq!(after.cursor, before.cursor);
        assert!(after.effects.commit.is_empty());
        assert!(!after.effects.delete_backward);
        assert!(!after.effects.send_return);
    }
    assert!(!input
        .apply(InputOperation::Select { index: 0 })
        .unwrap()
        .effects
        .commit
        .is_empty());
}
