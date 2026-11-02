mod support;

use guanyinma::{ModelDatabase, Table};
use std::path::PathBuf;

fn canonical_database() -> PathBuf {
    support::model_path()
}

#[test]
fn real_table_sources_keep_their_original_order() {
    let database = ModelDatabase::open(canonical_database()).unwrap();
    let traditional = database.lookup_table(Table::Traditional, r"\O").unwrap();
    assert_eq!(&traditional[..3], ["你", "妳", "擬"]);
    assert_eq!(
        database.lookup_table(Table::Cangjie, "a").unwrap(),
        ["日", "曰"]
    );
    let simplex = database.lookup_table(Table::Simplex, "ab").unwrap();
    assert!(
        simplex.len() > 9,
        "the data layer must not trim results to one page"
    );
    assert_eq!(&simplex[..4], ["明", "晞", "晴", "閒"]);
}

#[test]
fn real_language_model_preserves_scores_and_boundary_rows() {
    let database = ModelDatabase::open(canonical_database()).unwrap();
    let rows = database.unigrams(r"\O").unwrap();
    let ni = rows.iter().find(|entry| entry.current == "你").unwrap();
    assert_eq!(ni.qstring, r"\O");
    assert!(ni.probability.is_finite() && ni.probability < 0.0);
    assert!(ni.backoff.is_finite());
    let bos = database.unigrams("!").unwrap();
    assert_eq!(bos.len(), 1);
    assert!(bos[0].current.is_empty(), "BOS has a legitimate empty word");
    let bigrams = database.bigrams(r"! \O").unwrap();
    assert!(!bigrams.is_empty());
    assert!(bigrams.iter().all(|row| row.previous.is_empty()));
    assert!(bigrams.iter().any(|row| row.current == "你"));
}

#[test]
fn bound_keys_do_not_change_the_query_and_empty_property_values_survive() {
    let database = ModelDatabase::open(canonical_database()).unwrap();
    assert!(database
        .lookup_table(Table::Cangjie, "a' OR 1=1 --")
        .unwrap()
        .is_empty());
    assert!(database.unigrams("not-a-model-reading").unwrap().is_empty());
    assert!(database
        .lookup_table(Table::Simplex, "")
        .unwrap()
        .is_empty());
    assert_eq!(
        database
            .lookup_table(Table::Cangjie, "__property_gen_inp")
            .unwrap(),
        [""]
    );
}
