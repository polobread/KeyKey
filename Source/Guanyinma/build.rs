//! Converts the existing shared Cangjie data headers into Rust constants.
//! This does not read, generate, or change KeyKey.db.
use std::collections::HashSet;
use std::env;
use std::fs;
use std::path::PathBuf;

fn body<'a>(source: &'a str, marker: &str) -> &'a str {
    let start = source
        .find(marker)
        .expect("shared Cangjie data marker is missing")
        + marker.len();
    let rest = &source[start..];
    let open = rest
        .find('{')
        .expect("shared Cangjie array has no opening brace");
    let rest = &rest[open + 1..];
    let end = rest
        .find("};")
        .expect("shared Cangjie array has no closing brace");
    &rest[..end]
}

fn pairs(source: &str, marker: &str) -> Vec<(u32, u32)> {
    let mut result: Vec<(u32, u32)> = Vec::new();
    for line in body(source, marker).lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with("//") {
            continue;
        }
        let row = line
            .strip_prefix('{')
            .and_then(|line| line.strip_suffix("},"))
            .expect("unexpected shared Cangjie pair syntax");
        let (first, second) = row
            .split_once(',')
            .expect("shared Cangjie pair has no comma");
        let scalar = |value: &str| {
            u32::from_str_radix(
                value
                    .trim()
                    .strip_prefix("0x")
                    .expect("shared Cangjie scalar must use hex"),
                16,
            )
            .expect("invalid shared Cangjie scalar")
        };
        let pair = (scalar(first), scalar(second));
        assert!(pair.0 <= 0x10ffff && pair.1 <= 0x10ffff);
        if let Some(previous) = result.last() {
            assert!(
                previous.0 < pair.0,
                "shared Cangjie data must be sorted and unique"
            );
        }
        result.push(pair);
    }
    assert!(!result.is_empty(), "shared Cangjie data must not be empty");
    result
}

fn main() {
    let shared = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap()).join("../Shared");
    let ranking_path = shared.join("CangjieRankingData.h");
    let unicode_path = shared.join("CangjieUnicodeData.h");
    for path in [&ranking_path, &unicode_path] {
        println!("cargo:rerun-if-changed={}", path.display());
    }
    let ranking = fs::read_to_string(ranking_path).expect("cannot read shared Cangjie ranks");
    let unicode =
        fs::read_to_string(unicode_path).expect("cannot read shared Cangjie Unicode data");
    let marker = "RankedCharacters[] = \"";
    let rest = &ranking[ranking
        .find(marker)
        .expect("shared Cangjie rank string is missing")
        + marker.len()..];
    let characters = &rest[..rest
        .find('"')
        .expect("shared Cangjie rank string is unterminated")];
    assert!(!characters.is_empty() && !characters.contains('\\'));
    let unique: HashSet<char> = characters.chars().collect();
    assert_eq!(
        unique.len(),
        characters.chars().count(),
        "shared ranks contain duplicate scalars"
    );
    let canonical = pairs(&unicode, "CanonicalCjk[]");
    for &(source, target) in &canonical {
        assert!(char::from_u32(source).is_some() && char::from_u32(target).is_some());
    }
    let excluded = pairs(&unicode, "ExcludedRanges[]");
    for &(start, end) in &excluded {
        assert!(start <= end, "invalid shared Unicode range");
    }
    for adjacent in excluded.windows(2) {
        assert!(
            adjacent[0].1 < adjacent[1].0,
            "shared Unicode ranges overlap"
        );
    }
    let output = format!(
        "// Generated from Source/Shared/CangjieRankingData.h and CangjieUnicodeData.h.\n\
         // Unicode-derived data retains Unicode License V3 (Source/Shared/Unicode-LICENSE.txt).\n\
         pub const RANKED_CHARACTERS: &str = {characters:?};\n\
         pub const CANONICAL_CJK: &[(u32, u32)] = &{canonical:?};\n\
         pub const EXCLUDED_RANGES: &[(u32, u32)] = &{excluded:?};\n"
    );
    let output_path = PathBuf::from(env::var_os("OUT_DIR").unwrap()).join("cangjie_data.rs");
    fs::write(output_path, output).expect("cannot write generated Cangjie Rust constants");
}
