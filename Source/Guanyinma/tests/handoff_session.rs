//! Explicit, atomic frontend handoff policies. No platform presets or UI.
mod support;

use guanyinma::{InputMethod, InputOperation, InputSession, Key, LearningOptions, SessionConfig};

fn session(method: InputMethod) -> InputSession {
    InputSession::open(
        support::model_path(),
        SessionConfig {
            method,
            ..SessionConfig::default()
        },
    )
    .unwrap()
}

fn handoff() -> InputOperation {
    // Exercise the public tagged JSON contract used by native C ABI adapters.
    serde_json::from_str(r#"{"type":"finish_composition","complete_reading":true,"select_highlighted_candidate":true,"discard_table_code":true}"#).unwrap()
}

#[test]
fn handoff_completes_valid_smart_reading_without_learning_or_duplicate_commit() {
    let mut input = session(InputMethod::Smart);
    for ch in "5j/".chars() {
        input.apply(InputOperation::character(ch)).unwrap();
    }
    assert_eq!(input.snapshot().visible_text, "ㄓㄨㄥ");
    let result = input.apply(handoff()).unwrap();
    assert_eq!(result.effects.commit, "中");
    assert!(result.visible_text.is_empty());
    assert_eq!(result.user_data.overrides, 0);
    assert_eq!(result.user_data.bigrams, 0);
    assert!(input.apply(handoff()).unwrap().effects.commit.is_empty());
    assert!(input.snapshot().effects.commit.is_empty());
}

#[test]
fn handoff_preserves_highlighted_traditional_candidate_without_selecting_again() {
    let mut input = session(InputMethod::Traditional);
    for ch in "5j/".chars() {
        input.apply(InputOperation::character(ch)).unwrap();
    }
    input.apply(InputOperation::key(Key::Space)).unwrap();
    let view = input
        .apply(InputOperation::MoveHighlight { delta: 1 })
        .unwrap();
    let expected = view.displayed_candidates[view.highlight.unwrap()].clone();
    let result = input.apply(handoff()).unwrap();
    assert_eq!(result.effects.commit, expected);
    assert!(result.candidates.is_empty());
    assert!(result.visible_text.is_empty());
    assert_eq!(result.user_data.table_entries, 0);
}

#[test]
fn discard_table_handoff_does_not_change_original_finish_contract() {
    for method in [InputMethod::Cangjie, InputMethod::Simplex] {
        let mut input = session(method);
        let before = input.apply(InputOperation::character('a')).unwrap();
        assert!(!before.visible_text.is_empty());
        let result = input.apply(handoff()).unwrap();
        assert!(result.effects.commit.is_empty());
        assert!(result.visible_text.is_empty());
        input.apply(InputOperation::character('a')).unwrap();
        let original = input.apply(InputOperation::Finish).unwrap();
        assert_eq!(original.effects.commit, before.visible_text);
    }
}

#[test]
fn unspecified_handoff_flags_keep_visible_text_finish_policy() {
    let mut input = session(InputMethod::Cangjie);
    let before = input.apply(InputOperation::character('a')).unwrap();
    let operation = serde_json::from_str(r#"{"type":"finish_composition"}"#).unwrap();
    assert_eq!(
        input.apply(operation).unwrap().effects.commit,
        before.visible_text
    );
    assert!(serde_json::from_str::<InputOperation>(
        r#"{"type":"finish_composition","linux":true}"#
    )
    .is_err());
}

#[test]
fn preserving_a_table_highlight_is_not_selection_learning() {
    let mut input = InputSession::open(
        support::model_path(),
        SessionConfig {
            method: InputMethod::Cangjie,
            learning: LearningOptions {
                table_learning: true,
                ..LearningOptions::default()
            },
            ..SessionConfig::default()
        },
    )
    .unwrap();
    input.apply(InputOperation::character('h')).unwrap();
    input.apply(InputOperation::key(Key::Space)).unwrap();
    let view = input
        .apply(InputOperation::MoveHighlight { delta: 1 })
        .unwrap();
    assert!(view.displayed_candidates.len() > 1);
    let expected = view.displayed_candidates[view.highlight.unwrap()].clone();
    let result = input
        .apply(InputOperation::FinishComposition {
            complete_reading: false,
            select_highlighted_candidate: true,
            discard_table_code: false,
        })
        .unwrap();
    assert_eq!(result.effects.commit, expected);
    assert_eq!(result.user_data.table_entries, 0);
    input.apply(InputOperation::character('h')).unwrap();
    input.apply(InputOperation::key(Key::Space)).unwrap();
    assert_eq!(
        input
            .apply(InputOperation::Select { index: 1 })
            .unwrap()
            .user_data
            .table_entries,
        1
    );
}
