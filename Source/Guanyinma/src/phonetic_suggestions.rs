//! Bounded, provisional phonetic suggestions for opted-in touch input.
//!
//! Copyright (c) 2026 Chui-Ping Cheng. MIT License.

use crate::bopomofo::{phonetic_query, phonetic_syllable, phonetic_tone, BopomofoLayout};
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
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct PhoneticSuggestion {
    pub text: String,
    pub chunks: Vec<PhoneticChunk>,
    pub consumed: usize,
}

pub(crate) fn exact_toned_syllable(layout: BopomofoLayout, raw: &str) -> Option<String> {
    let (last, spelling) = raw.as_bytes().split_last()?;
    let tone = phonetic_tone(layout, *last)?;
    let syllable = phonetic_syllable(layout, std::str::from_utf8(spelling).ok()?, true)?;
    Some(phonetic_query(syllable, tone))
}

struct SyllableMatch {
    end: usize,
    queries: Vec<String>,
}

fn syllable_matches(layout: BopomofoLayout, raw: &str, start: usize) -> Vec<SyllableMatch> {
    let mut matches = Vec::new();
    for end in start + 1..=raw.len().min(start + MAX_SYLLABLE_KEYS) {
        let tone = raw
            .as_bytes()
            .get(end)
            .and_then(|key| phonetic_tone(layout, *key));
        let Some(syllable) = phonetic_syllable(layout, &raw[start..end], tone.is_some()) else {
            continue;
        };
        let queries = match tone {
            Some(tone) => vec![phonetic_query(syllable, tone)],
            None => (0..5).map(|tone| phonetic_query(syllable, tone)).collect(),
        };
        matches.push(SyllableMatch {
            end: end + usize::from(tone.is_some()),
            queries,
        });
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
}

impl<'a> WordLookup<'a> {
    fn new(
        db: &'a ModelDatabase,
        user: &'a UserSnapshot,
        user_phrases: bool,
        filter: &'a CandidateFilter,
    ) -> Result<Self, DatabaseError> {
        let mut lookup = Self {
            db,
            queries: db.phonetic_queries()?,
            filter,
            custom: HashMap::new(),
            custom_prefixes: HashSet::new(),
            words: HashMap::new(),
            longer: HashMap::new(),
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
                rows.truncate(SUGGESTION_LIMIT);
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
    if raw.is_empty() || !raw.is_ascii() {
        return Ok(Vec::new());
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
    let mut lookup = WordLookup::new(db, user, user_phrases, filter)?;

    for start in 0..raw.len() {
        if paths[start].is_empty() {
            continue;
        }
        let heads = paths[start].clone();
        let mut queue = VecDeque::from([(start, String::new())]);
        let mut seen = HashSet::new();
        'words: while let Some((position, prefix)) = queue.pop_front() {
            for edge in &matches[position] {
                for syllable in &edge.queries {
                    let query = prefix.clone() + syllable;
                    if !seen.insert((edge.end, query.clone())) {
                        continue;
                    }
                    if seen.len() > MAX_QUERIES_PER_START {
                        break 'words;
                    }
                    for (word, probability) in lookup.words(&query)? {
                        for head in &heads {
                            let mut path = head.clone();
                            path.score += probability;
                            path.suggestion.text.push_str(word);
                            path.suggestion.chunks.push(PhoneticChunk {
                                query: query.clone(),
                                text: word.clone(),
                            });
                            path.suggestion.consumed = edge.end;
                            keep_best(&mut paths[edge.end], path);
                        }
                    }
                    if edge.end < raw.len()
                        && query.len() < MAX_WORD_SYLLABLES * 2
                        && !matches[edge.end].is_empty()
                        && lookup.has_longer(&query)?
                    {
                        queue.push_back((edge.end, query));
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
            }
        }
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
