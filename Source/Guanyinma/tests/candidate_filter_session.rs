//! Session contracts for frontend font/encoding eligibility; no migration fixtures.
mod support;

use guanyinma::{
    CandidateFilter, InputMethod, InputOperation, InputSession, Key, LearningOptions,
    ModelDatabase, SessionConfig, SessionSnapshot, Table, TableOptions,
};
use std::path::PathBuf;

fn model() -> PathBuf {
    support::model_path()
}
fn input(method: InputMethod, filter: CandidateFilter, prefix: bool) -> InputSession {
    InputSession::open_with_candidate_filter(
        model(),
        SessionConfig {
            method,
            learning: LearningOptions {
                table_learning: true,
                ..LearningOptions::default()
            },
            cangjie: Some(TableOptions {
                realtime: prefix,
                prefix,
                ..TableOptions::default()
            }),
            ..SessionConfig::default()
        },
        filter,
    )
    .unwrap()
}
fn type_keys(input: &mut InputSession, keys: &str) -> SessionSnapshot {
    let mut result = input.snapshot();
    for character in keys.chars() {
        result = input.apply(InputOperation::character(character)).unwrap();
    }
    result
}
fn key(input: &mut InputSession, key: Key) -> SessionSnapshot {
    input.apply(InputOperation::key(key)).unwrap()
}
fn hk_filter() -> CandidateFilter {
    CandidateFilter::new(|text| !matches!(text, "𥫜" | "\u{fd952}" | "𠆥"))
}

#[test]
fn cangjie_hk_filters_exact_rows_before_prefix_numbering_and_does_not_learn_extras() {
    let raw = ModelDatabase::open(model())
        .unwrap()
        .lookup_table(Table::Cangjie, "hk")
        .unwrap();
    assert_eq!(raw, ["夭", "𥫜", "\u{fd952}", "𠆥"]);
    let mut input = input(InputMethod::Cangjie, hk_filter(), true);
    let queried = type_keys(&mut input, "hk");
    assert_eq!(&queried.candidates[..2], ["夭", "喬"]);
    assert_eq!(&queried.displayed_candidates[..2], ["夭", "喬"]);
    assert_eq!(queried.candidates.len(), 37);
    let selected = type_keys(&mut input, "2");
    assert_eq!(selected.effects.commit, "喬");
    assert!(selected.candidates.is_empty());
    assert!(input.user_data().unwrap().table.is_empty());
    let again = type_keys(&mut input, "hk");
    assert_eq!(&again.candidates[..2], ["夭", "喬"]);
}

#[test]
fn wildcard_filtering_keeps_source_order_and_page_local_selection() {
    let raw = ModelDatabase::open(model())
        .unwrap()
        .lookup_table_pattern(Table::Cangjie, "hk?")
        .unwrap();
    let allowed = raw
        .iter()
        .filter(|text| text.chars().all(|c| (c as u32) <= 0xffff))
        .cloned()
        .collect::<Vec<_>>();
    assert!(allowed.len() > 9);
    let mut input = input(
        InputMethod::Cangjie,
        CandidateFilter::new(|text| text.chars().all(|c| (c as u32) <= 0xffff)),
        false,
    );
    type_keys(&mut input, "hk?");
    let queried = key(&mut input, Key::Space);
    assert_eq!(queried.candidates, allowed);
    input.apply(InputOperation::Page { delta: 1 }).unwrap();
    let selected = input.apply(InputOperation::Select { index: 1 }).unwrap();
    assert_eq!(selected.effects.commit, allowed[10]);
    assert!(input
        .user_data()
        .unwrap()
        .table
        .iter()
        .any(|row| row.current == allowed[10]));
}

#[test]
fn table_filter_controls_zero_and_single_candidate_confirmation() {
    for method in [InputMethod::Cangjie, InputMethod::Simplex] {
        let mut only = input(method, CandidateFilter::new(|text| text == "曰"), false);
        type_keys(&mut only, "a");
        assert_eq!(key(&mut only, Key::Space).effects.commit, "曰");
        let mut none = input(method, CandidateFilter::new(|_| false), false);
        type_keys(&mut none, "a");
        let result = key(&mut none, Key::Space);
        assert!(result.effects.commit.is_empty());
        assert!(result.effects.beep);
        assert!(result.candidates.is_empty());
    }
}

#[test]
fn traditional_filter_runs_before_single_candidate_auto_commit() {
    let mut only = input(
        InputMethod::Traditional,
        CandidateFilter::new(|text| text == "中"),
        false,
    );
    type_keys(&mut only, "5j/");
    let result = key(&mut only, Key::Space);
    assert_eq!(result.effects.commit, "中");
    assert!(result.candidates.is_empty());
    let mut none = input(
        InputMethod::Traditional,
        CandidateFilter::new(|_| false),
        false,
    );
    type_keys(&mut none, "5j/");
    let result = key(&mut none, Key::Space);
    assert!(result.effects.commit.is_empty());
    assert!(result.effects.beep);
    assert!(result.candidates.is_empty());
}

#[test]
fn rejected_table_rows_cannot_return_through_saved_learning() {
    let mut input = input(
        InputMethod::Cangjie,
        CandidateFilter::new(|text| text != "日"),
        false,
    );
    let archive = guanyinma::UserArchive::from_snapshot(&guanyinma::UserSnapshot {
        table: vec![guanyinma::TableLearning {
            method: "cangjie".into(),
            code: "a".into(),
            current: "日".into(),
            count: 7,
        }],
        ..guanyinma::UserSnapshot::default()
    })
    .unwrap();
    input
        .apply(InputOperation::ImportUserData { archive })
        .unwrap();
    type_keys(&mut input, "a");
    assert_eq!(key(&mut input, Key::Space).effects.commit, "曰");
    let stored = input.user_data().unwrap();
    assert_eq!(stored.table.len(), 1);
    assert_eq!(stored.table[0].current, "日");
    assert_eq!(stored.table[0].count, 7);
    input
        .apply(InputOperation::SetMethod {
            method: InputMethod::Smart,
        })
        .unwrap();
    let snapshot = type_keys(&mut input, "5j/ ");
    assert!(!snapshot.composition.contains('日'));
}

#[test]
fn smart_session_filters_composition_candidates_and_all_rejected_readings() {
    let mut only = input(
        InputMethod::Smart,
        CandidateFilter::new(|text| text == "中"),
        false,
    );
    let snapshot = type_keys(&mut only, "5j/ ");
    assert_eq!(snapshot.composition, "中");
    let opened = only
        .apply(InputOperation::OpenCandidates { index: 0 })
        .unwrap();
    // The canonical Smart UI opens only when at least two candidates remain.
    assert!(opened.candidates.is_empty());
    assert!(opened.effects.beep);
    assert_eq!(key(&mut only, Key::Return).effects.commit, "中");
    let mut pair = input(
        InputMethod::Smart,
        CandidateFilter::new(|text| matches!(text, "是" | "事")),
        false,
    );
    assert_eq!(type_keys(&mut pair, "g4").composition, "是");
    let opened = pair
        .apply(InputOperation::OpenCandidates { index: 0 })
        .unwrap();
    assert_eq!(opened.candidates, ["是", "事"]);
    let selected = pair.apply(InputOperation::Select { index: 1 }).unwrap();
    assert_eq!(selected.composition, "事");
    assert_eq!(key(&mut pair, Key::Return).effects.commit, "事");
    let mut none = input(InputMethod::Smart, CandidateFilter::new(|_| false), false);
    let snapshot = type_keys(&mut none, "5j/ ");
    assert!(snapshot.composition.is_empty());
    assert!(snapshot.readings.is_empty());
    assert!(snapshot.candidates.is_empty());
    assert!(snapshot.effects.commit.is_empty());
    assert!(snapshot.effects.beep);
}
