"""Coverage accounting unit tests; no Rust build, UI, model or profile fixtures."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("guanyinma_coverage", Path(__file__).parents[1] / "test-coverage.py")
COVERAGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(COVERAGE)


class CoverageAccountingTests(unittest.TestCase):
    def test_test_helpers_modules_and_attributes_keep_later_production(self):
        source = '''fn before() {}
impl Example {
    #[cfg(test)]
    fn helper() {
        let raw = br###" } #[cfg(test)] { "###;
        let normal = "escaped \\" }";
        let brace = '}'; // } ignored
        /* outer { /* nested } */ } */
    }
    fn production_after_helper() {}
}
#[derive(Clone)]
#[cfg(test)]
mod tests {
    #[test]
    fn nested() { let value: &'static str = "{"; }
}
#[cfg(test)]
#[path = "support.rs"]
mod test_support;
fn after() {}
'''
        ranges = COVERAGE.test_only_ranges(source)
        excluded = lambda n: any(first <= n <= last for first, last in ranges)
        for index, line in enumerate(source.splitlines(), 1):
            if any(word in line for word in ("fn before", "production_after_helper", "fn after")):
                self.assertFalse(excluded(index), line)
            elif any(word in line for word in ("fn helper", "fn nested", "derive(Clone)", "mod test_support")):
                self.assertTrue(excluded(index), line)

    def test_unknown_cfg_and_mixed_line_items_fail_closed(self):
        for source in ["#[cfg(any(test, feature = \"x\"))]\nfn test_only() {}",
                       "#[cfg(test)] fn only_test() {} fn production() {}",
                       "#[cfg(test)]\nfn broken() { let s = r#\"missing; }"]:
            with self.subTest(source=source), self.assertRaises(ValueError):
                COVERAGE.test_only_ranges(source)

    def test_lcov_deduplicates_objects_and_excludes_tests_and_dependencies(self):
        with tempfile.TemporaryDirectory() as directory:
            path = (Path(directory) / "module.rs").resolve()
            source = "fn production() {}\n#[cfg(test)]\nfn test_helper() {}\nfn later() {}\n"
            raw = f"SF:{path}\nDA:1,0\nDA:3,15\nDA:4,0\nend_of_record\nSF:{path}\nDA:1,4\nDA:3,17\nend_of_record\nSF:/dependency.rs\nDA:1,100\nend_of_record\n"
            records, _ = COVERAGE.production_lines(raw, {path: source})
            self.assertEqual(records, {path: {1: 4, 4: 0}})

    def test_floor_uses_unrounded_percent_and_refuses_empty_denominator(self):
        self.assertTrue(COVERAGE.meets_floor(92, 100, 92))
        self.assertFalse(COVERAGE.meets_floor(91999, 100000, 92))
        self.assertTrue(COVERAGE.meets_floor(100, 100, 92))
        for args in [(0, 0, 92), (2, 1, 92), (1, 1, float("nan")), (1, 1, 101)]:
            with self.subTest(args=args), self.assertRaises(ValueError):
                COVERAGE.meets_floor(*args)


if __name__ == "__main__":
    unittest.main()
