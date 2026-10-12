import unittest

from run_xcode_tests_verified import verify_summary


class VerifyXcodeSummaryTests(unittest.TestCase):
    def summary(self, **overrides):
        data = {
            "result": "Passed",
            "totalTestCount": 3,
            "passedTests": 2,
            "skippedTests": 1,
            "expectedFailures": 0,
            "failedTests": 0,
        }
        data.update(overrides)
        return data

    def test_accepts_finished_all_passed_summary_without_optional_timestamp(self):
        ok, _ = verify_summary(self.summary())
        self.assertTrue(ok)

    def test_accepts_expected_failure_when_accounted_by_summary(self):
        ok, _ = verify_summary(self.summary(totalTestCount=3, passedTests=2,
                                            skippedTests=0, expectedFailures=1))
        self.assertTrue(ok)

    def test_rejects_failed_test(self):
        ok, _ = verify_summary(self.summary(passedTests=2, skippedTests=0,
                                            totalTestCount=3, failedTests=1))
        self.assertFalse(ok)

    def test_rejects_incomplete_test_accounting(self):
        ok, _ = verify_summary(self.summary(totalTestCount=3, passedTests=1,
                                            skippedTests=0, failedTests=0))
        self.assertFalse(ok)

    def test_rejects_unrecognized_result(self):
        ok, _ = verify_summary(self.summary(result="Testing"))
        self.assertFalse(ok)

    def test_rejects_missing_counts(self):
        ok, _ = verify_summary({"result": "Passed"})
        self.assertFalse(ok)

    def test_rejects_missing_total_count(self):
        data = self.summary()
        data.pop("totalTestCount")
        ok, _ = verify_summary(data)
        self.assertFalse(ok)


if __name__ == "__main__":
    unittest.main()
