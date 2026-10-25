//! Frontend-selected learning behavior. No platform presets or storage paths.
//!
//! Original Guanyinma additions, Copyright (c) 2026 Chui-Ping Cheng. MIT.
use serde::{Deserialize, Serialize};

/// Reading custom words and recording preferences are independent choices.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct LearningOptions {
    pub user_phrases: bool,
    pub candidate_overrides: bool,
    pub bigrams: bool,
    pub table_learning: bool,
}
impl Default for LearningOptions {
    fn default() -> Self {
        Self {
            user_phrases: true,
            candidate_overrides: false,
            bigrams: false,
            table_learning: false,
        }
    }
}
