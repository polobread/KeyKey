// Copyright (c) 2012, Yahoo! Inc. All rights reserved.
// Copyright (c) 2004-2010 The OpenVanilla Project (http://openvanilla.org)
// Copyright (c) 2026 Chui-Ping Cheng
//
// State behavior derives from OVIMSmartMandarin and ManjusriComposer.
// Manjusri material retains BSD-3-Clause; OpenVanilla material retains MIT.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
// 1. Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
// 3. Neither the name of Yahoo! Inc. nor the names of its contributors may be
//    used to endorse or promote products derived from this software without
//    specific prior written permission.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
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

//! Smart Mandarin composition state, independent of a native frontend.
//!
//! Coordinates used for graph edits and candidate targets count completed
//! readings. Visible text coordinates count Unicode scalars.

use crate::bopomofo::{BopomofoLayout, BopomofoReading};
use crate::candidate_filter::CandidateFilter;
use crate::database::ModelDatabase;
use crate::engine::{Effects, EngineError, Key, Modifiers};
use crate::learning::LearningOptions;
use crate::user_store::{UserChange, UserSnapshot};
use crate::walker::{SmartCandidate, SmartGraph, SmartSegment};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct SmartOptions {
    /// Use model Bigram probabilities and context backoff during composition.
    pub use_bigrams: bool,
    pub space_opens_candidates: bool,
    pub candidate_cursor_at_end: bool,
    pub clear_composing_with_escape: bool,
    /// Force explicit Shift ASCII letters to uppercase after FE translation.
    pub shift_always_uppercase: bool,
    /// Frontend-selectable composition threshold, within 10..=20 readings.
    pub max_completed_syllables: usize,
    /// Shift when the threshold is reached, rather than exceeded.
    /// A threshold of ten with this enabled retains the established 9/10 handoff.
    pub shift_at_limit: bool,
    pub selection_returns_to_end: bool,
    pub candidate_selection_keys: Option<String>,
}

impl Default for SmartOptions {
    fn default() -> Self {
        Self {
            use_bigrams: true,
            space_opens_candidates: true,
            candidate_cursor_at_end: false,
            clear_composing_with_escape: false,
            shift_always_uppercase: false,
            max_completed_syllables: 10,
            shift_at_limit: false,
            selection_returns_to_end: false,
            candidate_selection_keys: None,
        }
    }
}

impl SmartOptions {
    pub fn validate(&self) -> Result<(), EngineError> {
        if !(10..=20).contains(&self.max_completed_syllables) {
            return Err(EngineError::InvalidInput(
                "smart composition limit must be within 10..20 completed readings".into(),
            ));
        }
        if let Some(keys) = &self.candidate_selection_keys {
            let bytes = keys.as_bytes();
            let mut seen = std::collections::HashSet::new();
            if bytes.is_empty()
                || bytes.len() > 32
                || !bytes
                    .iter()
                    .all(|byte| (0x21..=0x7e).contains(byte) && seen.insert(byte))
            {
                return Err(EngineError::InvalidInput(
                    "smart candidate keys must be 1..32 unique printable ASCII keys".into(),
                ));
            }
        }
        Ok(())
    }

    pub fn selection_keys(&self, layout: BopomofoLayout) -> String {
        self.candidate_selection_keys.clone().unwrap_or_else(|| {
            match layout {
                BopomofoLayout::Hsu => "asdfzxcv",
                BopomofoLayout::ETen26 => "asdfjkl;",
                _ => "12345678",
            }
            .into()
        })
    }
}

/// A marked completed-reading range and its visible Unicode-scalar bounds.
/// Native frontend code localizes the instruction/confirmation text.
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct MarkedPhrase {
    pub reading_start: usize,
    pub reading_span: usize,
    pub text_start: usize,
    pub text_length: usize,
    pub qstring: String,
    pub text: String,
}

/// One composing context. Its graph never writes the model or learning tables.
#[derive(Clone, Debug)]
pub struct SmartState {
    graph: SmartGraph,
    reading: BopomofoReading,
    cursor: usize,
    candidates: Vec<SmartCandidate>,
    mark_anchor: Option<usize>,
    marked_phrase_request: Option<MarkedPhrase>,
}

impl SmartState {
    pub fn new(layout: BopomofoLayout) -> Self {
        Self::with_candidate_filter(layout, CandidateFilter::default())
    }

    pub fn with_candidate_filter(layout: BopomofoLayout, filter: CandidateFilter) -> Self {
        Self {
            graph: SmartGraph::with_candidate_filter(filter),
            reading: BopomofoReading::new(layout),
            cursor: 0,
            candidates: Vec::new(),
            mark_anchor: None,
            marked_phrase_request: None,
        }
    }

    pub fn set_user_data(
        &mut self,
        database: &ModelDatabase,
        data: &UserSnapshot,
        options: LearningOptions,
    ) -> Result<(), EngineError> {
        if self.graph.set_user_data(database, data, options)? {
            self.candidates.clear();
        }
        Ok(())
    }
    pub fn drain_user_changes(&mut self) -> Vec<UserChange> {
        self.graph.drain_user_changes()
    }

    pub fn clear(&mut self) {
        self.mark_anchor = None;
        self.marked_phrase_request = None;
        self.graph.clear();
        self.reading.clear();
        self.cursor = 0;
        self.candidates.clear();
    }

    /// Apply scoring choices without committing, dropping readings, or moving
    /// the cursor. Native frontends can redraw the re-walked composition.
    pub fn set_options(&mut self, options: &SmartOptions) {
        self.sync_model_options(options);
        self.candidates.clear();
    }

    fn sync_model_options(&mut self, options: &SmartOptions) {
        self.graph.set_use_bigrams(options.use_bigrams);
    }

    pub fn set_layout(&mut self, layout: BopomofoLayout) {
        self.mark_anchor = None;
        self.reading = BopomofoReading::new(layout);
        self.candidates.clear();
    }

    pub fn is_empty(&self) -> bool {
        self.graph.is_empty() && self.reading.is_empty()
    }

    pub fn composition(&self) -> String {
        self.graph.text()
    }
    pub fn reading(&self) -> String {
        self.reading.display_text()
    }
    pub fn reading_cursor(&self) -> usize {
        self.cursor
    }
    pub fn completed_readings(&self) -> &[String] {
        self.graph.readings()
    }
    pub fn segments(&self) -> Vec<SmartSegment> {
        self.graph.segments()
    }
    pub fn candidates(&self) -> &[SmartCandidate] {
        &self.candidates
    }
    pub fn cancel_candidates(&mut self) {
        self.candidates.clear();
    }

    fn text_cursor_at(&self, reading_cursor: usize) -> usize {
        let mut result = 0;
        for segment in self.graph.segments() {
            if reading_cursor >= segment.start + segment.span {
                result += segment.text.chars().count();
            } else if reading_cursor > segment.start {
                result += (reading_cursor - segment.start).min(segment.text.chars().count());
                break;
            } else {
                break;
            }
        }
        result
    }

    fn text_cursor(&self) -> usize {
        self.text_cursor_at(self.cursor)
    }

    pub fn marked_phrase(&self) -> Option<MarkedPhrase> {
        let anchor = self.mark_anchor?;
        let start = anchor.min(self.cursor).min(self.graph.len());
        let end = anchor.max(self.cursor).min(self.graph.len());
        if start == end {
            return None;
        }
        let text_start = self.text_cursor_at(start);
        let text_length = self.text_cursor_at(end).saturating_sub(text_start);
        Some(MarkedPhrase {
            reading_start: start,
            reading_span: end - start,
            text_start,
            text_length,
            qstring: self.graph.readings()[start..end].concat(),
            text: self
                .graph
                .text()
                .chars()
                .skip(text_start)
                .take(text_length)
                .collect(),
        })
    }

    /// The session's transaction owner validates and saves a confirmed mark.
    /// Marking/confirming never commits host text.
    pub fn take_marked_phrase_request(&mut self) -> Option<MarkedPhrase> {
        self.marked_phrase_request.take()
    }

    /// Reject a stale frontend mark without changing composition or cursor.
    pub fn cancel_phrase_mark(&mut self) {
        self.mark_anchor = None;
        self.marked_phrase_request = None;
    }

    fn cancel_mark_for_other_key(&mut self, effects: &mut Effects) {
        if let Some(anchor) = self.mark_anchor.take() {
            self.cursor = anchor.min(self.graph.len());
            effects.beep = true;
        }
    }

    fn process_mark_key(&mut self, key: Key, modifiers: Modifiers, effects: &mut Effects) -> bool {
        if modifiers.shift
            && self.reading.is_empty()
            && !self.graph.is_empty()
            && matches!(key, Key::Left | Key::Right | Key::Home | Key::End)
        {
            let anchor = *self.mark_anchor.get_or_insert(self.cursor);
            let next = match key {
                Key::Left => self.cursor.saturating_sub(1),
                Key::Right => self.cursor.saturating_add(1),
                Key::Home => 0,
                _ => self.graph.len(),
            };
            // Canonical Manjusri permits at most six completed readings.
            self.cursor = next.clamp(
                anchor.saturating_sub(6),
                anchor.saturating_add(6).min(self.graph.len()),
            );
            self.candidates.clear();
            if self.cursor == anchor {
                self.mark_anchor = None;
                effects.beep = true;
            }
            return true;
        }
        if self.mark_anchor.is_some() {
            match key {
                Key::Return => {
                    self.marked_phrase_request = self.marked_phrase();
                    self.mark_anchor = None;
                    self.candidates.clear();
                    return true;
                }
                Key::Escape | Key::Left | Key::Right => {
                    self.mark_anchor = None;
                    self.candidates.clear();
                    return true;
                }
                _ => self.cancel_mark_for_other_key(effects),
            }
        }
        false
    }

    pub fn cursor(&self) -> usize {
        self.text_cursor() + self.reading.display_text().chars().count()
    }

    pub fn visible_text(&self) -> String {
        let composition = self.composition();
        let cursor = self.text_cursor();
        let mut characters = composition.chars();
        let before: String = characters.by_ref().take(cursor).collect();
        before + &self.reading.display_text() + characters.as_str()
    }

    pub fn set_cursor(&mut self, index: usize) -> bool {
        if index > self.graph.len() || !self.reading.is_empty() {
            return false;
        }
        self.cursor = index;
        self.mark_anchor = None;
        self.candidates.clear();
        true
    }

    pub fn finish(&mut self, effects: &mut Effects) {
        effects.commit.push_str(&self.visible_text());
        self.clear();
    }

    pub fn open_candidates(
        &mut self,
        index: Option<usize>,
        options: &SmartOptions,
        effects: &mut Effects,
    ) -> Result<(), EngineError> {
        self.sync_model_options(options);
        self.mark_anchor = None;
        if !self.reading.is_empty() {
            effects.beep = true;
            return Ok(());
        }
        self.candidates.clear();
        if self.graph.is_empty() {
            effects.handled = false;
            return Ok(());
        }
        let target = if let Some(index) = index {
            if index >= self.graph.len() {
                return Err(EngineError::InvalidInput(
                    "smart candidate target is outside completed readings".into(),
                ));
            }
            self.cursor = index + usize::from(options.candidate_cursor_at_end);
            self.cursor
        } else if options.candidate_cursor_at_end {
            self.cursor.max(1)
        } else {
            self.cursor.min(self.graph.len() - 1)
        };
        let candidates = self
            .graph
            .candidates_at(target, options.candidate_cursor_at_end);
        if candidates.len() < 2 {
            effects.beep = true;
        } else {
            self.candidates = candidates;
        }
        Ok(())
    }

    pub fn select(&mut self, index: usize, options: &SmartOptions) -> Result<(), EngineError> {
        self.sync_model_options(options);
        let candidate = self.candidates.get(index).cloned().ok_or_else(|| {
            EngineError::InvalidInput("smart candidate index is outside the open list".into())
        })?;
        if !self.graph.select(&candidate) {
            return Err(EngineError::InvalidInput(
                "smart candidate no longer belongs to the graph".into(),
            ));
        }
        if options.selection_returns_to_end {
            self.cursor = self.graph.len();
        } else if !options.candidate_cursor_at_end {
            self.cursor = candidate.start + candidate.span;
        }
        self.cursor = self.cursor.min(self.graph.len());
        self.candidates.clear();
        Ok(())
    }

    fn enforce_limit(&mut self, options: &SmartOptions, effects: &mut Effects) {
        if !self.reading.is_empty() {
            return;
        }
        let retained_limit = options
            .max_completed_syllables
            .saturating_sub(usize::from(options.shift_at_limit));
        while self.graph.len() > retained_limit {
            if !self.shift_segment(effects) {
                break;
            }
            // Preserve the canonical handoff's treatment of leading ASCII
            // spaces: a host must never receive a stranded leading space.
            while self.graph.text().starts_with(' ') {
                if !self.shift_segment(effects) {
                    break;
                }
            }
        }
        self.cursor = self.cursor.min(self.graph.len());
    }

    fn shift_segment(&mut self, effects: &mut Effects) -> bool {
        if let Some(segment) = self.graph.shift() {
            effects.commit.push_str(&segment.text);
            self.cursor = self.cursor.saturating_sub(segment.span);
            self.mark_anchor = self
                .mark_anchor
                .map(|anchor| anchor.saturating_sub(segment.span));
            self.candidates.clear();
            true
        } else {
            false
        }
    }

    fn insert(
        &mut self,
        database: &ModelDatabase,
        query: &str,
        options: &SmartOptions,
        effects: &mut Effects,
    ) -> Result<bool, EngineError> {
        self.candidates.clear();
        let index = if options.selection_returns_to_end {
            self.graph.len()
        } else {
            self.cursor
        };
        if self.graph.insert(database, index, query)? {
            self.cursor = index + 1;
            self.enforce_limit(options, effects);
            Ok(true)
        } else {
            effects.beep = true;
            Ok(false)
        }
    }

    fn complete_reading(
        &mut self,
        database: &ModelDatabase,
        options: &SmartOptions,
        effects: &mut Effects,
    ) -> Result<(), EngineError> {
        if self.reading.is_empty() {
            return Ok(());
        }
        let query = self.reading.query_key();
        // The reading must stay intact on a rejected syllable.
        let index = if options.selection_returns_to_end {
            self.graph.len()
        } else {
            self.cursor
        };
        if self.graph.insert(database, index, &query)? {
            self.cursor = index + 1;
            self.reading.clear();
            self.candidates.clear();
            self.enforce_limit(options, effects);
        } else {
            effects.beep = true;
        }
        Ok(())
    }

    /// Explicit literal input joins the composing graph when text already
    /// exists, and commits immediately in an otherwise empty context.
    pub fn literal(
        &mut self,
        database: &ModelDatabase,
        text: &str,
        options: &SmartOptions,
        effects: &mut Effects,
    ) -> Result<(), EngineError> {
        self.sync_model_options(options);
        if !self.reading.is_empty() {
            effects.beep = true;
            return Ok(());
        }
        if self.graph.is_empty() {
            effects.commit.push_str(text);
            return Ok(());
        }
        for character in text.chars() {
            let key = if character == ' ' {
                "space".into()
            } else {
                character.to_string()
            };
            self.insert(database, &format!("_passthru_{key} "), options, effects)?;
        }
        Ok(())
    }

    /// Native direct-text key: replace unfinished phonetics and insert one
    /// literal graph block, preserving the completed composition and cursor.
    /// This is distinct from lifecycle finish and from around-filter callbacks.
    pub fn direct_text(
        &mut self,
        database: &ModelDatabase,
        text: &str,
        options: &SmartOptions,
        effects: &mut Effects,
    ) -> Result<(), EngineError> {
        self.sync_model_options(options);
        self.reading.clear();
        self.candidates.clear();
        self.cancel_mark_for_other_key(effects);
        if self.graph.is_empty() {
            effects.commit.push_str(text);
            return Ok(());
        }
        let key = if text == " " { "space" } else { text };
        self.insert(database, &format!("_passthru_{key} "), options, effects)?;
        Ok(())
    }

    pub fn character(
        &mut self,
        database: &ModelDatabase,
        character: char,
        modifiers: Modifiers,
        options: &SmartOptions,
        effects: &mut Effects,
    ) -> Result<(), EngineError> {
        self.sync_model_options(options);
        if modifiers.release {
            effects.handled = false;
            return Ok(());
        }
        if character == ' ' {
            return self.key(database, Key::Space, modifiers, options, effects);
        }
        if modifiers.keypad && (modifiers.control || modifiers.alt || modifiers.command) {
            effects.handled = false;
            return Ok(());
        }
        if modifiers.command || (modifiers.alt && !modifiers.control) {
            effects.handled = !self.is_empty();
            effects.beep = effects.handled;
            return Ok(());
        }
        if modifiers.control {
            if modifiers.caps_lock || !self.reading.is_empty() {
                if self.is_empty() {
                    effects.handled = false;
                } else {
                    effects.beep = true;
                }
                return Ok(());
            }
            self.cancel_mark_for_other_key(effects);
            let query = if modifiers.alt {
                format!("_ctrl_opt_{character}")
            } else if character == '0' || character == '1' {
                "_punctuation_list".into()
            } else {
                format!("_ctrl_{character}")
            };
            if !self.graph.is_in_dictionary(database, &query)? {
                if self.is_empty() {
                    effects.handled = false;
                } else {
                    effects.beep = true;
                }
                return Ok(());
            }
            if self.insert(database, &query, options, effects)?
                && self.graph.has_multiple_candidates(database, &query)?
            {
                // The native Ctrl-punctuation long jump uses the ordinary
                // keyboard target and leaves the actual reading caret intact.
                self.open_candidates(None, options, effects)?;
            }
            return Ok(());
        }
        if modifiers.caps_lock || (modifiers.shift && character.is_ascii_alphabetic()) {
            self.cancel_mark_for_other_key(effects);
            let character = if modifiers.shift && options.shift_always_uppercase {
                character.to_ascii_uppercase()
            } else {
                character
            };
            return self.literal(database, &character.to_string(), options, effects);
        }
        if self.reading.layout().is_reading_key(character) && !character.is_ascii_uppercase() {
            self.candidates.clear();
            self.reading.combine(character);
            if self.reading.has_tone_marker() {
                self.complete_reading(database, options, effects)?;
            }
            return Ok(());
        }
        self.cancel_mark_for_other_key(effects);
        if self.reading.layout() == BopomofoLayout::Hsu
            && character == 'q'
            && self.reading.is_empty()
            && !self.graph.is_empty()
        {
            return self.open_candidates(None, options, effects);
        }
        if !self.reading.is_empty() {
            if character.is_ascii() {
                effects.beep = true;
                return Ok(());
            }
            // Native direct text supersedes an unfinished phonetic sequence.
            self.reading.clear();
        }
        let names = [
            format!(
                "_punctuation_{}_{}",
                layout_name(self.reading.layout()),
                character
            ),
            format!("_punctuation_{character}"),
        ];
        for query in names {
            if self.graph.is_in_dictionary(database, &query)? {
                self.insert(database, &query, options, effects)?;
                return Ok(());
            }
        }
        self.literal(database, &character.to_string(), options, effects)
    }

    pub fn key(
        &mut self,
        database: &ModelDatabase,
        key: Key,
        modifiers: Modifiers,
        options: &SmartOptions,
        effects: &mut Effects,
    ) -> Result<(), EngineError> {
        self.sync_model_options(options);
        if modifiers.release {
            effects.handled = false;
            return Ok(());
        }
        if modifiers.control || modifiers.alt || modifiers.command {
            if self.is_empty() {
                effects.handled = false;
            } else {
                effects.beep = true;
                effects.handled = true;
            }
            return Ok(());
        }
        if self.process_mark_key(key, modifiers, effects) {
            return Ok(());
        }
        self.candidates.clear();
        match key {
            Key::Space | Key::Return | Key::Down => {
                if !self.reading.is_empty() {
                    self.complete_reading(database, options, effects)?;
                } else if self.graph.is_empty() {
                    if matches!(key, Key::Space)
                        && (!options.space_opens_candidates || modifiers.caps_lock)
                    {
                        effects.commit.push(' ');
                    } else {
                        // Native Space-to-candidates is Down semantically. An
                        // empty desktop context leaves that event to the host.
                        effects.handled = false;
                    }
                } else if matches!(key, Key::Return) {
                    self.finish(effects);
                } else if matches!(key, Key::Down)
                    || (options.space_opens_candidates && !modifiers.caps_lock)
                {
                    self.open_candidates(None, options, effects)?;
                } else {
                    self.literal(database, " ", options, effects)?;
                }
            }
            Key::Backspace => {
                if !self.reading.is_empty() {
                    self.reading.backspace();
                } else if self.graph.is_empty() {
                    effects.handled = false;
                } else if self.cursor == 0 {
                    effects.beep = true;
                } else {
                    self.graph.remove(database, self.cursor - 1)?;
                    self.cursor -= 1;
                }
            }
            Key::Delete => {
                if !self.reading.is_empty() {
                    effects.beep = true;
                } else if self.graph.is_empty() {
                    effects.handled = false;
                } else if self.cursor == self.graph.len() {
                    effects.beep = true;
                } else {
                    self.graph.remove(database, self.cursor)?;
                }
            }
            Key::Escape => {
                if !self.reading.is_empty() {
                    self.reading.clear();
                } else if self.graph.is_empty() {
                    effects.handled = false;
                } else if options.clear_composing_with_escape {
                    self.clear();
                } else {
                    effects.beep = true;
                }
            }
            Key::Left | Key::Right | Key::Home | Key::End => {
                if !self.reading.is_empty() {
                    effects.beep = true;
                } else if self.graph.is_empty() {
                    effects.handled = false;
                } else {
                    let next = match key {
                        Key::Left => self.cursor.saturating_sub(1),
                        Key::Right => (self.cursor + 1).min(self.graph.len()),
                        Key::Home => 0,
                        _ => self.graph.len(),
                    };
                    effects.beep = next == self.cursor;
                    self.cursor = next;
                }
            }
            Key::Up | Key::PageUp | Key::PageDown | Key::Tab => {
                if self.is_empty() {
                    effects.handled = false;
                } else {
                    effects.beep = true;
                }
            }
        }
        self.cursor = self.cursor.min(self.graph.len());
        Ok(())
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn database() -> ModelDatabase {
        ModelDatabase::open(crate::test_support::model_path()).unwrap()
    }

    fn effects() -> Effects {
        Effects {
            handled: true,
            ..Effects::default()
        }
    }

    fn type_keys(
        state: &mut SmartState,
        db: &ModelDatabase,
        keys: &str,
        options: &SmartOptions,
    ) -> String {
        let mut committed = String::new();
        for character in keys.chars() {
            let mut effect = effects();
            state
                .character(db, character, Modifiers::default(), options, &mut effect)
                .unwrap();
            assert!(
                !effect.beep,
                "unexpected beep for {character:?} after {}",
                state.visible_text()
            );
            committed += &effect.commit;
        }
        committed
    }

    fn press(
        state: &mut SmartState,
        db: &ModelDatabase,
        key: Key,
        options: &SmartOptions,
    ) -> Effects {
        let mut effect = effects();
        state
            .key(db, key, Modifiers::default(), options, &mut effect)
            .unwrap();
        effect
    }

    fn select_text(state: &mut SmartState, index: usize, text: &str, options: &SmartOptions) {
        state
            .open_candidates(Some(index), options, &mut effects())
            .unwrap();
        let choice = state
            .candidates()
            .iter()
            .position(|candidate| candidate.text == text)
            .unwrap();
        state.select(choice, options).unwrap();
    }

    #[test]
    fn behavior_options_validate_without_an_operating_system_profile() {
        let mut options = SmartOptions::default();
        assert!(options.validate().is_ok());
        assert_eq!(options.selection_keys(BopomofoLayout::Standard), "12345678");
        assert_eq!(options.selection_keys(BopomofoLayout::Hsu), "asdfzxcv");
        assert_eq!(options.selection_keys(BopomofoLayout::ETen26), "asdfjkl;");
        for valid in [10, 20] {
            options.max_completed_syllables = valid;
            assert!(options.validate().is_ok());
        }
        for invalid in [0, 9, 21, usize::MAX] {
            options.max_completed_syllables = invalid;
            assert!(options.validate().is_err());
        }
        options.max_completed_syllables = 10;
        for invalid in ["", "aa", "a b", "注音"] {
            options.candidate_selection_keys = Some(invalid.into());
            assert!(options.validate().is_err());
        }
    }

    #[test]
    fn tone_completes_a_reading_and_return_confirms_an_unfinished_first_tone() {
        let db = database();
        let options = SmartOptions::default();
        let mut state = SmartState::new(BopomofoLayout::Standard);
        assert!(type_keys(&mut state, &db, "g4", &options).is_empty());
        assert_eq!(state.composition(), "是");
        assert!(state.reading().is_empty());
        assert_eq!(state.completed_readings().len(), 1);
        let committed = press(&mut state, &db, Key::Return, &options);
        assert_eq!(committed.commit, "是");
        assert!(state.is_empty());

        type_keys(&mut state, &db, "5j/", &options);
        assert_eq!(state.reading(), "ㄓㄨㄥ");
        assert!(state.composition().is_empty());
        let complete = press(&mut state, &db, Key::Return, &options);
        assert!(complete.commit.is_empty());
        assert_eq!(state.composition(), "中");
        assert!(state.reading().is_empty());
    }

    #[test]
    fn candidate_selection_changes_the_target_and_obeys_cursor_choices() {
        let db = database();
        let mut options = SmartOptions::default();
        let mut state = SmartState::new(BopomofoLayout::Standard);
        type_keys(&mut state, &db, "su3cl3", &options);
        assert_eq!(state.composition(), "你好");
        select_text(&mut state, 0, "妳", &options);
        assert_eq!(state.composition(), "妳好");
        assert_eq!(state.reading_cursor(), 1);
        assert!(state.candidates().is_empty());

        state.clear();
        options.selection_returns_to_end = true;
        type_keys(&mut state, &db, "su3cl3", &options);
        select_text(&mut state, 0, "妳", &options);
        assert_eq!(state.reading_cursor(), 2);
        type_keys(&mut state, &db, "su3", &options);
        assert_eq!(state.completed_readings().len(), 3);
        assert!(state.composition().starts_with("妳好"));
    }

    #[test]
    fn editing_uses_completed_reading_positions_and_keeps_unfinished_readings_visible() {
        let db = database();
        let options = SmartOptions::default();
        let mut state = SmartState::new(BopomofoLayout::Standard);
        type_keys(&mut state, &db, "su3cl3", &options);
        press(&mut state, &db, Key::Left, &options);
        type_keys(&mut state, &db, "su3", &options);
        assert_eq!(state.composition(), "你你好");
        assert_eq!(state.reading_cursor(), 2);

        state.clear();
        type_keys(&mut state, &db, "su3cl3", &options);
        press(&mut state, &db, Key::Left, &options);
        press(&mut state, &db, Key::Backspace, &options);
        assert_eq!(state.composition(), "好");
        assert_eq!(state.reading_cursor(), 0);
        type_keys(&mut state, &db, "su", &options);
        assert_eq!(state.visible_text(), "ㄋㄧ好");
        assert_eq!(state.cursor(), 2);
        assert!(!state.set_cursor(1));
        press(&mut state, &db, Key::Backspace, &options);
        assert_eq!(state.reading(), "ㄋ");
        let mut finish = effects();
        state.finish(&mut finish);
        assert_eq!(finish.commit, "ㄋ好");
        assert!(state.is_empty());
    }

    #[test]
    fn escape_and_space_are_explicit_composition_behaviors() {
        let db = database();
        let mut options = SmartOptions::default();
        let mut state = SmartState::new(BopomofoLayout::Standard);
        type_keys(&mut state, &db, "su3", &options);
        assert!(press(&mut state, &db, Key::Escape, &options).beep);
        assert_eq!(state.composition(), "你");
        options.clear_composing_with_escape = true;
        assert!(!press(&mut state, &db, Key::Escape, &options).beep);
        assert!(state.is_empty());
        type_keys(&mut state, &db, "su3", &options);
        press(&mut state, &db, Key::Space, &options);
        assert!(state.candidates().len() >= 2);
        state.cancel_candidates();
        options.space_opens_candidates = false;
        press(&mut state, &db, Key::Space, &options);
        assert_eq!(state.composition(), "你 ");
        assert!(state.candidates().is_empty());
    }

    #[test]
    fn ten_eleven_and_nineteen_reading_handoffs_preserve_every_character() {
        let db = database();
        let options = SmartOptions::default();
        let mut state = SmartState::new(BopomofoLayout::Standard);
        let mut committed = type_keys(&mut state, &db, "fu/3ru84ul4fm4s83xu3j06", &options);
        assert_eq!(state.composition(), "請假要去哪裡完");
        select_text(&mut state, 6, "玩", &options);
        press(&mut state, &db, Key::End, &options);
        committed += &type_keys(&mut state, &db, "sk7fm4c93", &options);
        assert_eq!(state.completed_readings().len(), 10);
        assert!(committed.is_empty());
        assert_eq!(state.composition(), "請假要去哪裡玩呢去海");

        committed += &type_keys(&mut state, &db, "1u0 ", &options);
        assert_eq!(committed, "請假");
        assert_eq!(state.composition(), "要去哪裡玩呢去海邊");
        committed += &type_keys(&mut state, &db, "up jo4s84xu3u.31u3ru su6", &options);
        assert_eq!(committed, "請假要去哪裡玩呢去");
        assert_eq!(state.composition(), "海邊因為那裡有比基尼");
        assert_eq!(state.completed_readings().len(), 10);
        let mut finish = effects();
        state.finish(&mut finish);
        committed += &finish.commit;
        assert_eq!(committed, "請假要去哪裡玩呢去海邊因為那裡有比基尼");
        assert!(state.is_empty());
    }

    #[test]
    fn nine_reading_limit_is_selected_by_behavior_and_committed_text_cannot_be_edited() {
        let db = database();
        let options = SmartOptions {
            max_completed_syllables: 10,
            shift_at_limit: true,
            ..SmartOptions::default()
        };
        let mut state = SmartState::new(BopomofoLayout::Standard);
        let mut committed = type_keys(&mut state, &db, "fu/3ru84ul4fm4s83xu3j06", &options);
        select_text(&mut state, 6, "玩", &options);
        press(&mut state, &db, Key::End, &options);
        committed += &type_keys(&mut state, &db, "sk7fm4", &options);
        assert_eq!(state.completed_readings().len(), 9);
        assert!(committed.is_empty());
        committed += &type_keys(&mut state, &db, "c93", &options);
        assert_eq!(committed, "請假");
        assert_eq!(state.composition(), "要去哪裡玩呢去海");
        for _ in 0..state.completed_readings().len() {
            press(&mut state, &db, Key::Backspace, &options);
        }
        assert!(state.is_empty());
        assert!(!press(&mut state, &db, Key::Backspace, &options).handled);
        assert_eq!(committed, "請假");
    }
    #[test]
    fn all_five_layouts_feed_the_same_smart_model_query() {
        let db = database();
        let options = SmartOptions::default();
        for (layout, keys) in [
            (BopomofoLayout::Standard, "5j/"),
            (BopomofoLayout::Hsu, "jxl"),
            (BopomofoLayout::ETen, ",x-"),
            (BopomofoLayout::ETen26, "gxl"),
            (BopomofoLayout::HanyuPinyin, "zhong"),
        ] {
            let mut state = SmartState::new(layout);
            type_keys(&mut state, &db, keys, &options);
            assert!(!state.reading().is_empty(), "{layout:?}");
            assert!(press(&mut state, &db, Key::Space, &options)
                .commit
                .is_empty());
            assert_eq!(state.composition(), "中", "{layout:?}");
            assert!(state.reading().is_empty());
            assert_eq!(state.completed_readings(), &["9>"]);
        }
    }

    #[test]
    fn end_of_target_candidates_preserve_the_original_reading_cursor() {
        let db = database();
        let options = SmartOptions {
            candidate_cursor_at_end: true,
            ..SmartOptions::default()
        };
        let mut state = SmartState::new(BopomofoLayout::Standard);
        type_keys(&mut state, &db, "su3cl3", &options);
        assert!(state.set_cursor(1));
        state
            .open_candidates(None, &options, &mut effects())
            .unwrap();
        let index = state
            .candidates()
            .iter()
            .position(|candidate| candidate.text == "妳")
            .unwrap();
        state.select(index, &options).unwrap();
        assert_eq!(state.composition(), "妳好");
        assert_eq!(state.reading_cursor(), 1);
        assert_eq!(state.cursor(), 1);
    }

    #[test]
    fn frontend_candidate_filter_preserves_explicit_literals_inside_composition() {
        let db = database();
        let options = SmartOptions {
            space_opens_candidates: false,
            ..SmartOptions::default()
        };
        let mut state = SmartState::with_candidate_filter(
            BopomofoLayout::Standard,
            CandidateFilter::new(|text| text == "你"),
        );
        type_keys(&mut state, &db, "su3", &options);
        assert_eq!(state.composition(), "你");
        let mut literal = effects();
        state.literal(&db, " A1 ", &options, &mut literal).unwrap();
        assert!(literal.commit.is_empty());
        assert_eq!(state.composition(), "你 A1 ");
        assert_eq!(state.completed_readings().len(), 5);
        // Clear the composing graph but retain its query cache, then verify
        // cached literal rows are neither filtered nor lost on the next input.
        state.clear();
        type_keys(&mut state, &db, "su3", &options);
        state.literal(&db, " A1 ", &options, &mut literal).unwrap();
        let mut finish = effects();
        state.finish(&mut finish);
        assert_eq!(finish.commit, "你 A1 ");
        assert!(state.is_empty());
    }

    #[test]
    fn handoff_also_commits_leading_ascii_spaces_and_leaves_no_replayable_prefix() {
        let db = database();
        let options = SmartOptions::default();
        let mut state = SmartState::new(BopomofoLayout::Standard);
        type_keys(&mut state, &db, "su3", &options);
        let mut prefix = effects();
        state
            .literal(&db, " 12345678", &options, &mut prefix)
            .unwrap();
        assert!(prefix.commit.is_empty());
        assert_eq!(state.completed_readings().len(), 10);
        let mut handoff = effects();
        state.literal(&db, "9", &options, &mut handoff).unwrap();
        assert_eq!(handoff.commit, "你 ");
        assert_eq!(state.composition(), "123456789");
        let mut finish = effects();
        state.finish(&mut finish);
        assert_eq!(handoff.commit + &finish.commit, "你 123456789");
        assert!(state.is_empty());
    }
    #[test]
    fn ordinary_shortcuts_preserve_active_composition_and_keypad_shortcuts_stay_with_host() {
        let db = database();
        let options = SmartOptions::default();
        let mut state = SmartState::new(BopomofoLayout::Standard);
        for active in [false, true] {
            if active {
                type_keys(&mut state, &db, "su3", &options);
            }
            let before = state.visible_text();
            for modifiers in [
                Modifiers {
                    command: true,
                    ..Modifiers::default()
                },
                Modifiers {
                    alt: true,
                    ..Modifiers::default()
                },
            ] {
                let mut effect = effects();
                state
                    .character(&db, 'c', modifiers, &options, &mut effect)
                    .unwrap();
                assert_eq!(effect.handled, active);
                assert_eq!(effect.beep, active);
                assert!(effect.commit.is_empty());
                assert_eq!(state.visible_text(), before);
            }
            for modifiers in [
                Modifiers {
                    control: true,
                    ..Modifiers::default()
                },
                Modifiers {
                    alt: true,
                    ..Modifiers::default()
                },
                Modifiers {
                    command: true,
                    ..Modifiers::default()
                },
            ] {
                let mut effect = effects();
                state
                    .character(
                        &db,
                        '1',
                        Modifiers {
                            keypad: true,
                            ..modifiers
                        },
                        &options,
                        &mut effect,
                    )
                    .unwrap();
                assert!(!effect.handled);
                assert!(!effect.beep);
                assert!(effect.commit.is_empty());
                assert_eq!(state.visible_text(), before);
            }
        }
    }
    #[test]
    fn twenty_reading_limit_shifts_a_complete_phrase_at_twenty_one_without_loss_or_duplication() {
        let db = database();
        let options = SmartOptions {
            max_completed_syllables: 20,
            ..SmartOptions::default()
        };
        options.validate().unwrap();
        let mut state = SmartState::new(BopomofoLayout::Standard);
        let prefix = type_keys(&mut state, &db, "fu/3ru84", &options);
        assert!(prefix.is_empty());
        assert_eq!(state.composition(), "請假");
        let rest = type_keys(&mut state, &db, &"su3".repeat(18), &options);
        assert!(rest.is_empty());
        assert_eq!(state.completed_readings().len(), 20);
        assert_eq!(state.composition(), format!("請假{}", "你".repeat(18)));
        assert_eq!(state.segments()[0].text, "請假");
        assert_eq!(state.segments()[0].span, 2);

        let mut committed = type_keys(&mut state, &db, "su3", &options);
        assert_eq!(committed, "請假");
        assert_eq!(state.completed_readings().len(), 19);
        assert_eq!(state.composition(), "你".repeat(19));
        let mut finish = effects();
        state.finish(&mut finish);
        committed += &finish.commit;
        assert_eq!(committed, format!("請假{}", "你".repeat(19)));
        assert!(state.is_empty());
    }
    #[test]
    fn bigram_setting_rewalks_without_losing_pending_readings_cursor_or_manual_selection() {
        use rusqlite::{params, Connection};
        use std::sync::atomic::{AtomicU64, Ordering};

        struct ScratchModel(PathBuf);
        impl Drop for ScratchModel {
            fn drop(&mut self) {
                let _ = std::fs::remove_dir_all(&self.0);
            }
        }
        static NEXT: AtomicU64 = AtomicU64::new(0);
        let fixture = loop {
            let id = NEXT.fetch_add(1, Ordering::Relaxed);
            let path = std::env::temp_dir().join(format!(
                "guanyinma-smart-options-{}-{id}",
                std::process::id()
            ));
            match std::fs::create_dir(&path) {
                Ok(()) => break ScratchModel(path),
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(error) => panic!("{error}"),
            }
        };
        let path = fixture.0.join("model.db");
        let writer = Connection::open(&path).unwrap();
        writer
            .execute_batch(
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
        let query = |keys: &str| {
            let mut reading = BopomofoReading::new(BopomofoLayout::Standard);
            for character in keys.chars() {
                assert!(reading.combine(character));
            }
            reading.query_key()
        };
        let first = query("su3");
        let second = query("g4");
        for (q, text, probability, backoff) in [
            (&first, "甲", -1.0, -5.0),
            (&second, "乙", -2.0, 0.0),
            (&second, "異", -3.0, 0.0),
        ] {
            writer
                .execute(
                    "INSERT INTO unigrams VALUES(?1,?2,?3,?4)",
                    params![q, text, probability, backoff],
                )
                .unwrap();
        }
        writer
            .execute(
                "INSERT INTO bigrams VALUES(?1,'甲','異',0)",
                [format!("{first} {second}")],
            )
            .unwrap();
        drop(writer);
        let db = ModelDatabase::open(path).unwrap();
        let enabled = SmartOptions::default();
        let disabled = SmartOptions {
            use_bigrams: false,
            ..SmartOptions::default()
        };
        let mut state = SmartState::new(BopomofoLayout::Standard);
        type_keys(&mut state, &db, "su3g4", &enabled);
        assert_eq!(state.composition(), "甲異");
        assert!(state.set_cursor(1));
        type_keys(&mut state, &db, "su", &enabled);
        let completed = state.completed_readings().to_vec();
        assert_eq!(state.visible_text(), "甲ㄋㄧ異");

        state.set_options(&disabled);
        assert_eq!(state.composition(), "甲乙");
        assert_eq!(state.reading(), "ㄋㄧ");
        assert_eq!(state.reading_cursor(), 1);
        assert_eq!(state.completed_readings(), completed);
        assert_eq!(state.visible_text(), "甲ㄋㄧ乙");
        state.set_options(&enabled);
        assert_eq!(state.visible_text(), "甲ㄋㄧ異");
        assert_eq!(state.reading_cursor(), 1);
        press(&mut state, &db, Key::Escape, &enabled);
        select_text(&mut state, 1, "乙", &enabled);
        assert_eq!(state.composition(), "甲乙");
        assert!(state.set_cursor(1));
        state
            .open_candidates(None, &enabled, &mut effects())
            .unwrap();
        assert!(!state.candidates().is_empty());
        state.set_options(&disabled);
        assert!(state.candidates().is_empty());
        assert_eq!(state.composition(), "甲乙");
        assert_eq!(state.reading_cursor(), 1);
        state.set_options(&enabled);
        assert_eq!(
            state.composition(),
            "甲乙",
            "manual selection must survive the scoring-mode switch"
        );

        let mut initially_disabled = SmartState::new(BopomofoLayout::Standard);
        type_keys(&mut initially_disabled, &db, "su3g4", &disabled);
        assert_eq!(
            initially_disabled.composition(),
            "甲乙",
            "options must apply before the first inserted reading"
        );
    }
    #[test]
    fn explicit_selection_learning_survives_finish_and_changes_the_next_reading_only() {
        let db = database();
        let options = SmartOptions::default();
        let mut state = SmartState::new(BopomofoLayout::Standard);
        let learning = LearningOptions {
            candidate_overrides: true,
            ..LearningOptions::default()
        };
        state
            .set_user_data(&db, &UserSnapshot::default(), learning)
            .unwrap();
        type_keys(&mut state, &db, "g4", &options);
        select_text(&mut state, 0, "事", &options);
        assert_eq!(state.composition(), "事");
        let committed = press(&mut state, &db, Key::Return, &options);
        assert_eq!(committed.commit, "事");
        assert!(state.is_empty());
        let events = state.drain_user_changes();
        assert_eq!(events.len(), 1);
        assert!(
            matches!(&events[0],UserChange::SetOverride{qstring,current:Some(text)} if qstring=="0_"&&text=="事")
        );
        type_keys(&mut state, &db, "g4", &options);
        assert_eq!(state.composition(), "事");
        state
            .open_candidates(Some(0), &options, &mut effects())
            .unwrap();
        assert_eq!(state.candidates()[0].text, "事");
        state.select(0, &options).unwrap();
        assert_eq!(
            state.drain_user_changes(),
            [UserChange::SetOverride {
                qstring: "0_".into(),
                current: None
            }]
        );
        press(&mut state, &db, Key::Return, &options);
        type_keys(&mut state, &db, "g4", &options);
        assert_eq!(state.composition(), "是");
        assert!(state.drain_user_changes().is_empty());
    }
    #[test]
    fn external_user_data_refresh_preserves_pending_reading_cursor_and_manual_choice() {
        let db = database();
        let options = SmartOptions::default();
        let mut state = SmartState::new(BopomofoLayout::Standard);
        type_keys(&mut state, &db, "su3cl3", &options);
        select_text(&mut state, 0, "妳", &options);
        type_keys(&mut state, &db, "su", &options);
        assert_eq!(state.visible_text(), "妳ㄋㄧ好");
        let before_readings = state.completed_readings().to_vec();
        let query = before_readings.concat();
        let custom = crate::database::Unigram {
            qstring: query,
            current: "泥豪".into(),
            probability: db.max_unigram_probability().unwrap(),
            backoff: 0.,
        };
        let data = UserSnapshot {
            revision: 1,
            phrases: vec![custom.clone()],
            ..UserSnapshot::default()
        };
        state
            .set_user_data(&db, &data, LearningOptions::default())
            .unwrap();
        assert_eq!(state.visible_text(), "妳ㄋㄧ好");
        assert_eq!(state.reading_cursor(), 1);
        assert_eq!(state.completed_readings(), before_readings);
        assert!(state.drain_user_changes().is_empty());
        let mut invalid = data.clone();
        invalid.phrases[0].probability = f64::NAN;
        assert!(state
            .set_user_data(&db, &invalid, LearningOptions::default())
            .is_err());
        assert_eq!(state.visible_text(), "妳ㄋㄧ好");
        press(&mut state, &db, Key::Escape, &options);
        state
            .open_candidates(Some(0), &options, &mut effects())
            .unwrap();
        assert!(state
            .candidates()
            .iter()
            .any(|candidate| candidate.text == "泥豪"));
        let mut removed = data;
        removed.revision += 1;
        removed.phrases.clear();
        state
            .set_user_data(&db, &removed, LearningOptions::default())
            .unwrap();
        assert!(state.candidates().is_empty());
        assert_eq!(state.composition(), "妳好");
        assert_eq!(state.reading_cursor(), 0);
    }
}
