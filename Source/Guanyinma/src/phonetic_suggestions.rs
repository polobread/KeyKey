//! Bounded, provisional phonetic suggestions for opted-in touch input.
//!
//! Copyright (c) 2026 Chui-Ping Cheng. MIT License.

use crate::bopomofo::{
    phonetic_query, phonetic_syllable, phonetic_tone, phonetic_toned_syllable, BopomofoLayout,
};
use crate::candidate_filter::CandidateFilter;
use crate::database::{DatabaseError, ModelDatabase, PhoneticQueries, Table};
use crate::user_store::UserSnapshot;
use std::collections::{HashMap, HashSet, VecDeque};

pub(crate) use crate::bopomofo::phonetic_display;

const SUGGESTION_LIMIT: usize = 8;
const MAX_SYLLABLE_KEYS: usize = 6;
const MAX_WORD_SYLLABLES: usize = 8;
const MAX_QUERIES_PER_START: usize = 256;

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct PhoneticChunk {
    pub query: String,
    pub text: String,
    pub syllable_ends: Vec<usize>,
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct PhoneticSuggestion {
    pub text: String,
    pub chunks: Vec<PhoneticChunk>,
    pub consumed: usize,
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct PhoneticSyllable {
    pub start: usize,
    pub end: usize,
    pub query: String,
    pub text: String,
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct PhoneticChoice {
    pub query: String,
    pub text: String,
}

impl PhoneticSuggestion {
    pub(crate) fn syllables(&self) -> Vec<PhoneticSyllable> {
        let mut syllables = Vec::new();
        let mut start = 0;
        for chunk in &self.chunks {
            let characters: Vec<_> = chunk.text.chars().collect();
            let count = chunk.syllable_ends.len();
            for (index, &end) in chunk.syllable_ends.iter().enumerate() {
                let first = index * characters.len() / count;
                let last = (index + 1) * characters.len() / count;
                syllables.push(PhoneticSyllable {
                    start,
                    end,
                    query: chunk.query[index * 2..index * 2 + 2].to_owned(),
                    text: characters[first..last].iter().collect(),
                });
                start = end;
            }
        }
        syllables
    }

    /// An unfinished Pinyin spelling can temporarily look like two syllables
    /// (for example, `yua` as `yu` + `a`). Wait for enough keys to resolve
    /// that tail before permanently shifting a word from a full grid.
    pub(crate) fn may_merge_pinyin_tail(
        &self,
        raw: &str,
        overflow: usize,
        locks: &[PhoneticSyllable],
    ) -> bool {
        let last_lock_end = locks.iter().map(|lock| lock.end).max().unwrap_or(0);
        let earliest_start = last_lock_end.max(raw.len().saturating_sub(MAX_SYLLABLE_KEYS - 1));
        std::iter::once(0)
            .chain(
                self.chunks
                    .iter()
                    .flat_map(|chunk| chunk.syllable_ends.iter().copied()),
            )
            .rev()
            .skip(overflow + 1)
            .take_while(|&start| start >= earliest_start)
            .any(|start| pinyin_syllable_can_extend(&raw[start..]))
    }
}

fn pinyin_syllable_can_extend(tail: &str) -> bool {
    if !tail.bytes().all(|key| key.is_ascii_lowercase()) {
        return false;
    }
    let mut spelling = String::with_capacity(MAX_SYLLABLE_KEYS);
    spelling.push_str(tail);
    for key in b'a'..=b'z' {
        spelling.push(char::from(key));
        if phonetic_syllable(BopomofoLayout::HanyuPinyin, &spelling, false).is_some() {
            return true;
        }
        spelling.pop();
    }
    if spelling.len() + 2 <= MAX_SYLLABLE_KEYS {
        spelling.push_str("ng");
        return phonetic_syllable(BopomofoLayout::HanyuPinyin, &spelling, false).is_some();
    }
    false
}

pub(crate) fn exact_toned_syllable(layout: BopomofoLayout, raw: &str) -> Option<String> {
    let (last, spelling) = raw.as_bytes().split_last()?;
    let (syllable, tone) =
        phonetic_toned_syllable(layout, std::str::from_utf8(spelling).ok()?, *last)?;
    Some(phonetic_query(syllable, tone))
}

struct SyllableMatch {
    end: usize,
    queries: Vec<String>,
}

fn syllable_matches(layout: BopomofoLayout, raw: &str, start: usize) -> Vec<SyllableMatch> {
    let mut matches = Vec::new();
    for end in start + 1..=raw.len().min(start + MAX_SYLLABLE_KEYS) {
        let spelling = &raw[start..end];
        let tone_key = raw.as_bytes().get(end).copied();
        let explicit = tone_key.is_some_and(|key| phonetic_tone(layout, key).is_some());
        // Hsu's letter tones are also initial consonants, so keep the
        // untoned boundary alongside a possible tone-consuming edge.
        let ambiguous = layout == BopomofoLayout::Hsu && tone_key != Some(b' ');
        if let Some((syllable, tone)) =
            tone_key.and_then(|key| phonetic_toned_syllable(layout, spelling, key))
        {
            matches.push(SyllableMatch {
                end: end + 1,
                queries: vec![phonetic_query(syllable, tone)],
            });
        }
        if !explicit || ambiguous {
            if let Some(syllable) = phonetic_syllable(layout, spelling, false) {
                matches.push(SyllableMatch {
                    end,
                    queries: (0..5).map(|tone| phonetic_query(syllable, tone)).collect(),
                });
            }
        }
    }
    matches
}

#[derive(Clone)]
struct Ranked {
    suggestion: PhoneticSuggestion,
    score: f64,
}

fn keep_best(paths: &mut Vec<Ranked>, path: Ranked) {
    if let Some(existing) = paths
        .iter()
        .position(|item| item.suggestion.text == path.suggestion.text)
    {
        if paths[existing].score >= path.score {
            return;
        }
        paths.remove(existing);
    }
    let insert = paths.partition_point(|item| item.score >= path.score);
    if insert < SUGGESTION_LIMIT {
        paths.insert(insert, path);
        paths.truncate(SUGGESTION_LIMIT);
    }
}

struct WordLookup<'a> {
    db: &'a ModelDatabase,
    queries: PhoneticQueries<'a>,
    filter: &'a CandidateFilter,
    custom: HashMap<&'a str, Vec<(&'a str, f64)>>,
    custom_prefixes: HashSet<&'a str>,
    words: HashMap<String, Vec<(String, f64)>>,
    longer: HashMap<String, bool>,
    word_limit: usize,
}

impl<'a> WordLookup<'a> {
    fn new(
        db: &'a ModelDatabase,
        user: &'a UserSnapshot,
        user_phrases: bool,
        filter: &'a CandidateFilter,
        word_limit: usize,
    ) -> Result<Self, DatabaseError> {
        let mut lookup = Self {
            db,
            queries: db.phonetic_queries()?,
            filter,
            custom: HashMap::new(),
            custom_prefixes: HashSet::new(),
            words: HashMap::new(),
            longer: HashMap::new(),
            word_limit,
        };
        if user_phrases {
            for row in user.phrases.iter().filter(|row| row.qstring.is_ascii()) {
                lookup
                    .custom
                    .entry(&row.qstring)
                    .or_default()
                    .push((&row.current, row.probability));
                lookup.custom_prefixes.extend(
                    (2..row.qstring.len())
                        .step_by(2)
                        .map(|end| &row.qstring[..end]),
                );
            }
        }
        Ok(lookup)
    }

    fn words(&mut self, query: &str) -> Result<&[(String, f64)], DatabaseError> {
        use std::collections::hash_map::Entry;
        let words = match self.words.entry(query.to_owned()) {
            Entry::Occupied(entry) => entry.into_mut(),
            Entry::Vacant(entry) => {
                let mut rows = self.queries.words(query)?;
                if let Some(custom) = self.custom.get(query) {
                    rows.extend(
                        custom
                            .iter()
                            .map(|(text, score)| (text.to_string(), *score)),
                    );
                }
                rows.retain(|(text, _)| !text.is_empty() && self.filter.accepts(text));
                if rows.is_empty() && query.len() == 2 {
                    // The Smart graph also accepts single characters present only in CIN.
                    let fallback_score = self
                        .db
                        .unigrams("*")?
                        .first()
                        .map_or(-99.0, |row| row.probability);
                    rows.extend(
                        self.db
                            .lookup_table(Table::Traditional, query)?
                            .into_iter()
                            .filter(|text| !text.is_empty() && self.filter.accepts(text))
                            .map(|text| (text, fallback_score)),
                    );
                }
                rows.sort_by(|left, right| right.1.total_cmp(&left.1));
                let mut seen = HashSet::new();
                rows.retain(|(text, _)| seen.insert(text.clone()));
                rows.truncate(self.word_limit);
                entry.insert(rows)
            }
        };
        Ok(words)
    }

    fn has_longer(&mut self, query: &str) -> Result<bool, DatabaseError> {
        if self.custom_prefixes.contains(query) {
            return Ok(true);
        }
        if let Some(value) = self.longer.get(query) {
            return Ok(*value);
        }
        let value = self.queries.has_longer(query)?;
        self.longer.insert(query.to_owned(), value);
        Ok(value)
    }
}

pub(crate) fn character_choices(
    layout: BopomofoLayout,
    raw: &str,
    db: &ModelDatabase,
    user: &UserSnapshot,
    user_phrases: bool,
    filter: &CandidateFilter,
) -> Result<Vec<PhoneticChoice>, DatabaseError> {
    if raw.is_empty() || !raw.is_ascii() {
        return Ok(Vec::new());
    }
    let mut lookup = WordLookup::new(db, user, user_phrases, filter, usize::MAX)?;
    let mut rows = Vec::new();
    for edge in syllable_matches(layout, raw, 0) {
        if edge.end != raw.len() {
            continue;
        }
        for query in edge.queries {
            for (text, score) in lookup.words(&query)? {
                if text.chars().count() == 1 {
                    rows.push((
                        PhoneticChoice {
                            query: query.clone(),
                            text: text.clone(),
                        },
                        *score,
                    ));
                }
            }
        }
    }
    rows.sort_by(|left, right| right.1.total_cmp(&left.1));
    let mut seen = HashSet::new();
    Ok(rows
        .into_iter()
        .filter_map(|(choice, _)| seen.insert(choice.text.clone()).then_some(choice))
        .collect())
}

/// Consider complete spellings and explicit tone constraints. The exact model
/// keys travel with each suggestion so choosing it can reuse the Smart graph.
/// Search only actual dictionary prefixes, with a bounded queue per position.
pub(crate) fn suggestions(
    layout: BopomofoLayout,
    raw: &str,
    db: &ModelDatabase,
    user: &UserSnapshot,
    user_phrases: bool,
    filter: &CandidateFilter,
) -> Result<Vec<PhoneticSuggestion>, DatabaseError> {
    suggestions_with_choices(layout, raw, db, user, user_phrases, filter, &[])
}

pub(crate) fn suggestions_with_choices(
    layout: BopomofoLayout,
    raw: &str,
    db: &ModelDatabase,
    user: &UserSnapshot,
    user_phrases: bool,
    filter: &CandidateFilter,
    choices: &[PhoneticSyllable],
) -> Result<Vec<PhoneticSuggestion>, DatabaseError> {
    if raw.is_empty() || !raw.is_ascii() {
        return Ok(Vec::new());
    }
    if choices
        .iter()
        .any(|choice| choice.start >= choice.end || choice.end > raw.len())
    {
        return Err(DatabaseError::InvalidData(
            "selected phonetic syllable is outside the pending reading".into(),
        ));
    }
    let matches: Vec<_> = (0..raw.len())
        .map(|start| syllable_matches(layout, raw, start))
        .collect();
    let mut paths = vec![Vec::new(); raw.len() + 1];
    paths[0].push(Ranked {
        suggestion: PhoneticSuggestion {
            text: String::new(),
            chunks: Vec::new(),
            consumed: 0,
        },
        score: 0.0,
    });
    let mut lookup = WordLookup::new(db, user, user_phrases, filter, SUGGESTION_LIMIT)?;

    for start in 0..raw.len() {
        if paths[start].is_empty() {
            continue;
        }
        let heads = paths[start].clone();
        let next_choice = choices
            .iter()
            .filter(|choice| choice.start >= start)
            .min_by_key(|choice| choice.start);
        if let Some(choice) = next_choice.filter(|choice| choice.start == start) {
            let chunk = PhoneticChunk {
                query: choice.query.clone(),
                text: choice.text.clone(),
                syllable_ends: vec![choice.end],
            };
            add_word(&heads, &mut paths[choice.end], &chunk, 0.0);
            continue;
        }

        // Explicitly selected characters keep both their raw range and tone.
        // Words on either side still use the usual dictionary search.
        let stop = next_choice.map_or(raw.len(), |choice| choice.start);
        let mut queue = VecDeque::from([(start, String::new(), [0; MAX_WORD_SYLLABLES])]);
        let mut seen = HashSet::new();
        'words: while let Some((position, prefix, prefix_ends)) = queue.pop_front() {
            for edge in &matches[position] {
                if edge.end > stop {
                    continue;
                }
                let syllable_count = prefix.len() / 2 + 1;
                let mut ends = prefix_ends;
                ends[syllable_count - 1] = edge.end;
                for syllable in &edge.queries {
                    let query = prefix.clone() + syllable;
                    if !seen.insert((edge.end, query.clone())) {
                        continue;
                    }
                    if seen.len() > MAX_QUERIES_PER_START {
                        break 'words;
                    }
                    for (word, probability) in lookup.words(&query)? {
                        let chunk = PhoneticChunk {
                            query: query.clone(),
                            text: word.clone(),
                            syllable_ends: ends[..syllable_count].to_vec(),
                        };
                        add_word(&heads, &mut paths[edge.end], &chunk, *probability);
                    }
                    if edge.end < stop
                        && syllable_count < MAX_WORD_SYLLABLES
                        && !matches[edge.end].is_empty()
                        && lookup.has_longer(&query)?
                    {
                        queue.push_back((edge.end, query, ends));
                    }
                }
            }
        }
    }

    // Keep an unfinished suffix editable. Picking a suggestion only consumes
    // its matched prefix, including any tone keys attached to that prefix.
    Ok(paths
        .into_iter()
        .skip(1)
        .rfind(|paths| !paths.is_empty())
        .unwrap_or_default()
        .into_iter()
        .map(|path| path.suggestion)
        .collect())
}

fn add_word(heads: &[Ranked], paths: &mut Vec<Ranked>, chunk: &PhoneticChunk, score: f64) {
    let end = *chunk
        .syllable_ends
        .last()
        .expect("a word has at least one syllable");
    for head in heads {
        let mut path = head.clone();
        path.score += score;
        path.suggestion.text.push_str(&chunk.text);
        path.suggestion.chunks.push(chunk.clone());
        path.suggestion.consumed = end;
        keep_best(paths, path);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn model_suggestions(layout: BopomofoLayout, raw: &str) -> Vec<PhoneticSuggestion> {
        suggestions(
            layout,
            raw,
            &ModelDatabase::open(crate::test_support::model_path()).unwrap(),
            &UserSnapshot::default(),
            false,
            &CandidateFilter::default(),
        )
        .unwrap()
    }

    #[test]
    fn standard_and_pinyin_find_the_same_untagged_phrase_and_preserve_a_partial_suffix() {
        for (layout, raw, partial) in [
            (BopomofoLayout::Standard, "sucl", "suclx"),
            (BopomofoLayout::HanyuPinyin, "nihao", "nihaoh"),
        ] {
            for reading in [raw, partial] {
                let candidates = model_suggestions(layout, reading);
                let best = &candidates[0];
                assert_eq!(best.text, "你好");
                assert_eq!(best.consumed, raw.len());
                assert_eq!(best.chunks.len(), 1);
                let syllables = best.syllables();
                assert_eq!(syllables.len(), 2);
                assert_eq!((syllables[0].start, syllables[0].end), (0, 2));
                assert_eq!((syllables[1].start, syllables[1].end), (2, raw.len()));
                assert_eq!(
                    (syllables[0].text.as_str(), syllables[1].text.as_str()),
                    ("你", "好")
                );
            }
        }
    }

    #[test]
    fn a_selected_character_constrains_its_syllable_and_preserves_the_suffix() {
        let db = ModelDatabase::open(crate::test_support::model_path()).unwrap();
        let user = UserSnapshot::default();
        let filter = CandidateFilter::default();
        let layout = BopomofoLayout::HanyuPinyin;
        let alternatives = character_choices(layout, "ni3", &db, &user, false, &filter).unwrap();
        let query = exact_toned_syllable(layout, "ni3").unwrap();
        assert!(alternatives.iter().all(|choice| choice.query == query));
        let chosen = alternatives
            .into_iter()
            .find(|choice| choice.text == "妳")
            .unwrap();
        let locked = PhoneticSyllable {
            start: 0,
            end: 3,
            query: chosen.query,
            text: chosen.text,
        };
        let candidates = suggestions_with_choices(
            layout,
            "ni3haoh",
            &db,
            &user,
            false,
            &filter,
            std::slice::from_ref(&locked),
        )
        .unwrap();
        assert_eq!(candidates[0].text, "妳好");
        assert_eq!(candidates[0].consumed, "ni3hao".len());
        assert!(candidates
            .iter()
            .all(|choice| choice.syllables().first() == Some(&locked)));
    }

    #[test]
    fn a_pinyin_prefix_can_merge_a_temporary_overflow_without_crossing_a_choice() {
        let layout = BopomofoLayout::HanyuPinyin;
        for (prefix, complete) in [("yua", "yuan"), ("shuan", "shuang")] {
            let raw = "ni".repeat(10) + prefix;
            let candidates = model_suggestions(layout, &raw);
            let best = &candidates[0];
            let syllables = best.syllables();
            assert_eq!(syllables.len(), 12);
            assert!(best.may_merge_pinyin_tail(&raw, 1, &[]));
            let last = syllables.last().unwrap();
            assert!(!best.may_merge_pinyin_tail(&raw, 1, std::slice::from_ref(last)));
            assert_eq!(
                model_suggestions(layout, &("ni".repeat(10) + complete))[0]
                    .syllables()
                    .len(),
                11
            );
        }
        let raw = "ni".repeat(12);
        assert!(!model_suggestions(layout, &raw)[0].may_merge_pinyin_tail(&raw, 1, &[]));
    }

    #[test]
    fn explicit_tones_constrain_their_syllables_and_do_not_consume_a_second_spelling() {
        let layout = BopomofoLayout::HanyuPinyin;
        assert!(exact_toned_syllable(layout, "ni3").is_some());
        assert!(exact_toned_syllable(layout, "nihao3").is_none());
        assert!(model_suggestions(layout, "nihao3")
            .iter()
            .any(|row| row.text == "你好"));
        assert!(model_suggestions(layout, "nihao4")
            .iter()
            .all(|row| row.text != "你好"));
        assert!(model_suggestions(layout, "bshi").is_empty());
        assert!(exact_toned_syllable(layout, "bshi3").is_none());
        assert!(exact_toned_syllable(layout, "wing3").is_none());
        assert!(exact_toned_syllable(layout, "ingv3").is_none());
        let standard = BopomofoLayout::Standard;
        assert_eq!(
            exact_toned_syllable(standard, "us3"),
            exact_toned_syllable(standard, "su3")
        );
        assert!(exact_toned_syllable(standard, "sucl3").is_none());
    }

    #[test]
    fn custom_phrases_respect_learning_and_font_filter_and_keep_the_best_reading() {
        let model = ModelDatabase::open(crate::test_support::model_path()).unwrap();
        let layout = BopomofoLayout::HanyuPinyin;
        let hao = exact_toned_syllable(layout, "hao3").unwrap();
        let low_key = exact_toned_syllable(layout, "ni ").unwrap() + &hao;
        let high_key = exact_toned_syllable(layout, "ni3").unwrap() + &hao;
        let user = UserSnapshot {
            phrases: [(low_key, -0.5), (high_key.clone(), 0.0)]
                .into_iter()
                .map(|(qstring, probability)| crate::database::Unigram {
                    qstring,
                    current: "自訂".into(),
                    probability,
                    backoff: 0.0,
                })
                .collect(),
            ..UserSnapshot::default()
        };

        let enabled = suggestions(
            layout,
            "nihao",
            &model,
            &user,
            true,
            &CandidateFilter::default(),
        )
        .unwrap();
        assert_eq!(enabled[0].text, "自訂");
        assert_eq!(enabled[0].chunks[0].query, high_key);
        assert_eq!(enabled.iter().filter(|row| row.text == "自訂").count(), 1);

        let disabled = suggestions(
            layout,
            "nihao",
            &model,
            &user,
            false,
            &CandidateFilter::default(),
        )
        .unwrap();
        let filtered = suggestions(
            layout,
            "nihao",
            &model,
            &user,
            true,
            &CandidateFilter::new(|text| !text.contains('訂')),
        )
        .unwrap();
        for candidates in [disabled, filtered] {
            assert_eq!(candidates[0].text, "你好");
            assert!(candidates.iter().all(|row| !row.text.contains('訂')));
        }
    }

    #[test]
    fn ambiguous_spelling_keeps_single_and_multi_syllable_candidates() {
        let model = ModelDatabase::open(crate::test_support::model_path()).unwrap();
        let filter = CandidateFilter::new(|text| matches!(text, "先" | "西" | "安" | "西安"));
        for (layout, raw) in [
            (BopomofoLayout::Standard, "vu0"),
            (BopomofoLayout::HanyuPinyin, "xian"),
        ] {
            let candidates = suggestions(
                layout,
                raw,
                &model,
                &UserSnapshot::default(),
                false,
                &filter,
            )
            .unwrap();
            for (word, syllables) in [("先", 1), ("西安", 2)] {
                let candidate = candidates.iter().find(|row| row.text == word).unwrap();
                assert_eq!(candidate.consumed, raw.len());
                assert_eq!(
                    candidate
                        .chunks
                        .iter()
                        .map(|chunk| chunk.query.len() / 2)
                        .sum::<usize>(),
                    syllables,
                );
            }
        }
    }
}
