import unittest
from unittest.mock import Mock
from container_lookup import lookup_container


class LookupTests(unittest.TestCase):
    def lookup(self, effects):
        run = Mock(side_effect=effects)
        sleep = Mock()
        return run, sleep

    @staticmethod
    def timeout(seconds, reaped=True):
        return RuntimeError(f"Command timed out after {seconds}s: xcrun; child_reaped={reaped}")

    def test_success_no_retry(self):
        run, sleep = self.lookup([' /tmp/container\n'])
        self.assertEqual(lookup_container(run, 'uid', sleep=sleep), '/tmp/container')
        run.assert_called_once_with(['xcrun','simctl','get_app_container','uid','de.nicofroeba16.iosnext','data'], timeout=30, emit_output=False)
        sleep.assert_not_called()

    def test_timeout_then_success(self):
        run, sleep = self.lookup([self.timeout(30), '/tmp/container'])
        self.assertEqual(lookup_container(run, 'uid', sleep=sleep), '/tmp/container')
        self.assertEqual([c.kwargs['timeout'] for c in run.call_args_list], [30,45])
        sleep.assert_called_once_with(2)

    def test_third_attempt(self):
        run, sleep = self.lookup([self.timeout(30),self.timeout(45),'/tmp/container'])
        self.assertEqual(lookup_container(run, 'uid', sleep=sleep), '/tmp/container')
        self.assertEqual([c.kwargs['timeout'] for c in run.call_args_list], [30,45,60])
        self.assertEqual([c.args[0] for c in sleep.call_args_list], [2,4])
        self.assertTrue(all(c.args == run.call_args_list[0].args for c in run.call_args_list))

    def test_exhaustion(self):
        run, sleep = self.lookup([self.timeout(30),self.timeout(45),self.timeout(60)])
        with self.assertRaises(RuntimeError): lookup_container(run, 'uid', sleep=sleep)
        self.assertEqual(run.call_count,3)

    def test_unreaped_child_no_retry(self):
        run, sleep = self.lookup([self.timeout(30,False),'/tmp/container'])
        with self.assertRaises(RuntimeError): lookup_container(run, 'uid', sleep=sleep)
        self.assertEqual(run.call_count,1)
        sleep.assert_not_called()

    def test_other_error_no_retry(self):
        run, sleep = self.lookup([RuntimeError('Command exited 1: xcrun'),'/tmp/container'])
        with self.assertRaises(RuntimeError): lookup_container(run, 'uid', sleep=sleep)
        self.assertEqual(run.call_count,1)

    def test_unknown_timeout_no_retry(self):
        run, sleep = self.lookup([RuntimeError('Command timed out after 45s: xcrun; child_reaped=True')])
        with self.assertRaises(RuntimeError): lookup_container(run, 'uid', sleep=sleep)
        self.assertEqual(run.call_count,1)


if __name__ == '__main__': unittest.main(verbosity=2)
