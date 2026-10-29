//! Transactional, separately owned user data for Guanyinma.
//!
//! Copyright (c) 2026 Chui-Ping Cheng. MIT License.
//! Learning table names and reset-generation semantics follow the existing
//! Manjusri / KeyKey user stores. The shared language model is never writable.

use crate::database::{Bigram, DatabaseError, Unigram};
use crate::user_archive::UserArchive;
use rusqlite::types::ValueRef;
use rusqlite::{Connection, OpenFlags, OptionalExtension, Row, TransactionBehavior};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

const APPLICATION_ID: i64 = 0x47594d41;
const SCHEMA_VERSION: i64 = 1;
pub const LEARNING_CAPACITY: usize = 200;

const SCHEMA: &str = r#"
CREATE TABLE guanyinma_metadata (
    id INTEGER PRIMARY KEY CHECK(id=1),
    generation INTEGER NOT NULL CHECK(generation>=0),
    revision INTEGER NOT NULL CHECK(revision>=0)
);
INSERT INTO guanyinma_metadata VALUES(1,0,0);
CREATE TABLE user_unigrams (
    qstring TEXT NOT NULL,
    current TEXT NOT NULL,
    probability REAL NOT NULL,
    backoff REAL NOT NULL,
    UNIQUE(qstring,current)
);
CREATE TABLE user_candidate_override_cache (
    qstring TEXT NOT NULL UNIQUE,
    current TEXT NOT NULL
);
CREATE TABLE user_bigram_cache (
    qstring TEXT NOT NULL UNIQUE,
    previous TEXT NOT NULL,
    current TEXT NOT NULL,
    probability REAL NOT NULL
);
CREATE TABLE table_learning (
    method TEXT NOT NULL,
    code TEXT NOT NULL,
    current TEXT NOT NULL,
    count INTEGER NOT NULL CHECK(count>0),
    UNIQUE(method,code,current)
);
"#;

#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CandidateOverride {
    pub qstring: String,
    pub current: String,
}
#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TableLearning {
    pub method: String,
    pub code: String,
    pub current: String,
    pub count: i64,
}
/// Vectors preserve source row order (oldest first). Frequency increments keep
/// their original table position, while cache replacement refreshes recency.
#[derive(Clone, Debug, Default, PartialEq, Serialize)]
pub struct UserSnapshot {
    pub generation: i64,
    pub revision: i64,
    pub phrases: Vec<Unigram>,
    pub overrides: Vec<CandidateOverride>,
    pub bigrams: Vec<Bigram>,
    pub table: Vec<TableLearning>,
}
#[derive(Clone, Debug, PartialEq, Serialize)]
pub enum UserChange {
    UpsertPhrase(Unigram),
    InsertPhraseIfAbsent(Unigram),
    RemovePhrase {
        qstring: String,
        current: String,
    },
    SetOverride {
        qstring: String,
        current: Option<String>,
    },
    SetBigram(Bigram),
    IncrementTable {
        method: String,
        code: String,
        current: String,
    },
    SetTable(TableLearning),
    ResetLearning,
    ResetSmartLearning,
    ResetTableLearning {
        method: String,
    },
}
impl UserSnapshot {
    pub fn validate(&self) -> Result<(), DatabaseError> {
        validate_snapshot(self)
    }

    /// Compute the same ordered delta without writing. Input sessions use this
    /// to complete all fallible model work before the durable transaction.
    pub fn preview(&self, changes: &[UserChange]) -> Result<Self, DatabaseError> {
        validate_snapshot(self)?;
        let mut result = self.clone();
        for change in changes {
            validate_change(change)?;
            match change {
                UserChange::UpsertPhrase(row) | UserChange::InsertPhraseIfAbsent(row) => {
                    if let Some(existing) = result
                        .phrases
                        .iter_mut()
                        .find(|value| value.qstring == row.qstring && value.current == row.current)
                    {
                        if matches!(change, UserChange::UpsertPhrase(_)) {
                            *existing = row.clone();
                        }
                    } else {
                        result.phrases.push(row.clone());
                    }
                }
                UserChange::RemovePhrase { qstring, current } => {
                    result
                        .phrases
                        .retain(|row| row.qstring != *qstring || row.current != *current);
                }
                UserChange::SetOverride { qstring, current } => {
                    result.overrides.retain(|row| row.qstring != *qstring);
                    if let Some(current) = current {
                        result.overrides.push(CandidateOverride {
                            qstring: qstring.clone(),
                            current: current.clone(),
                        });
                    }
                }
                UserChange::SetBigram(row) => {
                    result.bigrams.retain(|value| value.qstring != row.qstring);
                    result.bigrams.push(row.clone());
                }
                UserChange::IncrementTable {
                    method,
                    code,
                    current,
                } => {
                    if let Some(existing) = result.table.iter_mut().find(|row| {
                        row.method == *method && row.code == *code && row.current == *current
                    }) {
                        existing.count = existing
                            .count
                            .checked_add(1)
                            .ok_or_else(|| data_error("table frequency overflow"))?;
                    } else {
                        result.table.push(TableLearning {
                            method: method.clone(),
                            code: code.clone(),
                            current: current.clone(),
                            count: 1,
                        });
                    }
                }
                UserChange::SetTable(row) => {
                    if let Some(existing) = result.table.iter_mut().find(|value| {
                        value.method == row.method
                            && value.code == row.code
                            && value.current == row.current
                    }) {
                        *existing = row.clone();
                    } else {
                        result.table.push(row.clone());
                    }
                }
                UserChange::ResetSmartLearning => {
                    result.overrides.clear();
                    result.bigrams.clear();
                    result.generation = result
                        .generation
                        .checked_add(1)
                        .ok_or_else(|| data_error("learning generation overflow"))?;
                }
                UserChange::ResetTableLearning { method } => {
                    result.table.retain(|row| row.method != *method);
                    result.generation = result
                        .generation
                        .checked_add(1)
                        .ok_or_else(|| data_error("learning generation overflow"))?;
                }
                UserChange::ResetLearning => {
                    result.overrides.clear();
                    result.bigrams.clear();
                    result.table.clear();
                    result.generation = result
                        .generation
                        .checked_add(1)
                        .ok_or_else(|| data_error("learning generation overflow"))?;
                }
            }
        }
        if result.overrides.len() > LEARNING_CAPACITY {
            result
                .overrides
                .drain(..result.overrides.len() - LEARNING_CAPACITY);
        }
        if result.bigrams.len() > LEARNING_CAPACITY {
            result
                .bigrams
                .drain(..result.bigrams.len() - LEARNING_CAPACITY);
        }
        if !changes.is_empty() {
            result.revision = result
                .revision
                .checked_add(1)
                .ok_or_else(|| data_error("user revision overflow"))?;
        }
        validate_snapshot(&result)?;
        Ok(result)
    }
}
#[derive(Clone, Debug, PartialEq)]
pub enum SaveOutcome {
    Applied(UserSnapshot),
    /// A reset or import invalidated the old learning epoch. Nothing was saved.
    Stale(UserSnapshot),
}

#[derive(Debug)]
pub struct UserStore {
    connection: Connection,
    path: Option<PathBuf>,
    model_path: Option<PathBuf>,
}
impl UserStore {
    pub fn memory() -> Result<Self, DatabaseError> {
        let mut connection = Connection::open_in_memory().map_err(open_error)?;
        initialize(&mut connection)?;
        Ok(Self {
            connection,
            path: None,
            model_path: None,
        })
    }

    /// Only a new path may be initialized. Existing databases must already be
    /// Guanyinma-owned and valid; legacy profiles use explicit read-only import.
    pub fn open(
        path: impl AsRef<Path>,
        model_path: impl AsRef<Path>,
    ) -> Result<Self, DatabaseError> {
        let path = checked_path(path.as_ref())?;
        let model_path = fs::canonicalize(checked_path(model_path.as_ref())?)
            .map_err(|error| DatabaseError::Open(error.to_string()))?;
        reject_same_file(
            &path,
            &model_path,
            "user database must differ from shared model",
        )?;
        let exists = match fs::symlink_metadata(&path) {
            Ok(_) => true,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => false,
            Err(error) => return Err(DatabaseError::Open(error.to_string())),
        };
        if exists {
            if !fs::metadata(&path).map_err(open_error)?.is_file() {
                return Err(invalid("user database must be a regular file"));
            }
            // Check ownership through a read-only connection before requesting
            // any write access. This also protects model hardlinks on platforms
            // without Unix device/inode metadata.
            let probe = open_read_only(&path)?;
            reject_model_schema(&probe)?;
            validate_schema(&probe)?;
            load_snapshot(&probe)?;
        } else {
            // Exclusive reservation refuses dangling symlinks and existing
            // files instead of following a path while creating the database.
            fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&path)
                .map_err(open_error)?;
        }
        let path = fs::canonicalize(path).map_err(open_error)?;
        reject_same_file(
            &path,
            &model_path,
            "user database must differ from shared model",
        )?;
        let mut connection = Connection::open_with_flags(
            &path,
            OpenFlags::SQLITE_OPEN_READ_WRITE | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )
        .map_err(open_error)?;
        connection
            .busy_timeout(Duration::from_millis(100))
            .map_err(query_error)?;
        if !exists {
            initialize(&mut connection)?;
        }
        validate_schema(&connection)?;
        load_snapshot(&connection)?;
        Ok(Self {
            connection,
            path: Some(path),
            model_path: Some(model_path),
        })
    }

    pub fn version(&self) -> Result<(i64, i64), DatabaseError> {
        metadata(&self.connection)
    }
    pub fn snapshot(&self) -> Result<UserSnapshot, DatabaseError> {
        let transaction = self
            .connection
            .unchecked_transaction()
            .map_err(query_error)?;
        let snapshot = load_snapshot(&transaction)?;
        transaction.commit().map_err(query_error)?;
        Ok(snapshot)
    }

    /// Save only per-key changes, never overwrite another process's snapshot.
    /// All returned rows are validated before commit, so callers can update
    /// their in-memory state without a fallible query after durable success.
    pub fn apply(
        &mut self,
        expected_generation: i64,
        changes: &[UserChange],
    ) -> Result<SaveOutcome, DatabaseError> {
        if expected_generation < 0 {
            return Err(invalid("negative learning generation"));
        }
        for change in changes {
            validate_change(change)?;
        }
        let transaction = self
            .connection
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(query_error)?;
        let (generation, _) = metadata(&transaction)?;
        if generation != expected_generation {
            let snapshot = load_snapshot(&transaction)?;
            transaction.commit().map_err(query_error)?;
            return Ok(SaveOutcome::Stale(snapshot));
        }
        for change in changes {
            apply_change(&transaction, change)?;
        }
        if !changes.is_empty() {
            transaction
                .execute(
                    "UPDATE guanyinma_metadata SET revision=revision+1 WHERE id=1",
                    [],
                )
                .map_err(query_error)?;
            trim_caches(&transaction)?;
        }
        let snapshot = load_snapshot(&transaction)?;
        transaction.commit().map_err(query_error)?;
        Ok(SaveOutcome::Applied(snapshot))
    }

    pub fn reset_learning(&mut self) -> Result<UserSnapshot, DatabaseError> {
        let transaction = self
            .connection
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(query_error)?;
        reset(&transaction)?;
        transaction
            .execute(
                "UPDATE guanyinma_metadata SET revision=revision+1 WHERE id=1",
                [],
            )
            .map_err(query_error)?;
        let snapshot = load_snapshot(&transaction)?;
        transaction.commit().map_err(query_error)?;
        Ok(snapshot)
    }

    /// Prepare a separate legacy profile read-only, without writing the
    /// destination. Imports merge custom phrases and replace learned state.
    pub fn read_legacy(
        &self,
        path: impl AsRef<Path>,
        table_method: Option<&str>,
    ) -> Result<Vec<UserChange>, DatabaseError> {
        let path = checked_path(path.as_ref())?;
        if let Some(destination) = &self.path {
            reject_same_file(
                &path,
                destination,
                "import source must differ from destination",
            )?;
        }
        if let Some(model) = &self.model_path {
            reject_same_file(&path, model, "cannot import the shared model as user data")?;
        }
        let source = open_read_only(&path)?;
        reject_model_schema(&source)?;
        let transaction = source.unchecked_transaction().map_err(query_error)?;
        let imported = read_legacy(&transaction, table_method)?;
        let owned: i64 = transaction
            .pragma_query_value(None, "application_id", |row| row.get(0))
            .map_err(query_error)?;
        let smart = has_table(&transaction, "user_candidate_override_cache")?
            || has_table(&transaction, "user_bigram_cache")?;
        let generic = has_table(&transaction, "user_frequency")?;
        transaction.commit().map_err(query_error)?;
        let mut changes = Vec::new();
        if owned == APPLICATION_ID {
            changes.push(UserChange::ResetLearning);
        } else {
            if smart {
                changes.push(UserChange::ResetSmartLearning);
            }
            if generic {
                changes.push(UserChange::ResetTableLearning {
                    method: table_method
                        .ok_or_else(|| invalid("legacy table import requires method"))?
                        .into(),
                });
            }
        }
        changes.extend(
            imported
                .phrases
                .into_iter()
                .map(UserChange::InsertPhraseIfAbsent),
        );
        changes.extend(
            imported
                .overrides
                .into_iter()
                .map(|row| UserChange::SetOverride {
                    qstring: row.qstring,
                    current: Some(row.current),
                }),
        );
        changes.extend(imported.bigrams.into_iter().map(UserChange::SetBigram));
        changes.extend(imported.table.into_iter().map(UserChange::SetTable));
        for change in &changes {
            validate_change(change)?;
        }
        Ok(changes)
    }

    /// Convenience for non-session clients. Sessions prepare with read_legacy,
    /// preview and finish model work, then commit the returned delta atomically.
    pub fn import_legacy(
        &mut self,
        path: impl AsRef<Path>,
        table_method: Option<&str>,
    ) -> Result<UserSnapshot, DatabaseError> {
        let changes = self.read_legacy(path, table_method)?;
        let generation = self.version()?.0;
        match self.apply(generation, &changes)? {
            SaveOutcome::Applied(snapshot) => Ok(snapshot),
            SaveOutcome::Stale(_) => Err(data_error(
                "learning reset raced with import; retry with a new snapshot",
            )),
        }
    }

    /// Import a fully decoded portable archive in one transaction. Sessions use
    /// archive.changes() with their model preview and bounded epoch retry first.
    pub fn import_user_data(
        &mut self,
        archive: &UserArchive,
    ) -> Result<UserSnapshot, DatabaseError> {
        let changes = archive.changes()?;
        let generation = self.version()?.0;
        match self.apply(generation, &changes)? {
            SaveOutcome::Applied(snapshot) => Ok(snapshot),
            SaveOutcome::Stale(_) => Err(data_error(
                "learning reset raced with import; retry with a new snapshot",
            )),
        }
    }
}

fn checked_path(path: &Path) -> Result<PathBuf, DatabaseError> {
    if path.as_os_str().is_empty() || path.as_os_str().as_encoded_bytes().contains(&0) {
        return Err(invalid("database path must be nonempty and contain no NUL"));
    }
    Ok(path.to_path_buf())
}
fn reject_same_file(first: &Path, second: &Path, message: &str) -> Result<(), DatabaseError> {
    if let (Ok(a), Ok(b)) = (fs::canonicalize(first), fs::canonicalize(second)) {
        if a == b {
            return Err(invalid(message));
        }
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        if let (Ok(a), Ok(b)) = (fs::metadata(first), fs::metadata(second)) {
            if a.dev() == b.dev() && a.ino() == b.ino() {
                return Err(invalid(message));
            }
        }
    }
    #[cfg(windows)]
    if fs::metadata(first).is_ok() && fs::metadata(second).is_ok() {
        // Fail closed when a filesystem cannot provide stable identity for
        // two existing files, rather than risk importing onto its own source.
        let a = windows_file_identity(first).map_err(open_error)?;
        let b = windows_file_identity(second).map_err(open_error)?;
        if a == b {
            return Err(invalid(message));
        }
    }
    Ok(())
}
#[cfg(windows)]
fn windows_file_identity(path: &Path) -> Result<(u32, u64), std::io::Error> {
    use std::os::windows::io::AsRawHandle;
    // BY_HANDLE_FILE_INFORMATION consists of thirteen DWORDs; the volume
    // serial is DWORD 7 and the file-index high/low pair is DWORDs 11/12.
    #[link(name = "kernel32")]
    unsafe extern "system" {
        #[link_name = "GetFileInformationByHandle"]
        fn get_file_information_by_handle(
            handle: *mut std::ffi::c_void,
            info: *mut [u32; 13],
        ) -> i32;
    }
    let file = fs::File::open(path)?;
    let mut info = [0u32; 13];
    // SAFETY: file keeps a valid Windows file handle open; the writable array
    // has the documented size/alignment of BY_HANDLE_FILE_INFORMATION.
    if unsafe { get_file_information_by_handle(file.as_raw_handle(), &mut info) } == 0 {
        return Err(std::io::Error::last_os_error());
    }
    Ok((info[7], (u64::from(info[11]) << 32) | u64::from(info[12])))
}
fn open_read_only(path: &Path) -> Result<Connection, DatabaseError> {
    if !fs::metadata(path).map_err(open_error)?.is_file() {
        return Err(invalid("source must be a regular file"));
    }
    let path = fs::canonicalize(path).map_err(open_error)?;
    let connection = Connection::open_with_flags(
        path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )
    .map_err(open_error)?;
    connection
        .execute_batch("PRAGMA query_only=ON")
        .map_err(query_error)?;
    Ok(connection)
}
fn initialize(connection: &mut Connection) -> Result<(), DatabaseError> {
    let transaction = connection
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(query_error)?;
    transaction.execute_batch(SCHEMA).map_err(query_error)?;
    transaction
        .pragma_update(None, "application_id", APPLICATION_ID)
        .map_err(query_error)?;
    transaction
        .pragma_update(None, "user_version", SCHEMA_VERSION)
        .map_err(query_error)?;
    transaction.commit().map_err(query_error)
}
fn reject_model_schema(connection: &Connection) -> Result<(), DatabaseError> {
    for name in ["unigrams", "bigrams", "Mandarin-bpmf-cin", "Generic-cj-cin"] {
        if has_table(connection, name)? {
            return Err(invalid(
                "shared/model database cannot be used as writable user data",
            ));
        }
    }
    Ok(())
}
fn has_table(connection: &Connection, name: &str) -> Result<bool, DatabaseError> {
    connection.query_row("SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name=?1 COLLATE NOCASE)",
        [name], |row| row.get(0)).map_err(query_error)
}
fn validate_schema(connection: &Connection) -> Result<(), DatabaseError> {
    let application: i64 = connection
        .pragma_query_value(None, "application_id", |row| row.get(0))
        .map_err(query_error)?;
    let version: i64 = connection
        .pragma_query_value(None, "user_version", |row| row.get(0))
        .map_err(query_error)?;
    if application != APPLICATION_ID || version != SCHEMA_VERSION {
        return Err(DatabaseError::Schema(
            "not a supported Guanyinma user database; import legacy data explicitly".into(),
        ));
    }
    for (name, columns) in [
        ("guanyinma_metadata", &["id", "generation", "revision"][..]),
        (
            "user_unigrams",
            &["qstring", "current", "probability", "backoff"][..],
        ),
        ("user_candidate_override_cache", &["qstring", "current"][..]),
        (
            "user_bigram_cache",
            &["qstring", "previous", "current", "probability"][..],
        ),
        (
            "table_learning",
            &["method", "code", "current", "count"][..],
        ),
    ] {
        validate_columns(connection, name, columns)?;
    }
    let names = read_rows(connection,
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        |row| text(row, 0))?;
    let expected = [
        "guanyinma_metadata",
        "table_learning",
        "user_bigram_cache",
        "user_candidate_override_cache",
        "user_unigrams",
    ];
    if names != expected {
        return Err(DatabaseError::Schema(
            "unexpected user database tables".into(),
        ));
    }
    let executable: i64 = connection
        .query_row(
            "SELECT count(*) FROM sqlite_master WHERE type IN ('view','trigger')",
            [],
            |row| row.get(0),
        )
        .map_err(query_error)?;
    if executable != 0 {
        return Err(DatabaseError::Schema(
            "user database must not contain views or triggers".into(),
        ));
    }
    for (table, types, keys) in [
        (
            "user_unigrams",
            &["TEXT", "TEXT", "REAL", "REAL"][..],
            &["qstring", "current"][..],
        ),
        (
            "user_candidate_override_cache",
            &["TEXT", "TEXT"][..],
            &["qstring"][..],
        ),
        (
            "user_bigram_cache",
            &["TEXT", "TEXT", "TEXT", "REAL"][..],
            &["qstring"][..],
        ),
        (
            "table_learning",
            &["TEXT", "TEXT", "TEXT", "INTEGER"][..],
            &["method", "code", "current"][..],
        ),
    ] {
        let mut statement = connection
            .prepare("SELECT type FROM pragma_table_info(?1) ORDER BY cid")
            .map_err(query_error)?;
        let actual = statement
            .query_map([table], |row| row.get::<_, String>(0))
            .map_err(query_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(query_error)?;
        if actual != types {
            return Err(DatabaseError::Schema(format!(
                "unexpected types in {table}"
            )));
        }
        let mut statement = connection
            .prepare("SELECT name FROM pragma_index_list(?1) WHERE \"unique\"=1")
            .map_err(query_error)?;
        let indexes = statement
            .query_map([table], |row| row.get::<_, String>(0))
            .map_err(query_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(query_error)?;
        let mut valid = false;
        for index in indexes {
            let mut statement = connection
                .prepare("SELECT name FROM pragma_index_info(?1) ORDER BY seqno")
                .map_err(query_error)?;
            let columns = statement
                .query_map([index], |row| row.get::<_, String>(0))
                .map_err(query_error)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(query_error)?;
            valid |= columns == keys;
        }
        if !valid {
            return Err(DatabaseError::Schema(format!(
                "missing unique identity for {table}"
            )));
        }
    }
    metadata(connection)?;
    Ok(())
}
fn validate_columns(
    connection: &Connection,
    name: &str,
    columns: &[&str],
) -> Result<(), DatabaseError> {
    if !has_table(connection, name)? {
        return Err(DatabaseError::Schema(format!("missing user table {name}")));
    }
    let mut statement = connection
        .prepare("SELECT name FROM pragma_table_info(?1) ORDER BY cid")
        .map_err(query_error)?;
    let names = statement
        .query_map([name], |row| row.get::<_, String>(0))
        .map_err(query_error)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(query_error)?;
    if names != columns {
        return Err(DatabaseError::Schema(format!(
            "unexpected columns in {name}"
        )));
    }
    let sql = format!("SELECT rowid FROM \"{name}\" WHERE 0");
    connection
        .prepare(&sql)
        .map_err(|error| DatabaseError::Schema(error.to_string()))?;
    Ok(())
}
fn metadata(connection: &Connection) -> Result<(i64, i64), DatabaseError> {
    let (generation, revision, count): (i64, i64, i64) = connection.query_row(
        "SELECT generation,revision,(SELECT count(*) FROM guanyinma_metadata) FROM guanyinma_metadata WHERE id=1",
        [], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?))).map_err(query_error)?;
    if generation < 0 || revision < 0 || count != 1 {
        return Err(data_error("invalid user metadata"));
    }
    Ok((generation, revision))
}

fn text(row: &Row<'_>, index: usize) -> Result<String, DatabaseError> {
    match row.get_ref(index).map_err(query_error)? {
        ValueRef::Text(bytes) => std::str::from_utf8(bytes)
            .map(str::to_owned)
            .map_err(|_| data_error("user text is not valid UTF-8")),
        _ => Err(data_error("user text must be SQLite TEXT")),
    }
}
fn number(row: &Row<'_>, index: usize) -> Result<f64, DatabaseError> {
    let value = match row.get_ref(index).map_err(query_error)? {
        ValueRef::Integer(value) => value as f64,
        ValueRef::Real(value) => value,
        _ => return Err(data_error("user probability must be numeric")),
    };
    if !value.is_finite() {
        return Err(data_error("user probability must be finite"));
    }
    Ok(value)
}
// Historical macOS migration quoted the probability column into a typeless
// legacy table. Accept that exact finite numeric text only while importing;
// Guanyinma-owned rows continue to use the strict numeric reader above.
fn legacy_number(row: &Row<'_>, index: usize) -> Result<f64, DatabaseError> {
    if let ValueRef::Text(bytes) = row.get_ref(index).map_err(query_error)? {
        let value = std::str::from_utf8(bytes)
            .map_err(|_| data_error("legacy probability text is not valid UTF-8"))?
            .parse::<f64>()
            .map_err(|_| data_error("legacy probability text must be a complete number"))?;
        if !value.is_finite() {
            return Err(data_error("legacy probability must be finite"));
        }
        Ok(value)
    } else {
        number(row, index)
    }
}
fn integer(row: &Row<'_>, index: usize) -> Result<i64, DatabaseError> {
    match row.get_ref(index).map_err(query_error)? {
        ValueRef::Integer(value) => Ok(value),
        _ => Err(data_error("user frequency must be SQLite INTEGER")),
    }
}
fn read_rows<T>(
    connection: &Connection,
    sql: &str,
    mut read: impl FnMut(&Row<'_>) -> Result<T, DatabaseError>,
) -> Result<Vec<T>, DatabaseError> {
    let mut statement = connection.prepare(sql).map_err(query_error)?;
    let mut rows = statement.query([]).map_err(query_error)?;
    let mut values = Vec::new();
    while let Some(row) = rows.next().map_err(query_error)? {
        values.push(read(row)?);
    }
    Ok(values)
}
fn load_snapshot(connection: &Connection) -> Result<UserSnapshot, DatabaseError> {
    let (generation, revision) = metadata(connection)?;
    let phrases = read_rows(
        connection,
        "SELECT qstring,current,probability,backoff FROM user_unigrams ORDER BY rowid",
        |row| {
            let value = Unigram {
                qstring: text(row, 0)?,
                current: text(row, 1)?,
                probability: number(row, 2)?,
                backoff: number(row, 3)?,
            };
            validate_phrase(&value)?;
            Ok(value)
        },
    )?;
    let overrides = read_rows(
        connection,
        "SELECT qstring,current FROM user_candidate_override_cache ORDER BY rowid",
        |row| {
            let value = CandidateOverride {
                qstring: text(row, 0)?,
                current: text(row, 1)?,
            };
            validate_text(&value.qstring, "override query", false)?;
            validate_text(&value.current, "override text", false)?;
            Ok(value)
        },
    )?;
    let bigrams = read_rows(
        connection,
        "SELECT qstring,previous,current,probability FROM user_bigram_cache ORDER BY rowid",
        |row| {
            let value = Bigram {
                qstring: text(row, 0)?,
                previous: text(row, 1)?,
                current: text(row, 2)?,
                probability: number(row, 3)?,
            };
            validate_bigram(&value)?;
            Ok(value)
        },
    )?;
    let table = read_rows(
        connection,
        "SELECT method,code,current,count FROM table_learning ORDER BY rowid",
        |row| {
            let value = TableLearning {
                method: text(row, 0)?,
                code: text(row, 1)?,
                current: text(row, 2)?,
                count: integer(row, 3)?,
            };
            validate_table(&value)?;
            Ok(value)
        },
    )?;
    if overrides.len() > LEARNING_CAPACITY || bigrams.len() > LEARNING_CAPACITY {
        return Err(data_error("user learning cache exceeds capacity"));
    }
    let snapshot = UserSnapshot {
        generation,
        revision,
        phrases,
        overrides,
        bigrams,
        table,
    };
    validate_snapshot(&snapshot)?;
    Ok(snapshot)
}
fn validate_snapshot(snapshot: &UserSnapshot) -> Result<(), DatabaseError> {
    if snapshot.generation < 0 || snapshot.revision < 0 {
        return Err(data_error("invalid user metadata"));
    }
    if snapshot.overrides.len() > LEARNING_CAPACITY || snapshot.bigrams.len() > LEARNING_CAPACITY {
        return Err(data_error("user learning cache exceeds capacity"));
    }
    let mut seen = std::collections::HashSet::new();
    for row in &snapshot.phrases {
        validate_phrase(row)?;
        if !seen.insert((row.qstring.as_str(), row.current.as_str())) {
            return Err(data_error("duplicate custom phrase"));
        }
    }
    let mut seen = std::collections::HashSet::new();
    for row in &snapshot.overrides {
        validate_text(&row.qstring, "override query", false)?;
        validate_text(&row.current, "override text", false)?;
        if !seen.insert(row.qstring.as_str()) {
            return Err(data_error("duplicate override key"));
        }
    }
    let mut seen = std::collections::HashSet::new();
    for row in &snapshot.bigrams {
        validate_bigram(row)?;
        if !seen.insert(row.qstring.as_str()) {
            return Err(data_error("duplicate Bigram key"));
        }
    }
    let mut seen = std::collections::HashSet::new();
    for row in &snapshot.table {
        validate_table(row)?;
        if !seen.insert((row.method.as_str(), row.code.as_str(), row.current.as_str())) {
            return Err(data_error("duplicate table frequency"));
        }
    }
    Ok(())
}
fn validate_text(value: &str, kind: &str, allow_empty: bool) -> Result<(), DatabaseError> {
    if (!allow_empty && value.is_empty()) || value.contains('\0') {
        return Err(invalid(&format!(
            "{kind} must be nonempty and contain no NUL"
        )));
    }
    Ok(())
}
fn validate_phrase(value: &Unigram) -> Result<(), DatabaseError> {
    validate_text(&value.qstring, "phrase query", false)?;
    validate_text(&value.current, "phrase text", false)?;
    if !value.probability.is_finite() || !value.backoff.is_finite() {
        return Err(invalid("phrase scores must be finite"));
    }
    Ok(())
}
fn validate_bigram(value: &Bigram) -> Result<(), DatabaseError> {
    validate_text(&value.qstring, "bigram query", false)?;
    validate_text(&value.previous, "bigram previous", true)?;
    validate_text(&value.current, "bigram current", false)?;
    if !value.probability.is_finite() {
        return Err(invalid("bigram score must be finite"));
    }
    Ok(())
}
fn validate_method(method: &str) -> Result<(), DatabaseError> {
    if !matches!(method, "traditional" | "cangjie" | "simplex") {
        return Err(invalid("invalid table learning method"));
    }
    Ok(())
}
fn validate_table(value: &TableLearning) -> Result<(), DatabaseError> {
    validate_method(&value.method)?;
    validate_text(&value.code, "table query", false)?;
    validate_text(&value.current, "table text", false)?;
    if value.count <= 0 {
        return Err(invalid("table frequency must be positive"));
    }
    Ok(())
}
fn validate_change(change: &UserChange) -> Result<(), DatabaseError> {
    match change {
        UserChange::UpsertPhrase(row) | UserChange::InsertPhraseIfAbsent(row) => {
            validate_phrase(row)
        }
        UserChange::RemovePhrase { qstring, current } => {
            validate_text(qstring, "phrase query", false)?;
            validate_text(current, "phrase text", false)
        }
        UserChange::SetOverride { qstring, current } => {
            validate_text(qstring, "override query", false)?;
            if let Some(current) = current {
                validate_text(current, "override text", false)?;
            }
            Ok(())
        }
        UserChange::SetBigram(row) => validate_bigram(row),
        UserChange::IncrementTable {
            method,
            code,
            current,
        } => validate_table(&TableLearning {
            method: method.clone(),
            code: code.clone(),
            current: current.clone(),
            count: 1,
        }),
        UserChange::SetTable(row) => validate_table(row),
        UserChange::ResetLearning | UserChange::ResetSmartLearning => Ok(()),
        UserChange::ResetTableLearning { method } => validate_method(method),
    }
}
fn reset(connection: &Connection) -> Result<(), DatabaseError> {
    connection.execute_batch(
        "DELETE FROM user_candidate_override_cache; DELETE FROM user_bigram_cache; DELETE FROM table_learning;
         UPDATE guanyinma_metadata SET generation=generation+1 WHERE id=1;"
    ).map_err(query_error)
}
fn apply_change(connection: &Connection, change: &UserChange) -> Result<(), DatabaseError> {
    match change {
        UserChange::UpsertPhrase(row) => {
            connection.execute("INSERT INTO user_unigrams(qstring,current,probability,backoff) VALUES(?1,?2,?3,?4)
                ON CONFLICT(qstring,current) DO UPDATE SET probability=excluded.probability,backoff=excluded.backoff",
                (&row.qstring, &row.current, row.probability, row.backoff)).map_err(query_error)?;
        }
        UserChange::InsertPhraseIfAbsent(row) => {
            connection.execute("INSERT OR IGNORE INTO user_unigrams(qstring,current,probability,backoff) VALUES(?1,?2,?3,?4)",
                (&row.qstring, &row.current, row.probability, row.backoff)).map_err(query_error)?;
        }
        UserChange::RemovePhrase { qstring, current } => {
            connection
                .execute(
                    "DELETE FROM user_unigrams WHERE qstring=?1 AND current=?2",
                    (qstring, current),
                )
                .map_err(query_error)?;
        }
        UserChange::SetOverride { qstring, current } => {
            connection
                .execute(
                    "DELETE FROM user_candidate_override_cache WHERE qstring=?1",
                    [qstring],
                )
                .map_err(query_error)?;
            if let Some(current) = current {
                connection
                    .execute(
                        "INSERT INTO user_candidate_override_cache(qstring,current) VALUES(?1,?2)",
                        (qstring, current),
                    )
                    .map_err(query_error)?;
            }
        }
        UserChange::SetBigram(row) => {
            connection
                .execute(
                    "DELETE FROM user_bigram_cache WHERE qstring=?1",
                    [&row.qstring],
                )
                .map_err(query_error)?;
            connection.execute("INSERT INTO user_bigram_cache(qstring,previous,current,probability) VALUES(?1,?2,?3,?4)",
                (&row.qstring, &row.previous, &row.current, row.probability)).map_err(query_error)?;
        }
        UserChange::IncrementTable {
            method,
            code,
            current,
        } => {
            let count: Option<i64> = connection
                .query_row(
                    "SELECT count FROM table_learning WHERE method=?1 AND code=?2 AND current=?3",
                    (method, code, current),
                    |row| row.get(0),
                )
                .optional()
                .map_err(query_error)?;
            let count = count
                .unwrap_or(0)
                .checked_add(1)
                .ok_or_else(|| data_error("table frequency overflow"))?;
            connection
                .execute(
                    "INSERT INTO table_learning(method,code,current,count) VALUES(?1,?2,?3,?4)
                ON CONFLICT(method,code,current) DO UPDATE SET count=excluded.count",
                    (method, code, current, count),
                )
                .map_err(query_error)?;
        }
        UserChange::SetTable(row) => {
            connection
                .execute(
                    "INSERT INTO table_learning(method,code,current,count) VALUES(?1,?2,?3,?4)
                ON CONFLICT(method,code,current) DO UPDATE SET count=excluded.count",
                    (&row.method, &row.code, &row.current, row.count),
                )
                .map_err(query_error)?;
        }
        UserChange::ResetLearning => reset(connection)?,
        UserChange::ResetSmartLearning => {
            connection
                .execute_batch(
                    "DELETE FROM user_candidate_override_cache; DELETE FROM user_bigram_cache;
                UPDATE guanyinma_metadata SET generation=generation+1 WHERE id=1;",
                )
                .map_err(query_error)?;
        }
        UserChange::ResetTableLearning { method } => {
            connection
                .execute("DELETE FROM table_learning WHERE method=?1", [method])
                .map_err(query_error)?;
            connection
                .execute(
                    "UPDATE guanyinma_metadata SET generation=generation+1 WHERE id=1",
                    [],
                )
                .map_err(query_error)?;
        }
    }
    Ok(())
}
fn trim_caches(connection: &Connection) -> Result<(), DatabaseError> {
    connection
        .execute(
            "DELETE FROM user_candidate_override_cache WHERE rowid NOT IN
        (SELECT rowid FROM user_candidate_override_cache ORDER BY rowid DESC LIMIT ?1)",
            [LEARNING_CAPACITY as i64],
        )
        .map_err(query_error)?;
    connection
        .execute(
            "DELETE FROM user_bigram_cache WHERE rowid NOT IN
        (SELECT rowid FROM user_bigram_cache ORDER BY rowid DESC LIMIT ?1)",
            [LEARNING_CAPACITY as i64],
        )
        .map_err(query_error)?;
    Ok(())
}
fn read_legacy(
    connection: &Connection,
    table_method: Option<&str>,
) -> Result<UserSnapshot, DatabaseError> {
    let application: i64 = connection
        .pragma_query_value(None, "application_id", |row| row.get(0))
        .map_err(query_error)?;
    if application == APPLICATION_ID {
        validate_schema(connection)?;
        return load_snapshot(connection);
    }
    if application != 0 {
        return Err(DatabaseError::Schema(
            "unsupported legacy application id".into(),
        ));
    }
    let mut data = UserSnapshot::default();
    let mut recognized = false;
    if has_table(connection, "user_unigrams")? {
        recognized = true;
        validate_columns(
            connection,
            "user_unigrams",
            &["qstring", "current", "probability", "backoff"],
        )?;
        data.phrases = read_rows(
            connection,
            "SELECT qstring,current,probability,backoff FROM user_unigrams ORDER BY rowid",
            |row| {
                let value = Unigram {
                    qstring: text(row, 0)?,
                    current: text(row, 1)?,
                    probability: legacy_number(row, 2)?,
                    backoff: legacy_number(row, 3)?,
                };
                validate_phrase(&value)?;
                Ok(value)
            },
        )?;
    }
    if has_table(connection, "user_candidate_override_cache")? {
        recognized = true;
        validate_columns(
            connection,
            "user_candidate_override_cache",
            &["qstring", "current"],
        )?;
        data.overrides = read_rows(
            connection,
            "SELECT qstring,current FROM user_candidate_override_cache ORDER BY rowid",
            |row| {
                let value = CandidateOverride {
                    qstring: text(row, 0)?,
                    current: text(row, 1)?,
                };
                validate_change(&UserChange::SetOverride {
                    qstring: value.qstring.clone(),
                    current: Some(value.current.clone()),
                })?;
                Ok(value)
            },
        )?;
    }
    if has_table(connection, "user_bigram_cache")? {
        recognized = true;
        validate_columns(
            connection,
            "user_bigram_cache",
            &["qstring", "previous", "current", "probability"],
        )?;
        data.bigrams = read_rows(
            connection,
            "SELECT qstring,previous,current,probability FROM user_bigram_cache ORDER BY rowid",
            |row| {
                let value = Bigram {
                    qstring: text(row, 0)?,
                    previous: text(row, 1)?,
                    current: text(row, 2)?,
                    probability: legacy_number(row, 3)?,
                };
                validate_bigram(&value)?;
                Ok(value)
            },
        )?;
    }
    if has_table(connection, "user_frequency")? {
        recognized = true;
        let method =
            table_method.ok_or_else(|| invalid("legacy table frequency import requires method"))?;
        validate_columns(connection, "user_frequency", &["key", "value", "count"])?;
        data.table = read_rows(
            connection,
            "SELECT key,value,count FROM user_frequency ORDER BY rowid",
            |row| {
                let value = TableLearning {
                    method: method.into(),
                    code: text(row, 0)?,
                    current: text(row, 1)?,
                    count: integer(row, 2)?,
                };
                validate_table(&value)?;
                Ok(value)
            },
        )?;
    }
    if !recognized {
        return Err(DatabaseError::Schema(
            "no supported legacy user tables".into(),
        ));
    }
    Ok(data)
}
fn invalid(message: &str) -> DatabaseError {
    DatabaseError::InvalidInput(message.into())
}
fn data_error(message: &str) -> DatabaseError {
    DatabaseError::InvalidData(message.into())
}
fn open_error(error: impl std::fmt::Display) -> DatabaseError {
    DatabaseError::Open(error.to_string())
}
fn query_error(error: impl std::fmt::Display) -> DatabaseError {
    DatabaseError::Query(error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};
    static NEXT: AtomicU64 = AtomicU64::new(0);

    struct Profile {
        directory: PathBuf,
        model: PathBuf,
        user: PathBuf,
    }
    impl Profile {
        fn new() -> Self {
            let directory = loop {
                let id = NEXT.fetch_add(1, Ordering::Relaxed);
                let path = std::env::temp_dir()
                    .join(format!("guanyinma-user-store-{}-{id}", std::process::id()));
                match fs::create_dir(&path) {
                    Ok(()) => break path,
                    Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {}
                    Err(error) => panic!("{error}"),
                }
            };
            let model = directory.join("model.db");
            Connection::open(&model)
                .unwrap()
                .execute_batch("CREATE TABLE unigrams(qstring,current,probability,backoff);")
                .unwrap();
            Self {
                user: directory.join("user.db"),
                directory,
                model,
            }
        }
        fn store(&self) -> UserStore {
            UserStore::open(&self.user, &self.model).unwrap()
        }
    }
    impl Drop for Profile {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.directory);
        }
    }
    fn phrase(query: &str, current: &str) -> Unigram {
        Unigram {
            qstring: query.into(),
            current: current.into(),
            probability: -0.0000001,
            backoff: -3.0,
        }
    }
    fn override_change(query: &str, current: &str) -> UserChange {
        UserChange::SetOverride {
            qstring: query.into(),
            current: Some(current.into()),
        }
    }
    fn bigram(query: &str) -> UserChange {
        UserChange::SetBigram(Bigram {
            qstring: query.into(),
            previous: "前".into(),
            current: "後".into(),
            probability: -0.0000001,
        })
    }
    fn increment(current: &str) -> UserChange {
        UserChange::IncrementTable {
            method: "cangjie".into(),
            code: "a".into(),
            current: current.into(),
        }
    }
    fn applied(result: SaveOutcome) -> UserSnapshot {
        match result {
            SaveOutcome::Applied(snapshot) => snapshot,
            SaveOutcome::Stale(_) => panic!("unexpected stale generation"),
        }
    }

    #[test]
    fn preview_matches_committed_delta_and_never_mutates_the_source_snapshot() {
        let mut store = UserStore::memory().unwrap();
        let initial = store.snapshot().unwrap();
        let changes = vec![
            UserChange::UpsertPhrase(phrase("a", "甲")),
            override_change("a", "甲"),
            bigram("a b"),
            increment("曰"),
            increment("日"),
            increment("日"),
        ];
        let preview = initial.preview(&changes).unwrap();
        assert_eq!(store.snapshot().unwrap(), initial);
        assert_eq!(
            preview,
            applied(store.apply(initial.generation, &changes).unwrap())
        );
        assert_eq!(
            preview
                .table
                .iter()
                .map(|row| (&*row.current, row.count))
                .collect::<Vec<_>>(),
            [("曰", 1), ("日", 2)]
        );
        assert_eq!(initial, UserSnapshot::default());
    }

    #[test]
    fn portable_import_rolls_back_learning_and_metadata_when_a_later_insert_fails() {
        let mut store = UserStore::memory().unwrap();
        let before = applied(
            store
                .apply(
                    0,
                    &[
                        UserChange::UpsertPhrase(phrase("old", "舊")),
                        override_change("old", "舊"),
                        bigram("old next"),
                        increment("日"),
                    ],
                )
                .unwrap(),
        );
        store
            .connection
            .execute_batch(
                "CREATE TRIGGER reject_import BEFORE INSERT ON user_unigrams
             WHEN NEW.current='拒' BEGIN SELECT RAISE(ABORT,'import rejected'); END;",
            )
            .unwrap();
        let archive = UserArchive::from_snapshot(&UserSnapshot {
            phrases: vec![phrase("first", "先"), phrase("reject", "拒")],
            ..UserSnapshot::default()
        })
        .unwrap();
        assert!(store.import_user_data(&archive).is_err());
        assert_eq!(store.snapshot().unwrap(), before);
    }

    #[test]
    fn reopen_preserves_exact_phrase_scores_and_ordered_cache_and_frequency_state() {
        let profile = Profile::new();
        let mut store = profile.store();
        let changes = vec![
            UserChange::UpsertPhrase(phrase("a", "甲")),
            override_change("a", "甲"),
            override_change("b", "乙"),
            override_change("a", "另"),
            bigram("a b"),
            increment("曰"),
            increment("日"),
            increment("日"),
        ];
        let expected = applied(store.apply(0, &changes).unwrap());
        assert_eq!(
            expected
                .overrides
                .iter()
                .map(|row| row.qstring.as_str())
                .collect::<Vec<_>>(),
            ["b", "a"]
        );
        drop(store);
        assert_eq!(profile.store().snapshot().unwrap(), expected);
    }

    #[test]
    fn reset_learning_preserves_custom_phrases_and_invalidates_old_writers() {
        let profile = Profile::new();
        let mut first = profile.store();
        let mut second = profile.store();
        let before = applied(
            first
                .apply(
                    0,
                    &[
                        UserChange::UpsertPhrase(phrase("a", "甲")),
                        override_change("a", "甲"),
                        bigram("a b"),
                        increment("曰"),
                    ],
                )
                .unwrap(),
        );
        let reset = second.reset_learning().unwrap();
        assert_eq!(reset.generation, 1);
        assert_eq!(reset.phrases, before.phrases);
        assert!(reset.overrides.is_empty() && reset.bigrams.is_empty() && reset.table.is_empty());
        assert_eq!(
            first.apply(0, &[override_change("old", "不復活")]).unwrap(),
            SaveOutcome::Stale(reset.clone())
        );
        assert_eq!(first.snapshot().unwrap(), reset);
    }

    #[test]
    fn concurrent_writers_merge_per_key_without_overwriting_another_snapshot() {
        let profile = Profile::new();
        let mut first = profile.store();
        let mut second = profile.store();
        first
            .apply(0, &[override_change("a", "甲"), increment("曰")])
            .unwrap();
        let after = applied(
            second
                .apply(0, &[override_change("b", "乙"), increment("日")])
                .unwrap(),
        );
        assert_eq!(
            after
                .overrides
                .iter()
                .map(|row| row.qstring.as_str())
                .collect::<Vec<_>>(),
            ["a", "b"]
        );
        assert_eq!(
            after
                .table
                .iter()
                .map(|row| row.current.as_str())
                .collect::<Vec<_>>(),
            ["曰", "日"]
        );
        assert_eq!(after.revision, 2);
        assert_eq!(first.version().unwrap(), (0, 2));
    }

    #[test]
    fn bounded_caches_refresh_repeated_keys_and_keep_latest_two_hundred() {
        let mut store = UserStore::memory().unwrap();
        let mut changes = Vec::new();
        for index in 0..205 {
            changes.push(override_change(&format!("key{index}"), "字"));
            changes.push(bigram(&format!("query{index}")));
        }
        changes.push(override_change("key5", "新"));
        changes.push(bigram("query5"));
        let preview = store.snapshot().unwrap().preview(&changes).unwrap();
        let snapshot = applied(store.apply(0, &changes).unwrap());
        assert_eq!(snapshot, preview);
        assert_eq!(snapshot.overrides.len(), 200);
        assert_eq!(snapshot.bigrams.len(), 200);
        assert_eq!(snapshot.overrides.first().unwrap().qstring, "key6");
        assert_eq!(snapshot.overrides.last().unwrap().qstring, "key5");
        assert_eq!(snapshot.bigrams.last().unwrap().qstring, "query5");
    }

    #[test]
    fn invalid_input_and_mid_transaction_failure_leave_every_table_unchanged() {
        let profile = Profile::new();
        let mut store = profile.store();
        let before = store.snapshot().unwrap();
        let mut bad = phrase("a", "甲");
        bad.probability = f64::NAN;
        assert!(store.apply(0, &[UserChange::UpsertPhrase(bad)]).is_err());
        assert!(store.apply(0, &[override_change("bad\0", "甲")]).is_err());
        let writer = Connection::open(&profile.user).unwrap();
        writer.execute_batch("CREATE TRIGGER reject_override BEFORE INSERT ON user_candidate_override_cache WHEN NEW.qstring='deny' BEGIN SELECT RAISE(ABORT,'test rejection'); END;").unwrap();
        assert!(store
            .apply(
                0,
                &[
                    UserChange::UpsertPhrase(phrase("a", "甲")),
                    override_change("deny", "乙")
                ]
            )
            .is_err());
        assert_eq!(store.snapshot().unwrap(), before);
    }

    #[test]
    fn busy_save_can_retry_the_same_delta_without_partial_learning() {
        let profile = Profile::new();
        let mut store = profile.store();
        store
            .connection
            .busy_timeout(Duration::from_millis(1))
            .unwrap();
        let writer = Connection::open(&profile.user).unwrap();
        writer.execute_batch("BEGIN IMMEDIATE").unwrap();
        let changes = [override_change("a", "甲"), increment("曰")];
        assert!(store.apply(0, &changes).is_err());
        writer.execute_batch("ROLLBACK").unwrap();
        let after = applied(store.apply(0, &changes).unwrap());
        assert_eq!(after.overrides.len(), 1);
        assert_eq!(after.table[0].count, 1);
        assert_eq!(after.revision, 1);
    }

    #[test]
    fn model_aliases_and_unowned_existing_files_are_never_opened_writable() {
        let profile = Profile::new();
        let original = fs::read(&profile.model).unwrap();
        assert!(UserStore::open(&profile.model, &profile.model).is_err());
        let alias = profile.directory.join("hardlink.db");
        match fs::hard_link(&profile.model, &alias) {
            Ok(()) => assert!(UserStore::open(&alias, &profile.model).is_err()),
            Err(error)
                if cfg!(target_os = "android")
                    && error.kind() == std::io::ErrorKind::PermissionDenied =>
            {
                // Android SELinux forbids the adb shell domain from creating
                // hard links. Only this known fixture restriction is accepted;
                // other domains and failures must still fail the test.
                let context = fs::read_to_string("/proc/self/attr/current").unwrap();
                assert!(context.starts_with("u:r:shell:"), "{context:?}: {error}");
                assert_eq!(
                    fs::symlink_metadata(&alias).unwrap_err().kind(),
                    std::io::ErrorKind::NotFound
                );
                eprintln!(
                    "hardlink fixture unavailable: Android shell SELinux denied creation; \
                     hardlink rejection was not exercised in this environment"
                );
            }
            Err(error) => panic!("cannot create hardlink fixture: {error}"),
        }
        #[cfg(unix)]
        {
            let alias = profile.directory.join("symlink.db");
            std::os::unix::fs::symlink(&profile.model, &alias).unwrap();
            assert!(UserStore::open(&alias, &profile.model).is_err());
        }
        assert_eq!(fs::read(&profile.model).unwrap(), original);
        // A copied model has a different file identity, so the read-only
        // schema probe must also reject it before requesting write access.
        let model_copy = profile.directory.join("model-copy.db");
        fs::copy(&profile.model, &model_copy).unwrap();
        assert!(UserStore::open(&model_copy, &profile.model).is_err());
        assert_eq!(fs::read(&model_copy).unwrap(), original);
        let legacy = profile.directory.join("legacy.db");
        Connection::open(&legacy)
            .unwrap()
            .execute_batch("CREATE TABLE user_unigrams(qstring,current,probability,backoff);")
            .unwrap();
        let before = fs::read(&legacy).unwrap();
        assert!(UserStore::open(&legacy, &profile.model).is_err());
        assert_eq!(fs::read(&legacy).unwrap(), before);
    }

    #[test]
    fn explicit_legacy_import_is_read_only_preserves_phrases_and_starts_new_epoch() {
        let profile = Profile::new();
        let mut store = profile.store();
        store
            .apply(
                0,
                &[
                    UserChange::UpsertPhrase(phrase("a", "原")),
                    override_change("old", "舊"),
                ],
            )
            .unwrap();
        let legacy = profile.directory.join("legacy.db");
        let writer = Connection::open(&legacy).unwrap();
        writer
            .execute_batch(
                "CREATE TABLE user_unigrams(qstring,current,probability,backoff);
             CREATE TABLE user_candidate_override_cache(qstring,current);
             CREATE TABLE user_bigram_cache(qstring,previous,current,probability);
             INSERT INTO user_unigrams VALUES('a','原',-99,-99),('b','新',-0.0000001,-3);
             INSERT INTO user_candidate_override_cache VALUES('b','新');
             INSERT INTO user_bigram_cache VALUES('a b','原','新',0);",
            )
            .unwrap();
        drop(writer);
        let bytes = fs::read(&legacy).unwrap();
        let before = store.snapshot().unwrap();
        let changes = store.read_legacy(&legacy, None).unwrap();
        assert_eq!(store.snapshot().unwrap(), before);
        let preview = before.preview(&changes).unwrap();
        let actual = store.import_legacy(&legacy, None).unwrap();
        assert_eq!(preview, actual);
        assert_eq!(actual.generation, 1);
        assert_eq!(actual.phrases[0], phrase("a", "原"));
        assert_eq!(actual.phrases[1], phrase("b", "新"));
        assert_eq!(
            actual.overrides,
            [CandidateOverride {
                qstring: "b".into(),
                current: "新".into()
            }]
        );
        assert_eq!(fs::read(&legacy).unwrap(), bytes);
        assert!(store.read_legacy(&profile.user, None).is_err());
    }

    #[test]
    fn generic_legacy_import_requires_method_and_preserves_frequency_tie_order() {
        let profile = Profile::new();
        let mut store = profile.store();
        let legacy = profile.directory.join("generic.db");
        Connection::open(&legacy)
            .unwrap()
            .execute_batch(
                "CREATE TABLE user_frequency(key,value,count);
             INSERT INTO user_frequency VALUES('a','曰',1),('a','日',1);",
            )
            .unwrap();
        assert!(store.read_legacy(&legacy, None).is_err());
        let snapshot = store.import_legacy(&legacy, Some("cangjie")).unwrap();
        assert_eq!(
            snapshot
                .table
                .iter()
                .map(|row| row.current.as_str())
                .collect::<Vec<_>>(),
            ["曰", "日"]
        );
        let after = applied(
            store
                .apply(snapshot.generation, &[increment("日")])
                .unwrap(),
        );
        assert_eq!(
            after
                .table
                .iter()
                .map(|row| (&*row.current, row.count))
                .collect::<Vec<_>>(),
            [("曰", 1), ("日", 2)]
        );
    }

    #[test]
    fn malformed_legacy_import_and_owned_row_types_fail_without_changes() {
        let profile = Profile::new();
        let mut store = profile.store();
        let before = store.snapshot().unwrap();
        let legacy = profile.directory.join("bad.db");
        Connection::open(&legacy)
            .unwrap()
            .execute_batch(
                "CREATE TABLE user_unigrams(qstring,current,probability,backoff);
             INSERT INTO user_unigrams VALUES('a',x'FF',-1,0);",
            )
            .unwrap();
        assert!(store.import_legacy(&legacy, None).is_err());
        assert_eq!(store.snapshot().unwrap(), before);
        let writer = Connection::open(&profile.user).unwrap();
        writer
            .execute("INSERT INTO user_unigrams VALUES('a',x'FF',-1,0)", [])
            .unwrap();
        assert!(store.snapshot().is_err());
        drop(store);
        let bytes = fs::read(&profile.user).unwrap();
        assert!(UserStore::open(&profile.user, &profile.model).is_err());
        assert_eq!(fs::read(&profile.user).unwrap(), bytes);
    }

    #[test]
    fn bound_values_remain_data_and_counter_overflow_does_not_commit() {
        let mut store = UserStore::memory().unwrap();
        let query = "x'; DROP TABLE user_unigrams; --";
        let snapshot = applied(
            store
                .apply(
                    0,
                    &[
                        override_change(query, "值"),
                        UserChange::SetTable(TableLearning {
                            method: "cangjie".into(),
                            code: "a".into(),
                            current: "日".into(),
                            count: i64::MAX,
                        }),
                    ],
                )
                .unwrap(),
        );
        assert_eq!(snapshot.overrides[0].qstring, query);
        assert!(snapshot.preview(&[increment("日")]).is_err());
        assert!(store.apply(0, &[increment("日")]).is_err());
        assert_eq!(store.snapshot().unwrap(), snapshot);
    }
    #[test]
    fn incompatible_owned_schema_is_rejected_read_only_without_repair() {
        let profile = Profile::new();
        drop(profile.store());
        let writer = Connection::open(&profile.user).unwrap();
        writer
            .execute_batch(
                "ALTER TABLE user_unigrams RENAME TO replaced;
             CREATE TABLE user_unigrams(qstring TEXT,current TEXT,probability REAL,backoff REAL);
             DROP TABLE replaced;",
            )
            .unwrap();
        drop(writer);
        let bytes = fs::read(&profile.user).unwrap();
        assert!(UserStore::open(&profile.user, &profile.model).is_err());
        assert_eq!(fs::read(&profile.user).unwrap(), bytes);
    }
    #[test]
    fn legacy_import_replaces_only_present_learning_domains() {
        let profile = Profile::new();
        let mut store = profile.store();
        store
            .apply(
                0,
                &[
                    override_change("smart", "甲"),
                    bigram("a b"),
                    increment("曰"),
                    UserChange::SetTable(TableLearning {
                        method: "simplex".into(),
                        code: "ab".into(),
                        current: "明".into(),
                        count: 3,
                    }),
                ],
            )
            .unwrap();
        let generic = profile.directory.join("generic.db");
        Connection::open(&generic).unwrap().execute_batch(
            "CREATE TABLE user_frequency(key,value,count); INSERT INTO user_frequency VALUES('a','日',2);"
        ).unwrap();
        let snapshot = store.import_legacy(&generic, Some("cangjie")).unwrap();
        assert_eq!(snapshot.overrides[0].qstring, "smart");
        assert_eq!(snapshot.bigrams.len(), 1);
        assert_eq!(
            snapshot
                .table
                .iter()
                .map(|row| (&*row.method, &*row.current))
                .collect::<Vec<_>>(),
            [("simplex", "明"), ("cangjie", "日")]
        );
        let phrases = profile.directory.join("phrases.db");
        Connection::open(&phrases).unwrap().execute_batch(
            "CREATE TABLE user_unigrams(qstring,current,probability,backoff); INSERT INTO user_unigrams VALUES('a','新',-1,0);"
        ).unwrap();
        let after = store.import_legacy(&phrases, None).unwrap();
        assert_eq!(after.generation, snapshot.generation);
        assert_eq!(after.overrides, snapshot.overrides);
        assert_eq!(after.bigrams, snapshot.bigrams);
        assert_eq!(after.table, snapshot.table);
        assert_eq!(after.phrases.len(), 1);
        let smart = profile.directory.join("smart.db");
        Connection::open(&smart).unwrap().execute_batch(
            "CREATE TABLE user_candidate_override_cache(qstring,current); INSERT INTO user_candidate_override_cache VALUES('new','乙');"
        ).unwrap();
        let last = store.import_legacy(&smart, None).unwrap();
        assert_eq!(last.overrides[0].qstring, "new");
        assert!(last.bigrams.is_empty());
        assert_eq!(last.table, after.table);
        assert_eq!(last.phrases, after.phrases);
    }
    #[test]
    fn legacy_numeric_text_scores_import_without_relaxing_owned_numeric_reads() {
        let profile = Profile::new();
        let mut store = profile.store();
        let legacy = profile.directory.join("numeric-text.db");
        Connection::open(&legacy)
            .unwrap()
            .execute_batch(
                "CREATE TABLE user_unigrams(qstring,current,probability,backoff);
             CREATE TABLE user_bigram_cache(qstring,previous,current,probability);
             INSERT INTO user_unigrams VALUES('a','甲','-0.0000001','-3');
             INSERT INTO user_bigram_cache VALUES('a b','甲','乙','0.0');",
            )
            .unwrap();
        let original = fs::read(&legacy).unwrap();
        let snapshot = store.import_legacy(&legacy, None).unwrap();
        assert_eq!(snapshot.phrases, [phrase("a", "甲")]);
        assert_eq!(snapshot.bigrams[0].probability, 0.0);
        assert_eq!(fs::read(&legacy).unwrap(), original);

        let connection = Connection::open_in_memory().unwrap();
        let mut statement = connection.prepare("SELECT '-0.0000001'").unwrap();
        let mut rows = statement.query([]).unwrap();
        let row = rows.next().unwrap().unwrap();
        assert!(number(row, 0).is_err());
        assert_eq!(legacy_number(row, 0).unwrap(), -0.0000001);
    }

    #[test]
    fn legacy_numeric_text_rejects_nonfinite_partial_and_invalid_strings_atomically() {
        let profile = Profile::new();
        let mut store = profile.store();
        store
            .apply(
                0,
                &[
                    UserChange::UpsertPhrase(phrase("keep", "留")),
                    override_change("keep", "留"),
                ],
            )
            .unwrap();
        let before = store.snapshot().unwrap();
        let legacy = profile.directory.join("bad-numeric-text.db");
        let source = Connection::open(&legacy).unwrap();
        source
            .execute_batch("CREATE TABLE user_unigrams(qstring,current,probability,backoff);")
            .unwrap();
        for invalid in [
            "NaN", "inf", "-inf", "1e999", "-1junk", "", " 1", "1 ", "1\0",
        ] {
            source.execute("DELETE FROM user_unigrams", []).unwrap();
            source
                .execute(
                    "INSERT INTO user_unigrams VALUES('a','甲',?1,'0')",
                    [invalid],
                )
                .unwrap();
            assert!(store.import_legacy(&legacy, None).is_err(), "{invalid:?}");
            assert_eq!(store.snapshot().unwrap(), before);
            source
                .execute(
                    "UPDATE user_unigrams SET probability='-1',backoff=?1",
                    [invalid],
                )
                .unwrap();
            assert!(
                store.import_legacy(&legacy, None).is_err(),
                "backoff {invalid:?}"
            );
            assert_eq!(store.snapshot().unwrap(), before);
        }
    }

    #[test]
    fn preview_updates_existing_rows_and_empty_deltas_are_read_only() {
        let mut store = UserStore::memory().unwrap();
        let before = applied(
            store
                .apply(
                    0,
                    &[
                        UserChange::UpsertPhrase(phrase("a", "甲")),
                        UserChange::SetTable(TableLearning {
                            method: "cangjie".into(),
                            code: "a".into(),
                            current: "日".into(),
                            count: 2,
                        }),
                    ],
                )
                .unwrap(),
        );
        let mut replacement = phrase("a", "甲");
        replacement.probability = -2.;
        let changes = [
            UserChange::UpsertPhrase(replacement.clone()),
            UserChange::SetTable(TableLearning {
                count: 7,
                ..before.table[0].clone()
            }),
        ];
        let preview = before.preview(&changes).unwrap();
        assert_eq!(preview.phrases, [replacement]);
        assert_eq!(preview.table.len(), 1);
        assert_eq!(preview.table[0].count, 7);
        assert_eq!(store.snapshot().unwrap(), before);
        assert_eq!(applied(store.apply(0, &changes).unwrap()), preview);
        assert_eq!(preview.preview(&[]).unwrap(), preview);
        assert_eq!(applied(store.apply(0, &[]).unwrap()), preview);
        assert!(store.apply(-1, &changes).is_err());
        assert_eq!(store.snapshot().unwrap(), preview);
    }

    #[test]
    fn owned_import_replaces_all_learning_but_preserves_existing_custom_words() {
        let source = Profile::new();
        let mut source_store = source.store();
        let imported = applied(
            source_store
                .apply(
                    0,
                    &[
                        UserChange::UpsertPhrase(phrase("a", "甲")),
                        override_change("a", "甲"),
                        bigram("a b"),
                        increment("日"),
                    ],
                )
                .unwrap(),
        );
        drop(source_store);
        let source_bytes = fs::read(&source.user).unwrap();
        let destination = Profile::new();
        let mut store = destination.store();
        let before = applied(
            store
                .apply(
                    0,
                    &[
                        UserChange::UpsertPhrase(phrase("keep", "留")),
                        override_change("old", "舊"),
                        increment("曰"),
                    ],
                )
                .unwrap(),
        );
        let changes = store.read_legacy(&source.user, None).unwrap();
        assert_eq!(store.snapshot().unwrap(), before);
        let expected = before.preview(&changes).unwrap();
        let after = store.import_legacy(&source.user, None).unwrap();
        assert_eq!(after, expected);
        assert_eq!(after.generation, before.generation + 1);
        assert_eq!(after.phrases, [phrase("keep", "留"), phrase("a", "甲")]);
        assert_eq!(after.overrides, imported.overrides);
        assert_eq!(after.bigrams, imported.bigrams);
        assert_eq!(after.table, imported.table);
        assert_eq!(fs::read(&source.user).unwrap(), source_bytes);
    }

    #[test]
    fn later_invalid_import_domain_cannot_partially_add_valid_phrases() {
        let profile = Profile::new();
        let mut store = profile.store();
        let before = applied(
            store
                .apply(
                    0,
                    &[
                        UserChange::UpsertPhrase(phrase("keep", "留")),
                        override_change("keep", "留"),
                        increment("曰"),
                    ],
                )
                .unwrap(),
        );
        let legacy = profile.directory.join("mixed-domains.db");
        let source = Connection::open(&legacy).unwrap();
        source
            .execute_batch(
                "CREATE TABLE user_unigrams(qstring,current,probability,backoff);
            CREATE TABLE user_bigram_cache(qstring,previous,current,probability);
            INSERT INTO user_unigrams VALUES('new','新',-1,0);
            INSERT INTO user_bigram_cache VALUES('new next','新','後',1e999);",
            )
            .unwrap();
        drop(source);
        let bytes = fs::read(&legacy).unwrap();
        assert!(matches!(
            store.import_legacy(&legacy, None),
            Err(DatabaseError::InvalidData(_))
        ));
        assert_eq!(store.snapshot().unwrap(), before);
        assert_eq!(fs::read(&legacy).unwrap(), bytes);
    }
}
