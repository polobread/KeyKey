// Copyright (c) 2007-2012, Yahoo! Inc. All rights reserved.
// Copyright (c) 2007-2010 Lukhnos D. Liu (http://lukhnos.org)
// Copyright (c) 2026 Chui-Ping Cheng
//
// Mapping/disambiguation and packed syllables derive from Formosa Mandarin.h /
// Mandarin.cpp and the Swift Hsu transcription. The Yahoo-derived Hsu
// portion retains BSD-3-Clause; Formosa material retains the MIT terms below.
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

//! Stateful Bopomofo parsing with the existing two-byte database encoding.
//!
//! Ambiguous layouts re-encode the current syllable before every edit, rather
//! than retaining raw keystroke history. All platforms use the canonical
//! macOS Formosa disambiguation and Hanyu Pinyin behavior.

use serde::{Deserialize, Serialize};

const CONSONANT: u16 = 0x001f;
const MEDIAL: u16 = 0x0060;
const VOWEL: u16 = 0x0780;
const TONE: u16 = 0x3800;
const MASKS: [u16; 4] = [CONSONANT, MEDIAL, VOWEL, TONE];
const B: u16 = 1;
const P: u16 = 2;
const M: u16 = 3;
const F: u16 = 4;
const D: u16 = 5;
const T: u16 = 6;
const N: u16 = 7;
const L: u16 = 8;
const G: u16 = 9;
const K: u16 = 10;
const H: u16 = 11;
const J: u16 = 12;
const Q: u16 = 13;
const X: u16 = 14;
const ZH: u16 = 15;
const CH: u16 = 16;
const SH: u16 = 17;
const R: u16 = 18;
const Z: u16 = 19;
const C: u16 = 20;
const S: u16 = 21;
const I: u16 = 0x20;
const U: u16 = 0x40;
const UE: u16 = 0x60;
const A: u16 = 0x80;
const O: u16 = 0x100;
const ER: u16 = 0x180;
const E: u16 = 0x200;
const AI: u16 = 0x280;
const EI: u16 = 0x300;
const AO: u16 = 0x380;
const OU: u16 = 0x400;
const AN: u16 = 0x480;
const EN: u16 = 0x500;
const ANG: u16 = 0x580;
const ENG: u16 = 0x600;
const ERR: u16 = 0x680;
const TONE2: u16 = 0x800;
const TONE3: u16 = 0x1000;
const TONE4: u16 = 0x1800;
const TONE5: u16 = 0x2000;

/// All five keyboard layouts offered by the macOS phonetic core.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub enum BopomofoLayout {
    #[default]
    #[serde(rename = "standard", alias = "Standard")]
    Standard,
    #[serde(rename = "hsu", alias = "Hsu")]
    Hsu,
    #[serde(rename = "eten", alias = "ETen")]
    ETen,
    #[serde(rename = "eten26", alias = "ETen26")]
    ETen26,
    #[serde(
        rename = "hanyu_pinyin",
        alias = "HanyuPinyin",
        alias = "hanyupinyin",
        alias = "pinyin"
    )]
    HanyuPinyin,
}

/// The 22 × 4 × 14 × 5 syllable space used by the shared database.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct BopomofoSyllable {
    value: u16,
}

impl BopomofoSyllable {
    pub const COUNT: usize = 22 * 4 * 14 * 5;

    pub fn from_absolute_order(order: usize) -> Option<Self> {
        if order >= Self::COUNT {
            return None;
        }
        Some(Self {
            value: (order % 22) as u16
                | (((order / 22) % 4) as u16) << 5
                | (((order / 88) % 14) as u16) << 7
                | (((order / 1232) % 5) as u16) << 11,
        })
    }

    pub fn from_query_key(key: &str) -> Option<Self> {
        let bytes = key.as_bytes();
        if bytes.len() != 2 || bytes.iter().any(|byte| !(48..=126).contains(byte)) {
            return None;
        }
        Self::from_absolute_order(usize::from(bytes[0] - 48) + usize::from(bytes[1] - 48) * 79)
    }

    pub fn absolute_order(self) -> usize {
        usize::from(self.value & CONSONANT)
            + usize::from((self.value & MEDIAL) >> 5) * 22
            + usize::from((self.value & VOWEL) >> 7) * 88
            + usize::from((self.value & TONE) >> 11) * 1232
    }

    pub fn query_key(self) -> String {
        let order = self.absolute_order();
        let mut key = String::with_capacity(2);
        key.push(char::from(48 + (order % 79) as u8));
        key.push(char::from(48 + (order / 79) as u8));
        key
    }

    pub fn is_empty(self) -> bool {
        self.value == 0
    }

    pub fn has_tone_marker(self) -> bool {
        self.value & TONE != 0
    }

    pub fn bits(self) -> u16 {
        self.value
    }

    pub fn display_text(self) -> String {
        const INITIALS: [&str; 22] = [
            "", "ㄅ", "ㄆ", "ㄇ", "ㄈ", "ㄉ", "ㄊ", "ㄋ", "ㄌ", "ㄍ", "ㄎ", "ㄏ", "ㄐ", "ㄑ", "ㄒ",
            "ㄓ", "ㄔ", "ㄕ", "ㄖ", "ㄗ", "ㄘ", "ㄙ",
        ];
        const MEDIALS: [&str; 4] = ["", "ㄧ", "ㄨ", "ㄩ"];
        const FINALS: [&str; 14] = [
            "", "ㄚ", "ㄛ", "ㄜ", "ㄝ", "ㄞ", "ㄟ", "ㄠ", "ㄡ", "ㄢ", "ㄣ", "ㄤ", "ㄥ", "ㄦ",
        ];
        const TONES: [&str; 5] = ["", "ˊ", "ˇ", "ˋ", "˙"];
        [
            INITIALS[usize::from(self.value & CONSONANT)],
            MEDIALS[usize::from((self.value & MEDIAL) >> 5)],
            FINALS[usize::from((self.value & VOWEL) >> 7)],
            TONES[usize::from((self.value & TONE) >> 11)],
        ]
        .concat()
    }

    /// Replace a composed glyph's component, returning whether that class was
    /// already occupied. Unknown glyphs leave the syllable unchanged.
    pub(crate) fn replace_composed_character(&mut self, character: char) -> Option<bool> {
        let component = match character {
            '\u{3105}'..='\u{3119}' => (character as u32 - 0x3104) as u16,
            '\u{3127}'..='\u{3129}' => ((character as u32 - 0x3126) as u16) << 5,
            '\u{311a}'..='\u{3126}' => ((character as u32 - 0x3119) as u16) << 7,
            'ˊ' => TONE2,
            'ˇ' => TONE3,
            'ˋ' => TONE4,
            '˙' => TONE5,
            _ => return None,
        };
        let replaced = self.component(component_mask(component)) != 0;
        self.add(component);
        Some(replaced)
    }

    fn add(&mut self, component: u16) {
        for mask in MASKS {
            if component & mask != 0 {
                self.value = (self.value & !mask) | (component & mask);
            }
        }
    }

    fn mask_type(self) -> u16 {
        MASKS
            .iter()
            .filter(|&&mask| self.value & mask != 0)
            .fold(0, |result, &mask| result | mask)
    }

    fn component(self, mask: u16) -> u16 {
        self.value & mask
    }
}

static COMPONENTS: [u16; 41] = [
    B, P, M, F, D, T, N, L, G, K, H, J, Q, X, ZH, CH, SH, R, Z, C, S, I, U, UE, A, O, ER, E, AI,
    EI, AO, OU, AN, EN, ANG, ENG, ERR, TONE2, TONE3, TONE4, TONE5,
];
const STANDARD_KEYS: &[u8] = b"1qaz2wsxedcrfv5tgbyhnujm8ik,9ol.0p;/-6347";
const ETEN_KEYS: &[u8] = b"bpmfdtnlvkhg7c,./j;'sexuaorwiqzy890-=2341";
const HSU: &[(u8, &[u16])] = &[
    (b'b', &[B]),
    (b'p', &[P]),
    (b'm', &[M, AN]),
    (b'f', &[F, TONE3]),
    (b'd', &[D, TONE2]),
    (b't', &[T]),
    (b'n', &[N, EN]),
    (b'l', &[L, ENG, ERR]),
    (b'g', &[G, ER]),
    (b'k', &[K, ANG]),
    (b'h', &[H, O]),
    (b'j', &[J, ZH, TONE4]),
    (b'v', &[Q, CH]),
    (b'c', &[X, SH]),
    (b'r', &[R]),
    (b'z', &[Z]),
    (b'a', &[C, EI]),
    (b's', &[S, TONE5]),
    (b'e', &[I, E]),
    (b'x', &[U]),
    (b'u', &[UE]),
    (b'y', &[A]),
    (b'i', &[AI]),
    (b'w', &[AO]),
    (b'o', &[OU]),
];
const ETEN26: &[(u8, &[u16])] = &[
    (b'b', &[B]),
    (b'p', &[P, OU]),
    (b'm', &[M, AN]),
    (b'f', &[F, TONE2]),
    (b'd', &[D, TONE5]),
    (b't', &[T, ANG]),
    (b'n', &[N, EN]),
    (b'l', &[L, ENG]),
    (b'v', &[G, Q]),
    (b'k', &[K, TONE4]),
    (b'h', &[H, ERR]),
    (b'g', &[ZH, J]),
    (b'c', &[SH, X]),
    (b'y', &[CH]),
    (b'j', &[R, TONE3]),
    (b'q', &[Z, EI]),
    (b'w', &[C, E]),
    (b's', &[S]),
    (b'e', &[I]),
    (b'x', &[U]),
    (b'u', &[UE]),
    (b'a', &[A]),
    (b'o', &[O]),
    (b'r', &[ER]),
    (b'i', &[AI]),
    (b'z', &[AO]),
];

fn mapping(layout: BopomofoLayout, key: u8) -> &'static [u16] {
    let keys = match layout {
        BopomofoLayout::Standard => Some(STANDARD_KEYS),
        BopomofoLayout::ETen => Some(ETEN_KEYS),
        _ => None,
    };
    if let Some(keys) = keys {
        return keys
            .iter()
            .position(|&candidate| candidate == key)
            .map_or(&[], |index| &COMPONENTS[index..=index]);
    }
    let entries = match layout {
        BopomofoLayout::Hsu => HSU,
        BopomofoLayout::ETen26 => ETEN26,
        _ => return &[],
    };
    entries
        .iter()
        .find(|entry| entry.0 == key)
        .map_or(&[], |entry| entry.1)
}

fn component_key(layout: BopomofoLayout, component: u16) -> Option<u8> {
    if component == 0 {
        return None;
    }
    match layout {
        BopomofoLayout::Standard | BopomofoLayout::ETen => {
            let keys = if layout == BopomofoLayout::Standard {
                STANDARD_KEYS
            } else {
                ETEN_KEYS
            };
            COMPONENTS
                .iter()
                .position(|&candidate| candidate == component)
                .map(|index| keys[index])
        }
        BopomofoLayout::Hsu | BopomofoLayout::ETen26 => {
            let entries = if layout == BopomofoLayout::Hsu {
                HSU
            } else {
                ETEN26
            };
            entries
                .iter()
                .find(|entry| entry.1.contains(&component))
                .map(|entry| entry.0)
        }
        BopomofoLayout::HanyuPinyin => None,
    }
}

impl BopomofoLayout {
    pub fn is_reading_key(self, key: char) -> bool {
        if !key.is_ascii() {
            return false;
        }
        let key = key.to_ascii_lowercase() as u8;
        if self == Self::HanyuPinyin {
            return key.is_ascii_alphabetic() || (b'2'..=b'5').contains(&key);
        }
        !mapping(self, key).is_empty()
    }

    /// Tone-capable ambiguous keys are included, matching layout look-ahead.
    pub fn is_tone_key(self, key: char) -> bool {
        if !key.is_ascii() {
            return false;
        }
        if self == Self::HanyuPinyin {
            return ('2'..='5').contains(&key);
        }
        mapping(self, key.to_ascii_lowercase() as u8)
            .iter()
            .any(|component| component & TONE != 0)
    }

    pub fn punctuation(self, key: char) -> Option<&'static str> {
        if self != Self::Hsu {
            return None;
        }
        match key {
            ',' => Some("，"),
            '.' => Some("。"),
            '<' => Some("〈"),
            '>' => Some("〉"),
            ':' => Some("："),
            ';' => Some("；"),
            '\'' => Some("、"),
            '"' => Some("”"),
            '-' => Some("─"),
            '_' => Some("＿"),
            _ => None,
        }
    }
}

/// One editable reading, with canonical layout re-encoding on every edit.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BopomofoReading {
    layout: BopomofoLayout,
    syllable: BopomofoSyllable,
    pinyin_sequence: String,
}

impl Default for BopomofoReading {
    fn default() -> Self {
        Self::new(BopomofoLayout::Standard)
    }
}

impl BopomofoReading {
    pub fn new(layout: BopomofoLayout) -> Self {
        Self {
            layout,
            syllable: BopomofoSyllable::default(),
            pinyin_sequence: String::new(),
        }
    }

    pub fn layout(&self) -> BopomofoLayout {
        self.layout
    }

    pub fn is_empty(&self) -> bool {
        self.syllable.is_empty()
    }

    pub fn has_tone_marker(&self) -> bool {
        self.syllable.has_tone_marker()
    }

    pub fn syllable(&self) -> BopomofoSyllable {
        self.syllable
    }

    pub fn display_text(&self) -> String {
        if self.layout == BopomofoLayout::HanyuPinyin {
            self.pinyin_sequence.clone()
        } else {
            self.syllable.display_text()
        }
    }

    /// The absolute-order key used by all shared SQLite phonetic tables.
    pub fn query_key(&self) -> String {
        self.syllable.query_key()
    }

    /// Standard-layout keys, for CIN/reference interoperability.
    pub fn standard_key_sequence(&self) -> String {
        self.sequence_for(BopomofoLayout::Standard)
    }

    /// The canonical keys reconstructed from current components.
    /// For Pinyin, raw entered letters/tones are retained instead.
    pub fn input_key_sequence(&self) -> String {
        if self.layout == BopomofoLayout::HanyuPinyin {
            self.pinyin_sequence.clone()
        } else {
            self.sequence_for(self.layout)
        }
    }

    pub fn combine(&mut self, raw_key: char) -> bool {
        if !raw_key.is_ascii() {
            return false;
        }
        let key = raw_key.to_ascii_lowercase() as u8;
        if self.layout == BopomofoLayout::HanyuPinyin {
            let trailing_tone = self
                .pinyin_sequence
                .as_bytes()
                .last()
                .is_some_and(|byte| (b'2'..=b'5').contains(byte));
            let accepted = if key.is_ascii_alphabetic() {
                !trailing_tone
            } else if (b'2'..=b'5').contains(&key) {
                !self.pinyin_sequence.is_empty()
            } else {
                false
            };
            if !accepted {
                return false;
            }
            self.pinyin_sequence.push(char::from(key));
            self.syllable = parse_pinyin(&self.pinyin_sequence);
            return true;
        }
        if mapping(self.layout, key).is_empty() {
            return false;
        }
        let mut sequence = self.sequence_for(self.layout);
        sequence.push(char::from(key));
        self.syllable = parse_keys(sequence.as_bytes(), self.layout);
        true
    }

    pub fn backspace(&mut self) -> bool {
        if self.layout == BopomofoLayout::HanyuPinyin {
            if self.pinyin_sequence.pop().is_none() {
                return false;
            }
            self.syllable = parse_pinyin(&self.pinyin_sequence);
            return true;
        }
        let mut sequence = self.sequence_for(self.layout);
        if sequence.pop().is_none() {
            return false;
        }
        self.syllable = parse_keys(sequence.as_bytes(), self.layout);
        true
    }

    pub fn clear(&mut self) {
        self.syllable = BopomofoSyllable::default();
        self.pinyin_sequence.clear();
    }

    fn sequence_for(&self, layout: BopomofoLayout) -> String {
        MASKS
            .iter()
            .filter_map(|&mask| component_key(layout, self.syllable.component(mask)))
            .map(char::from)
            .collect()
    }
}

fn component_mask(component: u16) -> u16 {
    MASKS
        .iter()
        .filter(|&&mask| component & mask != 0)
        .fold(0, |result, &mask| result | mask)
}

fn jqx(component: u16) -> bool {
    matches!(component, J | Q | X)
}

fn zcsr(component: u16) -> bool {
    (ZH..=S).contains(&component)
}

fn parse_keys(sequence: &[u8], layout: BopomofoLayout) -> BopomofoSyllable {
    let mut syllable = BopomofoSyllable::default();
    let i_key = component_key(layout, I);
    let ue_key = component_key(layout, UE);
    for (index, &key) in sequence.iter().enumerate() {
        let components = mapping(layout, key);
        if components.is_empty() {
            continue;
        }
        if components.len() == 1 {
            syllable.add(components[0]);
            continue;
        }
        let head = components[0];
        let follow = components[1];
        let ending = *components.last().expect("nonempty mapping");
        let contains_i_or_ue = |keys: &[u8]| {
            keys.iter()
                .any(|&key| Some(key) == i_key || Some(key) == ue_key)
        };
        let before_i_or_ue = contains_i_or_ue(&sequence[..index]);
        let ahead_i_or_ue = contains_i_or_ue(&sequence[index + 1..]);
        let end_or_tone = index + 1 == sequence.len()
            || mapping(layout, sequence[index + 1])
                .iter()
                .any(|component| component & TONE != 0);
        if head == E || follow == E {
            syllable.add(if before_i_or_ue {
                E
            } else if head == E {
                follow
            } else {
                head
            });
        } else if jqx(head) != jqx(follow) {
            if syllable.is_empty() {
                syllable.add(if ahead_i_or_ue == jqx(head) {
                    head
                } else {
                    follow
                });
            } else if ending != follow {
                syllable.add(ending);
            }
        } else if sequence.len() == 1 {
            if (head & (MEDIAL | VOWEL) != 0) || follow & TONE != 0 || zcsr(head) {
                syllable.add(head);
            } else {
                syllable.add(if follow & (MEDIAL | VOWEL) != 0 || ending & TONE != 0 {
                    follow
                } else {
                    ending
                });
            }
        } else if (syllable.mask_type() & component_mask(head) == 0 && !end_or_tone)
            || (end_or_tone && zcsr(head) && syllable.is_empty())
        {
            syllable.add(head);
        } else {
            let choose_follow = syllable.mask_type() < component_mask(follow);
            syllable.add(if choose_follow { follow } else { ending });
        }
    }
    if layout == BopomofoLayout::Hsu {
        if syllable.component(VOWEL) == ENG
            && syllable.component(CONSONANT) == 0
            && syllable.component(MEDIAL) == 0
        {
            syllable.add(ERR);
        } else if syllable.component(CONSONANT) == G && matches!(syllable.component(MEDIAL), I | UE)
        {
            syllable.add(J);
        }
    }
    syllable
}

fn consume(sequence: &mut &str, prefix: &str) -> bool {
    if let Some(rest) = sequence.strip_prefix(prefix) {
        *sequence = rest;
        true
    } else {
        false
    }
}

fn parse_pinyin(raw: &str) -> BopomofoSyllable {
    let mut sequence = raw;
    let mut initial = 0;
    let mut medial = 0;
    let mut final_component = 0;
    let mut independent = false;
    for (prefix, middle, final_part) in [
        ("yuan", UE, AN),
        ("ying", I, ENG),
        ("yung", UE, ENG),
        ("yong", UE, ENG),
        ("yue", UE, E),
        ("yun", UE, EN),
        ("you", I, OU),
        ("yu", UE, 0),
    ] {
        if consume(&mut sequence, prefix) {
            medial = middle;
            final_component = final_part;
            break;
        }
    }
    if let Some(first) = sequence.as_bytes().first().copied() {
        initial = match first {
            b'b' => B,
            b'p' => P,
            b'm' => M,
            b'f' => F,
            b'd' => D,
            b't' => T,
            b'n' => N,
            b'l' => L,
            b'g' => G,
            b'k' => K,
            b'h' => H,
            b'j' => J,
            b'q' => Q,
            b'x' => X,
            _ => 0,
        };
        if initial != 0 {
            sequence = &sequence[1..];
        } else if consume(&mut sequence, "w") {
            medial = U;
        } else if consume(&mut sequence, "y") && medial == 0 && final_component == 0 {
            medial = I;
        }
    }
    for (prefix, component) in [
        ("zh", ZH),
        ("ch", CH),
        ("sh", SH),
        ("r", R),
        ("z", Z),
        ("c", C),
        ("s", S),
    ] {
        if consume(&mut sequence, prefix) {
            initial = component;
            independent = true;
            break;
        }
    }
    for (prefix, middle, final_part) in [
        ("veng", UE, ENG),
        ("iong", UE, ENG),
        ("ing", I, ENG),
        ("ien", I, EN),
        ("iou", I, OU),
        ("uen", U, EN),
        ("ven", UE, EN),
        ("uei", U, EI),
        ("ung", if initial == F { 0 } else { U }, ENG),
        ("ong", if initial == F { 0 } else { U }, ENG),
        ("un", if jqx(initial) { UE } else { U }, EN),
        ("iu", I, OU),
        ("in", I, EN),
        ("vn", UE, EN),
        ("ui", U, EI),
        ("ue", UE, E),
        ("ü", UE, 0),
    ] {
        if consume(&mut sequence, prefix) {
            medial = middle;
            final_component = final_part;
            break;
        }
    }
    if consume(&mut sequence, "i") {
        medial = if independent { 0 } else { I };
    } else if consume(&mut sequence, "u") {
        medial = if jqx(initial) { UE } else { U };
    } else if consume(&mut sequence, "v") {
        medial = UE;
    }
    for (prefix, component) in [
        ("ang", ANG),
        ("eng", ENG),
        ("err", ERR),
        ("ai", AI),
        ("ei", EI),
        ("ao", AO),
        ("ou", OU),
        ("an", AN),
        ("en", EN),
        ("er", ERR),
        ("a", A),
        ("o", O),
        ("e", if medial != 0 { E } else { ER }),
    ] {
        if consume(&mut sequence, prefix) {
            final_component = component;
            break;
        }
    }
    let tone = match sequence.as_bytes().first() {
        Some(b'2') => TONE2,
        Some(b'3') => TONE3,
        Some(b'4') => TONE4,
        Some(b'5') => TONE5,
        _ => 0,
    };
    BopomofoSyllable {
        value: initial | medial | final_component | tone,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn reading(layout: BopomofoLayout, keys: &str) -> BopomofoReading {
        let mut result = BopomofoReading::new(layout);
        for key in keys.chars() {
            assert!(result.combine(key), "{layout:?}: rejected {key:?}");
        }
        result
    }

    #[test]
    fn all_shared_database_keys_round_trip_and_bad_keys_are_rejected() {
        for order in 0..BopomofoSyllable::COUNT {
            let syllable = BopomofoSyllable::from_absolute_order(order).unwrap();
            assert_eq!(syllable.absolute_order(), order);
            assert_eq!(
                BopomofoSyllable::from_query_key(&syllable.query_key()),
                Some(syllable)
            );
            assert_eq!(syllable.query_key().len(), 2);
            assert!(syllable
                .query_key()
                .bytes()
                .all(|byte| (48..=126).contains(&byte)));
        }
        for key in ["", "0", "000", "ㄋ", "/0", "0/", "~~", "\0O"] {
            assert_eq!(BopomofoSyllable::from_query_key(key), None, "{key:?}");
        }
        assert_eq!(
            BopomofoSyllable::from_absolute_order(BopomofoSyllable::COUNT),
            None
        );
    }

    #[test]
    fn standard_query_encoding_and_canonical_backspace_match_the_database() {
        let mut input = reading(BopomofoLayout::Standard, "su3");
        assert_eq!(input.display_text(), "ㄋㄧˇ");
        assert_eq!(input.query_key(), r"\O");
        assert_eq!(input.standard_key_sequence(), "su3");
        assert!(input.has_tone_marker());
        assert!(input.backspace());
        assert_eq!(input.display_text(), "ㄋㄧ");
        assert!(input.backspace());
        assert_eq!(input.display_text(), "ㄋ");
        assert!(input.backspace());
        assert!(input.is_empty());
        assert!(!input.backspace());
        assert_eq!(
            reading(BopomofoLayout::Standard, "3us").display_text(),
            "ㄋㄧˇ"
        );
        assert_eq!(reading(BopomofoLayout::Standard, "1q").display_text(), "ㄆ");
    }

    #[test]
    fn ambiguous_hsu_keys_and_reencoded_edits_match_existing_behavior() {
        for (keys, standard, text) in [
            ("jxl", "5j/", "ㄓㄨㄥ"),
            ("llf", "x/3", "ㄌㄥˇ"),
            ("myd", "a86", "ㄇㄚˊ"),
            ("myf", "a83", "ㄇㄚˇ"),
            ("myj", "a84", "ㄇㄚˋ"),
            ("mys", "a87", "ㄇㄚ˙"),
            ("l", "-", "ㄦ"),
            ("gef", "ru3", "ㄐㄧˇ"),
            ("guf", "rm3", "ㄐㄩˇ"),
        ] {
            let input = reading(BopomofoLayout::Hsu, keys);
            assert_eq!(input.display_text(), text, "{keys}");
            assert_eq!(
                input.query_key(),
                reading(BopomofoLayout::Standard, standard).query_key()
            );
        }
        let mut input = reading(BopomofoLayout::Hsu, "llf");
        assert!(input.backspace());
        assert_eq!(input.display_text(), "ㄌㄥ");
        assert!(input.backspace());
        assert_eq!(input.display_text(), "ㄦ");
        let saved = input.clone();
        assert!(!input.combine('#'));
        assert_eq!(input, saved);
        input.clear();
        assert!(input.is_empty());
        assert_eq!(input.layout(), BopomofoLayout::Hsu);
    }

    #[test]
    fn desktop_layouts_share_the_same_canonical_model_query() {
        for (layout, keys) in [
            (BopomofoLayout::Standard, "5j/"),
            (BopomofoLayout::ETen, ",x-"),
            (BopomofoLayout::ETen26, "gxl"),
            (BopomofoLayout::Hsu, "jxl"),
            (BopomofoLayout::HanyuPinyin, "zhong"),
        ] {
            let input = reading(layout, keys);
            assert_eq!(
                input.query_key(),
                reading(BopomofoLayout::Standard, "5j/").query_key(),
                "{layout:?}"
            );
            assert_eq!(input.standard_key_sequence(), "5j/");
        }
        for (layout, keys) in [
            (BopomofoLayout::Standard, "x/3"),
            (BopomofoLayout::ETen, "l-3"),
            (BopomofoLayout::ETen26, "llj"),
            (BopomofoLayout::Hsu, "llf"),
            (BopomofoLayout::HanyuPinyin, "leng3"),
        ] {
            let input = reading(layout, keys);
            assert_eq!(
                input.query_key(),
                reading(BopomofoLayout::Standard, "x/3").query_key(),
                "{layout:?}"
            );
        }
    }

    #[test]
    fn all_four_tones_and_layout_punctuation_are_preserved() {
        for (layout, sequences) in [
            (BopomofoLayout::Standard, ["a86", "a83", "a84", "a87"]),
            (BopomofoLayout::ETen, ["ma2", "ma3", "ma4", "ma1"]),
            (BopomofoLayout::ETen26, ["maf", "maj", "mak", "mad"]),
            (BopomofoLayout::Hsu, ["myd", "myf", "myj", "mys"]),
            (BopomofoLayout::HanyuPinyin, ["ma2", "ma3", "ma4", "ma5"]),
        ] {
            for (index, keys) in sequences.iter().enumerate() {
                assert_eq!(
                    reading(layout, keys).display_text(),
                    if layout == BopomofoLayout::HanyuPinyin {
                        keys.to_string()
                    } else {
                        format!("ㄇㄚ{}", ["ˊ", "ˇ", "ˋ", "˙"][index])
                    }
                );
            }
        }
        assert!(!reading(BopomofoLayout::Standard, "su").has_tone_marker());
        assert_eq!(BopomofoLayout::Hsu.punctuation(','), Some("，"));
        assert_eq!(BopomofoLayout::Standard.punctuation(','), None);
    }

    #[test]
    fn pinyin_aliases_and_partial_edits_follow_formosa() {
        for (keys, standard) in [
            ("ba", "18"),
            ("po", "qi"),
            ("me", "ak"),
            ("fei", "zo"),
            ("diao", "2ul"),
            ("tun", "wjp"),
            ("neng", "s/"),
            ("lve", "xm,"),
            ("gang", "e;"),
            ("kou", "d."),
            ("heng", "c/"),
            ("ji", "ru"),
            ("quan", "fm0"),
            ("xiong", "vm/"),
            ("zhi", "5"),
            ("chi", "t"),
            ("shi", "g"),
            ("ri", "b"),
            ("zi", "y"),
            ("ci", "h"),
            ("si", "n"),
            ("yi", "u"),
            ("wu", "j"),
            ("yu", "m"),
            ("yuan", "m0"),
            ("yue", "m,"),
            ("yun", "mp"),
            ("ying", "u/"),
            ("yong", "m/"),
            ("wai", "j9"),
            ("wei", "jo"),
            ("wan", "j0"),
            ("wen", "jp"),
            ("wang", "j;"),
            ("weng", "j/"),
            ("fong", "z/"),
            ("zhong4", "5j/4"),
        ] {
            let input = reading(BopomofoLayout::HanyuPinyin, keys);
            assert_eq!(
                input.query_key(),
                reading(BopomofoLayout::Standard, standard).query_key(),
                "{keys}"
            );
        }
        let mut input = reading(BopomofoLayout::HanyuPinyin, "zhong4");
        let before = input.clone();
        assert!(!input.combine('a'));
        assert_eq!(input, before);
        // Formosa accepts another tone key; its prefix parser keeps the first.
        assert!(input.combine('3'));
        assert_eq!(input.display_text(), "zhong43");
        assert_eq!(input.query_key(), before.query_key());
        assert!(input.backspace());
        assert_eq!(input, before);
        for (keys, standard) in [
            ("y", "u"),
            ("w", "j"),
            ("zh", "5"),
            ("ch", "t"),
            ("sh", "g"),
        ] {
            let mut partial = reading(BopomofoLayout::HanyuPinyin, keys);
            assert_eq!(
                partial.query_key(),
                reading(BopomofoLayout::Standard, standard).query_key()
            );
            assert_eq!(partial.input_key_sequence(), keys);
            for _ in keys.chars() {
                assert!(partial.backspace());
            }
            assert!(partial.is_empty());
            assert!(partial.display_text().is_empty());
        }
    }

    #[test]
    fn unknown_non_ascii_and_tone_only_pinyin_keys_do_not_mutate_reading() {
        for layout in [
            BopomofoLayout::Standard,
            BopomofoLayout::Hsu,
            BopomofoLayout::ETen,
            BopomofoLayout::ETen26,
            BopomofoLayout::HanyuPinyin,
        ] {
            let mut input = BopomofoReading::new(layout);
            assert!(!input.combine('ㄋ'));
            assert!(!input.combine('😀'));
            assert!(!input.combine('#'));
            assert!(input.is_empty());
        }
        let mut input = BopomofoReading::new(BopomofoLayout::HanyuPinyin);
        assert!(!input.combine('3'));
        assert!(!input.combine('1'));
        assert!(input.is_empty());
    }

    #[test]
    fn reading_key_and_tone_classification_preserves_layout_boundaries() {
        for layout in [
            BopomofoLayout::Standard,
            BopomofoLayout::Hsu,
            BopomofoLayout::ETen,
            BopomofoLayout::ETen26,
            BopomofoLayout::HanyuPinyin,
        ] {
            assert!(!layout.is_reading_key('ㄋ'));
            assert!(!layout.is_tone_key('😀'));
            assert!(!layout.is_tone_key('#'));
        }
        for (layout, tone, initial) in [
            (BopomofoLayout::Standard, '3', 's'),
            (BopomofoLayout::Hsu, 'F', 'b'),
            (BopomofoLayout::ETen, '2', 'n'),
            (BopomofoLayout::ETen26, 'J', 'b'),
        ] {
            assert!(layout.is_tone_key(tone), "{layout:?}");
            assert!(layout.is_reading_key(tone));
            assert!(!layout.is_tone_key(initial));
        }
        for tone in ['2', '3', '4', '5'] {
            assert!(BopomofoLayout::HanyuPinyin.is_tone_key(tone));
        }
        for key in ['1', '6', 'a', 'A'] {
            assert!(!BopomofoLayout::HanyuPinyin.is_tone_key(key));
        }
    }

    #[test]
    fn hsu_punctuation_is_complete_and_other_layouts_do_not_claim_it() {
        for (key, text) in [
            (',', "，"),
            ('.', "。"),
            ('<', "〈"),
            ('>', "〉"),
            (':', "："),
            (';', "；"),
            ('\'', "、"),
            ('"', "”"),
            ('-', "─"),
            ('_', "＿"),
        ] {
            assert_eq!(BopomofoLayout::Hsu.punctuation(key), Some(text));
            for layout in [
                BopomofoLayout::Standard,
                BopomofoLayout::ETen,
                BopomofoLayout::ETen26,
                BopomofoLayout::HanyuPinyin,
            ] {
                assert_eq!(layout.punctuation(key), None);
            }
        }
        assert_eq!(BopomofoLayout::Hsu.punctuation('a'), None);
    }

    #[test]
    fn public_reading_accessors_expose_canonical_components_after_edits() {
        let mut input = BopomofoReading::default();
        assert_eq!(input.layout(), BopomofoLayout::Standard);
        assert_eq!(input.syllable().bits(), 0);
        assert!(input.input_key_sequence().is_empty());
        for key in "su3".chars() {
            assert!(input.combine(key));
        }
        assert_eq!(input.syllable().bits(), N | I | TONE3);
        assert_eq!(input.syllable().display_text(), "ㄋㄧˇ");
        assert_eq!(input.input_key_sequence(), "su3");
        assert!(input.backspace());
        assert_eq!(input.syllable().bits(), N | I);
        assert_eq!(input.input_key_sequence(), "su");
        input.clear();
        assert_eq!(input.syllable().bits(), 0);
        let mut pinyin = BopomofoReading::new(BopomofoLayout::HanyuPinyin);
        assert!(!pinyin.backspace());
        assert!(pinyin.is_empty());
        assert!(pinyin.input_key_sequence().is_empty());
    }

    #[test]
    fn ambiguous_layout_medials_disambiguate_e_without_losing_reencoded_input() {
        for (layout, keys, text) in [
            (BopomofoLayout::Hsu, "e", "ㄧ"),
            (BopomofoLayout::Hsu, "s", "ㄙ"),
            (BopomofoLayout::Hsu, "ue", "ㄩㄝ"),
            (BopomofoLayout::ETen26, "w", "ㄘ"),
            (BopomofoLayout::ETen26, "ew", "ㄧㄝ"),
        ] {
            let input = reading(layout, keys);
            assert_eq!(input.display_text(), text, "{layout:?}: {keys}");
            let canonical = input.input_key_sequence();
            assert_eq!(reading(layout, &canonical).query_key(), input.query_key());
        }
    }
}
