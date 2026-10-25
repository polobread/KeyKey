//! Shared phonetic, Smart Mandarin and table-input sessions.
//!
//! Copyright (c) 2026 Chui-Ping Cheng. MIT License.
//! Behavior follows the macOS OpenVanilla modules; the original mobile engines
//! supplied reference implementations of the platform-neutral operation shape.
//! State transitions port the OpenVanilla TraditionalMandarin/Generic behavior.
//! Original portions: Copyright (c) 2004-2010 the OpenVanilla Project (MIT).
//! Original MIT attribution: LICENSES/Formosa-OpenVanilla-NOTICES.txt.
//! The shared model remains read-only; validated user deltas use a separate store.

use crate::bopomofo::{BopomofoLayout, BopomofoReading, BopomofoSyllable};
use crate::candidate_filter::CandidateFilter;
use crate::database::{DatabaseError, ModelDatabase, Table, Unigram};
use crate::learning::LearningOptions;
use crate::smart::{MarkedPhrase, SmartOptions, SmartState};
use crate::table::{self, PunctuationStyle, TableQueryOptions, TableWildcards};
use crate::user_archive::UserArchive;
use crate::user_store::{SaveOutcome, UserChange, UserSnapshot, UserStore};
use crate::walker::{SmartCandidate, SmartSegment};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::fmt;
use std::path::Path;

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum InputMethod {
    #[default]
    Traditional,
    Smart,
    Cangjie,
    Simplex,
}
impl InputMethod {
    fn table(self) -> Table {
        match self {
            Self::Traditional | Self::Smart => Table::Traditional,
            Self::Cangjie => Table::Cangjie,
            Self::Simplex => Table::Simplex,
        }
    }
    fn maximum(self) -> usize {
        if self == Self::Simplex {
            2
        } else {
            5
        }
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BehaviorProfile {
    #[default]
    Desktop,
    Touch,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct TableOptions {
    pub realtime: bool,
    pub prefix: bool,
    pub clear_on_error: bool,
    pub query_at_maximum: bool,
    pub learn_selection: bool,
    pub punctuation: PunctuationStyle,
    pub maximum_radical_length: Option<usize>,
    pub space_as_first_selection_key: bool,
    pub space_commits_first_on_single_page: Option<bool>,
    pub wildcards: Option<TableWildcards>,
}
impl Default for TableOptions {
    fn default() -> Self {
        Self {
            realtime: false,
            prefix: false,
            clear_on_error: true,
            query_at_maximum: false,
            learn_selection: true,
            punctuation: PunctuationStyle::Original,
            maximum_radical_length: None,
            space_as_first_selection_key: false,
            space_commits_first_on_single_page: None,
            wildcards: None,
        }
    }
}
impl TableOptions {
    pub fn simplex() -> Self {
        Self {
            query_at_maximum: true,
            learn_selection: false,
            clear_on_error: false,
            ..Self::default()
        }
    }
    fn validate(&self) -> Result<(), EngineError> {
        if self
            .maximum_radical_length
            .is_some_and(|size| !(1..=128).contains(&size))
        {
            return Err(EngineError::InvalidInput(
                "maximum radical length must be between 1 and 128".into(),
            ));
        }
        if let Some(wildcards) = self.wildcards {
            if [wildcards.one, wildcards.many]
                .into_iter()
                .flatten()
                .any(|key| !key.is_ascii() || key.is_ascii_control() || key == ' ')
            {
                return Err(EngineError::InvalidInput(
                    "wildcard symbols must be printable non-space ASCII".into(),
                ));
            }
        }
        Ok(())
    }
    fn maximum(self, method: InputMethod) -> usize {
        self.maximum_radical_length
            .unwrap_or_else(|| method.maximum())
    }
    fn wildcard_symbols(self, method: InputMethod) -> TableWildcards {
        self.wildcards.unwrap_or_else(|| {
            if method == InputMethod::Cangjie {
                TableWildcards::cangjie()
            } else {
                TableWildcards::default()
            }
        })
    }
    fn space_commits_first(self, method: InputMethod) -> bool {
        self.space_commits_first_on_single_page
            .unwrap_or(method == InputMethod::Cangjie)
    }
    fn normalized(mut self, method: InputMethod) -> Self {
        if self.realtime {
            self.clear_on_error = false;
        }
        if method != InputMethod::Cangjie {
            self.prefix = false;
        }
        self
    }
}

/// Platform-independent input choices. Frontends supply their own defaults.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct BehaviorOptions {
    /// Unshifted letters compose Chinese regardless of Caps Lock or text case.
    /// English mode and explicit Shift literals retain the delivered text.
    pub ignore_caps_lock_in_chinese: bool,
    /// An actual keypad character finishes visible composition, then emits text.
    /// When disabled, keypad characters follow ordinary IME input handling.
    pub literal_keypad: bool,
}
impl Default for BehaviorOptions {
    fn default() -> Self {
        Self {
            ignore_caps_lock_in_chinese: false,
            literal_keypad: true,
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct SessionConfig {
    pub method: InputMethod,
    pub profile: BehaviorProfile,
    pub layout: BopomofoLayout,
    pub behaviors: BehaviorOptions,
    pub smart: SmartOptions,
    pub learning: LearningOptions,
    pub user_database: Option<String>,
    pub traditional_selection_keys: Option<String>,
    pub table_selection_keys: Option<String>,
    pub cangjie: Option<TableOptions>,
    pub simplex: Option<TableOptions>,
}
impl Default for SessionConfig {
    fn default() -> Self {
        Self {
            method: InputMethod::Traditional,
            profile: BehaviorProfile::Desktop,
            layout: BopomofoLayout::Standard,
            behaviors: BehaviorOptions::default(),
            smart: SmartOptions::default(),
            learning: LearningOptions::default(),
            user_database: None,
            traditional_selection_keys: None,
            table_selection_keys: None,
            cangjie: None,
            simplex: None,
        }
    }
}
impl SessionConfig {
    fn validate(&self) -> Result<(), EngineError> {
        self.smart.validate()?;
        for options in [self.cangjie, self.simplex].into_iter().flatten() {
            options.validate()?;
        }
        for keys in [&self.traditional_selection_keys, &self.table_selection_keys]
            .into_iter()
            .flatten()
        {
            let bytes = keys.as_bytes();
            if bytes.is_empty()
                || bytes.len() > 32
                || !bytes.iter().all(|b| (0x21..=0x7e).contains(b))
            {
                return Err(EngineError::InvalidInput(
                    "selection keys must contain 1..32 printable ASCII keys".into(),
                ));
            }
            let mut unique = std::collections::HashSet::new();
            if !bytes.iter().all(|key| unique.insert(key)) {
                return Err(EngineError::InvalidInput(
                    "selection keys must be unique".into(),
                ));
            }
        }
        Ok(())
    }
    fn options(&self, method: InputMethod) -> TableOptions {
        let value = match method {
            InputMethod::Cangjie => self.cangjie.unwrap_or_else(|| {
                if self.profile == BehaviorProfile::Touch {
                    TableOptions {
                        realtime: true,
                        prefix: true,
                        ..TableOptions::default()
                    }
                } else {
                    TableOptions::default()
                }
            }),
            InputMethod::Simplex => self.simplex.unwrap_or_else(TableOptions::simplex),
            InputMethod::Traditional | InputMethod::Smart => TableOptions::default(),
        };
        value.normalized(method)
    }
}

#[derive(Clone, Copy, Debug, Default, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Modifiers {
    pub shift: bool,
    pub control: bool,
    pub alt: bool,
    pub command: bool,
    pub caps_lock: bool,
    /// Global lock state; it must never classify a main-keyboard key as keypad.
    pub num_lock: bool,
    /// Actual numeric-keypad origin, independent of the global Num Lock state.
    /// Send Num Lock-off navigation/editing as Key operations instead.
    pub keypad: bool,
    pub repeat: bool,
    pub release: bool,
}
#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Key {
    #[serde(alias = "enter")]
    Return,
    Space,
    Backspace,
    Escape,
    Delete,
    Tab,
    Left,
    Right,
    Up,
    Down,
    Home,
    End,
    PageUp,
    PageDown,
}
#[derive(Clone, Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum InputOperation {
    Character {
        text: String,
        #[serde(default)]
        modifiers: Modifiers,
    },
    DirectText {
        text: String,
    },
    Key {
        key: Key,
        #[serde(default)]
        modifiers: Modifiers,
    },
    Select {
        index: usize,
    },
    Page {
        delta: i32,
    },
    MoveHighlight {
        delta: i32,
    },
    SetMethod {
        method: InputMethod,
    },
    SetLayout {
        layout: BopomofoLayout,
    },
    SetProfile {
        profile: BehaviorProfile,
    },
    SetTableOptions {
        method: InputMethod,
        options: TableOptions,
    },
    SetBehaviors {
        behaviors: BehaviorOptions,
    },
    SetSmartOptions {
        options: SmartOptions,
    },
    OpenCandidates {
        index: usize,
    },
    CloseCandidates,
    SetLearningOptions {
        options: LearningOptions,
    },
    AddUserPhrase {
        qstring: String,
        text: String,
    },
    UpdateUserPhrase {
        qstring: String,
        text: String,
        new_qstring: String,
        new_text: String,
    },
    RemoveUserPhrase {
        qstring: String,
        text: String,
    },
    /// Replace a frontend-owned phrase publication, preserving all learning.
    ReplaceUserPhrases {
        phrases: Vec<Unigram>,
    },
    ResetLearning,
    ResetMethodLearning {
        method: InputMethod,
    },
    SaveLearning,
    ImportLegacyUserData {
        path: String,
        #[serde(default)]
        method: Option<InputMethod>,
    },
    ImportUserData {
        archive: UserArchive,
    },
    SetCursor {
        index: usize,
    },
    SetEnglish {
        enabled: bool,
    },
    /// Semantic output-width choice. Gesture recognition belongs to the FE.
    SetFullWidth {
        enabled: bool,
    },
    ToggleFullWidth,
    /// A native Shift-tap recognizer or mode control sends this once per gesture.
    ToggleEnglish,
    Finish,
    Reset,
}
impl InputOperation {
    pub fn character(value: char) -> Self {
        Self::Character {
            text: value.to_string(),
            modifiers: Modifiers::default(),
        }
    }
    pub fn key(key: Key) -> Self {
        Self::Key {
            key,
            modifiers: Modifiers::default(),
        }
    }
    fn validate(&self) -> Result<(), EngineError> {
        if let Self::Character { text, .. } = self {
            if text.chars().count() != 1 || text.chars().any(char::is_control) {
                return Err(EngineError::InvalidInput(
                    "character text must be one non-control Unicode scalar".into(),
                ));
            }
        }
        if let Self::DirectText { text } = self {
            if text.is_empty() || text.contains('\0') {
                return Err(EngineError::InvalidInput(
                    "direct text must be nonempty without NUL".into(),
                ));
            }
        }
        if let Self::SetTableOptions { options, .. } = self {
            options.validate()?;
        }
        if matches!(
            self,
            Self::SetTableOptions {
                method: InputMethod::Traditional | InputMethod::Smart,
                ..
            }
        ) {
            return Err(EngineError::InvalidInput(
                "table options require Cangjie or Simplex".into(),
            ));
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct PhraseFeedback {
    pub text: String,
    pub added: bool,
}

#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize)]
pub struct Effects {
    pub commit: String,
    pub handled: bool,
    pub beep: bool,
    pub delete_backward: bool,
    pub send_return: bool,
    pub discard_composition: bool,
    pub phrase_feedback: Option<PhraseFeedback>,
}
#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize)]
pub struct UserDataSummary {
    pub generation: i64,
    pub revision: i64,
    pub phrases: usize,
    pub overrides: usize,
    pub bigrams: usize,
    pub table_entries: usize,
}
impl From<&UserSnapshot> for UserDataSummary {
    fn from(data: &UserSnapshot) -> Self {
        Self {
            generation: data.generation,
            revision: data.revision,
            phrases: data.phrases.len(),
            overrides: data.overrides.len(),
            bigrams: data.bigrams.len(),
            table_entries: data.table.len(),
        }
    }
}

#[derive(Clone, Debug, Serialize)]
pub struct SessionSnapshot {
    pub schema_version: u32,
    pub kind: &'static str,
    pub method: InputMethod,
    pub profile: BehaviorProfile,
    pub layout: BopomofoLayout,
    pub english: bool,
    pub full_width: bool,
    pub behaviors: BehaviorOptions,
    pub composition: String,
    pub visible_text: String,
    pub smart_options: SmartOptions,
    pub learning: LearningOptions,
    pub user_data: UserDataSummary,
    pub readings: Vec<String>,
    pub reading_cursor: usize,
    pub segments: Vec<SmartSegment>,
    pub candidate_spans: Vec<SmartCandidate>,
    pub marked_phrase: Option<MarkedPhrase>,
    pub reading: String,
    pub phonetic: String,
    pub code: String,
    pub cursor: usize,
    pub cursor_unit: &'static str,
    pub candidates: Vec<String>,
    pub displayed_candidates: Vec<String>,
    pub page: usize,
    pub page_size: usize,
    pub page_count: usize,
    pub highlight: Option<usize>,
    pub table_options: TableOptions,
    pub effects: Effects,
}
#[derive(Debug)]
pub enum EngineError {
    InvalidInput(String),
    Database(DatabaseError),
}
impl fmt::Display for EngineError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidInput(message) => write!(f, "{message}"),
            Self::Database(error) => error.fmt(f),
        }
    }
}
impl std::error::Error for EngineError {}
impl From<DatabaseError> for EngineError {
    fn from(error: DatabaseError) -> Self {
        Self::Database(error)
    }
}

#[derive(Clone, Debug)]
struct State {
    user_data: UserSnapshot,
    reload_user_data: bool,
    pending_user_changes: Vec<UserChange>,
    table_exact: HashSet<String>,
    smart: SmartState,
    reading: BopomofoReading,
    code: String,
    candidates: Vec<String>,
    preview: Option<String>,
    final_candidates: bool,
    page: usize,
    highlight: usize,
    page_size: usize,
    display: String,
    english: bool,
    full_width: bool,
}
/// One isolated input context. The C ABI serializes access with its own mutex.
pub struct InputSession {
    database: ModelDatabase,
    users: UserStore,
    config: SessionConfig,
    candidate_filter: CandidateFilter,
    state: State,
}
impl InputSession {
    pub fn open(path: impl AsRef<Path>, config: SessionConfig) -> Result<Self, EngineError> {
        Self::open_with_candidate_filter(path, config, CandidateFilter::default())
    }

    /// Open with a frontend-owned eligibility policy fixed for this session.
    pub fn open_with_candidate_filter(
        path: impl AsRef<Path>,
        config: SessionConfig,
        candidate_filter: CandidateFilter,
    ) -> Result<Self, EngineError> {
        config.validate()?;
        let database = ModelDatabase::open(path.as_ref())?;
        let users = if let Some(user_path) = &config.user_database {
            UserStore::open(user_path, path.as_ref())?
        } else {
            UserStore::memory()?
        };
        let user_data = users.snapshot()?;
        let state = State {
            user_data,
            reload_user_data: false,
            pending_user_changes: Vec::new(),
            table_exact: HashSet::new(),
            smart: SmartState::with_candidate_filter(config.layout, candidate_filter.clone()),
            reading: BopomofoReading::new(config.layout),
            code: String::new(),
            candidates: Vec::new(),
            preview: None,
            final_candidates: false,
            page: 0,
            highlight: 0,
            page_size: 9,
            display: String::new(),
            english: false,
            full_width: false,
        };
        let mut result = Self {
            database,
            users,
            config,
            candidate_filter,
            state,
        };
        result.state.smart.set_options(&result.config.smart);
        result.state.smart.set_user_data(
            &result.database,
            &result.state.user_data,
            result.config.learning,
        )?;
        result.state.page_size = result.selection_keys()?.len();
        Ok(result)
    }
    pub fn snapshot(&self) -> SessionSnapshot {
        self.make_snapshot(Effects::default())
    }
    /// Apply one operation atomically; model/query failures restore the old state.
    pub fn apply(&mut self, operation: InputOperation) -> Result<SessionSnapshot, EngineError> {
        operation.validate()?;
        let before = self.state.clone();
        let config = self.config.clone();
        let mut effects = Effects {
            handled: true,
            ..Effects::default()
        };
        let result = (|| {
            let invalidated_view = self.sync_user_data()?;
            if invalidated_view
                && matches!(
                    &operation,
                    InputOperation::Character { .. }
                        | InputOperation::Key { .. }
                        | InputOperation::Select { .. }
                        | InputOperation::Page { .. }
                        | InputOperation::MoveHighlight { .. }
                )
            {
                // The event refers to the old displayed list. Never reinterpret
                // its index/key as a new candidate or a whole-sentence commit.
                self.clear_candidates();
                self.state.smart.cancel_phrase_mark();
                effects.beep = true;
            } else {
                self.execute(operation, &mut effects)?;
                self.accept_marked_phrase_request(&mut effects)?;
            }
            self.refresh_display()?;
            self.save_user_changes()?;
            Ok::<(), EngineError>(())
        })();
        if let Err(error) = result {
            self.state = before;
            self.config = config;
            return Err(error);
        }
        effects.commit = self.render_output(&effects.commit);
        Ok(self.make_snapshot(effects))
    }
    /// A pure owned data read for editors/export; no host effects or input changes.
    pub fn user_data(&self) -> Result<UserSnapshot, EngineError> {
        Ok(self.users.snapshot()?)
    }
    fn sync_user_data(&mut self) -> Result<bool, EngineError> {
        let version = self.users.version()?;
        let old_view = (
            self.state.candidates.clone(),
            self.state.smart.candidates().to_vec(),
            self.state.page,
            self.state.highlight,
            self.state.page_size,
            self.state.smart.marked_phrase(),
        );
        if self.state.reload_user_data
            || version
                != (
                    self.state.user_data.generation,
                    self.state.user_data.revision,
                )
        {
            let data = self.users.snapshot()?;
            self.state
                .smart
                .set_user_data(&self.database, &data, self.config.learning)?;
            self.state.user_data = data;
            self.state.reload_user_data = false;
            if matches!(
                self.config.method,
                InputMethod::Cangjie | InputMethod::Simplex
            ) && !self.state.candidates.is_empty()
            {
                self.table_query(false, &mut Effects::default())?;
                if self.state.candidates == old_view.0 {
                    self.state.page = old_view.2;
                    self.state.highlight = old_view.3;
                }
            }
            if self.config.method == InputMethod::Smart
                && !old_view.0.is_empty()
                && self.state.smart.candidates().is_empty()
            {
                self.state.smart.open_candidates(
                    None,
                    &self.config.smart,
                    &mut Effects::default(),
                )?;
            }
            self.refresh_display()?;
            if self.state.candidates == old_view.0 && self.state.smart.candidates() == old_view.1 {
                self.state.page = old_view.2;
                self.state.highlight = old_view.3;
            }
            let new_view = (
                self.state.candidates.clone(),
                self.state.smart.candidates().to_vec(),
                self.state.page,
                self.state.highlight,
                self.state.page_size,
                self.state.smart.marked_phrase(),
            );
            return Ok((!old_view.0.is_empty() || old_view.5.is_some()) && old_view != new_view);
        }
        Ok(false)
    }
    fn save_user_changes(&mut self) -> Result<(), EngineError> {
        let mut changes = std::mem::take(&mut self.state.pending_user_changes);
        changes.extend(self.state.smart.drain_user_changes());
        if changes.is_empty() {
            return Ok(());
        }
        let management = changes.iter().any(|change| {
            !matches!(
                change,
                UserChange::SetOverride { .. }
                    | UserChange::SetBigram(_)
                    | UserChange::IncrementTable { .. }
            )
        });
        for attempt in 0..2 {
            let generation = self.state.user_data.generation;
            let preview = self.state.user_data.preview(&changes)?;
            // Finish every fallible model query before the user transaction commits.
            self.state
                .smart
                .set_user_data(&self.database, &preview, self.config.learning)?;
            self.state.user_data = preview;
            self.refresh_display()?;
            match self.users.apply(generation, &changes)? {
                SaveOutcome::Applied(data) => {
                    self.state.user_data = data;
                    self.state.reload_user_data = true;
                    return Ok(());
                }
                SaveOutcome::Stale(data) => {
                    self.state.user_data = data;
                    self.state.reload_user_data = true;
                    // Old learning must never undo a reset. Explicit dictionary
                    // edits/imports instead get one bounded retry in the new epoch.
                    if !management {
                        return Ok(());
                    }
                    if attempt == 1 {
                        return Err(DatabaseError::Query(
                            "user data changed during dictionary edit; retry the operation".into(),
                        )
                        .into());
                    }
                }
            }
        }
        unreachable!("bounded user save loop always returns")
    }
    fn method_name(&self) -> &'static str {
        match self.config.method {
            InputMethod::Cangjie => "cangjie",
            InputMethod::Simplex => "simplex",
            InputMethod::Traditional => "traditional",
            InputMethod::Smart => "smart",
        }
    }
    fn table_learning_enabled(&self) -> bool {
        self.config.learning.table_learning
            && matches!(
                self.config.method,
                InputMethod::Cangjie | InputMethod::Simplex
            )
            && self.options().learn_selection
    }
    fn phrase_exists(&self, qstring: &str, text: &str) -> Result<bool, EngineError> {
        Ok(self
            .state
            .user_data
            .phrases
            .iter()
            .any(|row| row.qstring == qstring && row.current == text)
            || self
                .database
                .unigrams(qstring)?
                .iter()
                .any(|row| row.current == text))
    }
    fn new_user_phrase(&self, qstring: String, text: String) -> Result<Unigram, EngineError> {
        let probability = self.database.max_unigram_probability()?;
        let mut unknown = self.database.unigrams("*")?;
        unknown.sort_by(|a, b| b.probability.total_cmp(&a.probability));
        let backoff = unknown.first().map_or(0.0, |row| row.backoff);
        Ok(Unigram {
            qstring,
            current: text,
            probability,
            backoff,
        })
    }
    fn add_user_phrase(&mut self, qstring: String, text: String) -> Result<(), EngineError> {
        validate_user_phrase(&qstring, &text)?;
        if !self.phrase_exists(&qstring, &text)? {
            let row = self.new_user_phrase(qstring, text)?;
            self.state
                .pending_user_changes
                .push(UserChange::UpsertPhrase(row));
            self.clear_candidates();
        }
        Ok(())
    }
    fn accept_marked_phrase_request(&mut self, effects: &mut Effects) -> Result<(), EngineError> {
        let Some(phrase) = self.state.smart.take_marked_phrase_request() else {
            return Ok(());
        };
        // The graph generated these blocks: like Manjusri's addUserUnigram,
        // marks may contain punctuation or a multiscalar DirectText block.
        // The external editor's canonical phonetic validation remains separate.
        let added = !self.phrase_exists(&phrase.qstring, &phrase.text)?;
        if added {
            let row = self.new_user_phrase(phrase.qstring, phrase.text.clone())?;
            self.state
                .pending_user_changes
                .push(UserChange::InsertPhraseIfAbsent(row));
        }
        effects.phrase_feedback = Some(PhraseFeedback {
            text: phrase.text,
            added,
        });
        Ok(())
    }
    fn make_snapshot(&self, effects: Effects) -> SessionSnapshot {
        let first = self.state.page.saturating_mul(self.state.page_size);
        let displayed = self
            .state
            .candidates
            .iter()
            .skip(first)
            .take(self.state.page_size)
            .cloned()
            .collect();
        SessionSnapshot {
            schema_version: 1,
            kind: "session",
            method: self.config.method,
            profile: self.config.profile,
            layout: self.config.layout,
            english: self.state.english,
            full_width: self.state.full_width,
            behaviors: self.config.behaviors,
            composition: if self.config.method == InputMethod::Smart {
                self.state.smart.composition()
            } else {
                self.state.display.clone()
            },
            visible_text: self.state.display.clone(),
            smart_options: self.config.smart.clone(),
            learning: self.config.learning,
            user_data: UserDataSummary::from(&self.state.user_data),
            readings: if self.config.method == InputMethod::Smart {
                self.state.smart.completed_readings().to_vec()
            } else {
                Vec::new()
            },
            reading_cursor: if self.config.method == InputMethod::Smart {
                self.state.smart.reading_cursor()
            } else {
                0
            },
            segments: if self.config.method == InputMethod::Smart {
                self.state.smart.segments()
            } else {
                Vec::new()
            },
            marked_phrase: if self.config.method == InputMethod::Smart {
                self.state.smart.marked_phrase()
            } else {
                None
            },
            candidate_spans: if self.config.method == InputMethod::Smart {
                self.state.smart.candidates().to_vec()
            } else {
                Vec::new()
            },
            reading: if self.config.method == InputMethod::Smart {
                self.state.smart.reading()
            } else {
                self.state.display.clone()
            },
            phonetic: if self.config.method == InputMethod::Smart {
                self.state.smart.reading()
            } else {
                self.state.reading.display_text()
            },
            code: if self.config.method == InputMethod::Traditional {
                if self.state.reading.is_empty() {
                    String::new()
                } else {
                    self.state.reading.query_key()
                }
            } else {
                self.state.code.clone()
            },
            cursor: if self.config.method == InputMethod::Smart {
                self.state.smart.cursor()
            } else {
                self.state.display.chars().count()
            },
            cursor_unit: "unicode_scalar",
            candidates: self.state.candidates.clone(),
            displayed_candidates: displayed,
            page: self.state.page,
            page_size: self.state.page_size,
            page_count: self.page_count(),
            highlight: if self.state.candidates.is_empty() {
                None
            } else {
                Some(self.state.highlight)
            },
            table_options: self.options(),
            effects,
        }
    }
    fn options(&self) -> TableOptions {
        self.config.options(self.config.method)
    }
    fn page_count(&self) -> usize {
        self.state.candidates.len().div_ceil(self.state.page_size)
    }
    fn empty(&self) -> bool {
        if self.config.method == InputMethod::Smart {
            return self.state.smart.is_empty();
        }
        self.state.reading.is_empty()
            && self.state.code.is_empty()
            && self.state.candidates.is_empty()
            && self.state.preview.is_none()
    }
    fn clear_candidates(&mut self) {
        self.state.table_exact.clear();
        self.state.smart.cancel_candidates();
        self.state.candidates.clear();
        self.state.preview = None;
        self.state.page = 0;
        self.state.highlight = 0;
        self.state.final_candidates = false;
    }
    fn clear_composition(&mut self) {
        self.state.smart.clear();
        self.clear_candidates();
        self.state.reading.clear();
        self.state.code.clear();
        self.state.display.clear();
    }
    fn render_output(&self, text: &str) -> String {
        if !self.state.full_width {
            return text.to_owned();
        }
        text.chars()
            .map(|ch| match ch {
                ' ' => '\u{3000}',
                '!'..='~' => char::from_u32(ch as u32 + 0xfee0).unwrap_or(ch),
                _ => ch,
            })
            .collect()
    }
    fn commit(&mut self, text: &str, effects: &mut Effects) {
        effects.commit.push_str(&self.render_output(text));
        self.clear_composition();
    }
    fn finish(&mut self, effects: &mut Effects) {
        if self.config.method == InputMethod::Smart {
            self.state.smart.finish(effects);
            self.clear_composition();
            return;
        }
        let text = self.state.display.clone();
        self.commit(&text, effects);
    }
    fn selection_keys(&self) -> Result<String, EngineError> {
        if self.config.method == InputMethod::Smart {
            return Ok(self.config.smart.selection_keys(self.config.layout));
        }
        if self.config.method == InputMethod::Traditional {
            return Ok(self
                .config
                .traditional_selection_keys
                .clone()
                .unwrap_or_else(|| {
                    match self.config.layout {
                        BopomofoLayout::Hsu => "asdfzxcv",
                        BopomofoLayout::ETen26 => "asdfjkl;",
                        _ => "123456789",
                    }
                    .to_owned()
                }));
        }
        let mut keys = if let Some(keys) = &self.config.table_selection_keys {
            keys.clone()
        } else {
            self.database
                .lookup_table(self.config.method.table(), "__property_selkey")?
                .first()
                .filter(|value| !value.is_empty())
                .cloned()
                .unwrap_or_else(|| "123456789".into())
        };
        // Property keys are validated just like caller supplied keys.
        if keys.len() > 32 || !keys.is_ascii() || keys.chars().any(char::is_control) {
            return Err(EngineError::InvalidInput(
                "invalid dictionary selection keys".into(),
            ));
        }
        if self.options().space_as_first_selection_key && !keys.starts_with(' ') {
            keys.insert(0, ' ');
        }
        Ok(keys)
    }
    fn refresh_display(&mut self) -> Result<(), EngineError> {
        if self.config.method == InputMethod::Smart {
            self.state.display = self.state.smart.visible_text();
            let values: Vec<String> = self
                .state
                .smart
                .candidates()
                .iter()
                .map(|c| c.text.clone())
                .collect();
            if values != self.state.candidates {
                self.state.page = 0;
                self.state.highlight = 0;
            }
            self.state.candidates = values;
            self.state.page_size = self.selection_keys()?.len();
            return Ok(());
        }
        self.state.display = if let Some(preview) = &self.state.preview {
            preview.clone()
        } else if self.config.method == InputMethod::Traditional {
            self.state.reading.display_text()
        } else {
            let mut result = String::new();
            for key in self.state.code.chars() {
                let values = self.database.lookup_table(
                    self.config.method.table(),
                    &format!("__property_keyname-{key}"),
                )?;
                result.push_str(values.first().map(String::as_str).unwrap_or_else(|| ""));
                if values.is_empty() {
                    result.push(key);
                }
            }
            result
        };
        Ok(())
    }
    fn select_absolute(&mut self, index: usize, effects: &mut Effects) -> Result<(), EngineError> {
        if self.config.method == InputMethod::Smart {
            self.state.smart.select(index, &self.config.smart)?;
            self.clear_candidates();
            return Ok(());
        }
        let selected = self.state.candidates.get(index).cloned().ok_or_else(|| {
            EngineError::InvalidInput("candidate index is outside the list".into())
        })?;
        if self.table_learning_enabled() && index != 0 && self.state.table_exact.contains(&selected)
        {
            self.state
                .pending_user_changes
                .push(UserChange::IncrementTable {
                    method: self.method_name().to_owned(),
                    code: self.state.code.clone(),
                    current: selected.clone(),
                });
        }
        self.commit(&selected, effects);
        Ok(())
    }
    fn commit_highlighted_without_learning(
        &mut self,
        effects: &mut Effects,
    ) -> Result<(), EngineError> {
        let text = self
            .state
            .candidates
            .get(self.selected_index())
            .cloned()
            .ok_or_else(|| {
                EngineError::InvalidInput("candidate index is outside the list".into())
            })?;
        self.commit(&text, effects);
        Ok(())
    }
    fn selected_index(&self) -> usize {
        self.state.page * self.state.page_size + self.state.highlight
    }
    fn page(&mut self, delta: i32, effects: &mut Effects) {
        let count = self.page_count();
        if count == 0 {
            return;
        }
        self.state.page =
            (self.state.page as i64 + i64::from(delta)).rem_euclid(count as i64) as usize;
        self.state.highlight = 0;
        effects.beep |= count == 1 && delta != 0;
    }
    fn move_highlight(&mut self, delta: i32, effects: &mut Effects) {
        let count = self.state.candidates.len();
        if count == 0 {
            return;
        }
        let requested = self.selected_index() as i64 + i64::from(delta);
        // A single page cannot flip to another page at its boundary.
        let next = if self.page_count() == 1 {
            effects.beep |= requested < 0 || requested >= count as i64;
            requested.clamp(0, count as i64 - 1) as usize
        } else {
            requested.rem_euclid(count as i64) as usize
        };
        self.state.page = next / self.state.page_size;
        self.state.highlight = next % self.state.page_size;
    }
    fn execute(
        &mut self,
        operation: InputOperation,
        effects: &mut Effects,
    ) -> Result<(), EngineError> {
        match operation {
            InputOperation::Character { text, modifiers } => {
                self.character(text.chars().next().unwrap(), modifiers, effects)?
            }
            InputOperation::DirectText { text } => self.direct_text(&text, effects)?,
            InputOperation::Key { key, modifiers } => self.key(key, modifiers, effects)?,
            InputOperation::Select { index } => {
                if index >= self.state.page_size {
                    return Err(EngineError::InvalidInput(
                        "candidate index is not page-local".into(),
                    ));
                }
                self.select_absolute(self.state.page * self.state.page_size + index, effects)?;
            }
            InputOperation::Page { delta } => self.page(delta, effects),
            InputOperation::MoveHighlight { delta } => self.move_highlight(delta, effects),
            InputOperation::SetMethod { method } => {
                if method != self.config.method {
                    self.finish(effects);
                    self.config.method = method;
                    self.state.page_size = self.selection_keys()?.len();
                }
            }
            InputOperation::SetProfile { profile } => self.config.profile = profile,
            InputOperation::SetLayout { layout } => {
                if layout != self.config.layout {
                    self.finish(effects);
                    self.config.layout = layout;
                    self.state.reading = BopomofoReading::new(layout);
                    self.state.smart.set_layout(layout);
                    self.state.page_size = self.selection_keys()?.len();
                }
            }
            InputOperation::SetTableOptions { method, options } => {
                if method == self.config.method {
                    self.finish(effects);
                }
                match method {
                    InputMethod::Cangjie => self.config.cangjie = Some(options.normalized(method)),
                    InputMethod::Simplex => self.config.simplex = Some(options.normalized(method)),
                    InputMethod::Traditional | InputMethod::Smart => unreachable!(),
                }
            }
            InputOperation::SetBehaviors { behaviors } => self.config.behaviors = behaviors,
            InputOperation::SetSmartOptions { options } => {
                options.validate()?;
                self.state.smart.set_options(&options);
                self.config.smart = options;
                if self.config.method == InputMethod::Smart {
                    self.clear_candidates();
                }
            }
            InputOperation::OpenCandidates { index } => {
                if self.config.method != InputMethod::Smart {
                    return Err(EngineError::InvalidInput(
                        "open_candidates requires Smart Mandarin".into(),
                    ));
                }
                if index >= self.state.smart.completed_readings().len() {
                    return Err(EngineError::InvalidInput(
                        "candidate target is outside completed readings".into(),
                    ));
                }
                self.clear_candidates();
                self.state
                    .smart
                    .open_candidates(Some(index), &self.config.smart, effects)?;
            }
            InputOperation::CloseCandidates => {
                if self.config.method != InputMethod::Smart {
                    return Err(EngineError::InvalidInput(
                        "close_candidates requires Smart Mandarin".into(),
                    ));
                }
                self.clear_candidates();
            }
            InputOperation::SetLearningOptions { options } => {
                self.state
                    .smart
                    .set_user_data(&self.database, &self.state.user_data, options)?;
                self.config.learning = options;
                self.clear_candidates();
            }
            InputOperation::AddUserPhrase { qstring, text } => {
                self.add_user_phrase(qstring, text)?
            }
            InputOperation::UpdateUserPhrase {
                qstring,
                text,
                new_qstring,
                new_text,
            } => {
                if !self
                    .state
                    .user_data
                    .phrases
                    .iter()
                    .any(|row| row.qstring == qstring && row.current == text)
                {
                    return Err(EngineError::InvalidInput(
                        "user phrase does not exist".into(),
                    ));
                }
                validate_user_phrase(&new_qstring, &new_text)?;
                if (qstring != new_qstring || text != new_text)
                    && self.phrase_exists(&new_qstring, &new_text)?
                {
                    return Err(EngineError::InvalidInput(
                        "replacement phrase already exists".into(),
                    ));
                }
                if qstring != new_qstring || text != new_text {
                    let row = self.new_user_phrase(new_qstring, new_text)?;
                    self.state
                        .pending_user_changes
                        .push(UserChange::RemovePhrase {
                            qstring,
                            current: text,
                        });
                    self.state
                        .pending_user_changes
                        .push(UserChange::UpsertPhrase(row));
                    self.clear_candidates();
                }
            }
            InputOperation::RemoveUserPhrase { qstring, text } => {
                if qstring.is_empty()
                    || text.is_empty()
                    || qstring.contains('\0')
                    || text.contains('\0')
                {
                    return Err(EngineError::InvalidInput(
                        "phrase query and text must be nonempty without NUL".into(),
                    ));
                }
                self.state
                    .pending_user_changes
                    .push(UserChange::RemovePhrase {
                        qstring,
                        current: text,
                    });
                self.clear_candidates();
            }
            InputOperation::ReplaceUserPhrases { phrases } => {
                UserSnapshot {
                    phrases: phrases.clone(),
                    ..UserSnapshot::default()
                }
                .validate()?;
                if phrases != self.state.user_data.phrases {
                    for row in &self.state.user_data.phrases {
                        self.state
                            .pending_user_changes
                            .push(UserChange::RemovePhrase {
                                qstring: row.qstring.clone(),
                                current: row.current.clone(),
                            });
                    }
                    self.state
                        .pending_user_changes
                        .extend(phrases.into_iter().map(UserChange::UpsertPhrase));
                    self.clear_candidates();
                }
            }
            InputOperation::ResetLearning => {
                self.state
                    .pending_user_changes
                    .push(UserChange::ResetLearning);
                self.clear_candidates();
            }
            InputOperation::ResetMethodLearning { method } => {
                let change = match method {
                    InputMethod::Smart => UserChange::ResetSmartLearning,
                    InputMethod::Cangjie => UserChange::ResetTableLearning {
                        method: "cangjie".into(),
                    },
                    InputMethod::Simplex => UserChange::ResetTableLearning {
                        method: "simplex".into(),
                    },
                    InputMethod::Traditional => {
                        return Err(EngineError::InvalidInput(
                            "Traditional Bopomofo has no learned data".into(),
                        ))
                    }
                };
                self.state.pending_user_changes.push(change);
                if method == self.config.method {
                    self.clear_candidates();
                }
            }
            InputOperation::SaveLearning => {}
            InputOperation::ImportLegacyUserData { path, method } => {
                let method = match method {
                    None => None,
                    Some(InputMethod::Cangjie) => Some("cangjie"),
                    Some(InputMethod::Simplex) => Some("simplex"),
                    _ => {
                        return Err(EngineError::InvalidInput(
                            "legacy table import requires Cangjie or Simplex".into(),
                        ))
                    }
                };
                let changes = self.users.read_legacy(path, method)?;
                self.state.pending_user_changes.extend(changes);
                self.clear_candidates();
            }
            InputOperation::ImportUserData { archive } => {
                self.state.pending_user_changes.extend(archive.changes()?);
                self.clear_candidates();
            }
            InputOperation::SetCursor { index } => {
                if self.config.method != InputMethod::Smart || !self.state.smart.set_cursor(index) {
                    return Err(EngineError::InvalidInput(
                        "cursor is outside the completed reading range".into(),
                    ));
                }
                self.clear_candidates();
            }
            InputOperation::SetEnglish { enabled } => {
                if enabled != self.state.english {
                    self.finish(effects);
                    self.state.english = enabled;
                }
            }
            InputOperation::SetFullWidth { enabled } => self.state.full_width = enabled,
            InputOperation::ToggleFullWidth => self.state.full_width = !self.state.full_width,
            InputOperation::ToggleEnglish => {
                self.finish(effects);
                self.state.english = !self.state.english;
            }
            InputOperation::Finish => self.finish(effects),
            InputOperation::Reset => self.clear_composition(),
        }
        Ok(())
    }
    fn traditional_query(
        &mut self,
        key: &str,
        punctuation: bool,
        effects: &mut Effects,
    ) -> Result<(), EngineError> {
        let mut values = self.database.lookup_table(Table::Traditional, key)?;
        values.retain(|text| self.candidate_filter.accepts(text));
        self.clear_candidates();
        if values.is_empty() {
            effects.beep = true;
            return Ok(());
        }
        if values.len() == 1 {
            self.commit(&values[0], effects);
            return Ok(());
        }
        self.state.preview = values.first().cloned();
        self.state.candidates = values;
        self.state.page_size = self.selection_keys()?.len();
        self.state.final_candidates = true;
        if punctuation {
            self.state.reading.clear();
        }
        Ok(())
    }
    fn table_query(&mut self, final_query: bool, effects: &mut Effects) -> Result<(), EngineError> {
        let options = self.options();
        let result = table::candidates_with_filter(
            &self.database,
            self.config.method.table(),
            &self.state.code,
            TableQueryOptions {
                prefix: options.realtime && options.prefix,
                punctuation: options.punctuation,
                wildcards: Some(options.wildcard_symbols(self.config.method)),
            },
            &self.candidate_filter,
        )?;
        self.clear_candidates();
        self.state.final_candidates = final_query;
        let mut values = result.values;
        self.state.table_exact = result.exact.iter().cloned().collect();
        if self.table_learning_enabled() {
            let count = result.exact.len();
            let mut exact = values.drain(..count).collect::<Vec<_>>();
            let available: HashSet<String> = exact.iter().cloned().collect();
            let mut learned: Vec<_> = self
                .state
                .user_data
                .table
                .iter()
                .filter(|row| {
                    row.method == self.method_name()
                        && row.code == self.state.code
                        && available.contains(&row.current)
                })
                .collect();
            learned.sort_by_key(|row| std::cmp::Reverse(row.count));
            let mut seen = HashSet::new();
            let mut sorted = Vec::new();
            for row in learned {
                if seen.insert(row.current.clone()) {
                    sorted.push(row.current.clone());
                }
            }
            sorted.extend(exact.drain(..).filter(|text| !seen.contains(text)));
            sorted.extend(values);
            values = sorted;
        }
        if values.is_empty() {
            effects.beep = final_query;
            if final_query && options.clear_on_error && !options.realtime {
                self.clear_composition();
            }
            return Ok(());
        }
        if values.len() == 1 && final_query {
            self.commit(&values[0], effects);
            return Ok(());
        }
        self.state.page_size = self.selection_keys()?.len().min(values.len());
        self.state.candidates = values;
        Ok(())
    }
    fn dictionary_key(&self, character: char) -> Result<bool, EngineError> {
        if matches!(
            self.config.method,
            InputMethod::Cangjie | InputMethod::Simplex
        ) && self
            .options()
            .wildcard_symbols(self.config.method)
            .contains(character)
        {
            return Ok(true);
        }
        Ok(!self
            .database
            .lookup_table(
                self.config.method.table(),
                &format!("__property_keyname-{character}"),
            )?
            .is_empty())
    }
    fn character(
        &mut self,
        character: char,
        modifiers: Modifiers,
        effects: &mut Effects,
    ) -> Result<(), EngineError> {
        if modifiers.release {
            effects.handled = false;
            return Ok(());
        }
        if character == ' ' {
            return self.key(Key::Space, modifiers, effects);
        }
        if self.config.method == InputMethod::Smart {
            return self.smart_character(character, modifiers, effects);
        }
        if modifiers.control || modifiers.alt || modifiers.command {
            if !self.state.english
                && self.config.method == InputMethod::Traditional
                && self.empty()
                && modifiers.control
                && !modifiers.command
                && !modifiers.keypad
            {
                let name = if modifiers.alt {
                    format!("_ctrl_opt_{character}")
                } else if character == '0' || character == '1' {
                    "_punctuation_list".to_owned()
                } else {
                    format!("_ctrl_{character}")
                };
                if !self
                    .database
                    .lookup_table(Table::Traditional, &name)?
                    .is_empty()
                {
                    return self.traditional_query(&name, true, effects);
                }
            }
            effects.handled = !self.state.english
                && !modifiers.keypad
                && self.config.method == InputMethod::Traditional
                && !self.empty();
            effects.beep = effects.handled;
            return Ok(());
        }
        if self.state.english {
            effects
                .commit
                .push_str(&self.render_output(&character.to_string()));
            return Ok(());
        }
        // Literal keypad input bypasses parsing, including when a
        // candidate panel or unfinished reading is visible. Global Num Lock
        // state alone has no bearing on ordinary keyboard input.
        if modifiers.keypad && self.config.behaviors.literal_keypad {
            self.finish(effects);
            effects
                .commit
                .push_str(&self.render_output(&character.to_string()));
            return Ok(());
        }
        let ignore_caps = self.config.behaviors.ignore_caps_lock_in_chinese;
        let character = if ignore_caps && !modifiers.shift {
            character.to_ascii_lowercase()
        } else {
            character
        };
        if (modifiers.caps_lock && !ignore_caps)
            || (modifiers.shift && character.is_ascii_alphabetic())
        {
            self.clear_composition();
            effects
                .commit
                .push_str(&self.render_output(&character.to_string()));
            return Ok(());
        }
        // Physical candidate keys select; touch phonetic keys continue a reading.
        if !self.state.candidates.is_empty()
            && (self.config.profile != BehaviorProfile::Touch
                || self.config.method != InputMethod::Traditional)
        {
            if let Some(index) = self
                .selection_keys()?
                .chars()
                .position(|key| key == character)
            {
                let absolute = self.state.page * self.state.page_size + index;
                if index < self.state.page_size && absolute < self.state.candidates.len() {
                    return self.select_absolute(absolute, effects);
                }
                effects.beep = true;
                return Ok(());
            }
        }
        if self.config.method != InputMethod::Traditional {
            return self.table_character(character, effects);
        }
        // A candidate continuation is accepted by the current reading buffer,
        // not merely by the layout's alphabet. In particular, Hanyu Pinyin
        // rejects new letters after a tone marker until selection/cancellation.
        let valid = !character.is_ascii_uppercase()
            && if self.state.candidates.is_empty() {
                self.config.layout.is_reading_key(character)
            } else {
                self.state.reading.clone().combine(character)
            };
        if valid {
            if !self.state.candidates.is_empty() {
                self.select_absolute(self.selected_index(), effects)?;
            }
            self.clear_candidates();
            if self.state.reading.combine(character) && self.state.reading.has_tone_marker() {
                let query = self.state.reading.query_key();
                self.traditional_query(&query, false, effects)?;
            }
            return Ok(());
        }
        if !self.state.reading.is_empty() && self.state.candidates.is_empty() {
            effects.beep = true;
            return Ok(());
        }
        let names = [
            format!(
                "_punctuation_{}_{}",
                layout_name(self.config.layout),
                character
            ),
            format!("_punctuation_{character}"),
        ];
        for name in names {
            if !self
                .database
                .lookup_table(Table::Traditional, &name)?
                .is_empty()
            {
                if !self.state.candidates.is_empty() {
                    self.select_absolute(self.selected_index(), effects)?;
                }
                return self.traditional_query(&name, true, effects);
            }
        }
        if !self.state.candidates.is_empty() {
            effects.beep = true;
            return Ok(());
        }
        effects
            .commit
            .push_str(&self.render_output(&character.to_string()));
        Ok(())
    }
    fn smart_character(
        &mut self,
        mut character: char,
        mut modifiers: Modifiers,
        effects: &mut Effects,
    ) -> Result<(), EngineError> {
        let shortcut = modifiers.control || modifiers.alt || modifiers.command;
        if shortcut && (self.state.english || modifiers.keypad) {
            effects.handled = false;
            return Ok(());
        }
        if self.state.english {
            effects.commit.push(character);
            return Ok(());
        }
        if modifiers.keypad && self.config.behaviors.literal_keypad {
            self.finish(effects);
            effects.commit.push(character);
            return Ok(());
        }
        if self.config.behaviors.ignore_caps_lock_in_chinese {
            if !modifiers.shift {
                character = character.to_ascii_lowercase();
            }
            modifiers.caps_lock = false;
        }
        if !self.state.candidates.is_empty() {
            if !shortcut {
                if let Some(index) = self
                    .selection_keys()?
                    .chars()
                    .position(|key| key == character)
                    .filter(|_| !modifiers.shift)
                {
                    let absolute = self.state.page * self.state.page_size + index;
                    if index < self.state.page_size && absolute < self.state.candidates.len() {
                        return self.select_absolute(absolute, effects);
                    }
                }
            }
            effects.beep = true;
            return Ok(());
        }
        self.state.smart.character(
            &self.database,
            character,
            modifiers,
            &self.config.smart,
            effects,
        )
    }
    fn direct_text(&mut self, text: &str, effects: &mut Effects) -> Result<(), EngineError> {
        if self.config.method == InputMethod::Smart {
            self.state
                .smart
                .direct_text(&self.database, text, &self.config.smart, effects)?;
            self.clear_candidates();
        } else {
            self.clear_composition();
            effects.commit.push_str(text);
        }
        Ok(())
    }
    fn table_character(
        &mut self,
        character: char,
        effects: &mut Effects,
    ) -> Result<(), EngineError> {
        if !self.dictionary_key(character)? {
            if self.empty() {
                effects
                    .commit
                    .push_str(&self.render_output(&character.to_string()));
            } else {
                effects.beep = true;
            }
            return Ok(());
        }
        let options = self.options();
        if !self.state.candidates.is_empty()
            && (!options.realtime || self.state.code.len() >= options.maximum(self.config.method))
        {
            self.commit_highlighted_without_learning(effects)?;
        }
        if self.state.code.len() >= options.maximum(self.config.method) {
            effects.beep = true;
            return Ok(());
        }
        self.state.code.push(character);
        self.clear_candidates();
        let end_keys = self
            .database
            .lookup_table(self.config.method.table(), "__property_endkey")?;
        let wildcard = self.state.code.len() > 1
            && options
                .wildcard_symbols(self.config.method)
                .contains(character);
        let final_query = (!wildcard
            && end_keys
                .first()
                .is_some_and(|keys| keys.contains(character)))
            || (options.query_at_maximum
                && self.state.code.len() >= options.maximum(self.config.method));
        let prefix_preview = options.realtime
            && options.prefix
            && self.config.method == InputMethod::Cangjie
            && table::is_cangjie_code(&self.state.code);
        if final_query || options.realtime {
            self.table_query(final_query && !prefix_preview, effects)?;
        }
        Ok(())
    }
    fn key(
        &mut self,
        key: Key,
        mut modifiers: Modifiers,
        effects: &mut Effects,
    ) -> Result<(), EngineError> {
        if self.config.behaviors.ignore_caps_lock_in_chinese && !self.state.english {
            modifiers.caps_lock = false;
        }
        if modifiers.release {
            effects.handled = false;
            return Ok(());
        }
        if modifiers.control || modifiers.alt || modifiers.command {
            if matches!(
                self.config.method,
                InputMethod::Smart | InputMethod::Traditional
            ) && !self.state.english
                && !modifiers.keypad
                && !self.empty()
            {
                effects.beep = true;
            } else {
                effects.handled = false;
            }
            return Ok(());
        }
        if self.config.method == InputMethod::Smart && self.state.candidates.is_empty() {
            let was_empty = self.state.smart.is_empty();
            self.state
                .smart
                .key(&self.database, key, modifiers, &self.config.smart, effects)?;
            if was_empty && !effects.handled && self.config.profile == BehaviorProfile::Touch {
                match key {
                    Key::Space => {
                        effects.handled = true;
                        effects.commit.push(' ');
                    }
                    Key::Backspace => {
                        effects.handled = true;
                        effects.delete_backward = true;
                    }
                    Key::Return => {
                        effects.handled = true;
                        effects.send_return = true;
                    }
                    _ => {}
                }
            }
            return Ok(());
        }
        if self.config.method == InputMethod::Smart {
            if matches!(key, Key::Escape) && !modifiers.shift {
                self.clear_candidates();
                return Ok(());
            }
            if matches!(key, Key::Return) && !modifiers.shift {
                return self.select_absolute(self.selected_index(), effects);
            }
            if !matches!(
                key,
                Key::Space
                    | Key::Left
                    | Key::Right
                    | Key::Up
                    | Key::Down
                    | Key::Home
                    | Key::End
                    | Key::PageUp
                    | Key::PageDown
            ) {
                effects.beep = true;
                return Ok(());
            }
        }
        if modifiers.shift
            && !self.state.candidates.is_empty()
            && matches!(
                key,
                Key::Left
                    | Key::Right
                    | Key::Up
                    | Key::Down
                    | Key::Home
                    | Key::End
                    | Key::PageUp
                    | Key::PageDown
            )
        {
            self.block_edit(effects);
            return Ok(());
        }
        match key {
            Key::Return | Key::Space => {
                if self.state.english || self.empty() {
                    if matches!(key, Key::Space) {
                        effects.commit.push_str(&self.render_output(" "));
                    } else if self.config.profile == BehaviorProfile::Touch {
                        effects.send_return = true;
                    } else {
                        effects.handled = false;
                    }
                } else if !self.state.candidates.is_empty() {
                    if matches!(key, Key::Space)
                        && matches!(
                            self.config.method,
                            InputMethod::Cangjie | InputMethod::Simplex
                        )
                        && self.options().space_as_first_selection_key
                    {
                        self.select_absolute(self.state.page * self.state.page_size, effects)?;
                    } else if matches!(key, Key::Return)
                        || (matches!(
                            self.config.method,
                            InputMethod::Cangjie | InputMethod::Simplex
                        ) && self.options().space_commits_first(self.config.method)
                            && self.page_count() == 1)
                    {
                        let selected = if matches!(key, Key::Space) {
                            0
                        } else {
                            self.selected_index()
                        };
                        self.select_absolute(selected, effects)?;
                    } else {
                        self.page(1, effects);
                    }
                } else if self.config.method == InputMethod::Traditional {
                    let query = self.state.reading.query_key();
                    self.traditional_query(&query, false, effects)?;
                } else {
                    self.table_query(true, effects)?;
                }
            }
            Key::Backspace => {
                if self.empty() {
                    effects.handled = self.config.profile == BehaviorProfile::Touch;
                    effects.delete_backward = effects.handled;
                } else {
                    self.clear_candidates();
                    if self.config.method == InputMethod::Traditional {
                        self.state.reading.backspace();
                    } else {
                        self.state.code.pop();
                        if self.options().realtime && !self.state.code.is_empty() {
                            self.table_query(false, effects)?;
                        }
                    }
                    effects.discard_composition =
                        self.state.reading.is_empty() && self.state.code.is_empty();
                }
            }
            Key::Escape => {
                if self.empty() {
                    effects.handled = false;
                } else {
                    self.clear_composition();
                }
            }
            Key::PageUp | Key::Left => {
                if self.state.candidates.is_empty() {
                    self.block_edit(effects);
                } else {
                    self.page(-1, effects);
                }
            }
            Key::PageDown | Key::Right => {
                if self.state.candidates.is_empty() {
                    self.block_edit(effects);
                } else {
                    self.page(1, effects);
                }
            }
            Key::Up => {
                if self.state.candidates.is_empty() {
                    self.block_edit(effects);
                } else {
                    self.move_highlight(-1, effects);
                }
            }
            Key::Down => {
                if self.state.candidates.is_empty() {
                    self.block_edit(effects);
                } else {
                    self.move_highlight(1, effects);
                }
            }
            Key::Home | Key::End => {
                if self.state.candidates.is_empty() {
                    self.block_edit(effects);
                } else {
                    let index = if matches!(key, Key::Home) {
                        0
                    } else {
                        self.state.candidates.len() - 1
                    };
                    self.state.page = index / self.state.page_size;
                    self.state.highlight = index % self.state.page_size;
                }
            }
            Key::Delete | Key::Tab => self.block_edit(effects),
        }
        Ok(())
    }
    fn block_edit(&self, effects: &mut Effects) {
        effects.handled = !self.empty();
        effects.beep = effects.handled;
    }
}
fn layout_name(layout: BopomofoLayout) -> &'static str {
    match layout {
        BopomofoLayout::Standard => "Standard",
        BopomofoLayout::Hsu => "Hsu",
        BopomofoLayout::ETen => "ETen",
        BopomofoLayout::ETen26 => "ETen26",
        BopomofoLayout::HanyuPinyin => "HanyuPinyin",
    }
}

fn validate_user_phrase(qstring: &str, text: &str) -> Result<(), EngineError> {
    let count = text.chars().count();
    let valid = (1..=8).contains(&count)
        && !text.chars().any(char::is_control)
        && qstring.is_ascii()
        && qstring.len() == count * 2
        && qstring.as_bytes().chunks_exact(2).all(|part| {
            std::str::from_utf8(part)
                .ok()
                .and_then(BopomofoSyllable::from_query_key)
                .is_some_and(|syllable| {
                    syllable
                        .display_text()
                        .chars()
                        .any(|ch| ('\u{3105}'..='\u{3129}').contains(&ch))
                })
        });
    if valid {
        Ok(())
    } else {
        Err(EngineError::InvalidInput(
            "user phrase needs 1..8 characters and matching canonical phonetic query keys".into(),
        ))
    }
}
