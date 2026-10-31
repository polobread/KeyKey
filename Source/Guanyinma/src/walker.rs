/*
Copyright (c) 2012, Yahoo! Inc.  All rights reserved.

Redistribution and use of this software in source and binary forms,
with or without modification, are permitted provided that the following
conditions are met:

* Redistributions of source code must retain the above
  copyright notice, this list of conditions and the
  following disclaimer.

* Redistributions in binary form must reproduce the above
  copyright notice, this list of conditions and the
  following disclaimer in the documentation and/or other
  materials provided with the distribution.

* Neither the name of Yahoo! Inc. nor the names of its
  contributors may be used to endorse or promote products
  derived from this software without specific prior
  written permission of Yahoo! Inc.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

//! macOS Manjusri graph and candidate selection.
use crate::candidate_filter::CandidateFilter;
use crate::database::{Bigram, DatabaseError, ModelDatabase, Table, Unigram};
use crate::learning::LearningOptions;
use crate::user_store::{CandidateOverride, UserChange, UserSnapshot};
use serde::Serialize;
use std::collections::{BTreeMap, HashMap, HashSet, VecDeque};

const MAXIMUM_SPAN: usize = 8;
const OVERRIDE_SCORE: f64 = 100.0;
const CACHE_CAPACITY: usize = 200;
type GraphPath = Vec<(usize, String, f64)>;
type WalkMemo = HashMap<(usize, String), GraphPath>;

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct SmartSegment {
    pub start: usize,
    pub span: usize,
    pub text: String,
    /// Cumulative score from this segment through EOS.
    pub score: f64,
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct SmartCandidate {
    pub start: usize,
    pub span: usize,
    pub text: String,
    pub query: String,
}
#[derive(Clone, Debug)]
struct Node {
    start: usize,
    span: usize,
    query: String,
    unigrams: Vec<Unigram>,
    bigrams: BTreeMap<String, Vec<(String, f64)>>,
    backoffs: BTreeMap<String, f64>,
    overridden: Option<String>,
}
impl Node {
    fn end(&self) -> usize {
        self.start + self.span
    }
    fn best(&self, previous: &str, unknown: (f64, f64), use_bigrams: bool) -> (String, f64) {
        if let Some(text) = &self.overridden {
            return (text.clone(), OVERRIDE_SCORE);
        }
        // Disabling context means unigram-only scoring: neither the Bigram
        // nor its fallback's previous-word backoff contributes.
        let backoff = if use_bigrams {
            self.backoffs.get(previous).copied().unwrap_or(unknown.1)
        } else {
            0.0
        };
        let fallback = self.unigrams.first().map_or_else(
            || (String::new(), unknown.0 + backoff),
            |row| (row.current.clone(), row.probability + backoff),
        );
        if use_bigrams {
            if let Some(pair) = self.bigrams.get(previous).and_then(|rows| rows.first()) {
                if pair.1 > fallback.1 {
                    return pair.clone();
                }
            }
        }
        fallback
    }
    fn bypassable_override(&self) -> bool {
        self.overridden.is_some()
            && self.query.len() > 13
            && self.query.starts_with("_punctuation_")
    }
}
#[derive(Clone, Debug)]
struct QueryCache<T> {
    values: HashMap<String, Vec<T>>,
    order: VecDeque<String>,
}
impl<T> Default for QueryCache<T> {
    fn default() -> Self {
        Self {
            values: HashMap::new(),
            order: VecDeque::new(),
        }
    }
}
impl<T: Clone> QueryCache<T> {
    fn get(&self, key: &str) -> Option<Vec<T>> {
        self.values.get(key).cloned()
    }
    fn insert(&mut self, key: &str, value: Vec<T>) {
        if self.values.contains_key(key) {
            return;
        }
        if self.order.len() == CACHE_CAPACITY {
            if let Some(old) = self.order.pop_front() {
                self.values.remove(&old);
            }
        }
        self.order.push_back(key.into());
        self.values.insert(key.into(), value);
    }
}
/// Cloneable graph; the model is borrowed for edits. Public positions exclude
/// the BOS/EOS sentinel blocks and no learning preference is persisted.
#[derive(Clone, Debug)]
pub struct SmartGraph {
    candidate_filter: CandidateFilter,
    readings: Vec<String>,
    nodes: Vec<Node>,
    path: GraphPath,
    unknown: (f64, f64),
    initialized: bool,
    use_bigrams: bool,
    unigrams: QueryCache<Unigram>,
    bigrams: QueryCache<Bigram>,
    user: UserSnapshot,
    learning: LearningOptions,
    pending: Vec<UserChange>,
    maximum_probability: f64,
}
impl Default for SmartGraph {
    fn default() -> Self {
        Self::new()
    }
}
impl SmartGraph {
    pub fn new() -> Self {
        Self::with_candidate_filter(CandidateFilter::default())
    }

    pub fn with_candidate_filter(candidate_filter: CandidateFilter) -> Self {
        Self {
            candidate_filter,
            readings: Vec::new(),
            nodes: Vec::new(),
            path: Vec::new(),
            unknown: (0.0, 0.0),
            initialized: false,
            use_bigrams: true,
            unigrams: QueryCache::default(),
            bigrams: QueryCache::default(),
            user: UserSnapshot::default(),
            learning: LearningOptions::default(),
            pending: Vec::new(),
            maximum_probability: -0.0000001,
        }
    }
    pub fn clear(&mut self) {
        self.readings.clear();
        self.nodes.clear();
        self.path.clear();
    }
    pub fn len(&self) -> usize {
        self.readings.len()
    }
    pub fn is_empty(&self) -> bool {
        self.readings.is_empty()
    }
    pub fn readings(&self) -> &[String] {
        &self.readings
    }
    /// Change context scoring without touching the model or discarding pending
    /// readings and explicit selections. Cached context remains available for
    /// re-enabling. The enabled default preserves canonical Manjusri behavior.
    pub fn set_use_bigrams(&mut self, enabled: bool) {
        if self.use_bigrams != enabled {
            self.use_bigrams = enabled;
            self.update();
        }
    }
    /// Refresh a user-data view without replacing explicit selections in the
    /// current composition. A persistence acknowledgement alone does not rebuild
    /// existing nodes or promote the just-selected candidate a second time.
    pub fn set_user_data(
        &mut self,
        db: &ModelDatabase,
        data: &UserSnapshot,
        options: LearningOptions,
    ) -> Result<bool, DatabaseError> {
        data.validate()?;
        let same_smart_data = self.user.phrases == data.phrases
            && self.user.overrides == data.overrides
            && self.user.bigrams == data.bigrams;
        let same_smart_options = self.learning.user_phrases == options.user_phrases
            && self.learning.candidate_overrides == options.candidate_overrides
            && self.learning.bigrams == options.bigrams;
        if same_smart_data && same_smart_options {
            self.user = data.clone();
            self.learning = options;
            return Ok(false);
        }
        let before = self.clone();
        let fixed: Vec<_> = self
            .nodes
            .iter()
            .filter_map(|n| {
                n.overridden
                    .as_ref()
                    .map(|text| (n.start, n.span, n.query.clone(), text.clone()))
            })
            .collect();
        self.user = data.clone();
        self.learning = options;
        self.initialized = false;
        self.unigrams = QueryCache::default();
        self.bigrams = QueryCache::default();
        self.nodes.clear();
        self.path.clear();
        let result = if self.readings.is_empty() {
            Ok(())
        } else {
            self.build(db)
        };
        if let Err(error) = result {
            *self = before;
            return Err(error);
        }
        for (start, span, query, text) in fixed {
            if let Some(node) = self.nodes.iter_mut().find(|n| {
                n.start == start
                    && n.span == span
                    && n.query == query
                    && n.unigrams.iter().any(|row| row.current == text)
            }) {
                node.overridden = Some(text);
            }
        }
        self.update();
        Ok(true)
    }
    pub fn drain_user_changes(&mut self) -> Vec<UserChange> {
        std::mem::take(&mut self.pending)
    }
    fn cached_selection(&self, query: &str) -> Option<String> {
        self.learning
            .candidate_overrides
            .then(|| {
                self.user
                    .overrides
                    .iter()
                    .rev()
                    .find(|row| {
                        row.qstring == query
                            && !row.current.is_empty()
                            && self.candidate_filter.accepts(&row.current)
                    })
                    .map(|row| row.current.clone())
            })
            .flatten()
    }
    fn remember_override(&mut self, query: &str, text: Option<&str>) {
        let existed = self.user.overrides.iter().any(|row| row.qstring == query);
        self.user.overrides.retain(|row| row.qstring != query);
        if let Some(text) = text {
            self.user.overrides.push(CandidateOverride {
                qstring: query.into(),
                current: text.into(),
            });
            if self.user.overrides.len() > CACHE_CAPACITY {
                self.user.overrides.remove(0);
            }
        }
        if text.is_some() || existed {
            self.pending.push(UserChange::SetOverride {
                qstring: query.into(),
                current: text.map(str::to_owned),
            });
        }
    }
    fn remember_bigram(&mut self, row: Bigram) {
        self.user.bigrams.retain(|old| old.qstring != row.qstring);
        self.user.bigrams.push(row.clone());
        if self.user.bigrams.len() > CACHE_CAPACITY {
            self.user.bigrams.remove(0);
        }
        self.pending.push(UserChange::SetBigram(row));
    }
    fn initialize(&mut self, db: &ModelDatabase) -> Result<(), DatabaseError> {
        if !self.initialized {
            if self.learning.bigrams {
                self.maximum_probability = db.max_unigram_probability()?;
            }
            let mut rows = db.unigrams("*")?;
            rows.sort_by(|a, b| {
                b.probability
                    .partial_cmp(&a.probability)
                    .expect("finite model probabilities")
            });
            if let Some(row) = rows.first() {
                self.unknown = (row.probability, row.backoff);
            }
            rows.retain(|row| self.candidate_filter.accepts(&row.current));
            self.unigrams.insert("*", rows);
            self.initialized = true;
        }
        Ok(())
    }
    fn find_unigrams(
        &mut self,
        db: &ModelDatabase,
        query: &str,
    ) -> Result<Vec<Unigram>, DatabaseError> {
        self.initialize(db)?;
        if let Some(rows) = self.unigrams.get(query) {
            return Ok(rows);
        }
        let mut rows = db.unigrams(query)?;
        if self.learning.user_phrases {
            for custom in self.user.phrases.iter().filter(|row| row.qstring == query) {
                if !rows.contains(custom) {
                    rows.push(custom.clone());
                }
            }
        }
        rows.retain(|row| self.candidate_filter.accepts(&row.current));
        rows.sort_by(|a, b| {
            b.probability
                .partial_cmp(&a.probability)
                .expect("finite model probabilities")
        });
        let mut seen: HashSet<String> = rows.iter().map(|row| row.current.clone()).collect();
        for text in db.lookup_table(Table::Traditional, query)? {
            if self.candidate_filter.accepts(&text) && seen.insert(text.clone()) {
                rows.push(Unigram {
                    qstring: query.into(),
                    current: text,
                    probability: self.unknown.0,
                    backoff: self.unknown.1,
                });
            }
        }
        if rows.is_empty() {
            if let Some(body) = query
                .strip_prefix("_passthru_")
                .and_then(|q| q.strip_suffix(' '))
            {
                if !body.is_empty() && !body.as_bytes().iter().skip(1).any(|b| *b == b' ') {
                    rows.push(Unigram {
                        qstring: query.into(),
                        current: if body == "space" {
                            " ".into()
                        } else {
                            body.into()
                        },
                        probability: self.unknown.0,
                        backoff: self.unknown.1,
                    });
                }
            }
        }
        // Native Manjusri synthesizes explicit literal passthrough after
        // filtering dictionary rows. Preserve caller text, including ASCII and
        // spaces, independently of candidate font/encoding eligibility.
        self.unigrams.insert(query, rows.clone());
        Ok(rows)
    }
    fn find_bigrams(
        &mut self,
        db: &ModelDatabase,
        query: &str,
    ) -> Result<Vec<Bigram>, DatabaseError> {
        if self.learning.bigrams {
            if let Some(row) = self
                .user
                .bigrams
                .iter()
                .rev()
                .find(|row| row.qstring == query && self.candidate_filter.accepts(&row.current))
            {
                return Ok(vec![row.clone()]);
            }
        }
        if let Some(rows) = self.bigrams.get(query) {
            return Ok(rows);
        }
        let mut rows = db.bigrams(query)?;
        rows.retain(|row| self.candidate_filter.accepts(&row.current));
        rows.sort_by(|a, b| {
            b.probability
                .partial_cmp(&a.probability)
                .expect("finite model probabilities")
        });
        self.bigrams.insert(query, rows.clone());
        Ok(rows)
    }
    pub(crate) fn has_multiple_candidates(
        &mut self,
        db: &ModelDatabase,
        query: &str,
    ) -> Result<bool, DatabaseError> {
        Ok(self.find_unigrams(db, query)?.len() > 1)
    }

    pub fn is_in_dictionary(
        &mut self,
        db: &ModelDatabase,
        query: &str,
    ) -> Result<bool, DatabaseError> {
        Ok(!self.find_unigrams(db, query)?.is_empty())
    }

    pub fn insert(
        &mut self,
        db: &ModelDatabase,
        index: usize,
        query: &str,
    ) -> Result<bool, DatabaseError> {
        if index > self.len() || !self.is_in_dictionary(db, query)? {
            return Ok(false);
        }
        let before = self.clone();
        let at = index + 1;
        let to = (at + 1).min(self.readings.len() + 2);
        self.nodes.retain_mut(|node| {
            let (x1, x2) = (node.start, node.end());
            let intersect =
                (at..=to).contains(&x1) || (at..=to).contains(&x2) || (at >= x1 && to <= x2);
            if intersect && node.overridden.is_none() {
                return false;
            }
            if node.start >= at {
                node.start += 1;
            }
            true
        });
        self.readings.insert(index, query.into());
        if let Err(error) = self.build(db) {
            *self = before;
            return Err(error);
        }
        Ok(true)
    }
    pub fn remove(&mut self, db: &ModelDatabase, index: usize) -> Result<bool, DatabaseError> {
        if index >= self.len() {
            return Ok(false);
        }
        let before = self.clone();
        let at = index + 1;
        let from = at - 1;
        let to = (at + 1).min(self.len() + 2);
        self.nodes.retain_mut(|node| {
            let (x1, x2) = (node.start, node.end());
            let intersect = (from..=to).contains(&x1) || (from..=to).contains(&x2);
            if intersect && !node.bypassable_override() {
                return false;
            }
            if node.start == at {
                return false;
            }
            if node.start > at {
                node.start -= 1;
            }
            true
        });
        self.readings.remove(index);
        if let Err(error) = self.build(db) {
            *self = before;
            return Err(error);
        }
        Ok(true)
    }
    fn sort_nodes(&mut self) {
        self.nodes
            .sort_by(|a, b| (a.start, a.span, &a.query).cmp(&(b.start, b.span, &b.query)));
    }
    fn build(&mut self, db: &ModelDatabase) -> Result<(), DatabaseError> {
        let mut source = vec!["!".to_owned()];
        source.extend(self.readings.iter().cloned());
        source.push("$".into());
        for start in 0..source.len() {
            for span in 1..=MAXIMUM_SPAN.min(source.len() - start) {
                let mut queries = vec![source[start..start + span].concat()];
                if let Some(alias) = reading_alias(&source[start]) {
                    queries.push(format!(
                        "{alias}{}",
                        source[start + 1..start + span].concat()
                    ));
                }
                for query in queries {
                    let unigrams = self.find_unigrams(db, &query)?;
                    if span > 1 && unigrams.is_empty() {
                        continue;
                    }
                    if self
                        .nodes
                        .iter()
                        .any(|n| n.start == start && n.span == span && n.query == query)
                    {
                        continue;
                    }
                    // NodeSet insert rejects later builds with the same
                    // location/query: the first predecessor supplies scoring.
                    let previous_query = self
                        .nodes
                        .iter()
                        .find(|n| n.end() == start)
                        .map(|n| n.query.clone());
                    let mut node = Node {
                        start,
                        span,
                        query: query.clone(),
                        unigrams,
                        bigrams: BTreeMap::new(),
                        backoffs: BTreeMap::new(),
                        overridden: None,
                    };
                    if let Some(previous) = previous_query {
                        for row in self.find_bigrams(db, &format!("{previous} {query}"))? {
                            node.bigrams
                                .entry(row.previous)
                                .or_default()
                                .push((row.current, row.probability));
                        }
                        for row in self.find_unigrams(db, &previous)? {
                            node.backoffs.insert(row.current, row.backoff);
                        }
                    }
                    let cached = self.cached_selection(&query);
                    if let Some(text) = &cached {
                        if let Some(index) =
                            node.unigrams.iter().position(|row| row.current == *text)
                        {
                            let chosen = node.unigrams.remove(index);
                            node.unigrams.insert(0, chosen);
                            if let Some(first) =
                                node.bigrams.get("").and_then(|rows| rows.first()).cloned()
                            {
                                if first.0 != *text {
                                    node.bigrams
                                        .get_mut("")
                                        .unwrap()
                                        .insert(0, (text.clone(), first.1));
                                }
                            }
                        }
                    }
                    self.nodes.push(node);
                    self.sort_nodes();
                    if cached.is_some() {
                        break;
                    }
                }
            }
        }
        self.update();
        Ok(())
    }
    fn update(&mut self) {
        fn walk(graph: &SmartGraph, at: usize, previous: &str, memo: &mut WalkMemo) -> GraphPath {
            let key = (at, previous.to_owned());
            if let Some(path) = memo.get(&key) {
                return path.clone();
            }
            let following: Vec<usize> = graph
                .nodes
                .iter()
                .enumerate()
                .filter(|(_, n)| n.start == at)
                .map(|(i, _)| i)
                .collect();
            let targets = if let Some(overridden) = following
                .iter()
                .find(|i| graph.nodes[**i].overridden.is_some())
            {
                vec![*overridden]
            } else {
                following
            };
            let mut best: Option<GraphPath> = None;
            for index in targets {
                let node = &graph.nodes[index];
                let (text, score) = node.best(previous, graph.unknown, graph.use_bigrams);
                let mut tail = walk(graph, node.end(), &text, memo);
                let total = score + tail.first().map_or(0.0, |entry| entry.2);
                tail.insert(0, (index, text, total));
                if best.as_ref().is_none_or(|path| total > path[0].2) {
                    best = Some(tail);
                }
            }
            let path = best.unwrap_or_default();
            memo.insert(key, path.clone());
            path
        }
        self.path = walk(self, 0, "", &mut HashMap::new());
    }
    pub fn segments(&self) -> Vec<SmartSegment> {
        self.path
            .iter()
            .filter_map(|(index, text, score)| {
                let node = &self.nodes[*index];
                (node.start > 0 && node.start <= self.len()).then(|| SmartSegment {
                    start: node.start - 1,
                    span: node.span,
                    text: text.clone(),
                    score: *score,
                })
            })
            .collect()
    }
    pub fn text(&self) -> String {
        self.segments().into_iter().map(|s| s.text).collect()
    }
    /// Cover the reading at index, or collect nodes ending at index when
    /// cursor_at_end is enabled. Deduplicate text after longest-span ordering.
    pub fn candidates_at(&self, index: usize, cursor_at_end: bool) -> Vec<SmartCandidate> {
        if index > self.len() || (!cursor_at_end && index == self.len()) {
            return Vec::new();
        }
        let at = index + 1;
        let mut nodes: Vec<&Node> = self
            .nodes
            .iter()
            .filter(|node| {
                node.start > 0
                    && node.end() <= self.len() + 1
                    && if cursor_at_end {
                        node.end() == at
                    } else {
                        node.start <= at && at < node.end()
                    }
            })
            .collect();
        nodes.sort_by_key(|node| std::cmp::Reverse(node.span));
        let mut seen = HashSet::new();
        let mut result = Vec::new();
        for node in nodes {
            for row in &node.unigrams {
                if seen.insert(row.current.clone()) {
                    result.push(SmartCandidate {
                        start: node.start - 1,
                        span: node.span,
                        text: row.current.clone(),
                        query: node.query.clone(),
                    });
                }
            }
        }
        result
    }
    pub fn select(&mut self, candidate: &SmartCandidate) -> bool {
        let Some(start) = candidate.start.checked_add(1) else {
            return false;
        };
        let Some(index) = self.nodes.iter().position(|node| {
            node.start == start
                && node.span == candidate.span
                && node.query == candidate.query
                && node
                    .unigrams
                    .iter()
                    .any(|row| row.current == candidate.text)
        }) else {
            return false;
        };
        let first = self.nodes[index]
            .unigrams
            .first()
            .map(|row| row.current.clone());
        for node in &mut self.nodes {
            if node.start <= start && start < node.end() {
                node.overridden = None;
            }
        }
        self.nodes[index].overridden = Some(candidate.text.clone());
        self.update();
        let eligible = !is_special_query(&candidate.query);
        if eligible && self.learning.candidate_overrides && !contains_bopomofo(&candidate.text) {
            if first.as_deref() == Some(candidate.text.as_str()) {
                self.remember_override(&candidate.query, None);
            } else {
                self.remember_override(&candidate.query, Some(&candidate.text));
            }
        }
        if eligible && self.learning.bigrams && self.use_bigrams {
            let previous = self.path.iter().find_map(|(index, text, _)| {
                let node = &self.nodes[*index];
                (node.start > 0 && node.end() == start).then(|| (node.query.clone(), text.clone()))
            });
            if let Some((query, text)) = previous {
                self.remember_bigram(Bigram {
                    qstring: format!("{query} {}", candidate.query),
                    previous: text,
                    current: candidate.text.clone(),
                    probability: self.maximum_probability,
                });
            }
        }
        true
    }
    /// Pop the first whole winning segment and freeze its winning successor
    /// before removing the left context, preserving the desktop handoff.
    pub fn shift(&mut self) -> Option<SmartSegment> {
        let position = self
            .path
            .iter()
            .position(|(i, _, _)| self.nodes[*i].start == 1)?;
        let (target_index, _, score) = self.path[position].clone();
        let target = self.nodes[target_index].clone();
        let text = target.best("", self.unknown, self.use_bigrams).0;
        if let Some((next_index, _, _)) = self.path.get(position + 1) {
            let next = &mut self.nodes[*next_index];
            let chosen = next.best(&text, self.unknown, self.use_bigrams).0;
            next.overridden = Some(chosen);
        }
        let end = target.end();
        self.nodes.retain_mut(|node| {
            if node.start >= target.start && node.start < end {
                return false;
            }
            if node.start >= end {
                node.start -= target.span;
            }
            true
        });
        self.readings.drain(..target.span);
        self.sort_nodes();
        self.update();
        Some(SmartSegment {
            start: 0,
            span: target.span,
            text,
            score,
        })
    }
}
fn is_special_query(query: &str) -> bool {
    ["_punctuation_", "_passthru_", "_ctrl_"]
        .iter()
        .any(|prefix| query.starts_with(prefix))
}
fn contains_bopomofo(text: &str) -> bool {
    text.chars()
        .any(|ch| ('\u{3105}'..='\u{3129}').contains(&ch) || matches!(ch, 'ˊ' | 'ˇ' | 'ˋ' | '˙'))
}
// MandarinAlias.h is applied in source order: zB's later qA mapping wins.
fn reading_alias(reading: &str) -> Option<&'static str> {
    match reading {
        "F0" | "5_" | "u?" => Some("F0#"),
        "L_" | "=@" => Some("L_#"),
        "p?" | "<C" | "{J" => Some("p?#"),
        ":b" => Some(":b#"),
        "qA" | "zB" => Some("qA#"),
        "Cb" | "rq" => Some("Cb#"),
        "mJ" | "\\y" => Some("mJ#"),
        "4W" | "cf" => Some("4W#"),
        "cp" | "lq" => Some("cp#"),
        "N0" | "]O" => Some("N0#"),
        "OP" | "|U" => Some("OP#"),
        "k@" | "Zo" => Some("k@#"),
        "p1" | "PA" => Some("p1#"),
        "K_" | "ZR" => Some("K_#"),
        "gg" | "2P" => Some("gg#"),
        "Eb" | "L`" => Some("Eb#"),
        "R3" | "|?" => Some("R3#"),
        "r4" | "2T" => Some("r4#"),
        "tI" | "{@" => Some("tI#"),
        "RO" | "an" => Some("RO#"),
        "V>" | "6N" => Some("V>#"),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bopomofo::{BopomofoLayout, BopomofoReading};
    use rusqlite::{params, Connection};
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};

    struct TestModel {
        directory: PathBuf,
        path: PathBuf,
    }
    impl TestModel {
        fn new(
            unigrams: &[(&str, &str, f64, f64)],
            bigrams: &[(&str, &str, &str, f64)],
            external: &[(&str, &str)],
        ) -> Self {
            static NEXT: AtomicU64 = AtomicU64::new(0);
            let directory = loop {
                let id = NEXT.fetch_add(1, Ordering::Relaxed);
                let candidate = std::env::temp_dir()
                    .join(format!("guanyinma-walker-{}-{id}", std::process::id()));
                match std::fs::create_dir(&candidate) {
                    Ok(()) => break candidate,
                    Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                    Err(error) => panic!("{error}"),
                }
            };
            let path = directory.join("model.db");
            let db = Connection::open(&path).unwrap();
            db.execute_batch(
                r#"
                CREATE TABLE unigrams(qstring,current,probability,backoff);
                CREATE TABLE bigrams(qstring,previous,current,probability);
                CREATE TABLE "Mandarin-bpmf-cin"(key,value);
                CREATE TABLE "Generic-cj-cin"(key,value);
                CREATE TABLE "Generic-simplex-cin"(key,value);
                INSERT INTO unigrams VALUES ('*','',-99,0),('!','',0,0),('$','',0,0);
            "#,
            )
            .unwrap();
            for &(q, text, probability, backoff) in unigrams {
                db.execute(
                    "INSERT INTO unigrams VALUES(?1,?2,?3,?4)",
                    params![q, text, probability, backoff],
                )
                .unwrap();
            }
            for &(q, previous, current, probability) in bigrams {
                db.execute(
                    "INSERT INTO bigrams VALUES(?1,?2,?3,?4)",
                    params![q, previous, current, probability],
                )
                .unwrap();
            }
            for &(q, text) in external {
                db.execute(
                    "INSERT INTO \"Mandarin-bpmf-cin\" VALUES(?1,?2)",
                    params![q, text],
                )
                .unwrap();
            }
            Self { directory, path }
        }
        fn open(&self) -> ModelDatabase {
            ModelDatabase::open(&self.path).unwrap()
        }
    }
    impl Drop for TestModel {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.directory);
        }
    }
    fn qstring(keys: &str) -> String {
        let mut reading = BopomofoReading::new(BopomofoLayout::Standard);
        for key in keys.chars() {
            assert!(reading.combine(key));
        }
        reading.query_key()
    }
    fn shared_model() -> ModelDatabase {
        ModelDatabase::open(crate::test_support::model_path()).unwrap()
    }
    fn insert(graph: &mut SmartGraph, db: &ModelDatabase, q: &str) {
        assert!(graph.insert(db, graph.len(), q).unwrap());
    }

    #[test]
    fn stable_probability_order_appends_external_fallback_without_truncation() {
        let fixture = TestModel::new(
            &[
                ("a", "低", -3., 0.),
                ("a", "同分先", -1., 0.),
                ("a", "同分後", -1., 0.),
            ],
            &[],
            &[
                ("a", "同分後"),
                ("a", "外部先"),
                ("a", "外部後"),
                ("a", "外部先"),
            ],
        );
        let db = fixture.open();
        let mut graph = SmartGraph::new();
        insert(&mut graph, &db, "a");
        let candidates = graph.candidates_at(0, false);
        assert_eq!(
            candidates
                .iter()
                .map(|c| c.text.as_str())
                .collect::<Vec<_>>(),
            ["同分先", "同分後", "低", "外部先", "外部後"]
        );
        assert_eq!(graph.text(), "同分先");
        assert_eq!(graph.unknown, (-99., 0.));
        assert_eq!(graph.segments()[0].score, -1.);
    }

    #[test]
    fn frontend_filter_applies_to_model_custom_bigram_and_cached_graph_rows() {
        use std::sync::atomic::AtomicUsize;
        use std::sync::Arc;
        let fixture = TestModel::new(
            &[
                ("a", "甲", -1., 0.),
                ("b", "乙", -2., 0.),
                ("b", "缺字", -0.5, 0.),
            ],
            &[("a b", "甲", "缺字", 20.), ("a b", "甲", "異", 10.)],
            &[("b", "外部"), ("b", "缺字")],
        );
        let db = fixture.open();
        let calls = Arc::new(AtomicUsize::new(0));
        let counted = calls.clone();
        let filter = CandidateFilter::new(move |text| {
            counted.fetch_add(1, Ordering::Relaxed);
            !text.contains("缺字")
        });
        let mut graph = SmartGraph::with_candidate_filter(filter);
        let data = UserSnapshot {
            phrases: vec![Unigram {
                qstring: "b".into(),
                current: "自訂缺字".into(),
                probability: 30.,
                backoff: 0.,
            }],
            overrides: vec![CandidateOverride {
                qstring: "b".into(),
                current: "缺字".into(),
            }],
            bigrams: vec![Bigram {
                qstring: "a b".into(),
                previous: "甲".into(),
                current: "缺字".into(),
                probability: 40.,
            }],
            ..UserSnapshot::default()
        };
        graph
            .set_user_data(
                &db,
                &data,
                LearningOptions {
                    user_phrases: true,
                    candidate_overrides: true,
                    bigrams: true,
                    ..LearningOptions::default()
                },
            )
            .unwrap();
        insert(&mut graph, &db, "a");
        insert(&mut graph, &db, "b");
        assert_eq!(graph.text(), "甲異");
        assert_eq!(
            graph
                .candidates_at(1, false)
                .iter()
                .map(|row| row.text.as_str())
                .collect::<Vec<_>>(),
            ["乙", "外部"]
        );
        assert!(graph
            .unigrams
            .values
            .values()
            .flatten()
            .all(|row| !row.current.contains("缺字")));
        assert!(graph
            .bigrams
            .values
            .values()
            .flatten()
            .all(|row| !row.current.contains("缺字")));
        assert_eq!(graph.unknown, (-99., 0.));
        let first_calls = calls.load(Ordering::Relaxed);
        graph.clear();
        insert(&mut graph, &db, "a");
        insert(&mut graph, &db, "b");
        assert_eq!(graph.text(), "甲異");
        assert_eq!(calls.load(Ordering::Relaxed), first_calls + 2);
        // The extra calls reject persisted override/Bigram entries; neither
        // query cache reintroduces rejected model/custom rows after clear().
        assert!(graph.drain_user_changes().is_empty());
        let mut unfiltered = SmartGraph::new();
        insert(&mut unfiltered, &db, "b");
        assert_eq!(unfiltered.text(), "缺字");
    }

    #[test]
    fn frontend_filter_can_reject_every_visible_smart_row_without_losing_sentinels() {
        let fixture = TestModel::new(&[("a", "甲", -1., 0.)], &[], &[]);
        let db = fixture.open();
        let mut graph = SmartGraph::with_candidate_filter(CandidateFilter::new(|_| false));
        assert!(!graph.insert(&db, 0, "a").unwrap());
        assert!(graph.is_empty());
        assert!(graph
            .find_unigrams(&db, "!")
            .unwrap()
            .iter()
            .any(|row| row.current.is_empty()));
        assert!(graph
            .find_unigrams(&db, "$")
            .unwrap()
            .iter()
            .any(|row| row.current.is_empty()));
        assert_eq!(graph.unknown, (-99., 0.));
    }

    #[test]
    fn node_uses_strict_bigram_comparison_and_previous_backoff() {
        let fixture = TestModel::new(
            &[
                ("a", "甲", -1., -5.),
                ("b", "乙", -2., 0.),
                ("b", "異", -3., 0.),
            ],
            &[("a b", "甲", "異", -7.)],
            &[],
        );
        let db = fixture.open();
        let mut graph = SmartGraph::new();
        insert(&mut graph, &db, "a");
        insert(&mut graph, &db, "b");
        // -2 + -5 ties the bigram: the unigram remains preferred.
        assert_eq!(graph.text(), "甲乙");
        let node = graph
            .nodes
            .iter()
            .find(|n| n.start == 2 && n.query == "b")
            .unwrap();
        assert_eq!(node.best("甲", graph.unknown, true), ("乙".into(), -7.));
        assert_eq!(
            node.best("缺少前文", graph.unknown, true),
            ("乙".into(), -2.)
        );
        let mut stronger = node.clone();
        stronger
            .bigrams
            .insert("甲".into(), vec![("異".into(), -6.99)]);
        assert_eq!(
            stronger.best("甲", graph.unknown, true),
            ("異".into(), -6.99)
        );
        stronger.unigrams.clear();
        stronger.bigrams.clear();
        assert_eq!(stronger.best("甲", graph.unknown, true), ("".into(), -104.));
    }

    #[test]
    fn global_segmentation_and_manual_override_keep_the_canonical_node_choices() {
        let fixture = TestModel::new(
            &[
                ("a", "甲", -4., 0.),
                ("a", "假", -5., 0.),
                ("b", "乙", -4., 0.),
                ("ab", "甲乙", -2., 0.),
            ],
            &[],
            &[],
        );
        let db = fixture.open();
        let mut graph = SmartGraph::new();
        insert(&mut graph, &db, "a");
        insert(&mut graph, &db, "b");
        assert_eq!(graph.text(), "甲乙");
        assert_eq!(
            graph.segments().iter().map(|s| s.span).collect::<Vec<_>>(),
            [2]
        );
        let candidates = graph.candidates_at(0, false);
        assert_eq!(
            candidates
                .iter()
                .map(|c| c.text.as_str())
                .collect::<Vec<_>>(),
            ["甲乙", "甲", "假"]
        );
        assert_eq!(candidates[0].span, 2);
        assert_eq!(graph.candidates_at(2, true)[0], candidates[0]);
        assert!(graph.candidates_at(2, false).is_empty());
        let chosen = candidates.iter().find(|c| c.text == "假").unwrap();
        assert!(graph.select(chosen));
        assert_eq!(graph.text(), "假乙");
        assert_eq!(
            graph.segments().iter().map(|s| s.span).collect::<Vec<_>>(),
            [1, 1]
        );
        assert!(graph.select(&candidates[0]));
        assert_eq!(graph.text(), "甲乙");
        assert!(!graph.select(&SmartCandidate {
            text: "偽造".into(),
            ..candidates[0].clone()
        }));
        assert_eq!(graph.text(), "甲乙");
    }

    #[test]
    fn segmentation_ties_keep_shorter_first_node_and_build_uses_first_predecessor() {
        let fixture = TestModel::new(
            &[
                ("a", "甲", -1., 0.),
                ("b", "乙", -1., 0.),
                ("ab", "甲乙", -2., 0.),
                ("c", "丙", -1., 0.),
                ("c", "另", -2., 0.),
            ],
            &[("b c", "乙", "另", 10.)],
            &[],
        );
        let db = fixture.open();
        let mut graph = SmartGraph::new();
        insert(&mut graph, &db, "a");
        insert(&mut graph, &db, "b");
        assert_eq!(
            graph.segments().iter().map(|s| s.span).collect::<Vec<_>>(),
            [1, 1]
        );
        insert(&mut graph, &db, "c");
        // At c the preceding ab node sorts before b. Only its scoring data
        // survives NodeSet insertion; using b's unrelated Bigram would differ.
        assert_eq!(graph.text(), "甲乙丙");
    }

    #[test]
    fn aliases_apply_only_to_first_block_and_keep_distinct_query_nodes() {
        assert_eq!(reading_alias("zB"), Some("qA#"));
        let fixture = TestModel::new(
            &[
                ("F0", "原", -3., 0.),
                ("F0#", "別", -2., 0.),
                ("F0#F0", "別原", -1., 0.),
                ("F0F0#", "錯誤後別", 10., 0.),
            ],
            &[],
            &[],
        );
        let db = fixture.open();
        let mut graph = SmartGraph::new();
        insert(&mut graph, &db, "F0");
        insert(&mut graph, &db, "F0");
        assert_eq!(graph.text(), "別原");
        assert!(graph.nodes.iter().any(|n| n.query == "F0#F0"));
        assert!(!graph.nodes.iter().any(|n| n.query == "F0F0#"));
        let candidates = graph.candidates_at(0, false);
        assert_eq!(
            candidates
                .iter()
                .map(|c| c.text.as_str())
                .collect::<Vec<_>>(),
            ["別原", "原", "別"]
        );
    }

    #[test]
    fn insert_delete_and_shift_preserve_overrides_and_context_handoff() {
        let fixture = TestModel::new(
            &[
                ("a", "甲", -1., 0.),
                ("b", "乙", -1., 0.),
                ("b", "異", -2., 0.),
                ("c", "丙", -1., 0.),
            ],
            &[("a b", "甲", "異", 0.)],
            &[],
        );
        let db = fixture.open();
        let mut graph = SmartGraph::new();
        for q in ["a", "b", "c"] {
            insert(&mut graph, &db, q);
        }
        assert_eq!(graph.text(), "甲異丙");
        let first = graph.shift().unwrap();
        assert_eq!((first.text.as_str(), first.span), ("甲", 1));
        assert_eq!(graph.text(), "異丙");
        insert(&mut graph, &db, "c");
        assert_eq!(graph.text(), "異丙丙");
        assert!(graph.remove(&db, 2).unwrap());
        // Removing a nearby reading invalidates its neighboring overridden
        // node, so the unconditioned unigram is restored.
        assert_eq!(graph.text(), "乙丙");
        assert!(!graph.insert(&db, 10, "a").unwrap());
        assert!(!graph.insert(&db, 0, "not-present").unwrap());
        assert!(!graph.remove(&db, 20).unwrap());
        graph.clear();
        assert!(graph.is_empty());
        assert!(graph.shift().is_none());
        assert!(graph.segments().is_empty());
    }

    #[test]
    fn passthru_text_uses_unknown_scores_and_does_not_form_multi_block_phrases() {
        let fixture = TestModel::new(&[], &[], &[]);
        let db = fixture.open();
        let mut graph = SmartGraph::new();
        for q in ["_passthru_a ", "_passthru_space ", "_passthru_字 "] {
            assert!(graph.is_in_dictionary(&db, q).unwrap());
            insert(&mut graph, &db, q);
        }
        assert_eq!(graph.text(), "a 字");
        assert_eq!(
            graph.segments().iter().map(|s| s.span).collect::<Vec<_>>(),
            [1, 1, 1]
        );
        assert!(!graph
            .is_in_dictionary(&db, "_passthru_a _passthru_b ")
            .unwrap());
        assert!(!graph.is_in_dictionary(&db, "_passthru_a").unwrap());
    }

    #[test]
    fn shared_model_has_complete_canonical_candidates_and_phrase_spans() {
        let db = shared_model();
        let mut graph = SmartGraph::new();
        insert(&mut graph, &db, &qstring("g4"));
        assert_eq!(graph.text(), "是");
        let values = graph.candidates_at(0, false);
        assert_eq!(values.len(), 368);
        assert_eq!(
            values
                .iter()
                .take(20)
                .map(|c| c.text.as_str())
                .collect::<Vec<_>>(),
            [
                "是", "事", "市", "式", "視", "世", "士", "試", "勢", "室", "識", "示", "釋", "氏",
                "飾", "適", "逝", "誓", "仕", "侍"
            ]
        );
        graph.clear();
        insert(&mut graph, &db, &qstring("su3"));
        insert(&mut graph, &db, &qstring("cl3"));
        assert_eq!(graph.text(), "你好");
        let values = graph.candidates_at(0, false);
        assert_eq!(values.len(), 87);
        assert_eq!(
            values
                .iter()
                .take(7)
                .map(|c| c.text.as_str())
                .collect::<Vec<_>>(),
            ["你好", "妳好", "你", "妳", "擬", "旎", "薿"]
        );
        assert_eq!((values[0].start, values[0].span), (0, 2));
        let chosen = values.iter().find(|c| c.text == "妳好").unwrap();
        assert!(graph.select(chosen));
        assert_eq!(graph.text(), "妳好");
    }
    #[test]
    fn maximum_phrase_span_is_eight_and_positions_reject_forged_candidates() {
        let fixture = TestModel::new(
            &[
                ("a", "甲", -1., 0.),
                ("aaaaaaaa", "八字", -0.5, 0.),
                ("aaaaaaaaa", "九字", 10., 0.),
            ],
            &[],
            &[],
        );
        let db = fixture.open();
        let mut graph = SmartGraph::new();
        for _ in 0..9 {
            insert(&mut graph, &db, "a");
        }
        assert_eq!(graph.len(), 9);
        assert!(!graph.nodes.iter().any(|node| node.span > 8));
        assert!(graph.segments().iter().any(|segment| segment.span == 8));
        let candidates = graph.candidates_at(0, false);
        assert_eq!(candidates[0].text, "八字");
        assert!(!candidates.iter().any(|candidate| candidate.text == "九字"));
        assert!(!graph.select(&SmartCandidate {
            start: usize::MAX,
            ..candidates[0].clone()
        }));
        assert_eq!(graph.len(), 9);
    }

    #[test]
    fn failed_insert_and_delete_restore_readings_nodes_overrides_and_text() {
        let fixture = TestModel::new(
            &[
                ("a", "甲", -1., 0.),
                ("a", "假", -2., 0.),
                ("b", "乙", -1., 0.),
                ("c", "丙", -1., 0.),
            ],
            &[],
            &[],
        );
        let writer = Connection::open(&fixture.path).unwrap();
        writer
            .execute("INSERT INTO bigrams VALUES('a b','甲','乙','invalid')", [])
            .unwrap();
        let db = fixture.open();
        let mut graph = SmartGraph::new();
        insert(&mut graph, &db, "a");
        let choice = graph
            .candidates_at(0, false)
            .into_iter()
            .find(|c| c.text == "假")
            .unwrap();
        assert!(graph.select(&choice));
        let before = graph.candidates_at(0, false);
        assert!(matches!(
            graph.insert(&db, 1, "b"),
            Err(DatabaseError::InvalidData(_))
        ));
        assert_eq!(graph.readings(), ["a"]);
        assert_eq!(graph.text(), "假");
        assert_eq!(graph.candidates_at(0, false), before);

        writer.execute("DELETE FROM bigrams", []).unwrap();
        // New graph avoids retaining cached rows from a different model state.
        // Ordinary sessions never mutate their borrowed readonly source.
        let mut graph = SmartGraph::new();
        for q in ["a", "b", "c"] {
            insert(&mut graph, &db, q);
        }
        writer
            .execute("INSERT INTO bigrams VALUES('a c','甲','丙','invalid')", [])
            .unwrap();
        let before_text = graph.text();
        let before = graph.candidates_at(0, false);
        assert!(matches!(
            graph.remove(&db, 1),
            Err(DatabaseError::InvalidData(_))
        ));
        assert_eq!(graph.readings(), ["a", "b", "c"]);
        assert_eq!(graph.text(), before_text);
        assert_eq!(graph.candidates_at(0, false), before);
    }
    #[test]
    fn context_switch_rewalks_without_queries_and_retains_manual_overrides() {
        let fixture = TestModel::new(
            &[
                ("a", "甲", -1., -5.),
                ("b", "乙", -2., 0.),
                ("b", "異", -3., 0.),
            ],
            &[("a b", "甲", "異", -1.)],
            &[],
        );
        let db = fixture.open();
        let mut graph = SmartGraph::new();
        insert(&mut graph, &db, "a");
        insert(&mut graph, &db, "b");
        assert_eq!(graph.text(), "甲異");
        let readings = graph.readings().to_vec();
        let candidates = graph.candidates_at(1, false);
        let cache_counts = (graph.unigrams.values.len(), graph.bigrams.values.len());
        // Pure runtime changes need no connection and keep the cached model.
        drop(db);
        graph.set_use_bigrams(false);
        assert_eq!(graph.text(), "甲乙");
        assert_eq!(graph.readings(), readings);
        assert_eq!(graph.candidates_at(1, false), candidates);
        assert_eq!(
            (graph.unigrams.values.len(), graph.bigrams.values.len()),
            cache_counts
        );
        let without_context = graph.segments();
        graph.set_use_bigrams(false);
        assert_eq!(graph.segments(), without_context);
        graph.set_use_bigrams(true);
        assert_eq!(graph.text(), "甲異");
        graph.set_use_bigrams(false);
        let alternate = candidates
            .iter()
            .find(|candidate| candidate.text == "異")
            .unwrap();
        assert!(graph.select(alternate));
        assert_eq!(graph.text(), "甲異");
        graph.set_use_bigrams(true);
        graph.set_use_bigrams(false);
        assert_eq!(graph.text(), "甲異");
        assert_eq!(graph.readings(), readings);
        graph.clear();
        assert!(!graph.use_bigrams);
        assert!(graph.is_empty());
    }

    #[test]
    fn context_switch_removes_previous_backoff_from_unigram_only_segmentation() {
        let fixture = TestModel::new(
            &[
                ("a", "甲", -1., -10.),
                ("b", "乙", -1., 0.),
                ("ab", "詞", -4., 0.),
            ],
            &[],
            &[],
        );
        let db = fixture.open();
        let mut graph = SmartGraph::new();
        insert(&mut graph, &db, "a");
        insert(&mut graph, &db, "b");
        // There are no Bigrams: the previous-word backoff alone changes the
        // winning segmentation, so merely bypassing Bigram lookup is wrong.
        assert_eq!(graph.text(), "詞");
        let candidates = graph.candidates_at(0, false);
        graph.set_use_bigrams(false);
        assert_eq!(graph.text(), "甲乙");
        assert_eq!(
            graph.segments().iter().map(|s| s.span).collect::<Vec<_>>(),
            [1, 1]
        );
        assert_eq!(graph.candidates_at(0, false), candidates);
        graph.set_use_bigrams(true);
        assert_eq!(graph.text(), "詞");
        assert_eq!(graph.segments()[0].span, 2);
    }

    #[test]
    fn shared_model_phrase_completion_and_context_switch_preserve_readings() {
        let db = shared_model();
        let mut graph = SmartGraph::new();
        for keys in ["fu/3", "ru84", "ul4", "fm4", "s83"] {
            insert(&mut graph, &db, &qstring(keys));
        }
        // The following syllable completes 哪裡; the prefix alone need not choose 哪.
        insert(&mut graph, &db, &qstring("xu3"));
        assert_eq!(graph.text(), "請假要去哪裡");
        let readings = graph.readings().to_vec();
        let candidates = graph.candidates_at(4, false);
        graph.set_use_bigrams(false);
        assert_eq!(graph.text(), "請假要去哪裡");
        assert_eq!(graph.readings(), readings);
        assert_eq!(graph.candidates_at(4, false), candidates);
        graph.set_use_bigrams(true);
        assert_eq!(graph.text(), "請假要去哪裡");
    }
    fn learned_options() -> LearningOptions {
        LearningOptions {
            candidate_overrides: true,
            bigrams: true,
            ..LearningOptions::default()
        }
    }
    #[test]
    fn cached_preference_keeps_original_scores_and_suppresses_the_alias_node() {
        let fixture = TestModel::new(
            &[
                ("F0", "原", -1., 0.),
                ("F0", "選", -3., 0.),
                ("F0#", "別", -0.1, 0.),
            ],
            &[("! F0", "", "原", -0.5)],
            &[],
        );
        let db = fixture.open();
        let data = UserSnapshot {
            overrides: vec![CandidateOverride {
                qstring: "F0".into(),
                current: "選".into(),
            }],
            ..UserSnapshot::default()
        };
        let mut graph = SmartGraph::new();
        graph.set_user_data(&db, &data, learned_options()).unwrap();
        insert(&mut graph, &db, "F0");
        assert_eq!(graph.text(), "選");
        assert_eq!(graph.candidates_at(0, false)[0].text, "選");
        let node = graph.nodes.iter().find(|n| n.query == "F0").unwrap();
        assert_eq!(node.unigrams[0].probability, -3.);
        assert_eq!(node.bigrams[""][0], ("選".into(), -0.5));
        assert!(node.overridden.is_none());
        assert!(!graph.nodes.iter().any(|n| n.query == "F0#"));
        assert!(graph.drain_user_changes().is_empty());
    }
    #[test]
    fn explicit_learning_reuses_and_removes_the_current_first_candidate_not_the_formal_first() {
        let fixture = TestModel::new(&[("a", "甲", -1., 0.), ("a", "假", -3., 0.)], &[], &[]);
        let db = fixture.open();
        let mut graph = SmartGraph::new();
        graph
            .set_user_data(&db, &UserSnapshot::default(), learned_options())
            .unwrap();
        insert(&mut graph, &db, "a");
        let chosen = graph.candidates_at(0, false)[1].clone();
        assert!(graph.select(&chosen));
        assert_eq!(
            graph.drain_user_changes(),
            [UserChange::SetOverride {
                qstring: "a".into(),
                current: Some("假".into())
            }]
        );
        // Acknowledging our own write must not alter the existing node order.
        let mut acknowledged = graph.user.clone();
        acknowledged.revision += 1;
        graph
            .set_user_data(&db, &acknowledged, learned_options())
            .unwrap();
        assert_eq!(graph.candidates_at(0, false)[0].text, "甲");
        graph.clear();
        insert(&mut graph, &db, "a");
        assert_eq!(graph.text(), "假");
        let first = graph.candidates_at(0, false)[0].clone();
        assert_eq!(first.text, "假");
        assert!(graph.select(&first));
        assert_eq!(
            graph.drain_user_changes(),
            [UserChange::SetOverride {
                qstring: "a".into(),
                current: None
            }]
        );
        graph.clear();
        insert(&mut graph, &db, "a");
        assert_eq!(graph.text(), "甲");

        // Selecting the original formal first while a learned value is first
        // stores that text; it is not treated as removing the preference.
        let data = UserSnapshot {
            overrides: vec![CandidateOverride {
                qstring: "a".into(),
                current: "假".into(),
            }],
            ..UserSnapshot::default()
        };
        graph.clear();
        graph.set_user_data(&db, &data, learned_options()).unwrap();
        insert(&mut graph, &db, "a");
        let original = graph
            .candidates_at(0, false)
            .into_iter()
            .find(|c| c.text == "甲")
            .unwrap();
        assert!(graph.select(&original));
        assert_eq!(
            graph.drain_user_changes(),
            [UserChange::SetOverride {
                qstring: "a".into(),
                current: Some("甲".into())
            }]
        );
    }
    #[test]
    fn explicit_adjacent_selection_replaces_model_bigrams_and_default_walks_never_learn() {
        let fixture = TestModel::new(
            &[
                ("a", "甲", -1., 0.),
                ("b", "乙", -2., 0.),
                ("b", "異", -3., 0.),
            ],
            &[("a b", "甲", "乙", -0.1), ("a b", "別", "乙", -0.2)],
            &[],
        );
        let db = fixture.open();
        let mut graph = SmartGraph::new();
        graph
            .set_user_data(
                &db,
                &UserSnapshot::default(),
                LearningOptions {
                    bigrams: true,
                    ..LearningOptions::default()
                },
            )
            .unwrap();
        insert(&mut graph, &db, "a");
        insert(&mut graph, &db, "b");
        assert_eq!(graph.text(), "甲乙");
        assert!(graph.drain_user_changes().is_empty());
        let chosen = graph
            .candidates_at(1, false)
            .into_iter()
            .find(|c| c.text == "異")
            .unwrap();
        assert!(graph.select(&chosen));
        let expected = Bigram {
            qstring: "a b".into(),
            previous: "甲".into(),
            current: "異".into(),
            probability: -0.0000001,
        };
        assert_eq!(
            graph.drain_user_changes(),
            [UserChange::SetBigram(expected.clone())]
        );
        assert_eq!(graph.find_bigrams(&db, "a b").unwrap(), [expected]);
        graph.clear();
        insert(&mut graph, &db, "a");
        insert(&mut graph, &db, "b");
        assert_eq!(graph.text(), "甲異");
        assert!(graph.drain_user_changes().is_empty());
        graph.shift();
        assert!(graph.drain_user_changes().is_empty());
    }
    #[test]
    fn disabled_context_and_special_targets_do_not_record_adjacent_learning() {
        let fixture = TestModel::new(
            &[
                ("a", "甲", -1., 0.),
                ("b", "乙", -2., 0.),
                ("b", "異", -3., 0.),
                ("_punctuation_,", "，", -1., 0.),
                ("_punctuation_,", "、", -2., 0.),
                ("_ctrl_x", "甲", -1., 0.),
                ("_ctrl_x", "乙", -2., 0.),
                ("_passthru_x ", "x", -1., 0.),
                ("_passthru_x ", "X", -2., 0.),
            ],
            &[],
            &[],
        );
        let db = fixture.open();
        for target in ["b", "_punctuation_,", "_ctrl_x", "_passthru_x "] {
            let mut graph = SmartGraph::new();
            graph
                .set_user_data(&db, &UserSnapshot::default(), learned_options())
                .unwrap();
            insert(&mut graph, &db, "a");
            insert(&mut graph, &db, target);
            if target == "b" {
                graph.set_use_bigrams(false);
            }
            let chosen = graph.candidates_at(1, false)[1].clone();
            assert!(graph.select(&chosen));
            let changes = graph.drain_user_changes();
            if target == "b" {
                assert!(changes
                    .iter()
                    .all(|event| !matches!(event, UserChange::SetBigram(_))));
            } else {
                assert!(changes.is_empty(), "{target}");
            }
        }
        let mut graph = SmartGraph::new();
        graph
            .set_user_data(&db, &UserSnapshot::default(), LearningOptions::default())
            .unwrap();
        insert(&mut graph, &db, "b");
        let choice = graph.candidates_at(0, false)[1].clone();
        assert!(graph.select(&choice));
        assert!(graph.drain_user_changes().is_empty());
    }
    #[test]
    fn custom_words_merge_before_external_fallback_and_reload_preserves_explicit_choices() {
        let fixture = TestModel::new(
            &[("a", "甲", -1., 0.), ("b", "乙", -1., 0.)],
            &[],
            &[("a", "外")],
        );
        let db = fixture.open();
        let data = UserSnapshot {
            phrases: vec![
                Unigram {
                    qstring: "a".into(),
                    current: "甲".into(),
                    probability: -1.,
                    backoff: 0.,
                },
                Unigram {
                    qstring: "a".into(),
                    current: "新".into(),
                    probability: -0.5,
                    backoff: 0.,
                },
                Unigram {
                    qstring: "ab".into(),
                    current: "新詞".into(),
                    probability: -0.1,
                    backoff: 0.,
                },
            ],
            ..UserSnapshot::default()
        };
        let mut graph = SmartGraph::new();
        graph
            .set_user_data(&db, &data, LearningOptions::default())
            .unwrap();
        insert(&mut graph, &db, "a");
        assert_eq!(
            graph
                .candidates_at(0, false)
                .iter()
                .map(|c| c.text.as_str())
                .collect::<Vec<_>>(),
            ["新", "甲", "外"]
        );
        let chosen = graph.candidates_at(0, false)[1].clone();
        assert!(graph.select(&chosen));
        let mut changed = data.clone();
        changed.revision += 1;
        changed.phrases.push(Unigram {
            qstring: "a".into(),
            current: "另".into(),
            probability: -0.2,
            backoff: 0.,
        });
        graph
            .set_user_data(&db, &changed, LearningOptions::default())
            .unwrap();
        assert_eq!(graph.text(), "甲");
        assert_eq!(graph.readings(), ["a"]);
        assert_eq!(graph.candidates_at(0, false)[0].text, "另");
        graph.clear();
        insert(&mut graph, &db, "a");
        insert(&mut graph, &db, "b");
        assert_eq!(graph.text(), "新詞");
        graph.clear();
        graph
            .set_user_data(
                &db,
                &data,
                LearningOptions {
                    user_phrases: false,
                    ..LearningOptions::default()
                },
            )
            .unwrap();
        insert(&mut graph, &db, "a");
        insert(&mut graph, &db, "b");
        assert_eq!(graph.text(), "甲乙");
        assert!(graph.drain_user_changes().is_empty());
    }
    #[test]
    fn bopomofo_symbol_candidates_never_create_a_preference() {
        let fixture = TestModel::new(&[("a", "甲", -1., 0.), ("a", "ㄅ", -2., 0.)], &[], &[]);
        let db = fixture.open();
        let mut graph = SmartGraph::new();
        graph
            .set_user_data(&db, &UserSnapshot::default(), learned_options())
            .unwrap();
        insert(&mut graph, &db, "a");
        let chosen = graph.candidates_at(0, false)[1].clone();
        assert!(graph.select(&chosen));
        assert_eq!(graph.text(), "ㄅ");
        assert!(graph.drain_user_changes().is_empty());
    }
    #[test]
    fn unrelated_table_updates_do_not_rebuild_the_smart_candidate_order() {
        let fixture = TestModel::new(&[("a", "甲", -1., 0.), ("a", "假", -3., 0.)], &[], &[]);
        let db = fixture.open();
        let options = learned_options();
        let mut graph = SmartGraph::new();
        graph
            .set_user_data(&db, &UserSnapshot::default(), options)
            .unwrap();
        insert(&mut graph, &db, "a");
        let choice = graph.candidates_at(0, false)[1].clone();
        assert!(graph.select(&choice));
        graph.drain_user_changes();
        let mut acknowledged = graph.user.clone();
        acknowledged.revision += 1;
        acknowledged.table.push(crate::user_store::TableLearning {
            method: "cangjie".into(),
            code: "a".into(),
            current: "曰".into(),
            count: 1,
        });
        assert!(!graph
            .set_user_data(
                &db,
                &acknowledged,
                LearningOptions {
                    table_learning: true,
                    ..options
                }
            )
            .unwrap());
        assert_eq!(graph.candidates_at(0, false)[0].text, "甲");
        assert_eq!(graph.text(), "假");
        assert!(graph.drain_user_changes().is_empty());
    }

    #[test]
    fn user_refresh_failure_restores_manual_selection_pending_learning_and_caches() {
        let fixture = TestModel::new(&[("a", "甲", -1., 0.), ("a", "假", -3., 0.)], &[], &[]);
        let broken = TestModel::new(&[("a", "甲", f64::INFINITY, 0.)], &[], &[]);
        let db = fixture.open();
        let bad_db = broken.open();
        let mut graph = SmartGraph::default();
        graph
            .set_user_data(&db, &UserSnapshot::default(), learned_options())
            .unwrap();
        insert(&mut graph, &db, "a");
        let choice = graph.candidates_at(0, false)[1].clone();
        assert!(graph.select(&choice));
        let before = graph.clone();
        let changed = UserSnapshot {
            phrases: vec![Unigram {
                qstring: "b".into(),
                current: "乙".into(),
                probability: -1.,
                backoff: 0.,
            }],
            ..graph.user.clone()
        };
        assert!(matches!(
            graph.set_user_data(&bad_db, &changed, learned_options()),
            Err(DatabaseError::InvalidData(_))
        ));
        assert_eq!(graph.text(), before.text());
        assert_eq!(graph.readings(), before.readings());
        assert_eq!(graph.segments(), before.segments());
        assert_eq!(
            graph.candidates_at(0, false),
            before.candidates_at(0, false)
        );
        assert_eq!(graph.user, before.user);
        assert_eq!(graph.pending, before.pending);
        assert_eq!(graph.unigrams.order, before.unigrams.order);
        assert_eq!(graph.bigrams.order, before.bigrams.order);
        assert!(graph
            .set_user_data(&db, &changed, learned_options())
            .unwrap());
        assert_eq!(graph.text(), "假");
    }

    #[test]
    fn explicit_learning_evicts_only_the_oldest_full_cache_entries() {
        let fixture = TestModel::new(
            &[
                ("a", "甲", -1., 0.),
                ("b", "乙", -1., 0.),
                ("b", "異", -3., 0.),
            ],
            &[],
            &[],
        );
        let db = fixture.open();
        let mut graph = SmartGraph::default();
        let data = UserSnapshot {
            overrides: (0..CACHE_CAPACITY)
                .map(|i| CandidateOverride {
                    qstring: format!("old{i}"),
                    current: "舊".into(),
                })
                .collect(),
            bigrams: (0..CACHE_CAPACITY)
                .map(|i| Bigram {
                    qstring: format!("old{i} next"),
                    previous: "前".into(),
                    current: "後".into(),
                    probability: -1.,
                })
                .collect(),
            ..UserSnapshot::default()
        };
        graph.set_user_data(&db, &data, learned_options()).unwrap();
        insert(&mut graph, &db, "a");
        insert(&mut graph, &db, "b");
        let choice = graph
            .candidates_at(1, false)
            .into_iter()
            .find(|c| c.text == "異")
            .unwrap();
        assert!(graph.select(&choice));
        assert_eq!(graph.text(), "甲異");
        assert_eq!(graph.user.overrides.len(), CACHE_CAPACITY);
        assert_eq!(graph.user.bigrams.len(), CACHE_CAPACITY);
        assert_eq!(graph.user.overrides.first().unwrap().qstring, "old1");
        assert_eq!(graph.user.overrides.last().unwrap().qstring, "b");
        assert_eq!(graph.user.bigrams.first().unwrap().qstring, "old1 next");
        assert_eq!(graph.user.bigrams.last().unwrap().qstring, "a b");
        assert_eq!(graph.drain_user_changes().len(), 2);
    }

    #[test]
    fn deleting_before_and_at_selected_punctuation_preserves_only_remaining_text() {
        let fixture = TestModel::new(
            &[
                ("a", "甲", -1., 0.),
                ("b", "乙", -1., 0.),
                ("_punctuation_,", "，", -1., 0.),
                ("_punctuation_,", "、", -2., 0.),
            ],
            &[],
            &[],
        );
        let db = fixture.open();
        let mut graph = SmartGraph::default();
        for q in ["a", "_punctuation_,", "b"] {
            insert(&mut graph, &db, q);
        }
        let chosen = graph
            .candidates_at(1, false)
            .into_iter()
            .find(|c| c.text == "、")
            .unwrap();
        assert!(graph.select(&chosen));
        assert_eq!(graph.text(), "甲、乙");
        assert!(graph.remove(&db, 0).unwrap());
        assert_eq!(graph.text(), "、乙");
        assert!(graph.remove(&db, 0).unwrap());
        assert_eq!(graph.text(), "乙");
        assert_eq!(graph.readings(), ["b"]);
        assert!(graph.drain_user_changes().is_empty());
    }
}
