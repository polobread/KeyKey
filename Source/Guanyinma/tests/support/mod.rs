//! Shared, UI-free model location for native and target-runner tests.
//! Copyright (c) 2026 Chui-Ping Cheng. MIT License.
use std::path::PathBuf;

pub(crate) fn model_path() -> PathBuf {
    match std::env::var_os("GUANYINMA_TEST_MODEL_PATH") {
        Some(path) => {
            assert!(
                !path.is_empty(),
                "GUANYINMA_TEST_MODEL_PATH must not be empty"
            );
            PathBuf::from(path)
        }
        None => PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../Distributions/Takao/CookedDatabase/KeyKey.db"),
    }
}
