#!/usr/bin/env python3
from pathlib import Path
import os

ROOT = Path(__file__).resolve().parents[1]

def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")

def require(condition: bool, message: str) -> None:
    if not condition:
        print(f"APPLE_FINAL_ACCEPTANCE=FAIL: {message}")
        raise SystemExit(1)

jarvis = read("Sources/Core/JarvisEngine.swift")
intents = read("Sources/Core/JarvisAppIntents.swift")
app = read("Sources/App/IOSNextApp.swift")
plist = read("Info.plist")
project = read("project.yml")

expected_version = os.environ.get("EXPECTED_VERSION", "1.4.0")
expected_build = os.environ.get("EXPECTED_BUILD", "20")

require(f"MARKETING_VERSION: {expected_version}" in project, f"marketing version is not {expected_version}")
require(f"CURRENT_PROJECT_VERSION: {expected_build}" in project, f"build version is not {expected_build}")

for key in (
    "NSMicrophoneUsageDescription",
    "NSSpeechRecognitionUsageDescription",
    "NSCameraUsageDescription",
    "NSFaceIDUsageDescription",
    "NSLocalNetworkUsageDescription",
):
    require(f"<key>{key}</key>" in plist, f"missing privacy usage key {key}")

require("requiresOnDeviceRecognition = true" in jarvis, "wakeword must require on-device recognition")
require("supportsOnDeviceRecognition" in jarvis, "wakeword must verify on-device recognition availability")
require("URLSession" not in jarvis, "wakeword source must not stream microphone data over network")
require("AVAudioSession.didBecomeInactiveNotification" in jarvis, "iOS 27 audio deactivation handling missing")
require("AVAudioSession.resumptionRecommendationNotification" in jarvis, "iOS 27 audio resumption handling missing")
require("AVAudioSession.routeChangeNotification" in jarvis, "audio route change recovery missing")
require("AVAudioSession.mediaServicesWereResetNotification" in jarvis, "media-services reset recovery missing")
require(".NSProcessInfoPowerStateDidChange" in jarvis, "Low Power Mode handling missing")
require("ProcessInfo.thermalStateDidChangeNotification" in jarvis, "thermal-state handling missing")
require("AVAudioApplication.requestRecordPermission()" in jarvis, "modern microphone permission API missing")
require("JarvisRuntimePolicy" in jarvis, "Jarvis runtime policy missing")
require("applicationActive && wakeRequested && !interrupted" in jarvis, "background microphone fail-closed policy missing")
require("scheduleRestart" in jarvis, "wakeword automatic recovery missing")
require("scenePhase" in app, "scene lifecycle integration missing")
require("appModel.setApplicationActive(active)" in app, "Home Assistant lifecycle integration missing")
require("JarvisEngine.shared.setApplicationActive(active)" in app, "Jarvis lifecycle integration missing")
require("IOSNextAppShortcuts.updateAppShortcutParameters()" in app, "App Shortcuts registration missing")
require("OpenJarvisIntent: AppIntent" in intents, "Jarvis App Intent missing")
require("openAppWhenRun = true" in intents, "Jarvis system invocation must foreground the app before microphone capture")
require("AppShortcutsProvider" in intents, "Jarvis App Shortcut provider missing")
require(".applicationName" in intents, "Siri shortcut phrases must identify the app")
require("<key>UIBackgroundModes</key>" not in plist, "unsupported background mode declared")

print("APPLE_FINAL_ACCEPTANCE=PASS")
print("wakeword=on-device")
print("background_policy=fail-closed-and-auto-resume")
print("system_voice_invocation=app-intents")
print("audio_lifecycle=ios27")
print("route_changes=covered")
print("media_services_reset=covered")
print("low_power=covered")
print("thermal_state=covered")
print("privacy_usage_descriptions=covered")
print("soak_test=excluded_by-release-plan")
