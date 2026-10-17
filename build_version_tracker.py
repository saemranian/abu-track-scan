import os
import sys
import json
import datetime
import re
import argparse


def increment_4part_version(version_str: str, component: str) -> str:
    """
    Increments a 4-part decimal version string (A.B.C.D) by +1 on the last digit
    with base-10 carry rollover (e.g., 0.1.0.9 -> 0.1.1.0).

    Handles one-time transitions from legacy 3-part versions:
      - desktop ("win"): "1.0.1" -> "0.1.0.2"
      - ue_plugin ("ue"): "1.0.0" or "0.0.0.0" -> "0.0.0.1"
      - ios ("ios"): "0.0.7" -> "0.0.7.1"
    """
    v = (version_str or "").strip().lstrip("vV")

    if component == "desktop" and v in ("1.0.1", "0.1.0.1", ""):
        return "0.1.0.2"
    if component == "ue_plugin" and v in ("1.0.0", "0.0.0.0", ""):
        return "0.0.0.1"
    if component == "ios" and v in ("0.0.7", "0.0.7.0", ""):
        return "0.0.7.1"

    parts = [int(p) for p in v.split(".") if p.isdigit()]
    while len(parts) < 4:
        parts.append(0)
    parts = parts[:4]

    total = parts[0] * 1000 + parts[1] * 100 + parts[2] * 10 + parts[3]
    total += 1

    a = total // 1000
    b = (total // 100) % 10
    c = (total // 10) % 10
    d = total % 10
    return f"{a}.{b}.{c}.{d}"


def sync_ios_files(root_dir: str, ios_data: dict):
    package_swift_path = os.path.join(root_dir, "Package.swift")
    version_swift_path = os.path.join(root_dir, "Sources", "VersionInfo.swift")

    if os.path.exists(package_swift_path):
        with open(package_swift_path, "r", encoding="utf-8") as f:
            content = f.read()

        content = re.sub(
            r'displayVersion:\s*"[^"]*"',
            f'displayVersion: "{ios_data["version"]}"',
            content
        )
        content = re.sub(
            r'bundleVersion:\s*"[^"]*"',
            f'bundleVersion: "{ios_data["build"]}"',
            content
        )

        with open(package_swift_path, "w", encoding="utf-8") as f:
            f.write(content)
        print(f"Updated Package.swift -> v{ios_data['version']} (Build {ios_data['build']})")

    os.makedirs(os.path.dirname(version_swift_path), exist_ok=True)
    with open(version_swift_path, "w", encoding="utf-8") as f:
        f.write(f"""// Generated automatically by build_version_tracker.py. Do not edit.
public struct VersionInfo {{
    public static let version = "{ios_data["version"]}"
    public static let build = "{ios_data["build"]}"
    public static let buildTime = "{ios_data["last_build_time"]}"
}}
""")
    print(f"Generated Sources/VersionInfo.swift -> v{ios_data['version']}")


def sync_win_files(root_dir: str, win_data: dict):
    version_py_path = os.path.join(root_dir, "DesktopSync", "version_info.py")
    os.makedirs(os.path.dirname(version_py_path), exist_ok=True)
    with open(version_py_path, "w", encoding="utf-8") as f:
        f.write(f"""# Generated automatically by build_version_tracker.py. Do not edit.
VERSION = "{win_data["version"]}"
BUILD = {win_data["build"]}
BUILD_TIME = "{win_data["last_build_time"]}"
""")
    print(f"Generated DesktopSync/version_info.py -> v{win_data['version']} (Build {win_data['build']})")


def sync_ue_files(root_dir: str, ue_data: dict):
    uplugin_path = os.path.join(root_dir, "UnrealPlugin", "LiveLinkAbuTrack", "LiveLinkAbuTrack.uplugin")
    version_h_path = os.path.join(
        root_dir,
        "UnrealPlugin",
        "LiveLinkAbuTrack",
        "Source",
        "LiveLinkAbuTrack",
        "Public",
        "LiveLinkAbuTrackVersion.h"
    )

    if os.path.exists(uplugin_path):
        with open(uplugin_path, "r", encoding="utf-8") as f:
            uplugin_json = json.load(f)
        uplugin_json["Version"] = int(ue_data["build"])
        uplugin_json["VersionName"] = ue_data["version"]
        with open(uplugin_path, "w", encoding="utf-8") as f:
            json.dump(uplugin_json, f, indent="\t")
            f.write("\n")
        print(f"Updated LiveLinkAbuTrack.uplugin -> v{ue_data['version']} (Version {ue_data['build']})")

    os.makedirs(os.path.dirname(version_h_path), exist_ok=True)
    with open(version_h_path, "w", encoding="utf-8") as f:
        f.write(f"""// Generated automatically by build_version_tracker.py. Do not edit.
#pragma once

#define LIVELINK_ABUTRACK_VERSION_STRING TEXT("{ue_data["version"]}")
#define LIVELINK_ABUTRACK_BUILD_NUMBER {ue_data["build"]}
#define LIVELINK_ABUTRACK_BUILD_TIME TEXT("{ue_data["last_build_time"]}")
""")
    print(f"Generated LiveLinkAbuTrackVersion.h -> v{ue_data['version']}")


def append_changelog(root_dir: str, entries: list):
    changelog_path = os.path.join(root_dir, "VERSION_CHANGELOG.md")
    if not os.path.exists(changelog_path):
        header = (
            "# Abu Track & Scan — Component Version Control & Audit Log\n\n"
            "This file is automatically maintained by `build_version_tracker.py`.\n"
            "Every code edit to the **Windows Workstation (`win`)**, **iOS App (`ios`)**, or "
            "**Unreal Engine 5 Plugin (`ue`)** increments that component's 4-part decimal version "
            "(`vA.B.C.D`, rolling `.9` -> `.1.0`) and records the implemented task.\n\n"
            "| Timestamp | Component | Version | Build | Implemented Task |\n"
            "| :--- | :--- | :--- | :---: | :--- |\n"
        )
        with open(changelog_path, "w", encoding="utf-8") as f:
            f.write(header)

    with open(changelog_path, "a", encoding="utf-8") as f:
        for e in entries:
            safe_task = e["task"].replace("|", "\\|")
            f.write(
                f"| `{e['timestamp']}` | **{e['component_label']}** | `v{e['version']}` | `#{e['build']}` | {safe_task} |\n"
            )


def update_versions(target: str = "all", task: str = "Version bump"):
    root_dir = os.path.dirname(os.path.abspath(__file__))
    versions_json_path = os.path.join(root_dir, "app_versions.json")
    desktop_versions_json_path = os.path.join(root_dir, "DesktopSync", "app_versions.json")

    data = None
    if os.path.exists(versions_json_path):
        with open(versions_json_path, "r", encoding="utf-8") as f:
            try:
                data = json.load(f)
            except Exception:
                data = None

    if not data:
        data = {
            "desktop": {
                "version": "1.0.1",
                "build": 94,
                "last_build_time": "2026-06-03 22:39:23"
            },
            "ios": {
                "version": "0.0.7",
                "build": 94,
                "last_build_time": "2026-06-03 22:39:23"
            },
            "ue_plugin": {
                "version": "0.0.0.0",
                "build": 0,
                "last_build_time": "2026-06-03 22:39:23"
            },
            "history": []
        }

    if "ue_plugin" not in data:
        data["ue_plugin"] = {
            "version": "0.0.0.0",
            "build": 0,
            "last_build_time": "2026-06-03 22:39:23"
        }
    if "history" not in data or not isinstance(data["history"], list):
        data["history"] = []

    now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    changelog_entries = []

    targets = []
    if target in ("win", "desktop", "all"):
        targets.append(("desktop", "Windows Workstation (DesktopSync)"))
    if target in ("ios", "all"):
        targets.append(("ios", "iOS App (Abu Track & Scan)"))
    if target in ("ue", "ue_plugin", "all"):
        targets.append(("ue_plugin", "UE5 Plugin (LiveLinkAbuTrack)"))

    for comp_key, comp_label in targets:
        old_ver = data[comp_key].get("version", "")
        new_ver = increment_4part_version(old_ver, comp_key)
        data[comp_key]["version"] = new_ver
        data[comp_key]["build"] = int(data[comp_key].get("build", 0)) + 1
        data[comp_key]["last_build_time"] = now_str
        data[comp_key]["last_task"] = task

        entry = {
            "timestamp": now_str,
            "component": comp_key,
            "component_label": comp_label,
            "previous_version": old_ver,
            "version": new_ver,
            "build": data[comp_key]["build"],
            "task": task
        }
        data["history"].append(entry)
        changelog_entries.append(entry)
        print(f"[{comp_label}] Bumped v{old_ver} -> v{new_ver} (Build #{data[comp_key]['build']}): {task}")

    with open(versions_json_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)

    os.makedirs(os.path.dirname(desktop_versions_json_path), exist_ok=True)
    with open(desktop_versions_json_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)

    if any(t[0] == "desktop" for t in targets):
        sync_win_files(root_dir, data["desktop"])
    if any(t[0] == "ios" for t in targets):
        sync_ios_files(root_dir, data["ios"])
    if any(t[0] == "ue_plugin" for t in targets):
        sync_ue_files(root_dir, data["ue_plugin"])

    if changelog_entries:
        append_changelog(root_dir, changelog_entries)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Abu Track & Scan Per-Component 4-Part Version Tracker")
    parser.add_argument(
        "--target",
        choices=["win", "desktop", "ios", "ue", "ue_plugin", "all"],
        default="all",
        help="Target component to bump version for (win, ios, ue, or all)."
    )
    parser.add_argument(
        "--task",
        type=str,
        default="Automated component build and version increment",
        help="Summary of the implemented task for the version changelog."
    )
    args = parser.parse_args()
    update_versions(target=args.target, task=args.task)
