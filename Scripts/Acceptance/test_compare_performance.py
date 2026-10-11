#!/usr/bin/env python3
"""Synthetic fixtures ONLY for validation of comparison math, not iOS benchmarks."""
import unittest
from compare_performance import compare, load
import tempfile
import json
from pathlib import Path

class PerformanceComparisonTests(unittest.TestCase):
    def payload(self, p95):
        return {
            "schema": "iosnext.perf.v1",
            "environment": {"device": "synthetic", "os": "fixture", "mode": "fixture", "fixture": "unit-test"},
            "scenarios": {"Nico.Open": {"p50_ms": 25.0, "p95_ms": p95}}
        }

    def test_accepts_equal_or_faster(self):
        a, b = self.payload(100), self.payload(70)
        self.assertEqual(compare(a, b, 0.05)["Nico.Open"]["p95_gate"], "PASS")
        self.assertEqual(compare(a, b, 0.05)["Nico.Open"]["delta_percent"]["p95_ms"], -30)

    def test_rejects_regression(self):
        a, b = self.payload(100), self.payload(111)
        self.assertEqual(compare(a, b, 0.05)["Nico.Open"]["p95_gate"], "FAIL")

    def test_rejects_mismatched_environment(self):
        a, b = self.payload(100), self.payload(90)
        b["environment"]["device"] = "different"
        with self.assertRaises(ValueError):
            compare(a, b, 0.05)

    def test_rejects_absent_measurement(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "metric.json"
            path.write_text(json.dumps({"schema":"iosnext.perf.v1","scenarios":{}}))
            with self.assertRaises(ValueError):
                load(path)

if __name__ == "__main__":
    unittest.main()
