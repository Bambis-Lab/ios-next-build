import subprocess
import sys
import unittest
from unittest.mock import MagicMock, patch
from boot_simulator import run_bounded, terminate_owned_process

class BoundedCleanupTests(unittest.TestCase):
    def test_real_subprocess_timeout(self):
        with self.assertRaisesRegex(RuntimeError, "timed out"):
            run_bounded([sys.executable, "-c", "import time; time.sleep(60)"], timeout=.1)

    def test_group_denied_falls_back_to_child(self):
        process=MagicMock()
        process.poll.return_value=None
        with patch("boot_simulator.os.killpg", side_effect=PermissionError):
            self.assertTrue(terminate_owned_process(process))
        process.send_signal.assert_called_once()
        process.wait.assert_called_once_with(timeout=3)

    def test_both_signals_denied_stays_bounded(self):
        process=MagicMock()
        process.poll.return_value=None
        process.send_signal.side_effect=PermissionError
        process.wait.side_effect=subprocess.TimeoutExpired("fixture",3)
        with patch("boot_simulator.os.killpg", side_effect=PermissionError):
            self.assertFalse(terminate_owned_process(process))
        self.assertEqual(process.wait.call_count,2)

    def test_timeout_preserved_when_group_signal_denied(self):
        process=MagicMock()
        process.poll.return_value=None
        process.communicate.side_effect=subprocess.TimeoutExpired("fixture",1)
        process.send_signal.side_effect=PermissionError
        process.wait.side_effect=subprocess.TimeoutExpired("fixture",3)
        with patch("boot_simulator.subprocess.Popen",return_value=process), patch("boot_simulator.os.killpg",side_effect=PermissionError):
            with self.assertRaisesRegex(RuntimeError,"timed out.*child_reaped=False"):
                run_bounded(["fixture"],timeout=1)
        process.stdout.close.assert_called_once()

if __name__=="__main__":
    unittest.main()
