//! Public learning/persistence behavior with isolated user stores.
//!
//! Native macOS source observations supply the homophone and frequency rules.
//! These tests never read or refresh the manual migration-baseline fixtures.

mod support;

use guanyinma::bopomofo::{BopomofoLayout, BopomofoReading};
use guanyinma::{
    Effects, InputMethod, InputOperation, InputSession, Key, LearningOptions, Modifiers,
    SessionConfig, SessionSnapshot, SmartOptions, TableOptions,
};
use rusqlite::Connection;
use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT_PROFILE: AtomicU64 = AtomicU64::new(0);

struct Profile {
    directory: PathBuf,
    database: PathBuf,
}
impl Profile {
    fn new() -> Self {
        loop {
            let id = NEXT_PROFILE.fetch_add(1, Ordering::Relaxed);
            let directory = std::env::temp_dir().join(format!(
                "guanyinma-learning-session-{}-{id}",
                std::process::id()
            ));
            match fs::create_dir(&directory) {
                Ok(()) => {
                    return Self {
                        database: directory.join("user.db"),
                        directory,
                    }
                }
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(error) => panic!("create isolated profile: {error}"),
            }
        }
    }
    fn config(&self, method: InputMethod, learning: LearningOptions) -> SessionConfig {
        SessionConfig {
            method,
            user_database: Some(self.database.to_string_lossy().into_owned()),
            learning,
            smart: SmartOptions {
                space_opens_candidates: false,
                ..SmartOptions::default()
            },
            ..SessionConfig::default()
        }
    }
    fn session(&self, method: InputMethod, learning: LearningOptions) -> InputSession {
        InputSession::open(model(), self.config(method, learning)).unwrap()
    }
}
impl Drop for Profile {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.directory);
    }
}
fn model() -> PathBuf {
    support::model_path()
}
fn overrides() -> LearningOptions {
    LearningOptions {
        candidate_overrides: true,
        ..LearningOptions::default()
    }
}
fn table_learning() -> LearningOptions {
    LearningOptions {
        table_learning: true,
        ..LearningOptions::default()
    }
}
fn type_keys(input: &mut InputSession, keys: &str) -> SessionSnapshot {
    let mut snapshot = input.snapshot();
    for character in keys.chars() {
        snapshot = input.apply(InputOperation::character(character)).unwrap();
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
        .position(|value| value == text)
        .unwrap_or_else(|| panic!("candidate missing: {text}"));
    let page = index / snapshot.page_size;
    if page != snapshot.page {
        input
            .apply(InputOperation::Page {
                delta: page as i32 - snapshot.page as i32,
            })
            .unwrap();
    }
    input
        .apply(InputOperation::Select {
            index: index % snapshot.page_size,
        })
        .unwrap()
}
fn query(syllables: &[&str]) -> String {
    syllables
        .iter()
        .map(|keys| {
            let mut reading = BopomofoReading::new(BopomofoLayout::Standard);
            for character in keys.chars() {
                assert!(reading.combine(character));
            }
            reading.query_key()
        })
        .collect()
}
fn state(input: &InputSession) -> serde_json::Value {
    serde_json::to_value(input.snapshot()).unwrap()
}

#[test]
fn explicit_override_is_reused_in_the_same_session_and_after_reopening() {
    let profile = Profile::new();
    let mut input = profile.session(InputMethod::Smart, overrides());
    assert_eq!(type_keys(&mut input, "su3cl3").composition, "你好");
    open(&mut input, 0);
    assert_eq!(select_text(&mut input, "妳").composition, "妳好");
    key(&mut input, Key::End);
    assert_eq!(type_keys(&mut input, "su3").composition, "妳好妳");
    assert_eq!(key(&mut input, Key::Return).effects.commit, "妳好妳");
    let data = input.user_data().unwrap();
    assert_eq!(data.overrides.len(), 1);
    assert_eq!(data.overrides[0].qstring, r"\O");
    assert_eq!(data.overrides[0].current, "妳");
    drop(input);

    let mut reopened = profile.session(InputMethod::Smart, overrides());
    assert_eq!(type_keys(&mut reopened, "su3").composition, "妳");
    assert_eq!(&open(&mut reopened, 0).candidates[..3], ["妳", "你", "擬"]);
}

#[test]
fn choosing_the_current_promoted_first_candidate_removes_its_cached_override() {
    let profile = Profile::new();
    let mut input = profile.session(InputMethod::Smart, overrides());
    type_keys(&mut input, "g4");
    open(&mut input, 0);
    select_text(&mut input, "事");
    key(&mut input, Key::Return);
    drop(input);
    let mut input = profile.session(InputMethod::Smart, overrides());
    assert_eq!(type_keys(&mut input, "g4").composition, "事");
    assert_eq!(&open(&mut input, 0).candidates[..2], ["事", "是"]);
    select_text(&mut input, "事");
    assert!(input.user_data().unwrap().overrides.is_empty());
    key(&mut input, Key::Return);
    drop(input);
    let mut input = profile.session(InputMethod::Smart, overrides());
    assert_eq!(type_keys(&mut input, "g4").composition, "是");
}

#[test]
fn selecting_the_original_model_default_while_promoted_is_another_preference() {
    let profile = Profile::new();
    let mut input = profile.session(InputMethod::Smart, overrides());
    type_keys(&mut input, "g4");
    open(&mut input, 0);
    select_text(&mut input, "事");
    key(&mut input, Key::Return);
    drop(input);
    let mut input = profile.session(InputMethod::Smart, overrides());
    type_keys(&mut input, "g4");
    assert_eq!(&open(&mut input, 0).candidates[..2], ["事", "是"]);
    select_text(&mut input, "是");
    let data = input.user_data().unwrap();
    assert_eq!(data.overrides.len(), 1);
    assert_eq!(data.overrides[0].current, "是");
}

#[test]
fn confirming_an_automatic_guess_does_not_create_preferences_or_bigrams() {
    let profile = Profile::new();
    let mut input = profile.session(
        InputMethod::Smart,
        LearningOptions {
            candidate_overrides: true,
            bigrams: true,
            ..LearningOptions::default()
        },
    );
    type_keys(&mut input, "g4su3cl3");
    key(&mut input, Key::Return);
    let data = input.user_data().unwrap();
    assert!(data.overrides.is_empty());
    assert!(data.bigrams.is_empty());
    assert!(data.phrases.is_empty());
    let revision = data.revision;
    input.apply(InputOperation::SaveLearning).unwrap();
    input.apply(InputOperation::SaveLearning).unwrap();
    assert_eq!(input.user_data().unwrap().revision, revision);
    assert_eq!(input.snapshot().effects, Effects::default());
}

#[test]
fn adjacent_explicit_selection_learns_context_without_reordering_unigrams() {
    let profile = Profile::new();
    let options = LearningOptions {
        bigrams: true,
        ..LearningOptions::default()
    };
    let mut input = profile.session(InputMethod::Smart, options);
    assert_eq!(type_keys(&mut input, "g4su3").composition, "是你");
    open(&mut input, 1);
    assert_eq!(select_text(&mut input, "妳").composition, "是妳");
    let data = input.user_data().unwrap();
    assert!(data.overrides.is_empty());
    assert_eq!(data.bigrams.len(), 1);
    assert_eq!(data.bigrams[0].qstring, r"0_ \O");
    assert_eq!(data.bigrams[0].previous, "是");
    assert_eq!(data.bigrams[0].current, "妳");
    key(&mut input, Key::Return);
    drop(input);
    let mut input = profile.session(
        InputMethod::Smart,
        LearningOptions {
            bigrams: true,
            ..LearningOptions::default()
        },
    );
    assert_eq!(type_keys(&mut input, "g4su3").composition, "是妳");
    assert_eq!(&open(&mut input, 1).candidates[..2], ["你", "妳"]);
}

#[test]
fn disabled_context_scoring_pauses_new_bigram_learning() {
    let profile = Profile::new();
    let mut config = profile.config(
        InputMethod::Smart,
        LearningOptions {
            candidate_overrides: true,
            bigrams: true,
            ..LearningOptions::default()
        },
    );
    config.smart.use_bigrams = false;
    let mut input = InputSession::open(model(), config).unwrap();
    type_keys(&mut input, "g4su3");
    open(&mut input, 1);
    select_text(&mut input, "妳");
    let data = input.user_data().unwrap();
    assert!(data.bigrams.is_empty());
    assert_eq!(data.overrides[0].current, "妳");
}

#[test]
fn punctuation_selection_does_not_create_candidate_or_context_learning() {
    let profile = Profile::new();
    let mut input = profile.session(
        InputMethod::Smart,
        LearningOptions {
            candidate_overrides: true,
            bigrams: true,
            ..LearningOptions::default()
        },
    );
    assert_eq!(type_keys(&mut input, "su3").composition, "你");
    let panel = input
        .apply(InputOperation::Character {
            text: "0".into(),
            modifiers: Modifiers {
                control: true,
                ..Modifiers::default()
            },
        })
        .unwrap();
    assert!(panel.candidates.contains(&"；".into()));
    assert_eq!(select_text(&mut input, "；").composition, "你；");
    let data = input.user_data().unwrap();
    assert!(data.overrides.is_empty());
    assert!(data.bigrams.is_empty());
}

#[test]
fn disabling_preferences_preserves_stored_choices_for_reenabling() {
    let profile = Profile::new();
    let mut input = profile.session(InputMethod::Smart, overrides());
    type_keys(&mut input, "g4");
    open(&mut input, 0);
    select_text(&mut input, "事");
    key(&mut input, Key::Return);
    input
        .apply(InputOperation::SetLearningOptions {
            options: LearningOptions::default(),
        })
        .unwrap();
    assert_eq!(type_keys(&mut input, "g4").composition, "是");
    key(&mut input, Key::Return);
    assert_eq!(input.user_data().unwrap().overrides[0].current, "事");
    input
        .apply(InputOperation::SetLearningOptions {
            options: overrides(),
        })
        .unwrap();
    assert_eq!(type_keys(&mut input, "g4").composition, "事");
}

#[test]
fn custom_phrases_are_idempotent_persist_and_survive_learning_reset() {
    let profile = Profile::new();
    let qstring = query(&["fu6", "fu6"]);
    let mut input = profile.session(InputMethod::Smart, overrides());
    for _ in 0..2 {
        input
            .apply(InputOperation::AddUserPhrase {
                qstring: qstring.clone(),
                text: "琦琦".into(),
            })
            .unwrap();
    }
    input
        .apply(InputOperation::AddUserPhrase {
            qstring: query(&["su3", "cl3"]),
            text: "你好".into(),
        })
        .unwrap();
    assert_eq!(input.user_data().unwrap().phrases.len(), 1);
    assert_eq!(type_keys(&mut input, "fu6fu6").composition, "琦琦");
    key(&mut input, Key::Return);
    type_keys(&mut input, "g4");
    open(&mut input, 0);
    select_text(&mut input, "事");
    assert_eq!(input.user_data().unwrap().overrides.len(), 1);
    input.apply(InputOperation::ResetLearning).unwrap();
    assert_eq!(input.snapshot().composition, "事");
    let data = input.user_data().unwrap();
    assert!(data.overrides.is_empty());
    assert!(data.bigrams.is_empty());
    assert_eq!(data.phrases.len(), 1);
    assert_eq!(data.phrases[0].current, "琦琦");
    key(&mut input, Key::Return);
    drop(input);

    let mut input = profile.session(InputMethod::Smart, overrides());
    assert_eq!(type_keys(&mut input, "fu6fu6").composition, "琦琦");
    key(&mut input, Key::Return);
    input
        .apply(InputOperation::RemoveUserPhrase {
            qstring: qstring.clone(),
            text: "琦琦".into(),
        })
        .unwrap();
    input
        .apply(InputOperation::RemoveUserPhrase {
            qstring,
            text: "琦琦".into(),
        })
        .unwrap();
    assert!(input.user_data().unwrap().phrases.is_empty());
    type_keys(&mut input, "fu6fu6");
    assert!(!open(&mut input, 0)
        .candidates
        .iter()
        .any(|text| text == "琦琦"));
}

#[test]
fn table_learning_promotes_exact_candidates_and_keeps_insertion_order_for_ties() {
    let profile = Profile::new();
    let mut input = profile.session(InputMethod::Cangjie, table_learning());
    type_keys(&mut input, "a");
    assert_eq!(key(&mut input, Key::Space).candidates, ["日", "曰"]);
    select_text(&mut input, "曰");
    drop(input);
    let mut input = profile.session(InputMethod::Cangjie, table_learning());
    type_keys(&mut input, "a");
    assert_eq!(key(&mut input, Key::Space).candidates, ["曰", "日"]);
    select_text(&mut input, "曰");
    assert_eq!(input.user_data().unwrap().table[0].count, 1);
    type_keys(&mut input, "a");
    key(&mut input, Key::Space);
    select_text(&mut input, "日");
    type_keys(&mut input, "a");
    assert_eq!(key(&mut input, Key::Space).candidates, ["曰", "日"]);
    select_text(&mut input, "日");
    type_keys(&mut input, "a");
    assert_eq!(key(&mut input, Key::Space).candidates, ["日", "曰"]);
    let data = input.user_data().unwrap();
    assert_eq!(
        data.table
            .iter()
            .find(|row| row.current == "日")
            .unwrap()
            .count,
        2
    );
    assert_eq!(
        data.table
            .iter()
            .find(|row| row.current == "曰")
            .unwrap()
            .count,
        1
    );
}

#[test]
fn prefix_only_selection_is_not_learned_and_simplex_requires_its_own_switch() {
    let profile = Profile::new();
    let mut config = profile.config(InputMethod::Cangjie, table_learning());
    config.cangjie = Some(TableOptions {
        realtime: true,
        prefix: true,
        ..TableOptions::default()
    });
    let mut input = InputSession::open(model(), config).unwrap();
    assert!(type_keys(&mut input, "hk")
        .candidates
        .contains(&"喬".into()));
    select_text(&mut input, "喬");
    assert!(input.user_data().unwrap().table.is_empty());

    input
        .apply(InputOperation::SetMethod {
            method: InputMethod::Simplex,
        })
        .unwrap();
    type_keys(&mut input, "ab");
    select_text(&mut input, "晴");
    assert!(input.user_data().unwrap().table.is_empty());
    input
        .apply(InputOperation::SetTableOptions {
            method: InputMethod::Simplex,
            options: TableOptions {
                learn_selection: true,
                ..TableOptions::simplex()
            },
        })
        .unwrap();
    let page = type_keys(&mut input, "ab");
    let text = page.candidates[page.page_size].clone();
    // A page-local zero is still a non-first candidate in the complete list.
    input.apply(InputOperation::Page { delta: 1 }).unwrap();
    input.apply(InputOperation::Select { index: 0 }).unwrap();
    let data = input.user_data().unwrap();
    assert_eq!(data.table.len(), 1);
    assert_eq!(data.table[0].code, "ab");
    assert_eq!(data.table[0].current, text);
}

#[test]
fn separate_sessions_merge_unrelated_choices_and_do_not_resurrect_reset_learning() {
    let profile = Profile::new();
    let mut first = profile.session(InputMethod::Smart, overrides());
    let mut second = profile.session(InputMethod::Smart, overrides());
    type_keys(&mut first, "g4");
    type_keys(&mut second, "su3");
    open(&mut second, 0);
    select_text(&mut second, "妳");
    open(&mut first, 0);
    select_text(&mut first, "事");
    assert_eq!(first.user_data().unwrap().overrides.len(), 2);
    second.apply(InputOperation::ResetLearning).unwrap();
    first.apply(InputOperation::SaveLearning).unwrap();
    assert!(first.user_data().unwrap().overrides.is_empty());
    // The currently selected word remains explicit until this composition ends.
    assert_eq!(key(&mut first, Key::Return).effects.commit, "事");
    assert_eq!(type_keys(&mut first, "g4").composition, "是");
    drop(first);
    drop(second);
    let input = profile.session(InputMethod::Smart, overrides());
    assert!(input.user_data().unwrap().overrides.is_empty());
}

#[test]
fn write_failure_rolls_back_selection_and_allows_retry_after_the_lock_is_released() {
    let profile = Profile::new();
    let mut input = profile.session(InputMethod::Smart, overrides());
    type_keys(&mut input, "g4");
    open(&mut input, 0);
    let before = state(&input);
    let blocker = Connection::open(&profile.database).unwrap();
    blocker.execute_batch("BEGIN IMMEDIATE").unwrap();
    assert!(input.apply(InputOperation::Select { index: 1 }).is_err());
    assert_eq!(state(&input), before);
    blocker.execute_batch("ROLLBACK").unwrap();
    let selected = input.apply(InputOperation::Select { index: 1 }).unwrap();
    assert_eq!(selected.composition, "事");
    assert_eq!(input.user_data().unwrap().overrides[0].current, "事");
}

#[test]
fn explicit_legacy_import_reads_a_copy_without_modifying_the_source() {
    let profile = Profile::new();
    let source = profile.directory.join("legacy-smart.db");
    let qstring = query(&["fu6", "fu6"]);
    {
        let old = Connection::open(&source).unwrap();
        old.execute_batch(
            "CREATE TABLE user_unigrams(qstring,current,probability,backoff);
             CREATE TABLE user_candidate_override_cache(qstring,current);
             CREATE TABLE user_bigram_cache(qstring,previous,current,probability);",
        )
        .unwrap();
        old.execute(
            "INSERT INTO user_unigrams VALUES(?1,'琦琦','-0.0000001',-2.5)",
            [&qstring],
        )
        .unwrap();
        // Historical macOS migration quoted probability with SQLite %Q.
        let stored_type: String = old
            .query_row("SELECT typeof(probability) FROM user_unigrams", [], |row| {
                row.get(0)
            })
            .unwrap();
        assert_eq!(stored_type, "text");
        old.execute(
            "INSERT INTO user_candidate_override_cache VALUES('0_','事')",
            [],
        )
        .unwrap();
        old.execute(
            r"INSERT INTO user_bigram_cache VALUES('0_ \O','是','妳',0.0)",
            [],
        )
        .unwrap();
    }
    let before = fs::read(&source).unwrap();
    let mut input = profile.session(
        InputMethod::Smart,
        LearningOptions {
            candidate_overrides: true,
            bigrams: true,
            ..LearningOptions::default()
        },
    );
    input
        .apply(InputOperation::ImportLegacyUserData {
            path: source.to_string_lossy().into_owned(),
            method: None,
        })
        .unwrap();
    assert_eq!(fs::read(&source).unwrap(), before);
    let data = input.user_data().unwrap();
    assert_eq!(data.phrases[0].current, "琦琦");
    assert_eq!(data.overrides[0].current, "事");
    assert_eq!(data.bigrams[0].current, "妳");
    assert_eq!(type_keys(&mut input, "g4").composition, "事");
}

#[test]
fn portable_smart_import_preserves_table_learning_and_refreshes_active_composition() {
    let profile = Profile::new();
    let mut input = profile.session(InputMethod::Smart, overrides());
    let mut archive = guanyinma::UserArchive::from_snapshot(&guanyinma::UserSnapshot {
        table: vec![
            guanyinma::TableLearning {
                method: "cangjie".into(),
                code: "a".into(),
                current: "曰".into(),
                count: 9,
            },
            guanyinma::TableLearning {
                method: "simplex".into(),
                code: "ab".into(),
                current: "明".into(),
                count: 4,
            },
        ],
        ..guanyinma::UserSnapshot::default()
    })
    .unwrap();
    input
        .apply(InputOperation::ImportUserData {
            archive: archive.clone(),
        })
        .unwrap();
    let table = input.user_data().unwrap().table;
    assert_eq!(type_keys(&mut input, "su3").composition, "你");
    open(&mut input, 0);
    let before_generation = input.user_data().unwrap().generation;
    archive.table = None;
    archive
        .smart
        .as_mut()
        .unwrap()
        .overrides
        .push(guanyinma::CandidateOverride {
            qstring: query(&["su3"]),
            current: "妳".into(),
        });
    let imported = input
        .apply(InputOperation::ImportUserData { archive })
        .unwrap();
    assert_eq!(imported.composition, "妳");
    assert!(imported.candidates.is_empty());
    assert!(imported.effects.commit.is_empty());
    assert_eq!(input.user_data().unwrap().table, table);
    assert!(input.user_data().unwrap().generation > before_generation);
    key(&mut input, Key::Return);
    assert_eq!(type_keys(&mut input, "su3").composition, "妳");
    assert_eq!(
        profile
            .session(InputMethod::Smart, overrides())
            .user_data()
            .unwrap(),
        input.user_data().unwrap()
    );
}

#[test]
fn portable_import_validation_and_locked_commit_preserve_input_and_all_user_data() {
    let profile = Profile::new();
    let mut input = profile.session(InputMethod::Cangjie, table_learning());
    type_keys(&mut input, "m");
    let before = state(&input);
    let data = input.user_data().unwrap();
    // Programmatic callers can construct values without deserialization, so the
    // operation boundary must independently reject the invalid archive too.
    let mut invalid = guanyinma::UserArchive::from_snapshot(&data).unwrap();
    invalid.phrases.push(guanyinma::Unigram {
        qstring: "query".into(),
        current: "詞".into(),
        probability: f64::NAN,
        backoff: 0.0,
    });
    assert!(input
        .apply(InputOperation::ImportUserData { archive: invalid })
        .is_err());
    assert_eq!(state(&input), before);
    assert_eq!(input.user_data().unwrap(), data);

    let mut valid = guanyinma::UserArchive::from_snapshot(&data).unwrap();
    valid.phrases.push(guanyinma::Unigram {
        qstring: query(&["fu6", "fu6"]),
        current: "琦琦".into(),
        probability: -0.0000001,
        backoff: -2.0,
    });
    let writer = Connection::open(&profile.database).unwrap();
    writer.execute_batch("BEGIN IMMEDIATE").unwrap();
    assert!(input
        .apply(InputOperation::ImportUserData { archive: valid })
        .is_err());
    assert_eq!(state(&input), before);
    assert_eq!(input.user_data().unwrap(), data);
    writer.execute_batch("ROLLBACK").unwrap();
    assert_eq!(
        profile
            .session(InputMethod::Cangjie, table_learning())
            .user_data()
            .unwrap(),
        data
    );
}

#[test]
fn invalid_user_paths_and_phrase_requests_do_not_modify_active_input() {
    let profile = Profile::new();
    // Even a regression in the same-file guard must only affect a disposable copy.
    let copied_model = profile.directory.join("model-copy.db");
    fs::copy(model(), &copied_model).unwrap();
    let mut bad = profile.config(InputMethod::Smart, overrides());
    bad.user_database = Some(copied_model.to_string_lossy().into_owned());
    assert!(InputSession::open(&copied_model, bad).is_err());
    let mut input = profile.session(InputMethod::Smart, overrides());
    type_keys(&mut input, "su3cl");
    let before = state(&input);
    for operation in [
        InputOperation::AddUserPhrase {
            qstring: "\0".into(),
            text: "詞".into(),
        },
        InputOperation::AddUserPhrase {
            qstring: query(&["su3"]),
            text: "兩字".into(),
        },
        InputOperation::RemoveUserPhrase {
            qstring: "bad\0".into(),
            text: "詞".into(),
        },
    ] {
        assert!(input.apply(operation).is_err());
        assert_eq!(state(&input), before);
        assert!(input.user_data().unwrap().phrases.is_empty());
    }
}

#[test]
fn editing_a_custom_phrase_is_atomic_and_persists_the_new_reading() {
    let profile = Profile::new();
    let old_query = query(&["fu6", "fu6"]);
    let new_query = query(&["fu6", "au04"]);
    let mut input = profile.session(InputMethod::Smart, LearningOptions::default());
    input
        .apply(InputOperation::AddUserPhrase {
            qstring: old_query.clone(),
            text: "琦琦".into(),
        })
        .unwrap();
    let before = input.user_data().unwrap();
    assert!(input
        .apply(InputOperation::UpdateUserPhrase {
            qstring: old_query.clone(),
            text: "琦琦".into(),
            new_qstring: "\0".into(),
            new_text: "琦麵".into(),
        })
        .is_err());
    assert_eq!(input.user_data().unwrap(), before);
    input
        .apply(InputOperation::UpdateUserPhrase {
            qstring: old_query,
            text: "琦琦".into(),
            new_qstring: new_query.clone(),
            new_text: "琦麵".into(),
        })
        .unwrap();
    let data = input.user_data().unwrap();
    assert_eq!(data.phrases.len(), 1);
    assert_eq!(data.phrases[0].qstring, new_query);
    assert_eq!(data.phrases[0].current, "琦麵");
    drop(input);
    let mut reopened = profile.session(InputMethod::Smart, LearningOptions::default());
    assert_eq!(type_keys(&mut reopened, "fu6au04").composition, "琦麵");
}

#[test]
fn stale_smart_panel_actions_are_consumed_after_an_external_reorder_or_reset() {
    for external_reset in [false, true] {
        for action in [
            InputOperation::Select { index: 1 },
            InputOperation::character('2'),
            InputOperation::key(Key::Return),
        ] {
            let profile = Profile::new();
            let mut other = profile.session(InputMethod::Smart, overrides());
            if external_reset {
                type_keys(&mut other, "g4");
                open(&mut other, 0);
                select_text(&mut other, "事");
                key(&mut other, Key::Return);
            }
            let mut input = profile.session(InputMethod::Smart, overrides());
            type_keys(&mut input, "g4");
            let old = open(&mut input, 0);
            assert_eq!(
                &old.candidates[..2],
                if external_reset {
                    ["事", "是"]
                } else {
                    ["是", "事"]
                },
            );
            if external_reset {
                other.apply(InputOperation::ResetLearning).unwrap();
            } else {
                type_keys(&mut other, "g4");
                open(&mut other, 0);
                select_text(&mut other, "事");
            }
            let stale = input.apply(action).unwrap();
            assert!(stale.effects.handled);
            assert!(stale.effects.beep);
            assert!(stale.effects.commit.is_empty());
            assert!(stale.candidates.is_empty());
            assert!(stale.candidate_spans.is_empty());
            let data = input.user_data().unwrap();
            if external_reset {
                assert!(data.overrides.is_empty());
            } else {
                assert_eq!(data.overrides.len(), 1);
                assert_eq!(data.overrides[0].current, "事");
            }
            let refreshed = open(&mut input, 0);
            assert_eq!(
                &refreshed.candidates[..2],
                if external_reset {
                    ["是", "事"]
                } else {
                    ["事", "是"]
                },
            );
            let selected = select_text(&mut input, if external_reset { "事" } else { "是" });
            assert_eq!(
                selected.composition,
                if external_reset { "事" } else { "是" }
            );
            assert!(!selected.effects.beep);
        }
    }
}

#[test]
fn stale_table_selection_never_commits_a_reassigned_candidate_index() {
    for external_reset in [false, true] {
        let profile = Profile::new();
        let mut other = profile.session(InputMethod::Cangjie, table_learning());
        if external_reset {
            type_keys(&mut other, "a");
            key(&mut other, Key::Space);
            select_text(&mut other, "曰");
        }
        let mut input = profile.session(InputMethod::Cangjie, table_learning());
        type_keys(&mut input, "a");
        let old = key(&mut input, Key::Space);
        assert_eq!(
            old.candidates,
            if external_reset {
                ["曰", "日"]
            } else {
                ["日", "曰"]
            },
        );
        if external_reset {
            other.apply(InputOperation::ResetLearning).unwrap();
        } else {
            type_keys(&mut other, "a");
            key(&mut other, Key::Space);
            select_text(&mut other, "曰");
        }
        let stale = input.apply(InputOperation::Select { index: 1 }).unwrap();
        assert!(stale.effects.handled);
        assert!(stale.effects.beep);
        assert!(stale.effects.commit.is_empty());
        assert!(stale.candidates.is_empty());
        let data = input.user_data().unwrap();
        if external_reset {
            assert!(data.table.is_empty());
        } else {
            assert_eq!(data.table.len(), 1);
            assert_eq!(data.table[0].current, "曰");
            assert_eq!(data.table[0].count, 1);
        }
        let refreshed = key(&mut input, Key::Space);
        assert_eq!(
            refreshed.candidates,
            if external_reset {
                ["日", "曰"]
            } else {
                ["曰", "日"]
            },
        );
        let selected = select_text(&mut input, if external_reset { "曰" } else { "日" });
        assert_eq!(
            selected.effects.commit,
            if external_reset { "曰" } else { "日" }
        );
        assert!(!selected.effects.beep);
    }
}

#[test]
fn unrelated_user_data_changes_preserve_candidate_page_and_highlight() {
    for method in [InputMethod::Smart, InputMethod::Simplex] {
        let profile = Profile::new();
        let mut input = profile.session(method, overrides());
        if method == InputMethod::Smart {
            type_keys(&mut input, "g4");
            open(&mut input, 0);
        } else {
            type_keys(&mut input, "ab");
        }
        input.apply(InputOperation::Page { delta: 1 }).unwrap();
        let before = input
            .apply(InputOperation::MoveHighlight { delta: 1 })
            .unwrap();
        let selected =
            before.candidates[before.page * before.page_size + before.highlight.unwrap()].clone();
        let mut other = profile.session(InputMethod::Smart, LearningOptions::default());
        other
            .apply(InputOperation::AddUserPhrase {
                qstring: query(&["fu6", "fu6"]),
                text: "琦琦".into(),
            })
            .unwrap();
        let after = key(&mut input, Key::Return);
        assert!(!after.effects.beep, "{method:?}");
        if method == InputMethod::Smart {
            assert_eq!(after.composition, selected);
            assert!(after.effects.commit.is_empty());
        } else {
            assert_eq!(after.effects.commit, selected);
            assert!(after.composition.is_empty());
        }
        assert_eq!(input.user_data().unwrap().phrases[0].current, "琦琦");
    }
}

#[test]
fn method_scoped_learning_resets_preserve_other_methods_and_custom_phrases() {
    let profile = Profile::new();
    let mut input = profile.session(
        InputMethod::Smart,
        LearningOptions {
            candidate_overrides: true,
            table_learning: true,
            ..LearningOptions::default()
        },
    );
    input
        .apply(InputOperation::AddUserPhrase {
            qstring: query(&["fu6", "fu6"]),
            text: "琦琦".into(),
        })
        .unwrap();
    type_keys(&mut input, "g4");
    open(&mut input, 0);
    select_text(&mut input, "事");
    key(&mut input, Key::Return);
    input
        .apply(InputOperation::SetMethod {
            method: InputMethod::Cangjie,
        })
        .unwrap();
    type_keys(&mut input, "a");
    key(&mut input, Key::Space);
    select_text(&mut input, "曰");
    let before = input.user_data().unwrap();
    assert_eq!(before.overrides.len(), 1);
    assert_eq!(before.table[0].current, "曰");
    assert_eq!(before.table[0].count, 1);

    input
        .apply(InputOperation::ResetMethodLearning {
            method: InputMethod::Smart,
        })
        .unwrap();
    let smart_reset = input.user_data().unwrap();
    assert!(smart_reset.overrides.is_empty());
    assert!(smart_reset.bigrams.is_empty());
    assert_eq!(smart_reset.table, before.table);
    assert_eq!(smart_reset.phrases, before.phrases);
    input
        .apply(InputOperation::SetMethod {
            method: InputMethod::Smart,
        })
        .unwrap();
    assert_eq!(type_keys(&mut input, "g4").composition, "是");
    open(&mut input, 0);
    select_text(&mut input, "事");
    key(&mut input, Key::Return);
    let learned_again = input.user_data().unwrap();

    input
        .apply(InputOperation::ResetMethodLearning {
            method: InputMethod::Cangjie,
        })
        .unwrap();
    let table_reset = input.user_data().unwrap();
    assert!(table_reset.table.is_empty());
    assert_eq!(table_reset.overrides, learned_again.overrides);
    assert_eq!(table_reset.phrases, learned_again.phrases);
    input
        .apply(InputOperation::SetMethod {
            method: InputMethod::Cangjie,
        })
        .unwrap();
    type_keys(&mut input, "a");
    assert_eq!(key(&mut input, Key::Space).candidates, ["日", "曰"]);
    select_text(&mut input, "日");
    input
        .apply(InputOperation::SetMethod {
            method: InputMethod::Smart,
        })
        .unwrap();
    assert_eq!(type_keys(&mut input, "g4").composition, "事");
    assert_eq!(input.user_data().unwrap().phrases[0].current, "琦琦");
}

#[test]
fn replace_user_phrases_removes_deleted_rows_preserves_learning_and_is_idempotent() {
    let profile = Profile::new();
    let mut input = profile.session(InputMethod::Cangjie, table_learning());
    type_keys(&mut input, "a");
    key(&mut input, Key::Space);
    select_text(&mut input, "曰");
    let initial = input.user_data().unwrap();
    assert!(!initial.table.is_empty());
    let phrase = guanyinma::Unigram {
        qstring: query(&["fu6", "fu6"]),
        current: "琦琦".into(),
        probability: -1.0,
        backoff: 0.0,
    };
    input
        .apply(InputOperation::ReplaceUserPhrases {
            phrases: vec![phrase.clone()],
        })
        .unwrap();
    let published = input.user_data().unwrap();
    assert_eq!(published.phrases.as_slice(), std::slice::from_ref(&phrase));
    assert_eq!(published.table, initial.table);
    assert_eq!(published.generation, initial.generation);
    input
        .apply(InputOperation::ReplaceUserPhrases {
            phrases: vec![phrase],
        })
        .unwrap();
    assert_eq!(input.user_data().unwrap(), published);
    input
        .apply(InputOperation::ReplaceUserPhrases { phrases: vec![] })
        .unwrap();
    let removed = input.user_data().unwrap();
    assert!(removed.phrases.is_empty());
    assert_eq!(removed.table, initial.table);
    assert_eq!(removed.overrides, initial.overrides);
    assert_eq!(removed.bigrams, initial.bigrams);
    assert_eq!(
        profile
            .session(InputMethod::Cangjie, table_learning())
            .user_data()
            .unwrap(),
        removed
    );
}

#[test]
fn replace_user_phrases_invalid_batch_or_locked_write_preserves_active_input() {
    let profile = Profile::new();
    let mut input = profile.session(InputMethod::Cangjie, table_learning());
    type_keys(&mut input, "m");
    let before = state(&input);
    let data = input.user_data().unwrap();
    let phrase = guanyinma::Unigram {
        qstring: query(&["fu6", "fu6"]),
        current: "琦琦".into(),
        probability: -1.0,
        backoff: 0.0,
    };
    assert!(input
        .apply(InputOperation::ReplaceUserPhrases {
            phrases: vec![phrase.clone(), phrase.clone()],
        })
        .is_err());
    assert_eq!(state(&input), before);
    assert_eq!(input.user_data().unwrap(), data);
    let writer = Connection::open(&profile.database).unwrap();
    writer.execute_batch("BEGIN IMMEDIATE").unwrap();
    assert!(input
        .apply(InputOperation::ReplaceUserPhrases {
            phrases: vec![phrase]
        })
        .is_err());
    assert_eq!(state(&input), before);
    assert_eq!(input.user_data().unwrap(), data);
    writer.execute_batch("ROLLBACK").unwrap();
    assert_eq!(
        profile
            .session(InputMethod::Cangjie, table_learning())
            .user_data()
            .unwrap(),
        data
    );
}
