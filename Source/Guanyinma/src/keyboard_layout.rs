//! Horizontal key slots from the width and row policy measured by a frontend.

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct KeyboardSlot {
    pub left: f64,
    pub right: f64,
}

#[derive(Clone, Copy)]
pub struct KeyboardRowLayout {
    pub width: f64,
    pub spacing: f64,
    pub leading_units: f64,
    pub total_units: f64,
    pub split_index: usize,
    pub split_gap: f64,
}

impl KeyboardRowLayout {
    pub fn slots(self, weights: &[f64]) -> Option<Vec<KeyboardSlot>> {
        if weights.is_empty()
            || ![
                self.width,
                self.spacing,
                self.leading_units,
                self.total_units,
                self.split_gap,
            ]
            .into_iter()
            .chain(weights.iter().copied())
            .all(|value| value.is_finite() && value >= 0.0)
            || self.width == 0.0
        {
            return None;
        }

        if self.total_units > 0.0 {
            return self.fixed_pitch_slots(weights);
        }
        if self.leading_units > 0.0 {
            return None;
        }

        let mut slots = Vec::with_capacity(weights.len());
        if self.split_index == 0 {
            append_group(&mut slots, weights, 0.0, self.width, self.spacing)?;
        } else {
            if self.split_index >= weights.len() || self.split_gap >= self.width {
                return None;
            }
            let (left, right) = weights.split_at(self.split_index);
            let half = (self.width - self.split_gap) / 2.0;
            append_group(&mut slots, left, 0.0, half, self.spacing)?;
            append_group(
                &mut slots,
                right,
                self.width - half,
                self.width,
                self.spacing,
            )?;
        }
        Some(slots)
    }

    /// Staggered rows use the same pitch over the whole plane. The last key
    /// may carry a fractional weight to reach its assigned column boundary.
    fn fixed_pitch_slots(self, weights: &[f64]) -> Option<Vec<KeyboardSlot>> {
        let units_used = self.leading_units + weights.iter().sum::<f64>();
        let pitch = (self.width + self.spacing) / self.total_units;
        if self.split_index != 0
            || !pitch.is_finite()
            || !units_used.is_finite()
            || units_used > self.total_units * (1.0 + 1e-12)
        {
            return None;
        }

        let mut units = self.leading_units;
        Some(
            weights
                .iter()
                .map(|weight| {
                    let left = (units * pitch).min(self.width);
                    let right = (left + (weight * pitch - self.spacing).max(0.0)).min(self.width);
                    units += weight;
                    KeyboardSlot { left, right }
                })
                .collect(),
        )
    }
}

fn append_group(
    slots: &mut Vec<KeyboardSlot>,
    weights: &[f64],
    left: f64,
    right: f64,
    spacing: f64,
) -> Option<()> {
    let total = weights.iter().sum::<f64>();
    if !total.is_finite() || total <= 0.0 {
        return None;
    }
    let width = right - left;
    let usable = (width - spacing * (weights.len() - 1) as f64).max(0.0);
    let mut x = left;
    for (index, weight) in weights.iter().enumerate() {
        let end = if index == weights.len() - 1 {
            right
        } else {
            (x + usable * (weight / total)).min(right)
        };
        slots.push(KeyboardSlot {
            left: x,
            right: end,
        });
        x = (end + spacing).min(right);
    }
    Some(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(width: f64) -> KeyboardRowLayout {
        KeyboardRowLayout {
            width,
            spacing: 0.0,
            leading_units: 0.0,
            total_units: 0.0,
            split_index: 0,
            split_gap: 0.0,
        }
    }

    #[test]
    fn staggered_rows_share_one_pitch_and_allow_wide_end_controls() {
        let layout = KeyboardRowLayout {
            spacing: 3.0,
            leading_units: 1.0,
            total_units: 4.0,
            ..row(117.0)
        };
        let slots = layout.slots(&[1.0, 2.0]).unwrap();
        assert_eq!(
            slots[0],
            KeyboardSlot {
                left: 30.0,
                right: 57.0
            }
        );
        assert_eq!(
            slots[1],
            KeyboardSlot {
                left: 60.0,
                right: 117.0
            }
        );
    }

    #[test]
    fn aligned_row_divides_the_width_by_key_weights() {
        let layout = KeyboardRowLayout {
            spacing: 5.0,
            ..row(110.0)
        };
        let slots = layout.slots(&[1.0, 3.0, 1.0]).unwrap();
        assert_eq!(
            slots[0],
            KeyboardSlot {
                left: 0.0,
                right: 20.0
            }
        );
        assert_eq!(
            slots[1],
            KeyboardSlot {
                left: 25.0,
                right: 85.0
            }
        );
        assert_eq!(
            slots[2],
            KeyboardSlot {
                left: 90.0,
                right: 110.0
            }
        );
    }

    #[test]
    fn split_rows_keep_the_reserved_middle_on_narrow_and_wide_windows() {
        for (width, gap) in [(350.0, 35.0), (620.0, 62.0), (820.0, 80.0), (1280.0, 80.0)] {
            let layout = KeyboardRowLayout {
                split_index: 2,
                split_gap: gap,
                spacing: 2.0,
                ..row(width)
            };
            let slots = layout.slots(&[1.0, 2.0, 1.0, 1.0, 1.0]).unwrap();
            assert_eq!(slots[0].left, 0.0);
            assert_eq!(slots[1].right, (width - gap) / 2.0);
            assert_eq!(slots[2].left - slots[1].right, gap);
            assert_eq!(slots[4].right, width);
            assert!(slots.iter().all(|slot| slot.left < slot.right));
        }
    }

    #[test]
    fn a_very_small_window_keeps_slots_inside_its_bounds() {
        let layout = KeyboardRowLayout {
            spacing: 20.0,
            ..row(10.0)
        };
        let slots = layout.slots(&[1.0, 1.0, 1.0]).unwrap();
        assert!(slots
            .iter()
            .all(|slot| slot.left <= slot.right && slot.right <= 10.0));
    }

    #[test]
    fn rejects_invalid_rows_and_weights() {
        assert!(row(0.0).slots(&[1.0]).is_none());
        assert!(row(100.0).slots(&[]).is_none());
        assert!(row(100.0).slots(&[1.0, f64::NAN]).is_none());
        assert!(row(100.0).slots(&[0.0]).is_none());
        let layout = KeyboardRowLayout {
            split_index: 1,
            split_gap: 101.0,
            ..row(100.0)
        };
        assert!(layout.slots(&[1.0, 1.0]).is_none());
        let layout = KeyboardRowLayout {
            leading_units: 1.0,
            total_units: 1.0,
            ..row(100.0)
        };
        assert!(layout.slots(&[1.0]).is_none());
        let layout = KeyboardRowLayout {
            leading_units: 1.0,
            ..row(100.0)
        };
        assert!(layout.slots(&[1.0]).is_none());
    }
}
