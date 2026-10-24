"""Regression tests for strict G99 acceptance log classification."""
import unittest

from check_fam_g99_ui_run import is_full_pass, is_infrastructure_only, mandatory_names


class G99LogClassificationTests(unittest.TestCase):
    @staticmethod
    def _passing_log():
        lines = [
            f"Test Case '-[IOSNextUITests.IOSNextUITests {name}]' passed (1.000 seconds)."
            for name in mandatory_names()
        ]
        return "\n".join(lines + [
            "Executed 10 tests, with 0 failures (0 unexpected)",
            "Test Suite 'Selected tests' passed",
            "** TEST EXECUTE SUCCEEDED **",
        ])

    @staticmethod
    def _timeout_log():
        test = "testAccessibilityCoreScreenRenders"
        return "\n".join([
            f"/tmp/X.swift:30: error: -[IOSNextUITests.IOSNextUITests {test}] : Failed to launch <XCUIApplicationImpl> via Xcode: Timed out while launching application via Xcode.",
            f"Test Case '-[IOSNextUITests.IOSNextUITests {test}]' failed (139.854 seconds).",
            "** TEST EXECUTE FAILED **",
        ])

    def test_only_exact_app_launch_timeout_is_retryable(self):
        self.assertTrue(is_infrastructure_only(self._timeout_log()))
        self.assertFalse(is_infrastructure_only(self._timeout_log().replace("Timed out while launching application via Xcode.", "Product screen did not render.")))
        self.assertFalse(is_infrastructure_only(self._timeout_log() + "\nXCTAssertTrue failed"))
        self.assertFalse(is_infrastructure_only(self._timeout_log() + "\nTest Case '-[IOSNextUITests.IOSNextUITests testChatComposerInteraction]' failed (1.000 seconds)."))
        self.assertFalse(is_infrastructure_only(self._timeout_log().replace("TEST EXECUTE FAILED", "TEST EXECUTE SUCCEEDED")))

    def test_all_ten_required_selectors_must_pass(self):
        log = self._passing_log()
        self.assertTrue(is_full_pass(log))
        self.assertFalse(is_full_pass(log.replace("** TEST EXECUTE SUCCEEDED **", "")))
        self.assertFalse(is_full_pass(log.replace("Test Case '-[IOSNextUITests.IOSNextUITests testChatComposerInteraction]' passed", "Test Case '-[IOSNextUITests.IOSNextUITests testChatComposerInteraction]' skipped")))
        self.assertFalse(is_full_pass(log + "\nTest Case '-[IOSNextUITests.IOSNextUITests testAccessibilityCoreScreenRenders]' failed (1.00 seconds)."))


if __name__ == "__main__":
    unittest.main()
