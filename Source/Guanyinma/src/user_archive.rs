//! Portable, explicitly scoped user-data archives.
//!
//! Copyright (c) 2026 Chui-Ping Cheng. MIT License.
//! Frontends decode legacy containers into this data contract before submitting
//! one import operation. No database path, SQL or local epoch is part of it.

use crate::database::{Bigram, DatabaseError, Unigram};
use crate::user_store::{CandidateOverride, TableLearning, UserChange, UserSnapshot};
use serde::{Deserialize, Serialize};

pub const USER_ARCHIVE_SCHEMA_VERSION: u32 = 1;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum UserArchiveFormat {
    GuanyinmaUserData,
}

/// Ordered Smart Mandarin caches, from oldest to newest.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SmartLearning {
    pub overrides: Vec<CandidateOverride>,
    pub bigrams: Vec<Bigram>,
}

/// Custom phrases merge without overwriting existing phrase scores. A present
/// learning scope replaces that scope, including when its collections are empty;
/// a missing or null scope preserves the destination's existing learning.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct UserArchive {
    pub format: UserArchiveFormat,
    pub schema_version: u32,
    pub phrases: Vec<Unigram>,
    #[serde(default)]
    pub smart: Option<SmartLearning>,
    /// All table methods together: Traditional Bopomofo, Cangjie and Simplex.
    #[serde(default)]
    pub table: Option<Vec<TableLearning>>,
}

impl UserArchive {
    /// Create a complete portable backup without exporting local metadata.
    pub fn from_snapshot(snapshot: &UserSnapshot) -> Result<Self, DatabaseError> {
        snapshot.validate()?;
        Ok(Self {
            format: UserArchiveFormat::GuanyinmaUserData,
            schema_version: USER_ARCHIVE_SCHEMA_VERSION,
            phrases: snapshot.phrases.clone(),
            smart: Some(SmartLearning {
                overrides: snapshot.overrides.clone(),
                bigrams: snapshot.bigrams.clone(),
            }),
            table: Some(snapshot.table.clone()),
        })
    }

    /// Validate the whole archive before deriving or writing any changes.
    pub fn validate(&self) -> Result<(), DatabaseError> {
        if self.schema_version != USER_ARCHIVE_SCHEMA_VERSION {
            return Err(DatabaseError::InvalidInput(
                "unsupported user archive schema version".into(),
            ));
        }
        // Reuse the store's complete row, duplicate-key and capacity contract.
        // Archive metadata cannot change the destination's local learning epoch.
        UserSnapshot {
            phrases: self.phrases.clone(),
            overrides: self
                .smart
                .as_ref()
                .map(|scope| scope.overrides.clone())
                .unwrap_or_default(),
            bigrams: self
                .smart
                .as_ref()
                .map(|scope| scope.bigrams.clone())
                .unwrap_or_default(),
            table: self.table.clone().unwrap_or_default(),
            ..UserSnapshot::default()
        }
        .validate()
    }

    /// Prepare one ordered delta for the normal preview/transaction boundary.
    /// Learning replacement advances the destination's epoch, invalidating
    /// unsaved learning from sessions displaying the previous state.
    pub fn changes(&self) -> Result<Vec<UserChange>, DatabaseError> {
        self.validate()?;
        let mut changes = Vec::new();
        match (&self.smart, &self.table) {
            (Some(_), Some(_)) => changes.push(UserChange::ResetLearning),
            (Some(_), None) => changes.push(UserChange::ResetSmartLearning),
            (None, Some(_)) => {
                for method in ["traditional", "cangjie", "simplex"] {
                    changes.push(UserChange::ResetTableLearning {
                        method: method.into(),
                    });
                }
            }
            (None, None) => {}
        }
        changes.extend(
            self.phrases
                .iter()
                .cloned()
                .map(UserChange::InsertPhraseIfAbsent),
        );
        if let Some(scope) = &self.smart {
            changes.extend(scope.overrides.iter().map(|row| UserChange::SetOverride {
                qstring: row.qstring.clone(),
                current: Some(row.current.clone()),
            }));
            changes.extend(scope.bigrams.iter().cloned().map(UserChange::SetBigram));
        }
        if let Some(scope) = &self.table {
            changes.extend(scope.iter().cloned().map(UserChange::SetTable));
        }
        Ok(changes)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::user_store::{SaveOutcome, UserStore, LEARNING_CAPACITY};
    use serde_json::{json, Value};

    fn phrase(qstring: &str, current: &str) -> Unigram {
        Unigram {
            qstring: qstring.into(),
            current: current.into(),
            probability: -0.25,
            backoff: -2.0,
        }
    }
    fn snapshot() -> UserSnapshot {
        UserSnapshot {
            generation: 12,
            revision: 34,
            phrases: vec![phrase("q", "詞")],
            overrides: vec![CandidateOverride {
                qstring: "o".into(),
                current: "選".into(),
            }],
            bigrams: vec![Bigram {
                qstring: "! q".into(),
                previous: String::new(),
                current: "詞".into(),
                probability: -0.5,
            }],
            table: ["traditional", "cangjie", "simplex"]
                .into_iter()
                .map(|method| TableLearning {
                    method: method.into(),
                    code: "a".into(),
                    current: "字".into(),
                    count: 3,
                })
                .collect(),
        }
    }
    fn minimal() -> Value {
        json!({"format":"guanyinma_user_data","schema_version":1,"phrases":[]})
    }
    fn parse(value: Value) -> Result<UserArchive, serde_json::Error> {
        serde_json::from_value(value)
    }

    #[test]
    fn full_backup_round_trips_every_method_without_local_metadata() {
        let source = snapshot();
        let archive = UserArchive::from_snapshot(&source).unwrap();
        let json = serde_json::to_value(&archive).unwrap();
        assert_eq!(json.as_object().unwrap().len(), 5);
        assert!(json.get("generation").is_none());
        assert!(json.get("revision").is_none());
        assert_eq!(parse(json).unwrap(), archive);
        let mut target = UserStore::memory().unwrap();
        let imported = target.import_user_data(&archive).unwrap();
        assert_eq!(imported.phrases, source.phrases);
        assert_eq!(imported.overrides, source.overrides);
        assert_eq!(imported.bigrams, source.bigrams);
        assert_eq!(imported.table, source.table);
        assert_eq!(imported.generation, 1);
        assert_eq!(imported.revision, 1);
    }

    #[test]
    fn missing_scopes_preserve_learning_and_empty_present_scopes_clear_it() {
        let mut target = UserStore::memory().unwrap();
        let original = target
            .import_user_data(&UserArchive::from_snapshot(&snapshot()).unwrap())
            .unwrap();
        let mut phrases_only = parse(minimal()).unwrap();
        let mut conflicting = phrase("q", "詞");
        conflicting.probability = -99.0;
        phrases_only.phrases = vec![conflicting, phrase("new", "新")];
        let merged = target.import_user_data(&phrases_only).unwrap();
        assert_eq!(
            merged.phrases,
            [original.phrases[0].clone(), phrase("new", "新")]
        );
        assert_eq!(merged.overrides, original.overrides);
        assert_eq!(merged.bigrams, original.bigrams);
        assert_eq!(merged.table, original.table);
        assert_eq!(merged.generation, original.generation);
        let repeated = target.import_user_data(&phrases_only).unwrap();
        assert_eq!(repeated.phrases, merged.phrases);

        let smart_only = parse(json!({
            "format":"guanyinma_user_data","schema_version":1,"phrases":[],
            "smart":{"overrides":[],"bigrams":[]},"table":null
        }))
        .unwrap();
        let cleared_smart = target.import_user_data(&smart_only).unwrap();
        assert!(cleared_smart.overrides.is_empty() && cleared_smart.bigrams.is_empty());
        assert_eq!(cleared_smart.table, original.table);
        assert!(cleared_smart.generation > repeated.generation);
        let table_only = parse(json!({
            "format":"guanyinma_user_data","schema_version":1,"phrases":[],
            "table":[]
        }))
        .unwrap();
        let cleared_table = target.import_user_data(&table_only).unwrap();
        assert!(cleared_table.table.is_empty());
        assert_eq!(cleared_table.phrases, merged.phrases);
    }

    #[test]
    fn table_replacement_preserves_smart_and_invalidates_old_learning() {
        let mut target = UserStore::memory().unwrap();
        let old = target
            .import_user_data(&UserArchive::from_snapshot(&snapshot()).unwrap())
            .unwrap();
        let archive = UserArchive {
            table: Some(vec![TableLearning {
                method: "simplex".into(),
                code: "ab".into(),
                current: "明".into(),
                count: 7,
            }]),
            ..parse(minimal()).unwrap()
        };
        let current = target.import_user_data(&archive).unwrap();
        assert_eq!(current.overrides, old.overrides);
        assert_eq!(current.bigrams, old.bigrams);
        assert_eq!(current.table, archive.table.unwrap());
        assert!(matches!(
            target
                .apply(
                    old.generation,
                    &[UserChange::SetOverride {
                        qstring: "old".into(),
                        current: Some("舊".into()),
                    }]
                )
                .unwrap(),
            SaveOutcome::Stale(_)
        ));
        assert_eq!(target.snapshot().unwrap(), current);
    }

    #[test]
    fn archive_schema_rejects_unknown_fields_and_missing_required_row_fields() {
        let full = serde_json::to_value(UserArchive::from_snapshot(&snapshot()).unwrap()).unwrap();
        for path in [
            "/generation",
            "/revision",
            "/smart/unknown",
            "/phrases/0/unknown",
            "/smart/overrides/0/unknown",
            "/smart/bigrams/0/unknown",
            "/table/0/unknown",
        ] {
            let mut value = full.clone();
            let (parent, key) = path.rsplit_once('/').unwrap();
            value
                .pointer_mut(parent)
                .unwrap()
                .as_object_mut()
                .unwrap()
                .insert(key.into(), json!(0));
            assert!(parse(value).is_err(), "unknown field {path}");
        }
        for path in [
            "/format",
            "/schema_version",
            "/phrases",
            "/smart/overrides",
            "/smart/bigrams",
            "/phrases/0/backoff",
            "/smart/overrides/0/current",
            "/smart/bigrams/0/previous",
            "/table/0/count",
        ] {
            let mut value = full.clone();
            let (parent, key) = path.rsplit_once('/').unwrap();
            value
                .pointer_mut(parent)
                .unwrap()
                .as_object_mut()
                .unwrap()
                .remove(key);
            assert!(parse(value).is_err(), "missing field {path}");
        }
        let mut unknown_format = minimal();
        unknown_format["format"] = json!("other_user_data");
        assert!(parse(unknown_format).is_err());
        let mut future = parse(minimal()).unwrap();
        future.schema_version = 2;
        assert!(future.validate().is_err());
    }

    #[test]
    fn invalid_complete_archives_never_partially_change_data_or_metadata() {
        let mut target = UserStore::memory().unwrap();
        let original = target
            .import_user_data(&UserArchive::from_snapshot(&snapshot()).unwrap())
            .unwrap();
        let full = UserArchive::from_snapshot(&original).unwrap();
        let mut invalid = Vec::new();
        let mut archive = full.clone();
        archive.phrases.push(archive.phrases[0].clone());
        invalid.push(archive);
        let mut archive = full.clone();
        let smart = archive.smart.as_mut().unwrap();
        smart.overrides.push(smart.overrides[0].clone());
        invalid.push(archive);
        let mut archive = full.clone();
        let smart = archive.smart.as_mut().unwrap();
        smart.bigrams.push(smart.bigrams[0].clone());
        invalid.push(archive);
        let mut archive = full.clone();
        let duplicate = archive.table.as_ref().unwrap()[0].clone();
        archive.table.as_mut().unwrap().push(duplicate);
        invalid.push(archive);
        let mut archive = full.clone();
        archive.smart.as_mut().unwrap().overrides = (0..=LEARNING_CAPACITY)
            .map(|index| CandidateOverride {
                qstring: index.to_string(),
                current: "字".into(),
            })
            .collect();
        invalid.push(archive);
        let mut archive = full.clone();
        archive.smart.as_mut().unwrap().bigrams = (0..=LEARNING_CAPACITY)
            .map(|index| Bigram {
                qstring: index.to_string(),
                previous: String::new(),
                current: "字".into(),
                probability: -0.5,
            })
            .collect();
        invalid.push(archive);
        for score in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
            let mut archive = full.clone();
            archive.phrases[0].probability = score;
            invalid.push(archive);
            let mut archive = full.clone();
            archive.phrases[0].backoff = score;
            invalid.push(archive);
            let mut archive = full.clone();
            archive.smart.as_mut().unwrap().bigrams[0].probability = score;
            invalid.push(archive);
        }
        let mut archive = full.clone();
        archive.table.as_mut().unwrap()[0].count = 0;
        invalid.push(archive);
        let mut archive = full.clone();
        archive.table.as_mut().unwrap()[0].method = "smart".into();
        invalid.push(archive);
        let mut archive = full;
        archive.smart.as_mut().unwrap().overrides[0]
            .current
            .push('\0');
        invalid.push(archive);
        for archive in invalid {
            assert!(target.import_user_data(&archive).is_err());
            assert_eq!(target.snapshot().unwrap(), original);
        }
    }
}
