//! Frontend-supplied candidate eligibility, independent of native font APIs.
//!
//! Copyright (c) 2026 Chui-Ping Cheng. MIT License.
use std::fmt;
use std::sync::Arc;

/// A stable policy shared by a session and its cloned graph/cache state.
///
/// Frontends may check font coverage or a selected encoding. The predicate must
/// remain deterministic for the session lifetime; install a new policy by opening
/// a new session at the frontend's safe boundary. Empty model sentinel text is
/// always accepted without calling the predicate.
#[derive(Clone)]
pub struct CandidateFilter(Arc<dyn Fn(&str) -> bool + Send + Sync>);

impl CandidateFilter {
    pub fn new<F>(accepts: F) -> Self
    where
        F: Fn(&str) -> bool + Send + Sync + 'static,
    {
        Self(Arc::new(accepts))
    }

    pub fn accepts(&self, text: &str) -> bool {
        text.is_empty() || (self.0)(text)
    }
}

impl Default for CandidateFilter {
    fn default() -> Self {
        Self::new(|_| true)
    }
}

impl fmt::Debug for CandidateFilter {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("CandidateFilter")
            .finish_non_exhaustive()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn policy_is_cloneable_and_preserves_empty_model_sentinels() {
        let filter = CandidateFilter::new(|text| text == "喬");
        assert!(filter.accepts(""));
        assert!(filter.clone().accepts("喬"));
        assert!(!filter.accepts("𥫜"));
        assert!(CandidateFilter::default().accepts("𥫜"));
    }
}
