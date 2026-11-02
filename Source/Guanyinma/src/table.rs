//! Read-only Cangjie/Simplex candidate lookup and bounded prefix selection.
//!
//! Selection follows Source/Shared/CangjiePrefix.h, which is original MIT
//! material. Unicode-derived identity/filter data retains Unicode License V3.
use crate::candidate_filter::CandidateFilter;
use crate::database::{DatabaseError, ModelDatabase, Table};
use serde::{Deserialize, Serialize};
use std::borrow::Cow;
use std::collections::{HashMap, HashSet};
use std::sync::LazyLock;

mod shared {
    include!(concat!(env!("OUT_DIR"), "/cangjie_data.rs"));
}

/// The number of supplemental prefix candidates, excluding exact-code results.
pub const PREFIX_LIMIT: usize = 36;

/// Existing punctuation override tables; a frontend may select them for either table method.
#[repr(u8)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PunctuationStyle {
    #[default]
    Original = 0,
    Mixed = 1,
    Half = 2,
}

/// Native-independent wildcard symbols. An explicit pair of null symbols
/// disables wildcard lookup, while omitted options keep the method defaults.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct TableWildcards {
    pub one: Option<char>,
    pub many: Option<char>,
}
impl TableWildcards {
    pub const fn cangjie() -> Self {
        Self {
            one: Some('?'),
            many: Some('*'),
        }
    }
    pub fn contains(self, character: char) -> bool {
        self.one == Some(character) || self.many == Some(character)
    }
    pub fn pattern(self, code: &str) -> String {
        let mut pattern = String::new();
        for character in code.chars() {
            if self.one == Some(character) {
                pattern.push('?');
            } else if self.many == Some(character) {
                pattern.push('*');
            } else {
                match character {
                    '[' => pattern.push_str("[[]"),
                    '?' => pattern.push_str("[?]"),
                    '*' => pattern.push_str("[*]"),
                    _ => pattern.push(character),
                }
            }
        }
        pattern
    }
}

/// The engine is responsible for requiring realtime before enabling prefix.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct TableQueryOptions {
    pub prefix: bool,
    pub punctuation: PunctuationStyle,
    pub wildcards: Option<TableWildcards>,
}

/// Complete candidates and the subset produced by the exact typed code.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TableCandidates {
    pub values: Vec<String>,
    pub exact: Vec<String>,
    pub prefix: bool,
    pub wildcard: bool,
}

/// A lowercase Cangjie root code, including a complete five-root code.
pub fn is_cangjie_code(code: &str) -> bool {
    (1..=5).contains(&code.len()) && code.bytes().all(|byte| byte.is_ascii_lowercase())
}

/// A root code that can still have longer Cangjie completions.
pub fn is_cangjie_prefix_code(code: &str) -> bool {
    (1..=4).contains(&code.len()) && code.bytes().all(|byte| byte.is_ascii_lowercase())
}

/// Canonical identity for one CJK compatibility scalar; display text is retained.
pub fn canonical_identity(text: &str) -> Cow<'_, str> {
    let mut scalars = text.chars();
    let Some(first) = scalars.next() else {
        return Cow::Borrowed(text);
    };
    if scalars.next().is_some() {
        return Cow::Borrowed(text);
    }
    if let Ok(index) = shared::CANONICAL_CJK.binary_search_by_key(&(first as u32), |pair| pair.0) {
        // The build script validates all generated mapping targets.
        if let Some(mapped) = char::from_u32(shared::CANONICAL_CJK[index].1) {
            return Cow::Owned(mapped.to_string());
        }
    }
    Cow::Borrowed(text)
}

/// Existing common-character rank. Unranked or multiscalar words sort last.
pub fn rank(text: &str) -> usize {
    static RANKS: LazyLock<HashMap<char, usize>> = LazyLock::new(|| {
        shared::RANKED_CHARACTERS
            .chars()
            .enumerate()
            .map(|(offset, character)| (character, offset + 1))
            .collect()
    });
    let identity = canonical_identity(text);
    let mut scalars = identity.chars();
    match (scalars.next(), scalars.next()) {
        (Some(character), None) => RANKS.get(&character).copied().unwrap_or(usize::MAX),
        _ => usize::MAX,
    }
}

/// Shared Unicode punctuation/symbol/space exclusion, applied only to extras.
pub fn excluded_prefix_candidate(text: &str) -> bool {
    let Some(first) = text.chars().next() else {
        return true;
    };
    let scalar = first as u32;
    let end = shared::EXCLUDED_RANGES.partition_point(|range| range.0 <= scalar);
    end != 0 && scalar <= shared::EXCLUDED_RANGES[end - 1].1
}

fn unique(values: Vec<String>) -> Vec<String> {
    let mut seen = HashSet::new();
    values
        .into_iter()
        .filter(|text| seen.insert(canonical_identity(text).into_owned()))
        .collect()
}

struct PrefixSelection {
    seen: HashSet<String>,
    values: Vec<String>,
    filter: CandidateFilter,
}

impl PrefixSelection {
    #[cfg(test)]
    fn new(exact: &[String]) -> Self {
        Self::with_filter(exact, CandidateFilter::default())
    }

    fn with_filter(exact: &[String], filter: CandidateFilter) -> Self {
        Self {
            seen: exact
                .iter()
                .map(|text| canonical_identity(text).into_owned())
                .collect(),
            values: Vec::new(),
            filter,
        }
    }

    fn consider(&mut self, text: String) {
        if excluded_prefix_candidate(&text) {
            return;
        }
        let identity = canonical_identity(&text).into_owned();
        if self.seen.contains(&identity) {
            return;
        }
        let candidate_rank = rank(&text);
        if self.values.len() == PREFIX_LIMIT && candidate_rank >= rank(self.values.last().unwrap())
        {
            return;
        }
        if !self.filter.accepts(&text) {
            return;
        }
        self.seen.insert(identity);
        let offset = self
            .values
            .partition_point(|value| rank(value) <= candidate_rank);
        self.values.insert(offset, text);
        if self.values.len() > PREFIX_LIMIT {
            self.values.pop();
        }
    }
}

/// Query using the canonical macOS SQLite source row order.
pub fn candidates(
    database: &ModelDatabase,
    table: Table,
    code: &str,
    options: TableQueryOptions,
) -> Result<TableCandidates, DatabaseError> {
    candidates_with_filter(database, table, code, options, &CandidateFilter::default())
}

/// Apply frontend eligibility before exact ordering and bounded prefix selection.
/// Raw ModelDatabase queries continue to return every original source row.
pub fn candidates_with_filter(
    database: &ModelDatabase,
    table: Table,
    code: &str,
    options: TableQueryOptions,
    filter: &CandidateFilter,
) -> Result<TableCandidates, DatabaseError> {
    let wildcards = options.wildcards.unwrap_or_else(|| {
        if table == Table::Cangjie {
            TableWildcards::cangjie()
        } else {
            TableWildcards::default()
        }
    });
    let wildcard = code.len() > 1 && code.chars().any(|character| wildcards.contains(character));
    let prefix = table == Table::Cangjie && options.prefix && !wildcard && is_cangjie_code(code);
    let mut values = if wildcard {
        // Configured symbols become wildcards; unconfigured GLOB metacharacters
        // remain literal, just as the original Generic wildcard expression.
        let pattern = wildcards.pattern(code);
        database.lookup_table_pattern(table, &pattern)?
    } else {
        let punctuation = if matches!(table, Table::Cangjie | Table::Simplex) {
            match options.punctuation {
                PunctuationStyle::Original => Vec::new(),
                PunctuationStyle::Mixed => database.lookup_cangjie_punctuation(code, false)?,
                PunctuationStyle::Half => database.lookup_cangjie_punctuation(code, true)?,
            }
        } else {
            Vec::new()
        };
        if punctuation.is_empty() {
            database.lookup_table(table, code)?
        } else {
            punctuation
        }
    };
    values.retain(|text| filter.accepts(text));
    if prefix {
        values = unique(values);
    }
    let exact = values.clone();
    if prefix && is_cangjie_prefix_code(code) {
        let mut selection = PrefixSelection::with_filter(&exact, filter.clone());
        database.for_each_cangjie_prefix_value(code, |text| selection.consider(text))?;
        values.extend(selection.values);
    }
    Ok(TableCandidates {
        values,
        exact,
        prefix,
        wildcard,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn model() -> ModelDatabase {
        ModelDatabase::open(crate::test_support::model_path()).unwrap()
    }

    #[test]
    fn shared_unicode_identity_filtering_and_stable_rank() {
        assert_eq!(canonical_identity("豈"), "豈");
        assert_eq!(canonical_identity("丽"), "丽");
        assert_eq!(canonical_identity("豈字"), "豈字");
        assert_eq!(rank("的"), 1);
        assert!(rank("日") < rank("曰"));
        assert!(excluded_prefix_candidate("，"));
        assert!(excluded_prefix_candidate("😀"));
        assert!(excluded_prefix_candidate(" "));
        assert!(!excluded_prefix_candidate("𪂇"));
        let mut selection = PrefixSelection::new(&["豈".to_owned()]);
        selection.consider("豈".to_owned());
        selection.consider("，".to_owned());
        selection.consider("未排名甲".to_owned());
        selection.consider("未排名乙".to_owned());
        assert_eq!(selection.values, ["未排名甲", "未排名乙"]);
    }

    #[test]
    fn prefix_retains_only_the_best_thirty_six_without_displacing_equal_ranked_rows() {
        let mut selection = PrefixSelection::new(&[]);
        for index in 0..100 {
            selection.consider(format!("未排名{index}"));
        }
        assert_eq!(selection.values.len(), PREFIX_LIMIT);
        assert_eq!(selection.values.first().unwrap(), "未排名0");
        assert_eq!(selection.values.last().unwrap(), "未排名35");
        selection.consider("的".to_owned());
        assert_eq!(selection.values.first().unwrap(), "的");
        assert_eq!(selection.values.last().unwrap(), "未排名34");
    }

    #[test]
    fn frontend_filter_excludes_before_the_prefix_limit_and_keeps_order() {
        let mut selection = PrefixSelection::with_filter(
            &["完整碼".into()],
            CandidateFilter::new(|text| !text.starts_with("缺字")),
        );
        for index in 0..40 {
            selection.consider(format!("缺字{index}"));
        }
        for index in 0..40 {
            selection.consider(format!("可見{index}"));
        }
        assert_eq!(selection.values.len(), PREFIX_LIMIT);
        assert_eq!(selection.values.first().unwrap(), "可見0");
        assert_eq!(selection.values.last().unwrap(), "可見35");
        selection.consider("的".into());
        assert_eq!(selection.values.first().unwrap(), "的");
        assert_eq!(selection.values.last().unwrap(), "可見34");
    }

    #[test]
    fn real_prefix_candidates_keep_exact_results_first_and_refresh_at_five_roots() {
        let database = model();
        let options = TableQueryOptions {
            prefix: true,
            ..Default::default()
        };
        let expected_counts = [38, 40, 11, 2, 1];
        let expected_qiao = [None, Some(4), Some(5), Some(0), Some(0)];
        for (index, code) in ["h", "hk", "hkr", "hkrb", "hkrbr"].iter().enumerate() {
            let result = candidates(&database, Table::Cangjie, code, options).unwrap();
            assert_eq!(result.values.len(), expected_counts[index], "{code}");
            assert_eq!(
                result.values.iter().position(|text| text == "喬"),
                expected_qiao[index],
                "{code}"
            );
            assert_eq!(&result.values[..result.exact.len()], result.exact);
            assert!(result.values.len() - result.exact.len() <= PREFIX_LIMIT);
        }
        let exact = candidates(&database, Table::Cangjie, "hk", Default::default()).unwrap();
        assert_eq!(exact.values, exact.exact);
        assert!(!exact.values.iter().any(|text| text == "喬"));
    }

    #[test]
    fn wildcards_are_not_prefix_limited_and_preserve_source_order() {
        let database = model();
        let options = TableQueryOptions {
            prefix: true,
            ..Default::default()
        };
        let source = candidates(&database, Table::Cangjie, "hk?", options).unwrap();
        assert!(source.wildcard && !source.prefix);
        assert!(source.values.len() > PREFIX_LIMIT);
        assert!(!source.values.iter().any(|text| text == "喬"));
        assert_eq!(
            source.values,
            database
                .lookup_table_pattern(Table::Cangjie, "hk?")
                .unwrap()
        );
        assert!(candidates(&database, Table::Cangjie, "a[?]", options)
            .unwrap()
            .values
            .is_empty());
        assert!(!database
            .lookup_table_pattern(Table::Cangjie, "__property_*")
            .unwrap()
            .is_empty());
    }

    #[test]
    fn known_punctuation_overrides_apply_to_both_tables_and_fall_back_for_roots() {
        let database = model();
        for style in [PunctuationStyle::Mixed, PunctuationStyle::Half] {
            let options = TableQueryOptions {
                punctuation: style,
                ..Default::default()
            };
            let result = candidates(&database, Table::Cangjie, "a", options).unwrap();
            assert_eq!(result.values, ["日", "曰"]);
            let simplex = candidates(&database, Table::Simplex, ",", options).unwrap();
            assert_eq!(
                simplex.values,
                database
                    .lookup_cangjie_punctuation(",", style == PunctuationStyle::Half)
                    .unwrap()
            );
        }
        let mixed = candidates(
            &database,
            Table::Cangjie,
            ",",
            TableQueryOptions {
                punctuation: PunctuationStyle::Mixed,
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(mixed.values, ["，"]);
        let half = candidates(
            &database,
            Table::Cangjie,
            ",",
            TableQueryOptions {
                punctuation: PunctuationStyle::Half,
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(half.values, [","]);
    }
}
