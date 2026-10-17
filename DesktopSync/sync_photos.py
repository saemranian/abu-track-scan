#!/usr/bin/env python3
"""
Abu Track & Scan - Professional DSLR/Mirrorless & Multi-Sensor Telemetry Post-Processor
Powered by Abu Clock (SMPTE ST 2059-2 / ST 12-1 + 64-bit TAI Nanoseconds)

Matches raw photo folders from professional DSLR/Mirrorless cameras and iOS cameras with
continuous telemetry logs exported from the Abu Track & Scan iOS app.
Performs:
- Optical Exposure-Midpoint timestamp extraction (EXIF DateTimeOriginal + SubSecTimeOriginal + ExposureTime / 2)
- Deterministic <SensorID>_<HHMMSSFF>_<TAI_ns> filename parsing
- Spherical Linear Quaternion Interpolation (SLERP) for 3D attitude + linear spatial interpolation
- Rotated 3D Lever-Arm & Boresight Offset Rig Correction
- Multi-target export: Metashape CSV, .abuscan.json manifest, and COLMAP / Postshot 3DGS images.txt
"""

import csv
import json
import math
import os
import re
import sys
from datetime import datetime
from PIL import Image
from PIL.ExifTags import TAGS

from abu_clock_bridge import AbuClockBridge, TAI_UTC_OFFSET_NS


def print_banner():
    banner = """
========================================================================
         ABU TRACK & SCAN - ABU CLOCK TELEMETRY POST-PROCESSOR
========================================================================
    * Optical Exposure-Midpoint Timestamping (T_mid = T_SOF + T_exp/2)
    * Spherical Linear Quaternion Interpolation (SLERP)
    * Rotated 3D Lever-Arm Offset Rig Correction
    * Unified .abuscan.json + COLMAP images.txt + Metashape CSV Export
========================================================================
"""
    print(banner)


def _rational_to_float(val) -> float:
    if val is None:
        return 0.0
    if isinstance(val, (int, float)):
        return float(val)
    if isinstance(val, tuple) and len(val) == 2 and val[1] != 0:
        return float(val[0]) / float(val[1])
    try:
        return float(val)
    except Exception:
        return 0.0


def load_exif_timestamp(img_path: str) -> float:
    """
    Retrieves the precise optical exposure midpoint timestamp in milliseconds since Unix Epoch (UTC):
    1. Deterministic AbuScan filename `<SensorID>_<HHMMSSFF>_<TAI_ns>_IMG_<N>.<ext>`
    2. EXIF DateTimeOriginal + SubSecTimeOriginal + 0.5 * ExposureTime
    3. Legacy filename regex (`YYYY_MM_DD_HH_MM_SS`)
    4. Filesystem mtime fallback
    """
    p_name = os.path.basename(img_path)

    # Layer 0: Deterministic AbuClock TAI nanosecond filename token (18-20 digit TAI ns)
    tai_match = re.search(r"_(\d{18,20})_", p_name)
    if tai_match:
        try:
            tai_ns = int(tai_match.group(1))
            if tai_ns > TAI_UTC_OFFSET_NS:
                return (tai_ns - TAI_UTC_OFFSET_NS) / 1_000_000.0
        except ValueError:
            pass

    # Layer 1: EXIF Metadata with SubSecTimeOriginal + ExposureTime/2
    try:
        with Image.open(img_path) as img:
            exif_data = img._getexif()
            if exif_data:
                tags = {}
                for tag_id, value in exif_data.items():
                    tag_name = TAGS.get(tag_id, tag_id)
                    tags[tag_name] = value

                date_str = tags.get("DateTimeOriginal") or tags.get("DateTime")
                if date_str:
                    if isinstance(date_str, bytes):
                        date_str = date_str.decode("utf-8", errors="ignore")
                    date_str = str(date_str).strip().rstrip("\x00")
                    subsec_raw = tags.get("SubSecTimeOriginal") or tags.get("SubSecTime") or "0"
                    if isinstance(subsec_raw, bytes):
                        subsec_raw = subsec_raw.decode("utf-8", errors="ignore")
                    subsec_str = str(subsec_raw).strip().rstrip("\x00")
                    dt = datetime.strptime(date_str, "%Y:%m:%d %H:%M:%S")
                    epoch_sec = dt.timestamp()
                    subsec = float("0." + subsec_str) if subsec_str.isdigit() else 0.0
                    exp_sec = _rational_to_float(tags.get("ExposureTime"))
                    if exp_sec <= 0.0 or exp_sec > 30.0:
                        exp_sec = 0.0
                    return (epoch_sec + subsec + 0.5 * exp_sec) * 1000.0
    except Exception:
        pass

    # Layer 2: Filename Regex Fallback (e.g. 2026_05_27_10_02_IMG_1255.JPG)
    match = re.search(r"(\d{4})_(\d{2})_(\d{2})_(\d{2})_(\d{2})_(\d{2})?", p_name)
    if match:
        parts = match.groups()
        try:
            if parts[5]:
                dt = datetime(int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4]), int(parts[5]))
            else:
                dt = datetime(int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4]))
            return dt.timestamp() * 1000.0
        except ValueError:
            pass

    # Layer 3: Filesystem modification time fallback
    return os.path.getmtime(img_path) * 1000.0


def load_telemetry_csv(csv_path: str):
    """
    Parses the Abu Track & Scan telemetry CSV (supporting both legacy 19-column and
    AbuClock 24-column formats) and returns records sorted by timestamp (ms).
    """
    records = []
    bridge = AbuClockBridge.instance()
    try:
        with open(csv_path, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            if reader.fieldnames:
                reader.fieldnames = [fn.strip().lower() for fn in reader.fieldnames]
            else:
                return []

            for rec in reader:
                raw_time = rec.get("timestamp_ms") or rec.get("epoch")
                if raw_time is None:
                    continue
                try:
                    t_val = float(raw_time)
                except ValueError:
                    continue

                if t_val < 1e11:
                    t_val *= 1000.0

                try:
                    raw_tai = rec.get("tai_ns")
                    if raw_tai and int(float(raw_tai)) > 0:
                        tai_ns = int(float(raw_tai))
                    else:
                        tai_ns = int(round(t_val * 1_000_000.0)) + TAI_UTC_OFFSET_NS

                    snap = bridge.synthesize_from_tai_ns(tai_ns)
                    smpte_tc = (rec.get("smpte_timecode") or "").strip() or snap.smpte_string
                    raw_bcd = (rec.get("bcd_timecode") or "").strip()
                    if raw_bcd.startswith(("0x", "0X")):
                        bcd_tc = int(raw_bcd, 16)
                    elif raw_bcd.isdigit():
                        bcd_tc = int(raw_bcd)
                    else:
                        bcd_tc = snap.bcd_timecode

                    records.append(
                        {
                            "timestamp": t_val,
                            "tai_ns": tai_ns,
                            "smpte_timecode": smpte_tc,
                            "bcd_timecode": bcd_tc,
                            "subframe_phase": float(rec.get("subframe_phase") or snap.phase),
                            "clock_lock_state": (rec.get("clock_lock_state") or "LOCKED").strip(),
                            "local_x": float(rec.get("local_x_m") or rec.get("local_x") or 0.0),
                            "local_y": float(rec.get("local_y_m") or rec.get("local_y") or 0.0),
                            "local_z": float(rec.get("local_z_m") or rec.get("local_z") or 0.0),
                            "baro_alt": float(rec.get("baro_alt_m") or rec.get("baro_altitude") or 0.0),
                            "pressure": float(rec.get("baro_press_kpa") or rec.get("pressure") or 0.0),
                            "pitch": float(rec.get("pitch_deg") or rec.get("pitch") or 0.0),
                            "roll": float(rec.get("roll_deg") or rec.get("roll") or 0.0),
                            "yaw": float(rec.get("yaw_deg") or rec.get("yaw") or 0.0),
                            "q_w": float(rec.get("q_w") or 1.0),
                            "q_x": float(rec.get("q_x") or 0.0),
                            "q_y": float(rec.get("q_y") or 0.0),
                            "q_z": float(rec.get("q_z") or 0.0),
                            "gps_enabled": int(float(rec.get("gps_enabled") or 0.0)) == 1,
                            "gps_lat": float(rec.get("gps_lat") or rec.get("gps_latitude") or 0.0),
                            "gps_lon": float(rec.get("gps_lon") or rec.get("gps_longitude") or 0.0),
                            "gps_alt": float(rec.get("gps_alt_m") or rec.get("gps_altitude") or 0.0),
                            "gps_acc_h": float(rec.get("gps_acc_h_m") or rec.get("gps_acc_h") or 0.0),
                            "gps_acc_v": float(rec.get("gps_acc_v_m") or rec.get("gps_acc_v") or 0.0),
                        }
                    )
                except (ValueError, TypeError):
                    continue
        records.sort(key=lambda x: x["timestamp"])
        return records
    except Exception as e:
        print(f"[!] Failed to parse telemetry CSV: {e}")
        return []


def slerp_quaternion(q1, q2, t: float):
    """Spherical Linear Interpolation (SLERP) between unit quaternions q1 and q2."""
    w1, x1, y1, z1 = q1
    w2, x2, y2, z2 = q2
    dot = w1 * w2 + x1 * x2 + y1 * y2 + z1 * z2
    if dot < 0.0:
        w2, x2, y2, z2 = -w2, -x2, -y2, -z2
        dot = -dot

    if dot > 0.9995:
        w = w1 + t * (w2 - w1)
        x = x1 + t * (x2 - x1)
        y = y1 + t * (y2 - y1)
        z = z1 + t * (z2 - z1)
        mag = math.sqrt(w * w + x * x + y * y + z * z)
        return (w / mag, x / mag, y / mag, z / mag) if mag > 0 else (1.0, 0.0, 0.0, 0.0)

    theta_0 = math.acos(max(-1.0, min(1.0, dot)))
    sin_theta_0 = math.sin(theta_0)
    theta_t = theta_0 * t
    sin_theta_t = math.sin(theta_t)
    s0 = math.cos(theta_t) - dot * sin_theta_t / sin_theta_0
    s1 = sin_theta_t / sin_theta_0
    return (
        s0 * w1 + s1 * w2,
        s0 * x1 + s1 * x2,
        s0 * y1 + s1 * y2,
        s0 * z1 + s1 * z2,
    )


def interpolate_telemetry(t: float, rec_a: dict, rec_b: dict) -> dict:
    """
    Executes linear spatial interpolation and Spherical Linear Quaternion Interpolation (SLERP)
    to obtain telemetry estimates at precise optical exposure-midpoint timestamp `t` (ms).
    """
    t_a = rec_a["timestamp"]
    t_b = rec_b["timestamp"]
    if abs(t_b - t_a) < 1e-5:
        return rec_a

    f = max(0.0, min(1.0, (t - t_a) / (t_b - t_a)))
    tai_ns = int(round(rec_a["tai_ns"] + f * (rec_b["tai_ns"] - rec_a["tai_ns"])))
    snap = AbuClockBridge.instance().synthesize_from_tai_ns(tai_ns)

    interp = {
        "timestamp": t,
        "tai_ns": tai_ns,
        "smpte_timecode": snap.smpte_string,
        "bcd_timecode": snap.bcd_timecode,
        "subframe_phase": snap.phase,
        "clock_lock_state": rec_a.get("clock_lock_state", "SLERP_INTERPOLATED"),
        "local_x": rec_a["local_x"] + f * (rec_b["local_x"] - rec_a["local_x"]),
        "local_y": rec_a["local_y"] + f * (rec_b["local_y"] - rec_a["local_y"]),
        "local_z": rec_a["local_z"] + f * (rec_b["local_z"] - rec_a["local_z"]),
        "baro_alt": rec_a["baro_alt"] + f * (rec_b["baro_alt"] - rec_a["baro_alt"]),
        "gps_enabled": rec_a["gps_enabled"],
        "gps_lat": rec_a["gps_lat"] + f * (rec_b["gps_lat"] - rec_a["gps_lat"]),
        "gps_lon": rec_a["gps_lon"] + f * (rec_b["gps_lon"] - rec_a["gps_lon"]),
        "gps_alt": rec_a["gps_alt"] + f * (rec_b["gps_alt"] - rec_a["gps_alt"]),
        "pitch": rec_a["pitch"] + f * (rec_b["pitch"] - rec_a["pitch"]),
        "roll": rec_a["roll"] + f * (rec_b["roll"] - rec_a["roll"]),
        "yaw": rec_a["yaw"] + f * (rec_b["yaw"] - rec_a["yaw"]),
    }

    q1 = (rec_a["q_w"], rec_a["q_x"], rec_a["q_y"], rec_a["q_z"])
    q2 = (rec_b["q_w"], rec_b["q_x"], rec_b["q_y"], rec_b["q_z"])
    interp["q_w"], interp["q_x"], interp["q_y"], interp["q_z"] = slerp_quaternion(q1, q2, f)
    return interp


def find_telemetry_for_timestamp(t: float, records: list):
    """Performs binary search to find bracketing telemetry samples and interpolate via SLERP."""
    if not records:
        return None
    if t <= records[0]["timestamp"]:
        return records[0]
    if t >= records[-1]["timestamp"]:
        return records[-1]

    low = 0
    high = len(records) - 1
    while low < high:
        mid = (low + high) // 2
        if records[mid]["timestamp"] < t:
            low = mid + 1
        else:
            high = mid

    return interpolate_telemetry(t, records[low - 1], records[low])


def rotate_vector_by_quaternion(v, q):
    """Rotates 3D vector v = (x, y, z) by unit quaternion q = (w, x, y, z)."""
    vx, vy, vz = v
    qw, qx, qy, qz = q
    cx = qy * vz - qz * vy + qw * vx
    cy = qz * vx - qx * vz + qw * vy
    cz = qx * vy - qy * vx + qw * vz
    rx = qy * cz - qz * cy
    ry = qz * cx - qx * cz
    rz = qx * cy - qy * cx
    return (vx + 2.0 * rx, vy + 2.0 * ry, vz + 2.0 * rz)


def export_abuscan_and_colmap_manifests(photo_dir: str, matched_cameras: list, session_name: str = "AbuScanSession"):
    """
    Writes:
    1. `<photo_dir>/session_manifest.abuscan.json`
    2. `<photo_dir>/colmap_images.txt`
    """
    bridge = AbuClockBridge.instance()
    entries = []
    colmap_lines = [
        "# Image list with two lines of data per image:",
        "#   IMAGE_ID, QW, QX, QY, QZ, TX, TY, TZ, CAMERA_ID, NAME",
        "#   POINTS2D[] as (X, Y, POINT3D_ID)",
    ]

    for idx, cam in enumerate(matched_cameras, start=1):
        tai_ns = int(cam.get("tai_ns") or (int(cam.get("epoch", 0.0) * 1e9) + TAI_UTC_OFFSET_NS))
        snap = bridge.synthesize_from_tai_ns(tai_ns)
        smpte_tc = cam.get("smpte_timecode") or snap.smpte_string
        bcd_tc = int(cam.get("bcd_timecode") or snap.bcd_timecode)
        qw = float(cam.get("q_w", 1.0))
        qx = float(cam.get("q_x", 0.0))
        qy = float(cam.get("q_y", 0.0))
        qz = float(cam.get("q_z", 0.0))
        tx = float(cam.get("x_local_m", cam.get("local_x", 0.0)))
        ty = float(cam.get("y_local_m", cam.get("local_y", 0.0)))
        tz = float(cam.get("z_local_m", cam.get("local_z", 0.0)))
        label = cam["label"]

        entries.append(
            {
                "image_id": idx,
                "sensor_id": cam.get("sensor_id", "DSLR-External"),
                "file_path": label,
                "tai_ns": tai_ns,
                "smpte_timecode": smpte_tc,
                "bcd_timecode": f"0x{bcd_tc:08X}",
                "subframe_phase": round(snap.phase, 6),
                "kalman_error_ns": snap.kalman_offset_ns,
                "pose": {
                    "qw": round(qw, 6),
                    "qx": round(qx, 6),
                    "qy": round(qy, 6),
                    "qz": round(qz, 6),
                    "tx_m": round(tx, 5),
                    "ty_m": round(ty, 5),
                    "tz_m": round(tz, 5),
                },
                "camera_model_id": 1,
            }
        )
        colmap_lines.append(f"{idx} {qw:.6f} {qx:.6f} {qy:.6f} {qz:.6f} {tx:.6f} {ty:.6f} {tz:.6f} 1 {label}")
        colmap_lines.append("")

    abuscan_path = os.path.join(photo_dir, "session_manifest.abuscan.json")
    colmap_path = os.path.join(photo_dir, "colmap_images.txt")

    manifest = {
        "schema": "abu.trackscan.manifest.v1",
        "session_name": session_name,
        "clock_engine": "AbuClock-ST2059",
        "fps_num": bridge.fps_num,
        "fps_den": bridge.fps_den,
        "drop_frame": bridge.drop_frame,
        "capture_count": len(entries),
        "captures": entries,
    }
    with open(abuscan_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)

    with open(colmap_path, "w", encoding="utf-8") as f:
        f.write("\n".join(colmap_lines))

    return abuscan_path, colmap_path


def main():
    print_banner()
    photo_dir = input("Enter path to Mirrorless Photos folder: ").strip().strip('"')
    telemetry_csv = input("Enter path to iPhone telemetry_log.csv: ").strip().strip('"')

    try:
        lx = float(input("  X Offset (Left/Right cm) [0.0]: ") or 0.0)
        ly = float(input("  Y Offset (Up/Down cm)    [0.0]: ") or 0.0)
        lz = float(input("  Z Offset (Depth cm)      [0.0]: ") or 0.0)
    except ValueError:
        lx = ly = lz = 0.0

    offset_m = (lx / 100.0, ly / 100.0, lz / 100.0)

    if not os.path.isdir(photo_dir) or not os.path.isfile(telemetry_csv):
        print("[!] Invalid folder or CSV path.")
        sys.exit(1)

    records = load_telemetry_csv(telemetry_csv)
    if not records:
        print("[!] No records parsed. Exiting.")
        sys.exit(1)

    valid_extensions = (".jpg", ".jpeg", ".tif", ".tiff", ".dng", ".heic", ".png")
    images = [os.path.join(photo_dir, f) for f in os.listdir(photo_dir) if f.lower().endswith(valid_extensions)]
    if not images:
        print(f"[!] No valid images found in: {photo_dir}")
        sys.exit(1)

    first_p_time_ms = load_exif_timestamp(images[0])
    tel_start_ms = records[0]["timestamp"]
    time_diff_hours = round((first_p_time_ms - tel_start_ms) / 3600000.0)
    auto_tz_offset_ms = time_diff_hours * 3600000.0 if abs(time_diff_hours) >= 1.0 else 0.0

    matched_cameras = []
    for img_path in images:
        filename = os.path.basename(img_path)
        raw_time_ms = load_exif_timestamp(img_path)
        img_time_ms = raw_time_ms - auto_tz_offset_ms
        closest = find_telemetry_for_timestamp(img_time_ms, records)
        q = (closest["q_w"], closest["q_x"], closest["q_y"], closest["q_z"])
        rot_offset = rotate_vector_by_quaternion(offset_m, q)

        corr_x = closest["local_x"] + rot_offset[0]
        corr_y = closest["local_y"] + rot_offset[1]
        corr_z = closest["local_z"] + rot_offset[2]

        corr_lat = closest["gps_lat"]
        corr_lon = closest["gps_lon"]
        corr_gps_alt = closest["gps_alt"] + rot_offset[2]
        if closest["gps_enabled"] and closest["gps_lat"] != 0.0:
            corr_lat += rot_offset[1] / 111111.0
            corr_lon += rot_offset[0] / (111111.0 * math.cos(closest["gps_lat"] * math.pi / 180.0))

        time_diff = (img_time_ms - closest["timestamp"]) / 1000.0
        matched_cameras.append(
            {
                "label": filename,
                "x_local_m": corr_x,
                "y_local_m": corr_y,
                "z_local_m": corr_z,
                "baro_alt_m": closest["baro_alt"] + rot_offset[2],
                "latitude": corr_lat,
                "longitude": corr_lon,
                "gps_alt_m": corr_gps_alt,
                "yaw": closest["yaw"],
                "pitch": closest["pitch"],
                "roll": closest["roll"],
                "q_w": closest["q_w"],
                "q_x": closest["q_x"],
                "q_y": closest["q_y"],
                "q_z": closest["q_z"],
                "time_diff_sec": time_diff,
                "tai_ns": closest["tai_ns"],
                "smpte_timecode": closest["smpte_timecode"],
                "bcd_timecode": closest["bcd_timecode"],
            }
        )

    matched_cameras.sort(key=lambda x: x["label"])
    output_csv = os.path.join(photo_dir, "dslr_metashape_cameras.csv")
    header = "label,x_local_m,y_local_m,z_local_m,baro_alt_m,latitude,longitude,gps_alt_m,yaw,pitch,roll,time_diff_sec,tai_ns,smpte_timecode,bcd_timecode\n"
    with open(output_csv, "w", encoding="utf-8") as f:
        f.write(header)
        for cam in matched_cameras:
            f.write(
                f"{cam['label']},{cam['x_local_m']:.6f},{cam['y_local_m']:.6f},{cam['z_local_m']:.6f},"
                f"{cam['baro_alt_m']:.6f},{cam['latitude']:.8f},{cam['longitude']:.8f},{cam['gps_alt_m']:.6f},"
                f"{cam['yaw']:.4f},{cam['pitch']:.4f},{cam['roll']:.4f},{cam['time_diff_sec']:.4f},"
                f"{cam['tai_ns']},{cam['smpte_timecode']},0x{cam['bcd_timecode']:08X}\n"
            )

    abuscan_path, colmap_path = export_abuscan_and_colmap_manifests(photo_dir, matched_cameras)
    print(f"Saved Metashape CSV: {output_csv}")
    print(f"Saved AbuScan Manifest: {abuscan_path}")
    print(f"Saved COLMAP Poses: {colmap_path}")


if __name__ == "__main__":
    main()
