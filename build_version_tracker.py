import os
import json
import datetime
import re

def update_versions():
    # 1. Paths
    root_dir = os.path.dirname(os.path.abspath(__file__))
    versions_json_path = os.path.join(root_dir, "app_versions.json")
    package_swift_path = os.path.join(root_dir, "Package.swift")
    version_swift_path = os.path.join(root_dir, "Sources", "VersionInfo.swift")
    version_py_path = os.path.join(root_dir, "DesktopSync", "version_info.py")
    
    # 2. Load existing versions or create default
    if os.path.exists(versions_json_path):
        with open(versions_json_path, "r", encoding="utf-8") as f:
            try:
                data = json.load(f)
            except Exception:
                data = None
    else:
        data = None
        
    if not data:
        data = {
            "desktop": {
                "version": "1.0.1",
                "build": 51,
                "last_build_time": ""
            },
            "ios": {
                "version": "0.0.7",
                "build": 51,
                "last_build_time": ""
            }
        }
    
    # Increment builds
    data["desktop"]["build"] += 1
    data["ios"]["build"] += 1
    
    now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    data["desktop"]["last_build_time"] = now_str
    data["ios"]["last_build_time"] = now_str
    
    # Save back to json
    with open(versions_json_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        
    print(f"Updated build numbers: Desktop Build #{data['desktop']['build']}, iOS Build #{data['ios']['build']}")
    
    # 3. Update Package.swift
    if os.path.exists(package_swift_path):
        with open(package_swift_path, "r", encoding="utf-8") as f:
            content = f.read()
            
        content = re.sub(
            r'displayVersion:\s*"[^"]*"',
            f'displayVersion: "{data["ios"]["version"]}"',
            content
        )
        content = re.sub(
            r'bundleVersion:\s*"[^"]*"',
            f'bundleVersion: "{data["ios"]["build"]}"',
            content
        )
        
        with open(package_swift_path, "w", encoding="utf-8") as f:
            f.write(content)
        print("Updated Package.swift version keys.")
        
    # 4. Write Sources/VersionInfo.swift
    os.makedirs(os.path.dirname(version_swift_path), exist_ok=True)
    with open(version_swift_path, "w", encoding="utf-8") as f:
        f.write(f"""// Generated automatically by build_version_tracker.py. Do not edit.
public struct VersionInfo {{
    public static let version = "{data["ios"]["version"]}"
    public static let build = "{data["ios"]["build"]}"
    public static let buildTime = "{data["ios"]["last_build_time"]}"
}}
""")
    print("Generated Sources/VersionInfo.swift")
    
    # 5. Write DesktopSync/version_info.py
    os.makedirs(os.path.dirname(version_py_path), exist_ok=True)
    with open(version_py_path, "w", encoding="utf-8") as f:
        f.write(f"""# Generated automatically by build_version_tracker.py. Do not edit.
VERSION = "{data["desktop"]["version"]}"
BUILD = {data["desktop"]["build"]}
BUILD_TIME = "{data["desktop"]["last_build_time"]}"
""")
    print("Generated DesktopSync/version_info.py")

if __name__ == "__main__":
    update_versions()
