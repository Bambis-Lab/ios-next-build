import unittest

from run_xcode_tests_verified import verify_summary


class VerifyXcodeSummaryTests(unittest.TestCase):
    def summary(self, **overrides):
        data = {
            "result": "Passed",
            "totalTestCount": 3,
            "passedTests": 2,
            "skippedTests": 1,
            "failedTests": 0,
            "finishTime": "2026-10-12T09:50:00Z",
        }
        data.update(overrides)
        return data

    def test_accepts_finished_all_passed_summary(self):
        ok, _ = verify_summary(self.summary())
        self.assertTrue(ok)

    def test_rejects_failed_test(self):
        ok, _ = verify_summary(self.summary(passedTests=2, skippedTests=0,
                                            totalTestCount=3, failedTests=1))
        self.assertFalse(ok)

    def test_rejects_incomplete_test_accounting(self):
        ok, _ = verify_summary(self.summary(totalTestCount=3, passedTests=1,
                                            skippedTests=0, failedTests=0))
        self.assertFalse(ok)

    def test_rejects_unfinished_summary(self):
        ok, _ = verify_summary(self.summary(finishTime=None))
        self.assertFalse(ok)

    def test_rejects_unrecognized_result(self):
        ok, _ = verify_summary(self.summary(result="Testing"))
        self.assertFalse(ok)

    def test_rejects_missing_counts(self):
        ok, _ = verify_summary({"result": "Passed", "finishTime": "done"})
        self.assertFalse(ok)


if __name__ == "__main__":
    unittest.main()
