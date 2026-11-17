//! Platform-independent scaling for painted keycaps and keyboard labels.

pub fn keycap_scale(area_ratio: f64) -> Option<f64> {
    (0.0..=1.0).contains(&area_ratio).then(|| area_ratio.sqrt())
}

pub fn key_font_size(level: u32, regular_fit: f64, largest_fit: f64) -> Option<f64> {
    if !regular_fit.is_finite()
        || !largest_fit.is_finite()
        || regular_fit < 0.0
        || largest_fit < 0.0
    {
        return None;
    }
    let largest = largest_fit.max(0.01);
    let regular = regular_fit.min(largest).max(0.01);
    // Equal proportional growth between the two measured endpoints.
    match level {
        0 => Some(regular),
        1 | 2 => {
            let fraction = f64::from(level) / 3.0;
            let growth = ((largest.ln() - regular.ln()) * fraction).exp();
            Some((regular * growth).min(largest))
        }
        3 => Some(largest),
        _ => None,
    }
}

pub fn strip_font_scale(level: u32) -> Option<f64> {
    [1.0, 1.15, 1.30, 1.45].get(level as usize).copied()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn visible_keycaps_shrink_proportionally_in_both_axes() {
        assert_eq!(keycap_scale(1.0), Some(1.0));
        assert_eq!(keycap_scale(0.0), Some(0.0));
        for area_ratio in [0.90, 0.80] {
            let scale = keycap_scale(area_ratio).unwrap();
            assert!((scale * scale - area_ratio).abs() < 1e-12);
        }
        assert_eq!(keycap_scale(-0.01), None);
        assert_eq!(keycap_scale(1.01), None);
        assert_eq!(keycap_scale(f64::NAN), None);
    }

    #[test]
    fn font_levels_follow_both_measured_endpoints() {
        for (level, expected) in [12.0, 24.0, 48.0, 96.0].into_iter().enumerate() {
            assert!((key_font_size(level as u32, 12.0, 96.0).unwrap() - expected).abs() < 1e-12);
        }
        assert_eq!(key_font_size(0, 60.0, 40.0), Some(40.0));
        assert_eq!(key_font_size(1, 0.0, 0.0), Some(0.01));
        let large = key_font_size(2, 0.01, f64::MAX).unwrap();
        assert!(large.is_finite() && large > 0.01 && large < f64::MAX);
        assert_eq!(key_font_size(4, 12.0, 96.0), None);
        assert_eq!(key_font_size(0, -1.0, 96.0), None);
        assert_eq!(key_font_size(0, 12.0, -1.0), None);
        assert_eq!(key_font_size(0, f64::NAN, 96.0), None);
        assert_eq!(key_font_size(0, 12.0, f64::INFINITY), None);
    }

    #[test]
    fn strip_font_scales_are_independent_of_key_fit() {
        for (level, expected) in [1.0, 1.15, 1.30, 1.45].into_iter().enumerate() {
            assert_eq!(strip_font_scale(level as u32), Some(expected));
        }
        assert_eq!(strip_font_scale(4), None);
    }
}
