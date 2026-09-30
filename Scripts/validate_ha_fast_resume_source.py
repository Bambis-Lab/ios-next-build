#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
client = (root / "Sources/Core/HomeAssistantClient.swift").read_text()
app_root = (root / "Sources/App/AppRootView.swift").read_text()

required = [
    "private static let registryCacheTTL: TimeInterval = 300",
    "resetTransport(clearRegistryCache: false)",
    "func disconnect() {\n        resetTransport(clearRegistryCache: true)",
    "reusableRegistryCache(baseURL: configuration.baseURL, currentUserID: currentUserID)",
    'async let statesResponse = command(type: "get_states")',
    'optionalRegistryCommand(type: "config/floor_registry/list")',
    'optionalRegistryCommand(type: "config/area_registry/list")',
    'optionalRegistryCommand(type: "config/device_registry/list")',
    'optionalRegistryCommand(type: "config/entity_registry/list")',
]
missing = [item for item in required if item not in client]
if missing:
    raise SystemExit(f"HA fast-resume contract missing: {missing}")

if "registryCache.currentUserID == currentUserID" not in client or "registryCache.baseURL == baseURL" not in client:
    raise SystemExit("HA registry cache must be scoped to HA server and current user")

if "Date().timeIntervalSince(registryCache.storedAt) <= Self.registryCacheTTL" not in client:
    raise SystemExit("HA registry cache TTL guard missing")

if "appModel.setApplicationActive(phase == .active)" not in app_root:
    raise SystemExit("scene phase must drive application-active state")

scene_block = app_root.split(".onChange(of: scenePhase)", 1)[1].split(".task", 1)[0]
if "disconnect(" in scene_block:
    raise SystemExit("background scene transition must not actively disconnect Home Assistant")

print("HA_FAST_RESUME_SOURCE=PASS")
