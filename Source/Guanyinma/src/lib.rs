//! Guanyinma is chichi77 KeyKey's shared Rust core.
//!
//! Read-only model access and owned C ABI sessions support Smart Mandarin,
//! Traditional Bopomofo, Cangjie and Simplex, with a separate user-data store.
//! The existing functional baseline remains a manual migration reference.

pub mod bopomofo;
pub mod candidate_filter;
pub mod database;
pub mod engine;
pub mod ffi;
pub mod learning;
pub mod smart;
pub mod table;
pub mod user_archive;
pub mod user_store;
pub mod walker;

pub use candidate_filter::CandidateFilter;
pub use database::{Bigram, DatabaseError, ModelDatabase, Table, Unigram};

pub use engine::{
    BehaviorOptions, BehaviorProfile, Effects, EngineError, InputMethod, InputOperation,
    InputSession, Key, Modifiers, PhraseFeedback, SessionConfig, SessionSnapshot, TableOptions,
    UserDataSummary,
};

pub use smart::{MarkedPhrase, SmartOptions};
pub use table::TableWildcards;
pub use walker::{SmartCandidate, SmartSegment};

pub use learning::LearningOptions;
pub use user_archive::{
    SmartLearning, UserArchive, UserArchiveFormat, USER_ARCHIVE_SCHEMA_VERSION,
};
pub use user_store::{
    CandidateOverride, SaveOutcome, TableLearning, UserChange, UserSnapshot, UserStore,
};

#[cfg(test)]
#[path = "../tests/support/mod.rs"]
mod test_support;
