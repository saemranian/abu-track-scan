#!/usr/bin/env python3
"""
CamTrack Pro - Professional DSLR/Mirrorless Telemetry Post-Processor
Author: Antigravity Agent (DeepMind Coding Team)

Matches raw photo folders from professional DSLR/Mirrorless cameras with continuous
telemetry logs exported from the CamTrack Pro iOS app. Performs linear spatial interpolation,
normalized quaternion LERP for 3D attitude, and applies a rotated 3D lever-arm offset correction.
"""

import os
import sys
import csv
import math
from datetime import datetime
from PIL import Image
from PIL.ExifTags import TAGS

def print_banner():
    banner = """
========================================================================
             CAMTRACK PRO - TELEMETRY POST-PROCESSOR
========================================================================
    * High-Precision Temporal Interpolation
    * Normalized Quaternion LERP (Drift-Free Rotation)
    * Rotated 3D Lever-Arm Offset Rig Correction
========================================================================
"""
    print(banner)

def load_exif_timestamp(img_path):
    """
    Reads EXIF tags using Pillow to retrieve the precise capture time with sub-seconds.
    Falls back to filename parsing or filesystem modification time to guarantee a timestamp.
    Returns: Timestamp in milliseconds since Epoch (UTC).
    """
    # Layer 1: EXIF Metadata
    try:
        with Image.open(img_path) as img:
            exif_data = img._getexif()
            if exif_data:
                tags = {}
                for tag_id, value in exif_data.items():
                    tag_name = TAGS.get(tag_id, tag_id)
                    tags[tag_name] = value
                
                date_str = tags.get('DateTimeOriginal') or tags.get('DateTime')
                if date_str:
                    subsec_str = tags.get('SubSecTimeOriginal') or tags.get('SubSecTime') or '0'
                    dt = datetime.strptime(date_str, "%Y:%m:%d %H:%M:%S")
                    epoch_sec = dt.timestamp()
                    subsec = float("0." + subsec_str) if subsec_str.isdigit() else 0.0
                    return (epoch_sec + subsec) * 1000.0
    except Exception:
        pass
        
    # Layer 2: Filename Regex Fallback (e.g. 2026_05_27_10_02_IMG_1255.JPG)
    p_name = os.path.basename(img_path)
    import re
    match = re.search(r'(\d{4})_(\d{2})_(\d{2})_(\d{2})_(\d{2})_(\d{2})?', p_name)
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

def load_telemetry_csv(csv_path):
    """
    Parses the CamTrack telemetry CSV and loads records sorted by timestamp.
    Supports both legacy and upgraded header formats.
    """
    records = []
    try:
        with open(csv_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            # Normalize fieldnames to lowercase for safe lookups
            if reader.fieldnames:
                reader.fieldnames = [fn.strip().lower() for fn in reader.fieldnames]
            else:
                return []
                
            for rec in reader:
                # Resolve timestamp/epoch (in milliseconds since epoch)
                raw_time = rec.get('timestamp_ms') or rec.get('epoch')
                if raw_time is None:
                    continue
                try:
                    t_val = float(raw_time)
                except ValueError:
                    continue
                    
                try:
                    records.append({
                        'timestamp': t_val,
                        'local_x': float(rec.get('local_x_m') or rec.get('local_x') or 0.0),
                        'local_y': float(rec.get('local_y_m') or rec.get('local_y') or 0.0),
                        'local_z': float(rec.get('local_z_m') or rec.get('local_z') or 0.0),
                        'baro_alt': float(rec.get('baro_alt_m') or rec.get('baro_altitude') or 0.0),
                        'pressure': float(rec.get('baro_press_kpa') or rec.get('pressure') or 0.0),
                        'pitch': float(rec.get('pitch_deg') or rec.get('pitch') or 0.0),
                        'roll': float(rec.get('roll_deg') or rec.get('roll') or 0.0),
                        'yaw': float(rec.get('yaw_deg') or rec.get('yaw') or 0.0),
                        'q_w': float(rec.get('q_w') or 1.0),
                        'q_x': float(rec.get('q_x') or 0.0),
                        'q_y': float(rec.get('q_y') or 0.0),
                        'q_z': float(rec.get('q_z') or 0.0),
                        'gps_enabled': int(float(rec.get('gps_enabled') or rec.get('gps_enabled') or 0.0)) == 1,
                        'gps_lat': float(rec.get('gps_lat') or rec.get('gps_latitude') or 0.0),
                        'gps_lon': float(rec.get('gps_lon') or rec.get('gps_longitude') or 0.0),
                        'gps_alt': float(rec.get('gps_alt_m') or rec.get('gps_altitude') or 0.0),
                        'gps_acc_h': float(rec.get('gps_acc_h_m') or rec.get('gps_acc_h') or 0.0),
                        'gps_acc_v': float(rec.get('gps_acc_v_m') or rec.get('gps_acc_v') or 0.0)
                    })
                except (ValueError, TypeError):
                    continue
        # Sort by timestamp to ensure binary search validity
        records.sort(key=lambda x: x['timestamp'])
        return records
    except Exception as e:
        print(f"[!] Failed to parse telemetry CSV: {e}")
        return []

def interpolate_telemetry(t, rec_a, rec_b):
    """
    Executes linear spatial interpolation and normalized quaternion Lerp (NLerp) 
    to obtain telemetry estimates at precise timestamp 't' between two records.
    """
    t_a = rec_a['timestamp']
    t_b = rec_b['timestamp']
    
    if abs(t_b - t_a) < 1e-5:
        return rec_a
        
    f = (t - t_a) / (t_b - t_a)
    
    # 1. Linear interpolation of position & barometer
    interp = {
        'timestamp': t,
        'local_x': rec_a['local_x'] + f * (rec_b['local_x'] - rec_a['local_x']),
        'local_y': rec_a['local_y'] + f * (rec_b['local_y'] - rec_a['local_y']),
        'local_z': rec_a['local_z'] + f * (rec_b['local_z'] - rec_a['local_z']),
        'baro_alt': rec_a['baro_alt'] + f * (rec_b['baro_alt'] - rec_a['baro_alt']),
        'gps_enabled': rec_a['gps_enabled'],
        'gps_lat': rec_a['gps_lat'] + f * (rec_b['gps_lat'] - rec_a['gps_lat']),
        'gps_lon': rec_a['gps_lon'] + f * (rec_b['gps_lon'] - rec_a['gps_lon']),
        'gps_alt': rec_a['gps_alt'] + f * (rec_b['gps_alt'] - rec_a['gps_alt']),
        # Copy orientations directly or calculate later
        'pitch': rec_a['pitch'] + f * (rec_b['pitch'] - rec_a['pitch']),
        'roll': rec_a['roll'] + f * (rec_b['roll'] - rec_a['roll']),
        'yaw': rec_a['yaw'] + f * (rec_b['yaw'] - rec_a['yaw'])
    }
    
    # 2. Normalized Quaternion LERP (NLerp) for 3D rotation interpolation
    q1 = [rec_a['q_w'], rec_a['q_x'], rec_a['q_y'], rec_a['q_z']]
    q2 = [rec_b['q_w'], rec_b['q_x'], rec_b['q_y'], rec_b['q_z']]
    
    # Ensure shortest path LERP (dot product check)
    dot = sum(a * b for a, b in zip(q1, q2))
    if dot < 0.0:
        q2 = [-val for val in q2]
        
    q_interp = [a + f * (b - a) for a, b in zip(q1, q2)]
    
    # Normalize quaternion
    mag = math.sqrt(sum(val * val for val in q_interp))
    if mag > 0:
        q_interp = [val / mag for val in q_interp]
    else:
        q_interp = [1.0, 0.0, 0.0, 0.0]
        
    interp['q_w'], interp['q_x'], interp['q_y'], interp['q_z'] = q_interp
    return interp

def find_telemetry_for_timestamp(t, records):
    """
    Performs binary search to find adjacent records and trigger interpolation.
    """
    if not records:
        return None
        
    if t <= records[0]['timestamp']:
        return records[0]
    if t >= records[-1]['timestamp']:
        return records[-1]
        
    low = 0
    high = len(records) - 1
    
    while low < high:
        mid = (low + high) // 2
        if records[mid]['timestamp'] < t:
            low = mid + 1
        else:
            high = mid
            
    # t is between records[low-1] and records[low]
    return interpolate_telemetry(t, records[low - 1], records[low])

def rotate_vector_by_quaternion(v, q):
    """
    Rotates 3D vector v = (x, y, z) by unit quaternion q = (w, x, y, z).
    Formula: v_corr = v + 2 * q_xyz x (q_xyz x v + q_w * v)
    """
    vx, vy, vz = v
    qw, qx, qy, qz = q
    
    # Cross product: q_xyz x v
    cx = qy * vz - qz * vy
    cy = qz * vx - qx * vz
    cz = qx * vy - qy * vx
    
    # Add q_w * v
    cx += qw * vx
    cy += qw * vy
    cz += qw * vz
    
    # Inner cross product: q_xyz x (q_xyz x v + q_w * v)
    rx = qy * cz - qz * cy
    ry = qz * cx - qx * cz
    rz = qx * cy - qy * cx
    
    # Result: v + 2 * rx_ry_rz
    return (
        vx + 2.0 * rx,
        vy + 2.0 * ry,
        vz + 2.0 * rz
    )

def main():
    print_banner()
    
    # 1. Interactive Inputs with defaults
    print("[*] Configuration Setup:")
    photo_dir = input("Enter path to Mirrorless Photos folder: ").strip().strip('"')
    telemetry_csv = input("Enter path to iPhone telemetry_log.csv: ").strip().strip('"')
    
    # Rig Calibration Offsets (in cm)
    print("\n[*] Rig Calibration Lever-Arm Offsets (cm):")
    try:
        lx = float(input("  X Offset (Left/Right) [0.0]: ") or 0.0)
        ly = float(input("  Y Offset (Up/Down)    [0.0]: ") or 0.0)
        lz = float(input("  Z Offset (Depth)      [0.0]: ") or 0.0)
    except ValueError:
        print("[!] Invalid values. Resetting offsets to 0.0 cm.")
        lx = ly = lz = 0.0
        
    # Convert offsets to meters
    offset_m = (lx / 100.0, ly / 100.0, lz / 100.0)
    
    # Validate Paths
    if not os.path.isdir(photo_dir):
        print(f"[!] Photo directory not found: {photo_dir}")
        sys.exit(1)
    if not os.path.isfile(telemetry_csv):
        print(f"[!] Telemetry CSV file not found: {telemetry_csv}")
        sys.exit(1)
        
    # 2. Parse Telemetry CSV
    print(f"\n[*] Parsing telemetry CSV logs...")
    records = load_telemetry_csv(telemetry_csv)
    if not records:
        print("[!] No records parsed. Exiting.")
        sys.exit(1)
    print(f"  [+] Loaded {len(records)} continuous tracking points.")
    print(f"  [+] Session Range: {datetime.fromtimestamp(records[0]['timestamp']/1000.0)} to {datetime.fromtimestamp(records[-1]['timestamp']/1000.0)}")
    
    # 3. Scan Photos
    print(f"\n[*] Scanning EXIF dates from image folder...")
    valid_extensions = ('.jpg', '.jpeg', '.tif', '.tiff', '.dng', '.heic', '.png')
    images = [os.path.join(photo_dir, f) for f in os.listdir(photo_dir) if f.lower().endswith(valid_extensions)]
    
    if not images:
        print(f"[!] No valid images found in: {photo_dir}")
        sys.exit(1)
        
    print(f"  [+] Found {len(images)} photos. Matching timestamps...")
    
    # Dynamic Hour Offset Alignment calculation
    first_p_time_ms = load_exif_timestamp(images[0])
    tel_start_ms = records[0]['timestamp']
    time_diff_hours = round((first_p_time_ms - tel_start_ms) / 3600000.0)
    auto_tz_offset_ms = time_diff_hours * 3600000.0
    
    if abs(time_diff_hours) >= 1.0:
        print(f"  [!] Large timezone/clock difference of {time_diff_hours:+.1f} hours detected.")
        print(f"  [!] Auto-aligning clocks by subtracting {time_diff_hours:+.1f} hours ({auto_tz_offset_ms/1000.0:+.0f}s).")
    else:
        auto_tz_offset_ms = 0.0
        
    # 4. Process matches
    matched_cameras = []
    missed_count = 0
    
    for img_path in images:
        filename = os.path.basename(img_path)
        raw_time_ms = load_exif_timestamp(img_path)
        img_time_ms = raw_time_ms - auto_tz_offset_ms
        
        # Find spatial marker
        closest = find_telemetry_for_timestamp(img_time_ms, records)
        
        # Calculate rotated lever-arm translation offset
        q = (closest['q_w'], closest['q_x'], closest['q_y'], closest['q_z'])
        rot_offset = rotate_vector_by_quaternion(offset_m, q)
        
        # Correct local positioning
        corr_x = closest['local_x'] + rot_offset[0]
        corr_y = closest['local_y'] + rot_offset[1]
        corr_z = closest['local_z'] + rot_offset[2]
        
        # Correct GPS coordinates if active
        corr_lat = closest['gps_lat']
        corr_lon = closest['gps_lon']
        corr_gps_alt = closest['gps_alt'] + rot_offset[2]
        
        if closest['gps_enabled'] and closest['gps_lat'] != 0.0:
            lat_offset_deg = rot_offset[1] / 111111.0
            lon_offset_deg = rot_offset[0] / (111111.0 * math.cos(closest['gps_lat'] * math.pi / 180.0))
            corr_lat += lat_offset_deg
            corr_lon += lon_offset_deg
            
        time_diff = (img_time_ms - closest['timestamp']) / 1000.0
        
        matched_cameras.append({
            'label': filename,
            'x_local_m': corr_x,
            'y_local_m': corr_y,
            'z_local_m': corr_z,
            'baro_alt_m': closest['baro_alt'] + rot_offset[2],
            'latitude': corr_lat,
            'longitude': corr_lon,
            'gps_alt_m': corr_gps_alt,
            'yaw': closest['yaw'],
            'pitch': closest['pitch'],
            'roll': closest['roll'],
            'time_diff_sec': time_diff
        })
        
    if not matched_cameras:
        print("[!] No cameras could be matched. Check camera clock sync settings.")
        sys.exit(1)
        
    # Sort matched cameras alphabetically for Metashape organization
    matched_cameras.sort(key=lambda x: x['label'])
    
    # 5. Output Matched CSV
    output_csv = os.path.join(photo_dir, "dslr_metashape_cameras.csv")
    print(f"\n[*] Writing results spreadsheet to: {output_csv}")
    
    header = "label,x_local_m,y_local_m,z_local_m,baro_alt_m,latitude,longitude,gps_alt_m,yaw,pitch,roll,time_diff_sec\n"
    try:
        with open(output_csv, 'w', encoding='utf-8') as f:
            f.write(header)
            for cam in matched_cameras:
                row = f"{cam['label']},{cam['x_local_m']:.6f},{cam['y_local_m']:.6f},{cam['z_local_m']:.6f}," \
                      f"{cam['baro_alt_m']:.6f},{cam['latitude']:.8f},{cam['longitude']:.8f},{cam['gps_alt_m']:.6f}," \
                      f"{cam['yaw']:.4f},{cam['pitch']:.4f},{cam['roll']:.4f},{cam['time_diff_sec']:.3f}\n"
                f.write(row)
        
        print("\n========================================================================")
        print(f" SUCCESS: Processed {len(matched_cameras)} images successfully!")
        if missed_count > 0:
            print(f" WARNING: Skipped {missed_count} images due to EXIF timestamp errors.")
        print(f" Saved: {output_csv}")
        print("========================================================================")
        print("Import steps for Metashape:")
        print(" 1. Import your DSLR photos into Metashape.")
        print(" 2. Open Reference Pane, tap Import, select 'dslr_metashape_cameras.csv'.")
        print(" 3. Choose 'Local Coordinates (m)' if GPS was disabled (Indoor Mode).")
        print(" 4. Map columns accordingly (Label=1, X=2, Y=3, Z=4, Yaw=9, Pitch=10, Roll=11).")
        print("========================================================================")
    except Exception as e:
        print(f"[!] Failed to write Metashape output file: {e}")

if __name__ == "__main__":
    main()
