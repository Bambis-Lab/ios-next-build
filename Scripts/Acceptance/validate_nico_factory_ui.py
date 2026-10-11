#!/usr/bin/env python3
"""Source-locked app-only guard for Nico tiles, HA performance and Factory Owner."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")

room=read("Sources/Features/RoomsView.swift")
light=read("Sources/Design/LightControlSheet.swift")
queue=read("Sources/Core/LatestValueCommandQueue.swift")
app=read("Sources/Core/AppModel.swift")
owner=read("Sources/Features/AdminAreaView.swift")
owner_dir=read("Sources/Features/Owner/Factory/FactoryOwnerDirectoryView.swift")
factory=read("Sources/Features/Owner/Factory/FactoryWorkspaceModulesView.swift")
fixture=read("Sources/Features/NicoRoomVisualAcceptanceView.swift")
root=read("Sources/App/AppRootView.swift")
ui=read("UITests/NicoRoomLayoutUITests.swift")
tests=read("Tests/LatestValueCommandQueueTests.swift")

checks={
    "unchanged_162": "MARKETING_VERSION: 1.6.2" in read("project.yml")
                     and "CURRENT_PROJECT_VERSION: 25" in read("project.yml"),
    "cabinet_primary_tile": 'NicoPrimaryLightTile(entity: cabinetLight' in room,
    "tv_primary_tiles": 'ForEach(tvLights)' in room and 'NicoPrimaryLightTile(entity: light' in room,
    "quarter_actions": 'HStack(alignment: .top, spacing: 12)' in room
                       and 'NicoMicroActionTile(' in room,
    "prisma_scene_kept": 'await appModel.activate(prismaScene)' in room,
    "desk_switch_kept": 'await appModel.toggle(deskSwitch)' in room,
    "removed_palette_button": 'NicoCompactControlTile' not in room
                              and 'showControls = true' in room,
    "cabinet_longpress": '.ios27HoldAction {' in room
                         and 'LightControlSheet(entityID: entity.entityID' in room,
    "accessible_ids": "nico-primary-" in room and "nico-micro-" in room,
    "indexed_lookup": 'func entity(withID entityID: String)' in app
                      and 'indexedEntities(inArea: areaID)' in app,
    "color_queue_serial": 'await next.apply(next.value)' in queue
                          and 'pending = Pending(value: value' in queue,
    "color_queue_integrated": 'colorCommandQueue.submit(desired)' in light,

    "no_duplicate_white_action": 'submitColor(.white(' in light and 'ignoredSynchronizedColor' in light,
    "owner_direct_route": "FactoryOwnerDirectoryView(" in owner
                          and "if factoryEmbedded" in owner
                          and 'AdminAreaView(appModel: appModel, factoryEmbedded: true)' in factory,
    "owner_auth_preserved": 'case .unlocked:' in owner
                            and "IOSNextControlCenterUnlockHost" in owner
                            and "IOSNextControlCenterLockHost" in owner,
    "offline_fixture": '--nico-room-layout-acceptance' in root
                       and '--nico-room-layout-acceptance' in fixture,
    "dark_large_test": '--nico-dark-acceptance' in fixture
                       and '--nico-large-type-acceptance' in fixture,
    "queue_tests": 'testLatestValueIsNotLostWhilePreviousWriteIsInFlight' in tests,
    "ui_tests": 'testCompactRoomTilesAndCabinetColorLongPress' in ui
                and 'testDarkCompactRoomLayout' in ui
                and 'reveal(desk, in: app)' in ui,
}
for name, passed in checks.items():
    print(f"NICO_FAI_{name.upper()}={'PASS' if passed else 'FAIL'}")
assert all(checks.values()), "Nico/Factory staged acceptance failed"
print("NICO_FAI_PORTABLE=PASS")
