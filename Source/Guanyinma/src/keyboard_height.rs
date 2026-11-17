//! Coordinate-only geometry for a keyboard whose lower edge can leave clearance.
//!
//! Coordinates increase upward from the usable bottom. The caller chooses the
//! units and supplies the constraints and window geometry for each operation.

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct KeyboardEdges {
    pub top: f64,
    pub bottom: f64,
}

#[derive(Clone, Copy)]
pub enum KeyboardEdge {
    Top,
    Bottom,
}

#[derive(Clone, Copy)]
pub struct KeyboardHeightLimits {
    pub minimum_content: f64,
    pub maximum_content: f64,
    pub maximum_top: f64,
    pub maximum_gap: f64,
}

impl KeyboardEdges {
    pub fn drag(
        self,
        edge: KeyboardEdge,
        delta: f64,
        limits: KeyboardHeightLimits,
    ) -> Option<Self> {
        if !delta.is_finite()
            || !valid_sizes([
                self.top,
                self.bottom,
                limits.minimum_content,
                limits.maximum_content,
                limits.maximum_top,
                limits.maximum_gap,
            ])
            || self.bottom > self.top
            || limits.minimum_content > limits.maximum_content
        {
            return None;
        }

        let edges = match edge {
            KeyboardEdge::Top => {
                let minimum = self.bottom + limits.minimum_content;
                let maximum = limits.maximum_top.min(self.bottom + limits.maximum_content);
                let top = moved_edge(self.top, delta, minimum, maximum)?;
                Self { top, ..self }
            }
            KeyboardEdge::Bottom => {
                let minimum = (self.top - limits.maximum_content).max(0.0);
                let maximum = limits.maximum_gap.min(self.top - limits.minimum_content);
                let bottom = moved_edge(self.bottom, delta, minimum, maximum)?;
                Self { bottom, ..self }
            }
        };
        Some(edges)
    }
}

/// Fit keys and their clearance in a window. Reserve clearance only to the
/// extent that it leaves room for the minimum usable content.
pub fn fit_keyboard_height(
    desired_content: f64,
    desired_gap: f64,
    window_height: f64,
    system_space: f64,
    minimum_content: f64,
) -> Option<KeyboardEdges> {
    if !valid_sizes([
        desired_content,
        desired_gap,
        window_height,
        system_space,
        minimum_content,
    ]) {
        return None;
    }
    let available = (window_height - system_space).max(0.0);
    let minimum = desired_content.min(minimum_content);
    let bottom = desired_gap.min((available - minimum).max(0.0));
    let top = available.min(desired_content + bottom);
    Some(KeyboardEdges { top, bottom })
}

fn valid_sizes<const N: usize>(values: [f64; N]) -> bool {
    values
        .into_iter()
        .all(|size| size.is_finite() && size >= 0.0)
}

fn moved_edge(start: f64, delta: f64, minimum: f64, maximum: f64) -> Option<f64> {
    (minimum <= maximum).then(|| (start + delta).clamp(minimum, maximum))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn edges(top: f64, bottom: f64) -> KeyboardEdges {
        KeyboardEdges { top, bottom }
    }

    #[test]
    fn dragging_changes_only_the_selected_edge_and_honors_its_limits() {
        let limits = KeyboardHeightLimits {
            minimum_content: 165.0,
            maximum_content: 660.0,
            maximum_top: 700.0,
            maximum_gap: 72.0,
        };
        let start = edges(330.0, 0.0);
        assert_eq!(
            start.drag(KeyboardEdge::Bottom, 20.0, limits),
            Some(edges(330.0, 20.0))
        );
        assert_eq!(start.drag(KeyboardEdge::Bottom, -40.0, limits), Some(start));
        assert_eq!(
            start.drag(KeyboardEdge::Bottom, 100.0, limits),
            Some(edges(330.0, 72.0))
        );
        let elevated = edges(340.0, 30.0);
        assert_eq!(
            elevated.drag(KeyboardEdge::Top, -300.0, limits),
            Some(edges(195.0, 30.0))
        );
        assert_eq!(
            elevated.drag(KeyboardEdge::Top, 700.0, limits),
            Some(edges(690.0, 30.0))
        );
        assert_eq!(
            edges(700.0, 72.0).drag(KeyboardEdge::Top, 40.0, limits),
            Some(edges(700.0, 72.0))
        );
        assert_eq!(
            edges(700.0, 72.0).drag(KeyboardEdge::Bottom, -40.0, limits),
            Some(edges(700.0, 40.0))
        );
        assert_eq!(
            edges(185.0, 10.0).drag(KeyboardEdge::Bottom, 50.0, limits),
            Some(edges(185.0, 20.0))
        );
    }

    #[test]
    fn callers_can_use_fractional_anchors_and_a_shorter_real_window() {
        let limits = KeyboardHeightLimits {
            minimum_content: 0.75,
            maximum_content: 1.35,
            maximum_top: 1.40,
            maximum_gap: 0.25,
        };
        assert_eq!(
            edges(1.0, 0.0).drag(KeyboardEdge::Bottom, 0.125, limits),
            Some(edges(1.0, 0.125))
        );
        assert_eq!(
            edges(1.25, 0.125).drag(KeyboardEdge::Top, 0.5, limits),
            Some(edges(1.4, 0.125))
        );
        let capped = KeyboardHeightLimits {
            minimum_content: 89.0,
            maximum_content: 660.0,
            maximum_top: 89.0,
            maximum_gap: 72.0,
        };
        assert_eq!(
            edges(89.0, 0.0).drag(KeyboardEdge::Top, 20.0, capped),
            Some(edges(89.0, 0.0))
        );
    }

    #[test]
    fn the_actual_window_determines_fitted_edges_even_after_a_shorter_probe() {
        for gap in [0.0, 42.0] {
            let probe = fit_keyboard_height(866.0, gap, 929.0 + gap, 126.0, 433.0);
            let actual = fit_keyboard_height(866.0, gap, 992.0 + gap, 126.0, 433.0);
            assert_eq!(probe, Some(edges(803.0 + gap, gap)));
            assert_eq!(actual, Some(edges(866.0 + gap, gap)));
        }
    }

    #[test]
    fn a_small_window_reduces_the_gap_before_sacrificing_minimum_content() {
        assert_eq!(
            fit_keyboard_height(330.0, 48.0, 219.0, 24.0, 165.0),
            Some(edges(195.0, 30.0))
        );
        assert_eq!(
            fit_keyboard_height(330.0, 48.0, 164.0, 24.0, 165.0),
            Some(edges(140.0, 0.0))
        );
        assert_eq!(
            fit_keyboard_height(330.0, 48.0, 15.0, 24.0, 165.0),
            Some(edges(0.0, 0.0))
        );
        // The host can choose a smaller requested height than its policy minimum.
        assert_eq!(
            fit_keyboard_height(100.0, 40.0, 150.0, 20.0, 165.0),
            Some(edges(130.0, 30.0))
        );
        assert_eq!(
            fit_keyboard_height(100.0, 20.0, 180.0, 0.0, 75.0),
            Some(edges(120.0, 20.0))
        );
    }

    #[test]
    fn rejects_invalid_sizes_and_infeasible_drag_bounds() {
        let limits = KeyboardHeightLimits {
            minimum_content: 165.0,
            maximum_content: 660.0,
            maximum_top: 700.0,
            maximum_gap: 72.0,
        };
        assert_eq!(
            edges(330.0, 0.0).drag(KeyboardEdge::Top, f64::NAN, limits),
            None
        );
        assert_eq!(
            edges(330.0, 340.0).drag(KeyboardEdge::Top, 0.0, limits),
            None
        );
        assert_eq!(
            edges(100.0, 0.0).drag(KeyboardEdge::Bottom, 20.0, limits),
            None
        );
        assert_eq!(
            edges(330.0, 0.0).drag(
                KeyboardEdge::Top,
                0.0,
                KeyboardHeightLimits {
                    maximum_content: 100.0,
                    ..limits
                },
            ),
            None
        );
        assert_eq!(fit_keyboard_height(330.0, -1.0, 480.0, 0.0, 165.0), None);
        assert_eq!(
            fit_keyboard_height(330.0, 0.0, f64::INFINITY, 0.0, 165.0),
            None
        );
    }
}
