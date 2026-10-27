// Copyright (c) 2004-2010 The OpenVanilla Project (http://openvanilla.org)
// All rights reserved.
// Copyright (c) 2026 Chui-Ping Cheng
//
// Associated phrase merging derives from OVAFAssociatedPhrase.cpp.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is furnished to do
// so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

//! Associated phrase data contracts, independent of candidate windows and keys.

use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};

/// One collection's comma-separated suffixes, in database source-row order.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AssociatedRow {
    pub source: String,
    pub data: String,
}

/// A collection's unchanged source identifier, display label and sort weight.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AssociatedCollection {
    pub source: String,
    pub display: String,
    pub sort_order: i64,
}

/// Tie-breaking behavior for collection lists; independent of platform names.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CollectionOrder {
    /// Sort weight, then display label, then original source-row identity.
    #[default]
    Display,
    /// Sort weight, then source identifier, then original source-row identity.
    Source,
}

/// Merge suffix rows in the caller's selected collection order.
///
/// The last source row for each collection replaces earlier rows, as in the
/// original macOS implementation. Candidate order inside that row is unchanged;
/// duplicate strings keep their first occurrence across and within collections.
/// Comma splitting keeps leading/interior empty fields and drops the terminal
/// empty field, matching OVStringHelper::Split. No whitespace, glyph filtering,
/// prefix restriction or page limit is imposed here. The caller can explicitly
/// omit empty suffixes for consumers that already used that behavior.
pub fn merge_associated_rows(
    rows: &[AssociatedRow],
    collections: &[String],
    omit_empty_suffixes: bool,
) -> Vec<String> {
    let by_source: HashMap<_, _> = rows
        .iter()
        .map(|row| (row.source.as_str(), row.data.as_str()))
        .collect();
    let mut seen = HashSet::new();
    let mut candidates = Vec::new();
    for source in collections {
        if let Some(data) = by_source.get(source.as_str()) {
            for suffix in data.split_terminator(',') {
                if omit_empty_suffixes && suffix.is_empty() {
                    continue;
                }
                if seen.insert(suffix) {
                    candidates.push(suffix.to_owned());
                }
            }
        }
    }
    candidates
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(source: &str, data: &str) -> AssociatedRow {
        AssociatedRow {
            source: source.into(),
            data: data.into(),
        }
    }

    fn selected(names: &[&str]) -> Vec<String> {
        names.iter().map(|name| (*name).into()).collect()
    }

    #[test]
    fn selected_order_and_first_occurrence_determine_candidates() {
        let rows = [row("a", "共同,甲,甲"), row("b", "乙,共同,丙")];
        assert_eq!(
            merge_associated_rows(&rows, &selected(&["b", "missing", "a", "b"]), false),
            ["乙", "共同", "丙", "甲"]
        );
        assert_eq!(
            merge_associated_rows(&rows, &selected(&["a", "b"]), false),
            ["共同", "甲", "乙", "丙"]
        );
        assert!(merge_associated_rows(&rows, &[], false).is_empty());
    }

    #[test]
    fn last_row_replaces_the_whole_collection_including_an_empty_row() {
        let rows = [
            row("a", "舊,共同"),
            row("b", "保留"),
            row("a", "新,共同"),
            row("b", ""),
        ];
        assert_eq!(
            merge_associated_rows(&rows, &selected(&["a", "b"]), false),
            ["新", "共同"]
        );
    }

    #[test]
    fn comma_edges_and_text_are_preserved_without_normalization() {
        let rows = [row("a", ",空,, 白,白,𠮷,尾,"), row("b", ",追加")];
        assert_eq!(
            merge_associated_rows(&rows, &selected(&["a", "b"]), false),
            ["", "空", " 白", "白", "𠮷", "尾", "追加"]
        );
        assert!(merge_associated_rows(&[row("a", "")], &selected(&["a"]), false).is_empty());
        assert_eq!(
            merge_associated_rows(&[row("a", ",")], &selected(&["a"]), false),
            [""]
        );
        assert_eq!(
            merge_associated_rows(&rows, &selected(&["a", "b"]), true),
            ["空", " 白", "白", "𠮷", "尾", "追加"]
        );
    }
}
