#!/usr/bin/env python3
"""Portable, read-only acceptance for the app-wide optimization foundation."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")

workflow=read(".github/workflows/nico-factory-performance-xcode27.yml")
watchdog=read("Scripts/Acceptance/xcode_watchdog.py")
tests=read("UITests/NicoRoomLayoutUITests.swift")
model=read("Sources/Core/AppModel.swift")
pipeline=read("Sources/Core/EntityCommandPipeline.swift")
pipeline_tests=read("Tests/EntityCommandPipelineTests.swift")
color=read("Sources/Design/LightControlSheet.swift")

checks={
    "manual_xcode_only": "if: github.event_name == 'workflow_dispatch'" in workflow,
    "bounded_job": "timeout-minutes: 18" in workflow,
    "bounded_test": "--timeout-seconds 240" in workflow,
    "bounded_compile": "--timeout-seconds 660" in workflow,
    "evidence_on_failure": "if: always()" in workflow
                           and "build/NicoFactoryiPhone.xcresult" in workflow,
    "no_automatic_xcode_push": "on:" in workflow and "needs: portable" in workflow,
    "watchdog_group_kill": "os.killpg(child.pid, signal.SIGKILL)" in watchdog
                           and "start_new_session=True" in watchdog,
    "lazy_scroll_test": "reveal(desk, in: app)" in tests
                        and "Nico-Accessibility-Hierarchy-ON-FAIL" in tests,
    "entity_serial_lane": "deviceCommands.execute(entityID:" in model,
    "inflight_state_guard": "entityStateRevisions[entityID, default: 0] == revisionAtDispatch" in model,
    "disconnect_invalidates": "deviceCommands.invalidatePending()" in model,
    "server_state_wins": "entities[index] = entities[index].updating(state: optimisticState)" in model,
    "no_busy_command_drop": "!activeActionEntityIDs.contains(entity.entityID)" not in model,
    "ordered_nonretry_actions": 'return nil' in model and "coalescingKey" in model,
    "color_and_white_serial": "submitColor(.white(" in color
                              and "submitColor(.rgb(" in color
                              and "colorCommandQueue.submit(desired)" in color,
    "live_segment_serial": '"light.appearance"' in model
                            and 'service: "set_segments"' in model,
    "pipeline_superseded_result": "item.continuation.resume(returning: false)" in pipeline,
    "pipeline_acceptance": "testQueuedAbsoluteValuesCoalesceWithoutDroppingFinalIntent" in pipeline_tests
                           and "testDisconnectDropsOnlyQueuedCommands" in pipeline_tests,
}
for key, result in checks.items():
    print(f"OPT_{key.upper()}={'PASS' if result else 'FAIL'}")
if not all(checks.values()):
    raise SystemExit("OPT_FOUNDATION=FAIL")
print("OPT_FOUNDATION=PASS")
