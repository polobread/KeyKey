//! Ordinary native-derived table/gesture contracts; no migration fixtures.
mod support;

use guanyinma::{
    InputMethod, InputOperation, InputSession, Key, LearningOptions, Modifiers, SessionConfig,
    SessionSnapshot, TableOptions, TableWildcards,
};
use std::path::PathBuf;

fn model() -> PathBuf {
    support::model_path()
}
fn table_input(method: InputMethod, options: TableOptions) -> InputSession {
    InputSession::open(
        model(),
        SessionConfig {
            method,
            learning: LearningOptions {
                table_learning: true,
                ..LearningOptions::default()
            },
            cangjie: Some(options),
            simplex: Some(options),
            ..SessionConfig::default()
        },
    )
    .unwrap()
}
fn typed(input: &mut InputSession, text: &str) -> SessionSnapshot {
    let mut snapshot = input.snapshot();
    for ch in text.chars() {
        snapshot = input.apply(InputOperation::character(ch)).unwrap();
    }
    snapshot
}
fn key(input: &mut InputSession, key: Key) -> SessionSnapshot {
    input.apply(InputOperation::key(key)).unwrap()
}

#[test]
fn implicit_acceptance_of_a_highlight_does_not_train_table_frequency() {
    for (method, mut options) in [
        (InputMethod::Cangjie, TableOptions::default()),
        (InputMethod::Simplex, TableOptions::simplex()),
    ] {
        options.learn_selection = true;
        let mut input = table_input(method, options);
        typed(&mut input, "a");
        key(&mut input, Key::Space);
        let first = input.snapshot().candidates;
        assert!(first.len() > 1);
        key(&mut input, Key::Down);
        let next = typed(&mut input, "b");
        assert_eq!(next.effects.commit, first[1]);
        assert_eq!(next.code, "b");
        assert!(input.user_data().unwrap().table.is_empty());
        input.apply(InputOperation::Reset).unwrap();
        typed(&mut input, "a");
        assert_eq!(key(&mut input, Key::Space).candidates, first);
        input.apply(InputOperation::Select { index: 1 }).unwrap();
        assert_eq!(input.user_data().unwrap().table.len(), 1);
    }
}

#[test]
fn simplex_default_keeps_bad_roots_and_cangjie_can_clear_them() {
    let mut simplex = InputSession::open(
        model(),
        SessionConfig {
            method: InputMethod::Simplex,
            ..SessionConfig::default()
        },
    )
    .unwrap();
    let bad = typed(&mut simplex, "zz");
    assert!(bad.effects.beep && !bad.code.is_empty());
    assert!(!bad.table_options.clear_on_error);
    let mut cangjie = table_input(InputMethod::Cangjie, TableOptions::default());
    typed(&mut cangjie, "zz");
    let bad = key(&mut cangjie, Key::Space);
    assert!(bad.effects.beep && bad.code.is_empty());
}

#[test]
fn custom_maximum_and_maximum_query_are_behaviors() {
    let mut limited = table_input(
        InputMethod::Cangjie,
        TableOptions {
            maximum_radical_length: Some(1),
            ..TableOptions::default()
        },
    );
    typed(&mut limited, "a");
    let rejected = typed(&mut limited, "b");
    assert_eq!(rejected.code, "a");
    assert!(rejected.effects.beep && rejected.effects.commit.is_empty());
    let mut queried = table_input(
        InputMethod::Cangjie,
        TableOptions {
            maximum_radical_length: Some(1),
            query_at_maximum: true,
            ..TableOptions::default()
        },
    );
    assert!(typed(&mut queried, "a").candidates.len() > 1);
    let next = typed(&mut queried, "b");
    assert_eq!(next.effects.commit, "日月");
    assert!(next.code.is_empty());
    for invalid in [0, 129] {
        assert!(InputSession::open(
            model(),
            SessionConfig {
                method: InputMethod::Cangjie,
                cangjie: Some(TableOptions {
                    maximum_radical_length: Some(invalid),
                    ..TableOptions::default()
                }),
                ..SessionConfig::default()
            }
        )
        .is_err());
    }
}

#[test]
fn space_can_be_the_first_candidate_key_with_consistent_numbering() {
    let mut input = table_input(
        InputMethod::Cangjie,
        TableOptions {
            space_as_first_selection_key: true,
            ..TableOptions::default()
        },
    );
    typed(&mut input, "a");
    let candidates = key(&mut input, Key::Space).candidates;
    assert_eq!(typed(&mut input, "1").effects.commit, candidates[1]);
    input.apply(InputOperation::Reset).unwrap();
    typed(&mut input, "a");
    key(&mut input, Key::Space);
    assert_eq!(key(&mut input, Key::Space).effects.commit, "曰"); // learned second candidate now first
                                                                  // A multi-page list includes Space in its page size and uses the current
                                                                  // page's first candidate, rather than the first candidate of the whole list.
    let mut input = table_input(
        InputMethod::Cangjie,
        TableOptions {
            realtime: true,
            prefix: true,
            space_as_first_selection_key: true,
            ..TableOptions::default()
        },
    );
    let first = typed(&mut input, "hk");
    assert_eq!(first.page_size, 10);
    let second = input.apply(InputOperation::Page { delta: 1 }).unwrap();
    let target = second.displayed_candidates[0].clone();
    assert_eq!(key(&mut input, Key::Space).effects.commit, target);
}

#[test]
fn one_page_space_policy_is_independent_of_table_method() {
    let mut cangjie = table_input(
        InputMethod::Cangjie,
        TableOptions {
            space_commits_first_on_single_page: Some(false),
            ..TableOptions::default()
        },
    );
    typed(&mut cangjie, "a");
    key(&mut cangjie, Key::Space);
    let kept = key(&mut cangjie, Key::Space);
    assert!(!kept.candidates.is_empty() && kept.effects.commit.is_empty());
    let mut simplex = table_input(
        InputMethod::Simplex,
        TableOptions {
            space_commits_first_on_single_page: Some(true),
            ..TableOptions::simplex()
        },
    );
    typed(&mut simplex, "a");
    let first = key(&mut simplex, Key::Space).candidates[0].clone();
    key(&mut simplex, Key::Down);
    assert_eq!(key(&mut simplex, Key::Space).effects.commit, first);
}

#[test]
fn custom_wildcards_match_the_original_query_order() {
    let mut regular = table_input(InputMethod::Cangjie, TableOptions::default());
    typed(&mut regular, "hk?");
    let expected = key(&mut regular, Key::Space).candidates;
    let mut custom = table_input(
        InputMethod::Cangjie,
        TableOptions {
            wildcards: Some(TableWildcards {
                one: Some('!'),
                many: Some('%'),
            }),
            ..TableOptions::default()
        },
    );
    typed(&mut custom, "hk!");
    assert_eq!(key(&mut custom, Key::Space).candidates, expected);
    custom.apply(InputOperation::Reset).unwrap();
    regular.apply(InputOperation::Reset).unwrap();
    typed(&mut regular, "hk*");
    let expected = key(&mut regular, Key::Space).candidates;
    typed(&mut custom, "hk%");
    assert_eq!(key(&mut custom, Key::Space).candidates, expected);
    custom.apply(InputOperation::Reset).unwrap();
    let invalid = custom.apply(InputOperation::SetTableOptions {
        method: InputMethod::Cangjie,
        options: TableOptions {
            wildcards: Some(TableWildcards {
                one: Some('字'),
                many: None,
            }),
            ..TableOptions::default()
        },
    });
    assert!(invalid.is_err());
    assert_eq!(
        TableWildcards {
            one: Some('!'),
            many: Some('%')
        }
        .pattern("a*?[!"),
        "a[*][?][[]?"
    );
}

#[test]
fn explicit_direct_text_discards_roots_but_finish_preserves_them() {
    for method in [
        InputMethod::Traditional,
        InputMethod::Cangjie,
        InputMethod::Simplex,
    ] {
        let mut session = InputSession::open(
            model(),
            SessionConfig {
                method,
                ..SessionConfig::default()
            },
        )
        .unwrap();
        typed(&mut session, "s");
        let visible = session.snapshot().visible_text;
        let direct = session
            .apply(InputOperation::DirectText {
                text: "Ａ🙂".into(),
            })
            .unwrap();
        assert_eq!(direct.effects.commit, "Ａ🙂");
        assert!(direct.visible_text.is_empty() && direct.candidates.is_empty());
        typed(&mut session, "s");
        let finished = session.apply(InputOperation::Finish).unwrap();
        assert_eq!(finished.effects.commit, visible);
    }
}

#[test]
fn unfinished_traditional_reading_protects_host_modified_events() {
    for modifiers in [
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
    ] {
        let mut input = InputSession::open(model(), SessionConfig::default()).unwrap();
        let before = typed(&mut input, "s");
        let result = input
            .apply(InputOperation::Character {
                text: "a".into(),
                modifiers,
            })
            .unwrap();
        assert!(result.effects.handled && result.effects.beep && result.effects.commit.is_empty());
        assert_eq!(result.phonetic, before.phonetic);
        let result = input
            .apply(InputOperation::Key {
                key: Key::Left,
                modifiers,
            })
            .unwrap();
        assert!(result.effects.handled && result.effects.beep);
    }
}

#[test]
fn semantic_width_operations_preserve_input_and_plain_shift_space_never_toggles() {
    for method in [
        InputMethod::Traditional,
        InputMethod::Cangjie,
        InputMethod::Simplex,
        InputMethod::Smart,
    ] {
        let mut input = InputSession::open(
            model(),
            SessionConfig {
                method,
                ..SessionConfig::default()
            },
        )
        .unwrap();
        let plain = input
            .apply(InputOperation::Key {
                key: Key::Space,
                modifiers: Modifiers {
                    shift: true,
                    ..Modifiers::default()
                },
            })
            .unwrap();
        assert!(!plain.full_width);
        input.apply(InputOperation::Reset).unwrap();
        let before = typed(
            &mut input,
            if method == InputMethod::Traditional || method == InputMethod::Smart {
                "su3"
            } else {
                "a"
            },
        );
        for enabled in [true, true, false, false] {
            let result = input
                .apply(InputOperation::SetFullWidth { enabled })
                .unwrap();
            assert_eq!(result.full_width, enabled);
            assert_eq!(result.visible_text, before.visible_text);
            assert_eq!(result.candidates, before.candidates);
            assert_eq!(result.code, before.code);
            assert_eq!(result.phonetic, before.phonetic);
            assert_eq!(result.page, before.page);
            assert_eq!(result.highlight, before.highlight);
            assert!(result.effects.commit.is_empty() && !result.effects.beep);
        }
        let toggled = input.apply(InputOperation::ToggleFullWidth).unwrap();
        assert!(toggled.full_width);
        assert_eq!(toggled.visible_text, before.visible_text);
        assert_eq!(toggled.candidates, before.candidates);
        let space = input
            .apply(InputOperation::Key {
                key: Key::Space,
                modifiers: Modifiers {
                    shift: true,
                    ..Modifiers::default()
                },
            })
            .unwrap();
        assert!(
            space.full_width,
            "ordinary Shift+Space retains the semantic width"
        );
        input.apply(InputOperation::Reset).unwrap();
        let unfinished = typed(&mut input, "s");
        let toggled = input.apply(InputOperation::ToggleFullWidth).unwrap();
        assert!(!toggled.full_width);
        assert_eq!(toggled.phonetic, unfinished.phonetic);
        assert_eq!(toggled.code, unfinished.code);
        assert!(toggled.effects.commit.is_empty());
        let set = input
            .apply(InputOperation::SetFullWidth { enabled: true })
            .unwrap();
        assert!(set.effects.commit.is_empty() && set.full_width);
        input.apply(InputOperation::Reset).unwrap();
        assert_eq!(
            input
                .apply(InputOperation::DirectText { text: "A1 ".into() })
                .unwrap()
                .effects
                .commit,
            "Ａ１　"
        );
        input
            .apply(InputOperation::SetFullWidth { enabled: false })
            .unwrap();
        assert_eq!(
            input
                .apply(InputOperation::DirectText { text: "A1 ".into() })
                .unwrap()
                .effects
                .commit,
            "A1 "
        );
    }
}

#[test]
fn marked_smart_phrase_uses_the_shared_atomic_user_store_and_feedback() {
    let mut input = InputSession::open(
        model(),
        SessionConfig {
            method: InputMethod::Smart,
            ..SessionConfig::default()
        },
    )
    .unwrap();
    let before = typed(&mut input, "su3cl3su3cl3");
    let marked = input
        .apply(InputOperation::Key {
            key: Key::Home,
            modifiers: Modifiers {
                shift: true,
                ..Modifiers::default()
            },
        })
        .unwrap();
    let phrase = marked.marked_phrase.clone().unwrap();
    assert_eq!(phrase.text, "你好你好");
    assert_eq!(phrase.reading_span, 4);
    let accepted = key(&mut input, Key::Return);
    assert!(accepted.effects.commit.is_empty());
    assert_eq!(accepted.composition, before.composition);
    let feedback = accepted.effects.phrase_feedback.unwrap();
    assert!(feedback.added);
    assert_eq!(feedback.text, phrase.text);
    assert_eq!(input.user_data().unwrap().phrases.len(), 1);
    assert!(accepted.marked_phrase.is_none());
    input
        .apply(InputOperation::Key {
            key: Key::End,
            modifiers: Modifiers {
                shift: true,
                ..Modifiers::default()
            },
        })
        .unwrap();
    let duplicate = key(&mut input, Key::Return);
    assert!(!duplicate.effects.beep && duplicate.effects.commit.is_empty());
    assert!(!duplicate.effects.phrase_feedback.unwrap().added);
    assert_eq!(input.user_data().unwrap().phrases.len(), 1);
    assert!(input.snapshot().effects.phrase_feedback.is_none());
}

#[test]
fn a_stale_mark_cannot_add_or_commit_the_rewalked_text() {
    let nonce = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let directory = std::env::temp_dir().join(format!(
        "guanyinma-mark-sync-{}-{nonce}",
        std::process::id()
    ));
    std::fs::create_dir(&directory).unwrap();
    let user = directory.join("users.db");
    let config = SessionConfig {
        method: InputMethod::Smart,
        user_database: Some(user.to_string_lossy().into_owned()),
        ..SessionConfig::default()
    };
    {
        let mut active = InputSession::open(model(), config.clone()).unwrap();
        typed(&mut active, "su3cl3su3cl3");
        let marked = active
            .apply(InputOperation::Key {
                key: Key::Home,
                modifiers: Modifiers {
                    shift: true,
                    ..Modifiers::default()
                },
            })
            .unwrap()
            .marked_phrase
            .unwrap();
        assert_eq!(marked.text, "你好你好");
        let mut editor = InputSession::open(model(), config).unwrap();
        editor
            .apply(InputOperation::AddUserPhrase {
                qstring: marked.qstring,
                text: "妳好你好".into(),
            })
            .unwrap();
        let rejected = key(&mut active, Key::Return);
        assert!(rejected.effects.handled && rejected.effects.beep);
        assert!(rejected.effects.commit.is_empty());
        assert!(rejected.effects.phrase_feedback.is_none());
        assert!(rejected.marked_phrase.is_none());
        assert_eq!(rejected.composition, "妳好你好");
        let data = active.user_data().unwrap();
        assert_eq!(data.phrases.len(), 1);
        assert_eq!(data.phrases[0].current, "妳好你好");
        assert_eq!(key(&mut active, Key::Return).effects.commit, "妳好你好");
    }
    std::fs::remove_dir_all(directory).unwrap();
}

#[test]
fn trusted_graph_marks_can_store_punctuation_and_multiscalar_literal_blocks() {
    for literal in [false, true] {
        let mut input = InputSession::open(
            model(),
            SessionConfig {
                method: InputMethod::Smart,
                ..SessionConfig::default()
            },
        )
        .unwrap();
        typed(&mut input, "su3");
        if literal {
            input
                .apply(InputOperation::DirectText {
                    text: "XYZWXYZWXYZW".into(),
                })
                .unwrap();
        } else {
            input
                .apply(InputOperation::Character {
                    text: "<".into(),
                    modifiers: Modifiers {
                        shift: true,
                        ..Modifiers::default()
                    },
                })
                .unwrap();
            input.apply(InputOperation::CloseCandidates).unwrap();
        }
        let before = input.snapshot().composition;
        assert_eq!(before, if literal { "你XYZWXYZWXYZW" } else { "你，" });
        let marked = input
            .apply(InputOperation::Key {
                key: Key::Home,
                modifiers: Modifiers {
                    shift: true,
                    ..Modifiers::default()
                },
            })
            .unwrap()
            .marked_phrase
            .unwrap();
        assert_eq!(marked.reading_span, 2);
        if literal {
            assert!(marked.text.chars().count() > 8);
            assert!(marked.qstring.contains("_passthru_"));
        } else {
            assert!(marked.qstring.contains("_punctuation_"));
        }
        let added = key(&mut input, Key::Return);
        assert!(added.effects.commit.is_empty() && !added.effects.beep);
        assert!(added.effects.phrase_feedback.unwrap().added);
        assert_eq!(added.composition, before);
        input
            .apply(InputOperation::Key {
                key: Key::End,
                modifiers: Modifiers {
                    shift: true,
                    ..Modifiers::default()
                },
            })
            .unwrap();
        let duplicate = key(&mut input, Key::Return);
        assert!(!duplicate.effects.phrase_feedback.unwrap().added);
        assert!(!duplicate.effects.beep && duplicate.effects.commit.is_empty());
        let data = input.user_data().unwrap();
        assert_eq!(data.phrases.len(), 1);
        assert_eq!(data.phrases[0].qstring, marked.qstring);
        assert_eq!(data.phrases[0].current, marked.text);
        let archive = guanyinma::UserArchive::from_snapshot(&data).unwrap();
        let encoded = serde_json::to_vec(&archive).unwrap();
        let decoded = serde_json::from_slice(&encoded).unwrap();
        let mut restored = InputSession::open(model(), SessionConfig::default()).unwrap();
        restored
            .apply(InputOperation::ImportUserData { archive: decoded })
            .unwrap();
        assert_eq!(restored.user_data().unwrap().phrases, data.phrases);
        // Public editor inserts still require canonical 1..8-character readings.
        assert!(restored
            .apply(InputOperation::AddUserPhrase {
                qstring: marked.qstring,
                text: marked.text,
            })
            .is_err());
    }
}

#[test]
fn empty_smart_space_preserves_desktop_and_touch_interaction_contracts() {
    for profile in [
        guanyinma::BehaviorProfile::Desktop,
        guanyinma::BehaviorProfile::Touch,
    ] {
        for opens in [false, true] {
            for caps in [false, true] {
                let mut input = InputSession::open(
                    model(),
                    SessionConfig {
                        method: InputMethod::Smart,
                        profile,
                        smart: guanyinma::SmartOptions {
                            space_opens_candidates: opens,
                            ..guanyinma::SmartOptions::default()
                        },
                        ..SessionConfig::default()
                    },
                )
                .unwrap();
                input
                    .apply(InputOperation::SetFullWidth { enabled: true })
                    .unwrap();
                let result = input
                    .apply(InputOperation::Key {
                        key: Key::Space,
                        modifiers: Modifiers {
                            caps_lock: caps,
                            ..Modifiers::default()
                        },
                    })
                    .unwrap();
                let consumes = profile == guanyinma::BehaviorProfile::Touch || !opens || caps;
                assert_eq!(result.effects.handled, consumes);
                assert_eq!(result.effects.commit, if consumes { "　" } else { "" });
                assert!(result.full_width);
                assert!(result.visible_text.is_empty());
            }
        }
    }
}

#[test]
fn traditional_pinyin_candidate_typeahead_uses_current_reading_acceptance() {
    for (keys, allows_typeahead) in [("ni3", false), ("ni", true)] {
        let mut input = InputSession::open(
            model(),
            SessionConfig {
                method: InputMethod::Traditional,
                layout: guanyinma::bopomofo::BopomofoLayout::HanyuPinyin,
                ..SessionConfig::default()
            },
        )
        .unwrap();
        typed(&mut input, keys);
        if allows_typeahead {
            key(&mut input, Key::Space);
        }
        let before = input.snapshot();
        assert!(!before.candidates.is_empty());
        let result = typed(&mut input, "a");
        if allows_typeahead {
            assert_eq!(result.effects.commit, before.candidates[0]);
            assert_eq!(result.phonetic, "a");
            assert!(result.candidates.is_empty());
        } else {
            assert!(result.effects.handled && result.effects.beep);
            assert!(result.effects.commit.is_empty());
            assert_eq!(result.candidates, before.candidates);
            assert_eq!(result.phonetic, before.phonetic);
        }
    }
}

#[test]
fn angle_bracket_characters_are_input_and_paging_is_a_semantic_operation() {
    for (symbol, pattern) in [('>', "hk?"), ('<', "hk*")] {
        let mut input = table_input(
            InputMethod::Cangjie,
            TableOptions {
                realtime: true,
                wildcards: Some(TableWildcards {
                    one: Some('>'),
                    many: Some('<'),
                }),
                ..TableOptions::default()
            },
        );
        typed(&mut input, "hk");
        let result = typed(&mut input, &symbol.to_string());
        assert_eq!(result.code, format!("hk{symbol}"));
        let expected = guanyinma::ModelDatabase::open(model())
            .unwrap()
            .lookup_table_pattern(guanyinma::Table::Cangjie, pattern)
            .unwrap();
        assert_eq!(result.candidates, expected);
        assert_eq!(result.page, 0);
        assert!(result.effects.commit.is_empty());
    }
    let mut input = InputSession::open(
        model(),
        SessionConfig {
            method: InputMethod::Smart,
            ..SessionConfig::default()
        },
    )
    .unwrap();
    typed(&mut input, "su3");
    input
        .apply(InputOperation::OpenCandidates { index: 0 })
        .unwrap();
    let before = input.apply(InputOperation::Page { delta: 1 }).unwrap();
    assert_eq!(before.page, 1);
    let literal = typed(&mut input, ">");
    assert_eq!(literal.page, before.page);
    assert_eq!(literal.candidates, before.candidates);
    assert!(literal.effects.beep && literal.effects.commit.is_empty());
    let page = input.apply(InputOperation::Page { delta: -1 }).unwrap();
    assert_eq!(page.page, 0);
    assert_eq!(page.candidates, before.candidates);
}
