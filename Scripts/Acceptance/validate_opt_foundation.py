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
chat=read("Sources/Core/ChatModel.swift")
lifecycle=read("Sources/Core/AppServiceLifecycleCoordinator.swift")
runtime=read("Sources/Core/IOSNextRuntime.swift")
search=read("Sources/Features/GlobalSearchView.swift")
search_index=read("Sources/Features/GlobalSearchIndex.swift")
media_view=read("Sources/Features/MediaView.swift")
media_snapshot=read("Sources/Core/MediaPresentationSnapshot.swift")
factory=read("Sources/Features/Owner/Factory/FactoryMCPService.swift")
owner=read("Sources/Core/AdminControlClient.swift")
audio=read("Sources/Core/AppAudioCoordinator.swift")
jarvis=read("Sources/Core/JarvisEngine.swift")
wireguard=read("Sources/Core/WireGuardTunnelController.swift")
dashboard=read("Sources/Features/HomeView.swift")
intents=read("Sources/Core/JarvisAppIntents.swift")
thumbnail=read("Sources/Core/ChatMediaThumbnailCache.swift")
pipeline=read("Sources/Core/EntityCommandPipeline.swift")
pipeline_tests=read("Tests/EntityCommandPipelineTests.swift")
search_tests=read("Tests/GlobalSearchIndexTests.swift")
media_tests=read("Tests/ChatMediaThumbnailCacheTests.swift")
audio_tests=read("Tests/AppAudioCoordinatorTests.swift")
dashboard_tests=read("Tests/DashboardPreferencesTests.swift")
color=read("Sources/Design/LightControlSheet.swift")

checks={
    "xcode_dispatch_is_scoped": "github.event_name == 'workflow_dispatch'" in workflow
                                and "refs/heads/acceptance/iosnext-opt-smoke-84b0d63" in workflow,
    "bounded_job": "timeout-minutes: 18" in workflow,
    "bounded_test": "--timeout-seconds 240" in workflow,
    "bounded_compile": "--timeout-seconds 660" in workflow,
    "evidence_on_failure": "if: always()" in workflow
                           and "build/NicoFactoryiPhone.xcresult" in workflow,
    "regular_feature_push_stays_portable": "feature/ios-next-opt-01-14-foundation-162" in workflow
                                           and "refs/heads/feature/ios-next-opt-01-14-foundation-162" not in workflow.split("if: github.event_name == 'workflow_dispatch'", 1)[-1]
                                           and "needs: portable" in workflow,
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
                              and "colorCommandQueue.submit(QueuedLightColorCommand(generation: generation, command: desired))" in color
                              and "isCurrentCommandGeneration(queued.generation)" in color
                              and "commandGenerationToken" in model,
    "live_segment_serial": '"light.appearance"' in model
                            and 'service: "set_segments"' in model,
    "pipeline_typed_results": "item.continuation.resume(returning: .superseded)" in pipeline
                               and "item.continuation.resume(returning: .cancelled)" in pipeline
                               and "let result = await operationTask.value" in pipeline,
    "pipeline_active_outcome": "activeResultDelivered" in pipeline
                               and "active.continuation.resume(returning: .outcomeUnknown(" in pipeline
                               and "activeOperationTasks[entityID]?.cancel()" in pipeline,
    "pipeline_acceptance": "testQueuedAbsoluteValuesCoalesceWithoutDroppingFinalIntent" in pipeline_tests
                           and "testDisconnectDropsOnlyQueuedCommands" in pipeline_tests
                           and "testNewGenerationWaitsUntilInvalidatedOperationUnwinds" in pipeline_tests,
    "chat_start_idempotent": "private var startupTask: Task<Void, Never>?" in chat
                             and "private func performRelayStart(epoch: UInt64)" in chat,
    "chat_draft_preserved": "if accepted && draft == originalDraft { draft = \"\" }" in chat,
    "thumbnail_off_main": "Task.detached(priority: .userInitiated)" in thumbnail
                          and "totalCostLimit = 24 * 1024 * 1024" in thumbnail,
    "lifecycle_single_flight": "chatStartupToken" in lifecycle and "lifecycleGeneration" in lifecycle,
    "search_debounced": ".milliseconds(120)" in search and "appModel.searchRevision" in search,
    "factory_tool_cache": "toolDiscoveryExpiresAt" in factory and "sessionOpeningTask" in factory,
    "owner_refresh_single_flight": "statusV2RefreshTask" in owner and "ownerSessionGeneration" in owner,
    "startup_lazy_services": "runnerModelStorage: RunnerControlModel?" in runtime
                             and "factoryWorkspaceStorage: FactoryWorkspaceCoordinator?" in runtime,
    "audio_leases": "activities: [UUID: AppAudioActivity]" in audio
                    and "setExternalAudioBusy" in jarvis,
    "wireguard_status_observer": ".NEVPNStatusDidChange" in wireguard,
    "dashboard_preferences": "DashboardPreferencesStore" in dashboard
                             and "home-dashboard-customize" in dashboard,
    "safe_navigation_intents": "OpenIOSNextRoomsIntent" in intents
                               and "OpenIOSNextMediaIntent" in intents,
    "indexed_search": "searchIndex.rebuild(" in search and "GlobalSearchIndex" in search_index
                      and "appModel.searchRevision" in search,
    "search_regressions": "testRebuildUpdatesChangedNamesAndStates" in search_tests,
    "grouped_media_snapshot": "MediaPresentationSnapshot.build(from: appModel)" in media_view
                              and "activePlayerCount" in media_snapshot,
    "media_preview_tests": "testValidImageIsDownsampledAndCachedOnlyInMemory" in media_tests,
    "audio_lease_tests": "testJarvisBusyStateChangesOnlyWhenFirstAndLastLeaseChanges" in audio_tests,
    "dashboard_preference_tests": "testVisibilityAndOrderingPersistPerProfile" in dashboard_tests,
    "identity_fenced_chat_send": "configurationGeneration" in chat
                                 and "sendGeneration == configurationGeneration" in chat,
}
for key, result in checks.items():
    print(f"OPT_{key.upper()}={'PASS' if result else 'FAIL'}")
if not all(checks.values()):
    raise SystemExit("OPT_FOUNDATION=FAIL")
print("OPT_FOUNDATION=PASS")
