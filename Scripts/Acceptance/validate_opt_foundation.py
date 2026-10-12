#!/usr/bin/env python3
"""Portable, read-only acceptance for the app-wide optimization foundation."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")

workflow=read(".github/workflows/nico-factory-performance-xcode27.yml")
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
    "manual_xcode_only": "if: github.event_name == 'workflow_dispatch'" in workflow,
    "no_process_watchdogs": "xcode_watchdog.py" not in workflow
                            and "run_xcode_tests_verified.py" not in workflow
                            and "timeout-seconds" not in workflow,
    "xcode_commands_are_direct": "xcodebuild build" in workflow
                                 and "build-for-testing 2>&1 | tee build/NicoFactoryBuild.log" in workflow
                                 and "xcodebuild test-without-building" in workflow,
    "no_xcode_step_timeouts": "timeout-minutes:" not in workflow[workflow.index("  xcode27:"):],
    "full_matrix_on_acceptance_push": workflow.count("SUITE: ${{ inputs.suite || 'full' }}") == 2
                                  and "inputs.suite == 'full' || github.event_name == 'push'" in workflow,
    "xcode_manages_simulator_boot": "boot_simulator.py" in workflow
                                    and "--resolve-only" in workflow
                                    and "Restart iPhone simulator" not in workflow
                                    and "simctl erase" not in workflow
                                    and "simctl bootstatus" not in workflow,
    "ipa_candidate_uploaded_before_tests": "Upload unsigned IPA candidate (not a release)" in workflow
                                           and workflow.index("Upload unsigned IPA candidate (not a release)")
                                           < workflow.index("Targeted iPhone unit tests")
                                           and "IOSNext-Unsigned-IPA-Candidate" in workflow,
    "diagnostic_evidence_uploaded_on_failure": "if: always()" in workflow
                                               and "Always upload test evidence (including red tests)" in workflow
                                               and "build/NicoFactoryiPhone.xcresult" in workflow,
    "no_automatic_xcode_push": "on:" in workflow and "needs: portable" in workflow,
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
    "search_normalize_shared_helper": "GlobalSearchIndex.normalize(" in search
                                      and "Self.normalize(" not in search,
    "search_regressions": "testRebuildUpdatesChangedNamesAndStates" in search_tests,
    "app_shortcuts_result_builder": "static var appShortcuts: [AppShortcut] {\n        AppShortcut(" in intents,
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
