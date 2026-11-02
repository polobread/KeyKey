// Copyright (c) 2007-2012, Yahoo! Inc. All rights reserved.
// Copyright (c) 2007-2010 Lukhnos D. Liu (http://lukhnos.org)
// Copyright (c) 2026 Chui-Ping Cheng
//
// Composed-reading conversion derives from Formosa Mandarin.h / Mandarin.cpp
// and the Manjusri BPMFUserPhraseHelper comma conversion. Yahoo-derived
// portions retain BSD-3-Clause; Formosa material retains the MIT terms below.
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

//! Stateless composed-reading and database-query conversion.
//!
//! The caller selects syntax and validation behavior. These options describe
//! data contracts rather than platform names; no model or session is opened.

use crate::bopomofo::BopomofoSyllable;
use serde::{Deserialize, Serialize};
use std::error::Error;
use std::fmt;

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EncodeSeparator {
    #[default]
    Comma,
    Whitespace,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ComponentPolicy {
    /// Ignore unknown glyphs; a later component replaces its own class.
    #[default]
    ReplaceKnown,
    /// Reject unknown glyphs and repeated component classes.
    UniqueKnown,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EmptySyllablePolicy {
    #[default]
    Skip,
    Reject,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct EncodeOptions {
    pub separator: EncodeSeparator,
    pub components: ComponentPolicy,
    pub empty: EmptySyllablePolicy,
    /// Require a consonant, medial or final rather than a tone marker alone.
    pub require_phonetic: bool,
}

impl Default for EncodeOptions {
    fn default() -> Self {
        Self {
            separator: EncodeSeparator::Comma,
            components: ComponentPolicy::ReplaceKnown,
            empty: EmptySyllablePolicy::Skip,
            require_phonetic: false,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DecodeSeparator {
    #[default]
    Comma,
    Space,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum QueryPolicy {
    /// Accept only canonical, printable two-byte keys with order below 6160.
    Canonical,
    /// Preserve the old printable overflow-key component modulo behavior.
    #[default]
    PrintableModulo,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum OddTailPolicy {
    #[default]
    Reject,
    Ignore,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct DecodeOptions {
    pub separator: DecodeSeparator,
    pub query: QueryPolicy,
    pub odd_tail: OddTailPolicy,
    /// Omit separators while the accumulated display text is still empty.
    /// Empty syllables after visible text still retain their separators.
    pub omit_leading_empty: bool,
}

impl Default for DecodeOptions {
    fn default() -> Self {
        Self {
            separator: DecodeSeparator::Comma,
            query: QueryPolicy::PrintableModulo,
            odd_tail: OddTailPolicy::Reject,
            omit_leading_empty: false,
        }
    }
}

/// Owned conversion result; the qstring is retained verbatim on decode,
/// including an ignored odd tail. Count records complete syllables, even when
/// their display form is empty. Encoding reports only accepted syllables.
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct CodecResult {
    pub qstring: String,
    pub reading: String,
    pub syllable_count: usize,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ReadingCodecError {
    EmbeddedNul,
    UnknownComponent(char),
    DuplicateComponent(char),
    EmptySyllable,
    MissingPhonetic,
    OddQueryLength,
    InvalidQueryKey,
}

impl fmt::Display for ReadingCodecError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::EmbeddedNul => formatter.write_str("reading codec input contains NUL"),
            Self::UnknownComponent(character) => {
                write!(formatter, "unknown phonetic component: {character}")
            }
            Self::DuplicateComponent(character) => {
                write!(formatter, "duplicate phonetic component class: {character}")
            }
            Self::EmptySyllable => formatter.write_str("reading contains an empty syllable"),
            Self::MissingPhonetic => {
                formatter.write_str("reading syllable needs a phonetic component")
            }
            Self::OddQueryLength => {
                formatter.write_str("phonetic query has an incomplete two-byte key")
            }
            Self::InvalidQueryKey => {
                formatter.write_str("phonetic query contains an invalid two-byte key")
            }
        }
    }
}

impl Error for ReadingCodecError {}

fn ascii_separator(character: char) -> bool {
    matches!(
        character,
        ' ' | '\t' | '\n' | '\r' | '\u{000b}' | '\u{000c}'
    )
}

/// Convert composed Bopomofo to the shared model's two-byte query keys.
/// Comma/reject trims the historical four ASCII edge whitespace characters;
/// whitespace syntax recognizes the six classic ASCII whitespace characters.
/// No keyboard layout interpretation or eight-syllable phrase limit is applied.
pub fn encode_reading(
    reading: &str,
    options: &EncodeOptions,
) -> Result<CodecResult, ReadingCodecError> {
    if reading.contains('\0') {
        return Err(ReadingCodecError::EmbeddedNul);
    }
    let parts: Vec<&str> = match options.separator {
        EncodeSeparator::Comma => reading.split(',').collect(),
        EncodeSeparator::Whitespace => reading
            .split(ascii_separator)
            .filter(|part| !part.is_empty())
            .collect(),
    };
    let mut qstring = String::new();
    let mut normalized = Vec::new();
    for part in parts {
        let part = if options.separator == EncodeSeparator::Comma
            && options.empty == EmptySyllablePolicy::Reject
        {
            part.trim_matches([' ', '\t', '\r', '\n'])
        } else {
            part
        };
        let mut syllable = BopomofoSyllable::default();
        for character in part.chars() {
            match syllable.replace_composed_character(character) {
                None if options.components == ComponentPolicy::UniqueKnown => {
                    return Err(ReadingCodecError::UnknownComponent(character))
                }
                Some(true) if options.components == ComponentPolicy::UniqueKnown => {
                    return Err(ReadingCodecError::DuplicateComponent(character))
                }
                _ => {}
            }
        }
        if syllable.is_empty() {
            if options.empty == EmptySyllablePolicy::Reject {
                return Err(ReadingCodecError::EmptySyllable);
            }
            continue;
        }
        if options.require_phonetic && syllable.bits() & 0x07ff == 0 {
            return Err(ReadingCodecError::MissingPhonetic);
        }
        qstring.push_str(&syllable.query_key());
        normalized.push(syllable.display_text());
    }
    if normalized.is_empty() && options.empty == EmptySyllablePolicy::Reject {
        return Err(ReadingCodecError::EmptySyllable);
    }
    Ok(CodecResult {
        qstring,
        reading: normalized.join(match options.separator {
            EncodeSeparator::Comma => ",",
            EncodeSeparator::Whitespace => " ",
        }),
        syllable_count: normalized.len(),
    })
}

/// Decode shared model query keys without accessing a database or session.
/// PrintableModulo intentionally accepts 6160..6240 and normalizes their
/// components modulo 6160. Bytes below '0', DEL, non-ASCII and NUL are rejected;
/// the old decoder's negative-shift/invalid-map behavior is not reproduced.
pub fn decode_reading(
    qstring: &str,
    options: &DecodeOptions,
) -> Result<CodecResult, ReadingCodecError> {
    if qstring.contains('\0') {
        return Err(ReadingCodecError::EmbeddedNul);
    }
    let bytes = qstring.as_bytes();
    if bytes.len() % 2 != 0 && options.odd_tail == OddTailPolicy::Reject {
        return Err(ReadingCodecError::OddQueryLength);
    }
    let separator = match options.separator {
        DecodeSeparator::Comma => ",",
        DecodeSeparator::Space => " ",
    };
    let mut reading = String::new();
    for (index, pair) in bytes.chunks_exact(2).enumerate() {
        if pair.iter().any(|byte| !(48..=126).contains(byte)) {
            return Err(ReadingCodecError::InvalidQueryKey);
        }
        let order = usize::from(pair[0] - 48) + usize::from(pair[1] - 48) * 79;
        let order = match options.query {
            QueryPolicy::Canonical if order >= BopomofoSyllable::COUNT => {
                return Err(ReadingCodecError::InvalidQueryKey)
            }
            QueryPolicy::Canonical => order,
            QueryPolicy::PrintableModulo => order % BopomofoSyllable::COUNT,
        };
        let syllable = BopomofoSyllable::from_absolute_order(order)
            .ok_or(ReadingCodecError::InvalidQueryKey)?;
        if if options.omit_leading_empty {
            !reading.is_empty()
        } else {
            index > 0
        } {
            reading.push_str(separator);
        }
        reading.push_str(&syllable.display_text());
    }
    Ok(CodecResult {
        qstring: qstring.into(),
        reading,
        syllable_count: bytes.len() / 2,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn strict_encoding() -> EncodeOptions {
        EncodeOptions {
            separator: EncodeSeparator::Whitespace,
            components: ComponentPolicy::UniqueKnown,
            empty: EmptySyllablePolicy::Reject,
            require_phonetic: true,
        }
    }

    #[test]
    fn composed_reading_uses_known_shared_query_bytes_and_canonical_display() {
        let converted = encode_reading("ㄋㄧˇ,ㄏㄠˇ", &EncodeOptions::default()).unwrap();
        assert_eq!(converted.qstring, r"\O:W");
        assert_eq!(converted.reading, "ㄋㄧˇ,ㄏㄠˇ");
        assert_eq!(converted.syllable_count, 2);
        assert_eq!(
            decode_reading(&converted.qstring, &DecodeOptions::default()).unwrap(),
            converted
        );
    }

    #[test]
    fn compatible_encoding_replaces_known_classes_ignores_unknown_and_skips_empty_parts() {
        let converted =
            encode_reading(",,ㄅㄆㄧ?ㄨˊˇ,unknown,,ˇㄧㄋ,", &EncodeOptions::default()).unwrap();
        assert_eq!(converted.reading, "ㄆㄨˇ,ㄋㄧˇ");
        assert_eq!(converted.syllable_count, 2);
        assert_eq!(
            converted.qstring,
            encode_reading("ㄆㄨˇ,ㄋㄧˇ", &EncodeOptions::default())
                .unwrap()
                .qstring
        );
        assert_eq!(
            encode_reading("ㄋㄧˇ ㄏㄠˇ", &EncodeOptions::default())
                .unwrap()
                .reading,
            "ㄏㄧㄠˇ"
        );
        assert_eq!(
            encode_reading("ㄋㄧˇ，ㄏㄠˇ", &EncodeOptions::default())
                .unwrap()
                .syllable_count,
            1
        );
        assert_eq!(
            encode_reading("", &EncodeOptions::default())
                .unwrap()
                .syllable_count,
            0
        );
    }

    #[test]
    fn required_comma_parts_trim_edges_but_never_drop_empty_or_unknown_syllables() {
        let options = EncodeOptions {
            empty: EmptySyllablePolicy::Reject,
            ..EncodeOptions::default()
        };
        assert_eq!(
            encode_reading(" \tㄋㄧˇ\r\n, ㄏㄠˇ ", &options)
                .unwrap()
                .qstring,
            r"\O:W"
        );
        for bad in [
            "",
            ",ㄋㄧˇ",
            "ㄋㄧˇ,",
            "ㄋㄧˇ,,ㄏㄠˇ",
            "ㄋㄧˇ,\t",
            "unknown",
        ] {
            assert_eq!(
                encode_reading(bad, &options),
                Err(ReadingCodecError::EmptySyllable),
                "{bad:?}"
            );
        }
    }

    #[test]
    fn unique_components_reject_duplicate_classes_and_unknown_input() {
        let options = strict_encoding();
        for bad in ["ㄅㄆ", "ㄋㄋ", "ㄧㄨ", "ㄚㄛ", "ˊˇ", "ㄋㄧˇˇ"] {
            assert!(
                matches!(
                    encode_reading(bad, &options),
                    Err(ReadingCodecError::DuplicateComponent(_))
                ),
                "{bad}"
            );
        }
        for bad in ["ㄋx", "su3", "ㄋ，ㄏ", "ㄋ\u{3000}ㄏ"] {
            assert!(
                matches!(
                    encode_reading(bad, &options),
                    Err(ReadingCodecError::UnknownComponent(_))
                ),
                "{bad}"
            );
        }
        assert_eq!(encode_reading("ˇㄧㄋ", &options).unwrap().reading, "ㄋㄧˇ");
    }

    #[test]
    fn tone_only_compatibility_and_phonetic_requirement_are_independent() {
        let converted = encode_reading("ˇ", &EncodeOptions::default()).unwrap();
        assert_eq!(converted.syllable_count, 1);
        assert_eq!(converted.reading, "ˇ");
        assert_eq!(
            decode_reading(&converted.qstring, &DecodeOptions::default())
                .unwrap()
                .reading,
            "ˇ"
        );
        let required = EncodeOptions {
            require_phonetic: true,
            ..EncodeOptions::default()
        };
        assert_eq!(
            encode_reading("ˇ", &required),
            Err(ReadingCodecError::MissingPhonetic)
        );
    }

    #[test]
    fn whitespace_syntax_preserves_classic_ascii_boundaries_without_a_phrase_length_limit() {
        let options = strict_encoding();
        for separator in [' ', '\t', '\r', '\n', '\u{000b}', '\u{000c}'] {
            assert_eq!(
                encode_reading(
                    &format!("{separator}ㄋㄧˇ{separator}ㄏㄠˇ{separator}"),
                    &options
                )
                .unwrap()
                .qstring,
                r"\O:W"
            );
        }
        let nine = ["ㄋㄧˇ"; 9].join(" ");
        assert_eq!(encode_reading(&nine, &options).unwrap().syllable_count, 9);
        assert_eq!(
            encode_reading(" \t\r\n", &options),
            Err(ReadingCodecError::EmptySyllable)
        );
    }

    #[test]
    fn every_canonical_query_pair_round_trips_through_composed_glyphs() {
        let options = DecodeOptions {
            query: QueryPolicy::Canonical,
            ..DecodeOptions::default()
        };
        for order in 0..BopomofoSyllable::COUNT {
            let query: String = [
                char::from(48 + (order % 79) as u8),
                char::from(48 + (order / 79) as u8),
            ]
            .into_iter()
            .collect();
            let decoded = decode_reading(&query, &options).unwrap();
            assert_eq!(decoded.qstring, query);
            assert_eq!(decoded.syllable_count, 1);
            let encoded = encode_reading(&decoded.reading, &EncodeOptions::default()).unwrap();
            if order == 0 {
                assert!(encoded.qstring.is_empty());
                assert_eq!(encoded.syllable_count, 0);
            } else {
                assert_eq!(encoded.qstring, query, "{order}");
                assert_eq!(encoded.syllable_count, 1);
            }
        }
    }

    #[test]
    fn printable_overflow_queries_keep_legacy_component_modulo_only_when_selected() {
        assert_eq!(
            decode_reading("}}", &DecodeOptions::default())
                .unwrap()
                .reading,
            ""
        );
        assert_eq!(
            decode_reading("~~", &DecodeOptions::default())
                .unwrap()
                .reading,
            "ㄒㄩ"
        );
        let canonical = DecodeOptions {
            query: QueryPolicy::Canonical,
            ..DecodeOptions::default()
        };
        for query in ["}}", "~~"] {
            assert_eq!(
                decode_reading(query, &canonical),
                Err(ReadingCodecError::InvalidQueryKey)
            );
        }
    }

    #[test]
    fn empty_syllable_display_policy_omits_only_leading_empty_text() {
        let query = "00\\O00:W00";
        let all = decode_reading(query, &DecodeOptions::default()).unwrap();
        assert_eq!(all.reading, ",ㄋㄧˇ,,ㄏㄠˇ,");
        assert_eq!(all.syllable_count, 5);
        let spaced = DecodeOptions {
            separator: DecodeSeparator::Space,
            query: QueryPolicy::Canonical,
            omit_leading_empty: true,
            ..DecodeOptions::default()
        };
        assert_eq!(
            decode_reading(query, &spaced).unwrap().reading,
            "ㄋㄧˇ  ㄏㄠˇ "
        );
        assert_eq!(decode_reading("0000", &spaced).unwrap().reading, "");
    }

    #[test]
    fn odd_query_tail_is_explicit_and_ignored_tail_does_not_change_original_query() {
        assert_eq!(
            decode_reading(r"\O!", &DecodeOptions::default()),
            Err(ReadingCodecError::OddQueryLength)
        );
        let ignore = DecodeOptions {
            odd_tail: OddTailPolicy::Ignore,
            ..DecodeOptions::default()
        };
        let converted = decode_reading(r"\O!", &ignore).unwrap();
        assert_eq!(converted.qstring, r"\O!");
        assert_eq!(converted.reading, "ㄋㄧˇ");
        assert_eq!(converted.syllable_count, 1);
        assert_eq!(decode_reading("!", &ignore).unwrap().reading, "");
    }

    #[test]
    fn invalid_query_bytes_and_embedded_nul_are_safe_errors() {
        for query in ["//", "\u{007f}0", "é", "ㄋ"] {
            assert!(
                decode_reading(query, &DecodeOptions::default()).is_err(),
                "{query:?}"
            );
        }
        assert_eq!(
            encode_reading("ㄋ\0ㄧ", &EncodeOptions::default()),
            Err(ReadingCodecError::EmbeddedNul)
        );
        assert_eq!(
            decode_reading("\0\0", &DecodeOptions::default()),
            Err(ReadingCodecError::EmbeddedNul)
        );
    }

    #[test]
    fn serialized_options_are_strict_and_omissions_keep_compatibility_defaults() {
        assert_eq!(
            serde_json::from_str::<EncodeOptions>("{}").unwrap(),
            EncodeOptions::default()
        );
        assert_eq!(
            serde_json::from_str::<DecodeOptions>("{}").unwrap(),
            DecodeOptions::default()
        );
        assert!(serde_json::from_str::<EncodeOptions>(r#"{"components":"unknown"}"#).is_err());
        assert!(serde_json::from_str::<DecodeOptions>(r#"{"query":"unknown"}"#).is_err());
        assert!(serde_json::from_str::<EncodeOptions>(r#"{"unexpected":true}"#).is_err());
        assert!(serde_json::from_str::<DecodeOptions>(r#"{"unexpected":true}"#).is_err());
        let options: EncodeOptions = serde_json::from_str(r#"{"separator":"whitespace","components":"unique_known","empty":"reject","require_phonetic":true}"#).unwrap();
        assert_eq!(options, strict_encoding());
        assert_eq!(
            serde_json::to_value(EncodeOptions::default()).unwrap()["components"],
            "replace_known"
        );
    }
}
