"""Retry only a reaped, timed-out read-only simulator container lookup."""
import re
import time


def lookup_container(run_bounded, uid, *, sleep=time.sleep):
    argv = ["xcrun", "simctl", "get_app_container", uid,
            "de.nicofroeba16.iosnext", "data"]
    for attempt, timeout in enumerate((30, 45, 60), 1):
        try:
            return run_bounded(argv, timeout=timeout, emit_output=False).strip()
        except RuntimeError as error:
            # Retry only a timeout whose original child was confirmed reaped.
            # Other failures, including unconfirmed termination, fail closed.
            if attempt == 3 or not re.fullmatch(
                    rf"Command timed out after {timeout}s: xcrun; child_reaped=True", str(error)):
                raise
            print(f"SR22_CONTAINER_LOOKUP_RETRY attempt={attempt + 1}", flush=True)
            sleep(2 * attempt)
    raise AssertionError("unreachable")
