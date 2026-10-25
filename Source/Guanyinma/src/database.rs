//! Read-only access to KeyKey's pre-generated, shared model database.
//!
//! These APIs expose source rows in SQLite rowid order. They do not apply
//! input-method scoring, candidate learning, prefix matching, or truncation.

use std::error::Error;
use std::fmt;
use std::fs;
use std::path::Path;

use rusqlite::types::ValueRef;
use rusqlite::{Connection, OpenFlags, OptionalExtension, Row, MAIN_DB};
use serde::{Deserialize, Serialize};

/// A raw exact-match character table in the shared database.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Table {
    /// Traditional Bopomofo, keyed by the existing absolute-order query string.
    Traditional,
    /// Cangjie, keyed by its ASCII radical code.
    Cangjie,
    /// Simplex, keyed by its ASCII radical code.
    Simplex,
}

impl Table {
    fn lookup_sql(self) -> &'static str {
        match self {
            Self::Traditional => {
                "SELECT value FROM \"Mandarin-bpmf-cin\" WHERE key = ?1 ORDER BY rowid"
            }
            Self::Cangjie => "SELECT value FROM \"Generic-cj-cin\" WHERE key = ?1 ORDER BY rowid",
            Self::Simplex => {
                "SELECT value FROM \"Generic-simplex-cin\" WHERE key = ?1 ORDER BY rowid"
            }
        }
    }
}

/// One unchanged Unigram row from the shared model.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Unigram {
    pub qstring: String,
    pub current: String,
    pub probability: f64,
    pub backoff: f64,
}

/// One unchanged Bigram row from the shared model.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Bigram {
    pub qstring: String,
    pub previous: String,
    pub current: String,
    pub probability: f64,
}

/// A model input, opening, schema, query, or row-data error.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum DatabaseError {
    InvalidInput(String),
    Open(String),
    Schema(String),
    Query(String),
    InvalidData(String),
}

impl fmt::Display for DatabaseError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let (kind, detail) = match self {
            Self::InvalidInput(detail) => ("invalid input", detail),
            Self::Open(detail) => ("could not open model", detail),
            Self::Schema(detail) => ("invalid model schema", detail),
            Self::Query(detail) => ("model query failed", detail),
            Self::InvalidData(detail) => ("invalid model data", detail),
        };
        write!(formatter, "{kind}: {detail}")
    }
}

impl Error for DatabaseError {}

/// An independently owned read-only model connection.
///
/// The underlying rusqlite Connection is not Sync. The C ABI supplies a Rust
/// mutex for shared-handle queries; callers must still prevent close races.
/// SQLite mutex flags alone do not provide this Rust-level synchronization.
#[derive(Debug)]
pub struct ModelDatabase {
    connection: Connection,
}

impl ModelDatabase {
    /// Open an existing regular SQLite file without creating or changing it.
    ///
    /// This validates the shared model's five required tables and columns.
    /// Official model content hashes remain the existing build verifier's job.
    pub fn open(path: impl AsRef<Path>) -> Result<Self, DatabaseError> {
        let path = path.as_ref();
        if path.as_os_str().is_empty() {
            return Err(DatabaseError::InvalidInput(
                "database path must not be empty".into(),
            ));
        }
        if path.as_os_str().as_encoded_bytes().contains(&0) {
            return Err(DatabaseError::InvalidInput(
                "database path must not contain NUL".into(),
            ));
        }
        let metadata =
            fs::metadata(path).map_err(|error| DatabaseError::Open(error.to_string()))?;
        if !metadata.is_file() {
            return Err(DatabaseError::InvalidInput(
                "database path must name an existing regular file".into(),
            ));
        }
        // An absolute native path also avoids accidentally interpreting a
        // relative filename beginning with "file:" as a SQLite URI.
        let path =
            fs::canonicalize(path).map_err(|error| DatabaseError::Open(error.to_string()))?;
        let flags = OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX;
        let connection = Connection::open_with_flags(path, flags)
            .map_err(|error| DatabaseError::Open(error.to_string()))?;
        if !connection
            .is_readonly(MAIN_DB)
            .map_err(|error| DatabaseError::Open(error.to_string()))?
        {
            return Err(DatabaseError::Open(
                "SQLite did not open the main database read-only".into(),
            ));
        }
        connection
            .execute_batch("PRAGMA query_only = ON;")
            .map_err(|error| DatabaseError::Open(error.to_string()))?;
        validate_schema(&connection)?;
        Ok(Self { connection })
    }

    /// Return exact-match table values in their original rowid order.
    ///
    /// Keys are bound values, never SQL. No wildcard expansion, candidate
    /// filtering, learning, deduplication, or result limit is applied here.
    pub fn lookup_table(&self, table: Table, key: &str) -> Result<Vec<String>, DatabaseError> {
        self.query_rows(table.lookup_sql(), key, |row| read_text(row, 0, "value"))
    }

    /// Return all rows matching a SQLite GLOB pattern in source order.
    ///
    /// The table is chosen by enum and the pattern remains a bound value.
    /// This preserves the canonical macOS data-source order, including property
    /// rows when the caller's wildcard matches them.
    pub fn lookup_table_pattern(
        &self,
        table: Table,
        pattern: &str,
    ) -> Result<Vec<String>, DatabaseError> {
        let sql = match table {
            Table::Traditional => {
                "SELECT value FROM \"Mandarin-bpmf-cin\" WHERE key GLOB ?1 ORDER BY rowid"
            }
            Table::Cangjie => {
                "SELECT value FROM \"Generic-cj-cin\" WHERE key GLOB ?1 ORDER BY rowid"
            }
            Table::Simplex => {
                "SELECT value FROM \"Generic-simplex-cin\" WHERE key GLOB ?1 ORDER BY rowid"
            }
        };
        self.query_rows(sql, pattern, |row| read_text(row, 0, "value"))
    }

    /// Return the existing mixed/half-width Cangjie punctuation override rows.
    pub fn lookup_cangjie_punctuation(
        &self,
        key: &str,
        half_width: bool,
    ) -> Result<Vec<String>, DatabaseError> {
        let sql = if half_width {
            "SELECT value FROM \"Punctuations-cj-halfwidth-cin\" WHERE key = ?1 ORDER BY rowid"
        } else {
            "SELECT value FROM \"Punctuations-cj-mixedwidth-cin\" WHERE key = ?1 ORDER BY rowid"
        };
        self.query_rows(sql, key, |row| read_text(row, 0, "value"))
    }

    /// Read source-order values for longer valid Cangjie codes.
    pub fn cangjie_prefix_values(&self, code: &str) -> Result<Vec<String>, DatabaseError> {
        let mut result = Vec::new();
        self.for_each_cangjie_prefix_value(code, |value| result.push(value))?;
        Ok(result)
    }

    /// Streams the range so bounded prefix selection need not retain all rows.
    pub(crate) fn for_each_cangjie_prefix_value(
        &self,
        code: &str,
        mut visitor: impl FnMut(String),
    ) -> Result<(), DatabaseError> {
        if code.contains('\0') {
            return Err(DatabaseError::InvalidInput(
                "query key must not contain NUL".into(),
            ));
        }
        if !(1..=4).contains(&code.len()) || !code.bytes().all(|byte| byte.is_ascii_lowercase()) {
            return Ok(());
        }
        let mut statement = self
            .connection
            .prepare(
                "SELECT value FROM \"Generic-cj-cin\" WHERE key GLOB ?1 \
             AND length(key) <= 5 AND key NOT GLOB '*[^a-z]*' ORDER BY rowid",
            )
            .map_err(query_error)?;
        let pattern = format!("{code}?*");
        let mut rows = statement.query([pattern]).map_err(query_error)?;
        while let Some(row) = rows.next().map_err(query_error)? {
            visitor(read_text(row, 0, "value")?);
        }
        Ok(())
    }

    /// Canonical Manjusri score used for explicit user words and learned pairs.
    /// Model boundary rows may make MAX zero; the source uses -1e-7 then.
    pub fn max_unigram_probability(&self) -> Result<f64, DatabaseError> {
        let mut statement = self
            .connection
            .prepare("SELECT MAX(probability) FROM unigrams")
            .map_err(query_error)?;
        let mut rows = statement.query([]).map_err(query_error)?;
        let maximum = match rows.next().map_err(query_error)? {
            Some(row) if !matches!(row.get_ref(0).map_err(query_error)?, ValueRef::Null) => {
                read_number(row, 0, "maximum unigram probability")?
            }
            _ => 0.0,
        };
        Ok(if maximum == 0.0 { -0.0000001 } else { maximum })
    }

    /// Return all matching raw Unigram rows in original rowid order.
    ///
    /// Empty current values are preserved, including the BOS/EOS entries.
    pub fn unigrams(&self, qstring: &str) -> Result<Vec<Unigram>, DatabaseError> {
        self.query_rows(
            "SELECT qstring, current, probability, backoff FROM unigrams \
             WHERE qstring = ?1 ORDER BY rowid",
            qstring,
            |row| {
                Ok(Unigram {
                    qstring: read_text(row, 0, "qstring")?,
                    current: read_text(row, 1, "current")?,
                    probability: read_number(row, 2, "probability")?,
                    backoff: read_number(row, 3, "backoff")?,
                })
            },
        )
    }

    /// Return all matching raw Bigram rows in original rowid order.
    ///
    /// The query is the existing combined qstring, including its separator.
    pub fn bigrams(&self, qstring: &str) -> Result<Vec<Bigram>, DatabaseError> {
        self.query_rows(
            "SELECT qstring, previous, current, probability FROM bigrams \
             WHERE qstring = ?1 ORDER BY rowid",
            qstring,
            |row| {
                Ok(Bigram {
                    qstring: read_text(row, 0, "qstring")?,
                    previous: read_text(row, 1, "previous")?,
                    current: read_text(row, 2, "current")?,
                    probability: read_number(row, 3, "probability")?,
                })
            },
        )
    }

    fn query_rows<T>(
        &self,
        sql: &'static str,
        key: &str,
        mut convert: impl FnMut(&Row<'_>) -> Result<T, DatabaseError>,
    ) -> Result<Vec<T>, DatabaseError> {
        if key.contains('\0') {
            return Err(DatabaseError::InvalidInput(
                "query key must not contain NUL".into(),
            ));
        }
        let mut statement = self.connection.prepare(sql).map_err(query_error)?;
        let mut rows = statement.query([key]).map_err(query_error)?;
        let mut result = Vec::new();
        while let Some(row) = rows.next().map_err(query_error)? {
            result.push(convert(row)?);
        }
        Ok(result)
    }
}

fn validate_schema(connection: &Connection) -> Result<(), DatabaseError> {
    // Bare column identifiers intentionally avoid SQLite's historical
    // double-quoted string-literal fallback for a missing column.
    const REQUIRED: &[(&str, &str)] = &[
        (
            "unigrams",
            "SELECT rowid, qstring, current, probability, backoff FROM unigrams WHERE 0",
        ),
        (
            "bigrams",
            "SELECT rowid, qstring, previous, current, probability FROM bigrams WHERE 0",
        ),
        (
            "Mandarin-bpmf-cin",
            "SELECT rowid, key, value FROM \"Mandarin-bpmf-cin\" WHERE 0",
        ),
        (
            "Generic-cj-cin",
            "SELECT rowid, key, value FROM \"Generic-cj-cin\" WHERE 0",
        ),
        (
            "Generic-simplex-cin",
            "SELECT rowid, key, value FROM \"Generic-simplex-cin\" WHERE 0",
        ),
    ];
    for &(table, probe) in REQUIRED {
        let kind: Option<String> = connection
            .query_row(
                "SELECT type FROM sqlite_master WHERE name = ?1",
                [table],
                |row| row.get(0),
            )
            .optional()
            .map_err(|error| DatabaseError::Schema(error.to_string()))?;
        if kind.as_deref() != Some("table") {
            return Err(DatabaseError::Schema(format!(
                "required table {table} is missing or is not a table"
            )));
        }
        connection
            .prepare(probe)
            .map_err(|error| DatabaseError::Schema(format!("{table}: {error}")))?;

        // Reject user-defined columns that hide SQLite's implicit source-row
        // identity. WITHOUT ROWID tables already fail the SELECT probe above.
        let mut statement = connection
            .prepare("SELECT name FROM pragma_table_info(?1)")
            .map_err(|error| DatabaseError::Schema(error.to_string()))?;
        let names = statement
            .query_map([table], |row| row.get::<_, String>(0))
            .map_err(|error| DatabaseError::Schema(error.to_string()))?;
        for name in names {
            let name = name.map_err(|error| DatabaseError::Schema(error.to_string()))?;
            if matches!(
                name.to_ascii_lowercase().as_str(),
                "rowid" | "_rowid_" | "oid"
            ) {
                return Err(DatabaseError::Schema(format!(
                    "{table} must not shadow SQLite rowid"
                )));
            }
        }
    }
    Ok(())
}

fn query_error(error: rusqlite::Error) -> DatabaseError {
    DatabaseError::Query(error.to_string())
}

fn read_text(row: &Row<'_>, index: usize, name: &str) -> Result<String, DatabaseError> {
    match row.get_ref(index).map_err(query_error)? {
        ValueRef::Text(bytes) => std::str::from_utf8(bytes)
            .map(str::to_owned)
            .map_err(|_| DatabaseError::InvalidData(format!("{name} is not valid UTF-8"))),
        _ => Err(DatabaseError::InvalidData(format!(
            "{name} must contain SQLite TEXT"
        ))),
    }
}

fn read_number(row: &Row<'_>, index: usize, name: &str) -> Result<f64, DatabaseError> {
    let number = match row.get_ref(index).map_err(query_error)? {
        ValueRef::Integer(value) => value as f64,
        ValueRef::Real(value) => value,
        _ => {
            return Err(DatabaseError::InvalidData(format!(
                "{name} must contain a SQLite number"
            )));
        }
    };
    if !number.is_finite() {
        return Err(DatabaseError::InvalidData(format!(
            "{name} must contain a finite number"
        )));
    }
    Ok(number)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};

    const SCHEMA: &str = r#"
        CREATE TABLE unigrams (qstring, current, probability, backoff);
        CREATE TABLE bigrams (qstring, previous, current, probability);
        CREATE TABLE "Mandarin-bpmf-cin" (key, value);
        CREATE TABLE "Generic-cj-cin" (key, value);
        CREATE TABLE "Generic-simplex-cin" (key, value);
    "#;
    static NEXT_DIRECTORY: AtomicU64 = AtomicU64::new(0);

    struct TempModel {
        directory: PathBuf,
        path: PathBuf,
    }

    impl TempModel {
        fn with_schema(schema: &str) -> Self {
            let directory = loop {
                let id = NEXT_DIRECTORY.fetch_add(1, Ordering::Relaxed);
                let candidate = std::env::temp_dir()
                    .join(format!("guanyinma-model-test-{}-{id}", std::process::id()));
                match fs::create_dir(&candidate) {
                    Ok(()) => break candidate,
                    Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
                    Err(error) => panic!("could not create isolated fixture directory: {error}"),
                }
            };
            let fixture = Self {
                path: directory.join("model.db"),
                directory,
            };
            fixture.seed(schema);
            fixture
        }

        fn new() -> Self {
            Self::with_schema(SCHEMA)
        }

        fn seed(&self, sql: &str) {
            let connection = Connection::open(&self.path).expect("open writable test fixture");
            connection
                .execute_batch(sql)
                .expect("seed isolated SQLite fixture");
        }
    }

    impl Drop for TempModel {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.directory);
        }
    }

    #[test]
    fn invalid_paths_never_create_a_database() {
        assert!(matches!(
            ModelDatabase::open(""),
            Err(DatabaseError::InvalidInput(_))
        ));
        assert!(matches!(
            ModelDatabase::open("invalid\0path"),
            Err(DatabaseError::InvalidInput(_))
        ));
        let fixture = TempModel::new();
        let missing = fixture.directory.join("does-not-exist.db");
        assert!(matches!(
            ModelDatabase::open(&missing),
            Err(DatabaseError::Open(_))
        ));
        assert!(!missing.exists());
        assert!(matches!(
            ModelDatabase::open(&fixture.directory),
            Err(DatabaseError::InvalidInput(_))
        ));
    }

    #[test]
    fn required_tables_columns_and_source_rowids_are_validated() {
        let schemas = [
            SCHEMA.replace("CREATE TABLE bigrams (qstring, previous, current, probability);", ""),
            SCHEMA.replace(
                "CREATE TABLE unigrams (qstring, current, probability, backoff);",
                "CREATE TABLE unigrams (qstring, current, probability, unrelated);",
            ),
            SCHEMA.replace(
                "CREATE TABLE unigrams (qstring, current, probability, backoff);",
                "CREATE TABLE unigrams (qstring PRIMARY KEY, current, probability, backoff) WITHOUT ROWID;",
            ),
            SCHEMA.replace(
                "CREATE TABLE unigrams (qstring, current, probability, backoff);",
                "CREATE TABLE unigrams (rowid, qstring, current, probability, backoff);",
            ),
            SCHEMA.replace(
                "CREATE TABLE unigrams (qstring, current, probability, backoff);",
                "CREATE TABLE source (qstring, current, probability, backoff); \
                 CREATE VIEW unigrams AS SELECT * FROM source;",
            ),
        ];
        for schema in schemas {
            let fixture = TempModel::with_schema(&schema);
            assert!(matches!(
                ModelDatabase::open(&fixture.path),
                Err(DatabaseError::Schema(_))
            ));
        }
    }

    #[test]
    fn source_order_and_empty_boundary_words_are_preserved() {
        let fixture = TempModel::new();
        fixture.seed(
            r#"
            INSERT INTO unigrams VALUES
                ('query', '低', -3.0, 0), ('query', '高', -1.0, -0.1),
                ('query', '並', -1.0, 0), ('!', '', 0, -1.25);
            INSERT INTO bigrams VALUES
                ('! query', '', '高', -0.5), ('! query', '', '低', -3.0);
            INSERT INTO "Mandarin-bpmf-cin" VALUES ('query', '妳'), ('query', '你');
            INSERT INTO "Generic-cj-cin" VALUES ('a', '日'), ('a', '曰');
            INSERT INTO "Generic-simplex-cin" VALUES ('ab', '明'), ('ab', '晞');
            "#,
        );
        let model = ModelDatabase::open(&fixture.path).unwrap();
        let words = model.unigrams("query").unwrap();
        assert_eq!(
            words
                .iter()
                .map(|word| word.current.as_str())
                .collect::<Vec<_>>(),
            ["低", "高", "並"]
        );
        assert_eq!(words[0].probability, -3.0);
        assert_eq!(words[1].backoff, -0.1);
        assert_eq!(model.unigrams("!").unwrap()[0].current, "");
        let pairs = model.bigrams("! query").unwrap();
        assert_eq!(pairs[0].previous, "");
        assert_eq!(pairs[0].current, "高");
        assert_eq!(pairs[1].current, "低");
        assert_eq!(
            model.lookup_table(Table::Traditional, "query").unwrap(),
            ["妳", "你"]
        );
        assert_eq!(
            model.lookup_table(Table::Cangjie, "a").unwrap(),
            ["日", "曰"]
        );
        assert_eq!(
            model.lookup_table(Table::Simplex, "ab").unwrap(),
            ["明", "晞"]
        );
    }

    #[test]
    fn raw_lookup_does_not_apply_the_mobile_sixty_four_row_limit() {
        let fixture = TempModel::new();
        {
            let connection = Connection::open(&fixture.path).unwrap();
            for index in 0..70 {
                connection
                    .execute(
                        "INSERT INTO unigrams VALUES (?1, ?2, ?3, 0)",
                        rusqlite::params!["query", format!("候選{index}"), -f64::from(index)],
                    )
                    .unwrap();
            }
        }
        let model = ModelDatabase::open(&fixture.path).unwrap();
        let rows = model.unigrams("query").unwrap();
        assert_eq!(rows.len(), 70);
        assert_eq!(rows[69].current, "候選69");
    }

    #[test]
    fn bound_keys_do_not_become_sql_and_returned_values_are_owned() {
        let fixture = TempModel::new();
        fixture.seed(r#"INSERT INTO "Generic-cj-cin" VALUES ('a', '日'), ('a', '曰');"#);
        let owned_values = {
            let model = ModelDatabase::open(&fixture.path).unwrap();
            let values = model.lookup_table(Table::Cangjie, "a").unwrap();
            assert!(model
                .lookup_table(Table::Cangjie, "a' OR 1=1 --")
                .unwrap()
                .is_empty());
            assert!(model.unigrams("' OR 1=1 --").unwrap().is_empty());
            assert!(model.bigrams("' OR 1=1 --").unwrap().is_empty());
            for result in [
                model.lookup_table(Table::Cangjie, "a\0"),
                model.unigrams("a\0").map(|_| Vec::<String>::new()),
                model.bigrams("a\0").map(|_| Vec::<String>::new()),
            ] {
                assert!(matches!(result, Err(DatabaseError::InvalidInput(_))));
            }
            values
        };
        assert_eq!(owned_values, ["日", "曰"]);
    }

    #[test]
    fn sqlite_read_only_mode_prevents_writes_even_without_query_only() {
        let fixture = TempModel::new();
        let before = fs::read(&fixture.path).unwrap();
        let model = ModelDatabase::open(&fixture.path).unwrap();
        assert!(model.connection.is_readonly(MAIN_DB).unwrap());
        model
            .connection
            .execute_batch("PRAGMA query_only = OFF;")
            .unwrap();
        assert!(model
            .connection
            .execute_batch("INSERT INTO unigrams VALUES ('q', '不可寫入', 0, 0);")
            .is_err());
        drop(model);
        assert_eq!(fs::read(&fixture.path).unwrap(), before);
    }

    #[test]
    fn invalid_model_values_are_errors_instead_of_coerced_partial_results() {
        let bad_rows = [
            "INSERT INTO unigrams VALUES ('query', '字', NULL, 0);",
            "INSERT INTO unigrams VALUES ('query', '字', 'not-a-number', 0);",
            "INSERT INTO unigrams VALUES ('query', NULL, -1, 0);",
            "INSERT INTO unigrams VALUES ('query', CAST(X'80' AS TEXT), -1, 0);",
            "INSERT INTO unigrams VALUES ('query', '字', 1e999, 0);",
            "INSERT INTO unigrams VALUES ('query', '字', -1, -1e999);",
        ];
        for bad_row in bad_rows {
            let fixture = TempModel::new();
            fixture.seed("INSERT INTO unigrams VALUES ('query', '正常', -1, 0);");
            fixture.seed(bad_row);
            let model = ModelDatabase::open(&fixture.path).unwrap();
            assert!(matches!(
                model.unigrams("query"),
                Err(DatabaseError::InvalidData(_))
            ));
        }
    }

    #[test]
    fn table_values_and_bigram_context_require_valid_text_and_numbers() {
        let fixture = TempModel::new();
        fixture.seed(
            r#"
            INSERT INTO "Generic-cj-cin" VALUES ('a', X'E697A5');
            INSERT INTO bigrams VALUES ('! query', NULL, '字', -1);
            INSERT INTO bigrams VALUES ('query $', '字', '', 'not-a-number');
            "#,
        );
        let model = ModelDatabase::open(&fixture.path).unwrap();
        assert!(matches!(
            model.lookup_table(Table::Cangjie, "a"),
            Err(DatabaseError::InvalidData(_))
        ));
        assert!(matches!(
            model.bigrams("! query"),
            Err(DatabaseError::InvalidData(_))
        ));
        assert!(matches!(
            model.bigrams("query $"),
            Err(DatabaseError::InvalidData(_))
        ));
    }
}
