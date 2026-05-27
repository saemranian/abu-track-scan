import os
import csv
from datetime import datetime

photo_dir = r"C:\Users\USer\Documents\Works\Gaussian Splatting\27th May\01_Exif_Track"
csv_path = r"C:\Users\USer\Documents\Works\Apps\CamTrack Pro 01\Exports\02\telemetry_log.csv"

# Load telemetry
with open(csv_path, 'r') as f:
    reader = csv.DictReader(f)
    telemetry = []
    for r in reader:
        epoch = float(r['timestamp_ms'])
        if epoch > 1e11:
            epoch = epoch / 1000.0
        telemetry.append(epoch)
telemetry.sort()

# Load photos EXIF
from PIL import Image
from PIL.ExifTags import TAGS

photos = sorted([os.path.join(photo_dir, f) for f in os.listdir(photo_dir) if f.lower().endswith(('.jpg', '.jpeg'))])
photo_times = []
for p in photos:
    exif_time = None
    try:
        with Image.open(p) as img:
            exif_data = img._getexif()
            if exif_data:
                date_str = exif_data.get(36867) or exif_data.get(306) # DateTimeOriginal or DateTime
                if date_str:
                    date_str = date_str.decode('utf-8') if isinstance(date_str, bytes) else date_str
                    dt = datetime.strptime(date_str, "%Y:%m:%d %H:%M:%S")
                    exif_time = dt.timestamp()
    except Exception:
        pass
    if exif_time is None:
        # Fallback to get_photo_time filename parsing
        p_name = os.path.basename(p)
        import re
        match = re.search(r'(\d{4})_(\d{2})_(\d{2})_(\d{2})_(\d{2})_(\d{2})?', p_name)
        if match:
            parts = match.groups()
            dt = datetime(int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4]), int(parts[5]) if parts[5] else 0)
            exif_time = dt.timestamp()
        else:
            exif_time = os.path.getmtime(p)
    photo_times.append((os.path.basename(p), exif_time))

# Test different offsets
for offset in [-34.0, -30.0, -26.0, 0.0, 30.0, 34.0]:
    matched_count = 0
    in_gap_1_count = 0
    in_gap_2_count = 0
    valid_matches = []
    
    for fname, p_time in photo_times:
        aligned_time = p_time + offset
        
        # Check closest telemetry record
        closest_t = None
        min_diff = float('inf')
        for t in telemetry:
            diff = abs(t - aligned_time)
            if diff < min_diff:
                min_diff = diff
                closest_t = t
                
        # Is it a match within 10 seconds?
        if min_diff <= 10.0:
            matched_count += 1
            valid_matches.append((fname, min_diff, aligned_time - closest_t))
            
        # Is it in the gaps?
        # Gap 1: 10:02:10.201 to 10:03:33.626
        # Gap 2: 10:04:35.497 to 10:16:00.994
        gap_1_start = telemetry[0] + 8.0 # line 77 is about 8s in
        gap_1_end = telemetry[0] + 91.0 # line 78 is about 91s in
        gap_2_start = telemetry[0] + 153.0 # line 689 is about 153s in
        gap_2_end = telemetry[-1] - 6.0 # line 690 is about 6s from end
        
        if gap_1_start <= aligned_time <= gap_1_end:
            in_gap_1_count += 1
        elif gap_2_start <= aligned_time <= gap_2_end:
            in_gap_2_count += 1
            
    print(f"\nOffset: {offset:+.1f}s")
    print(f"  Matched (<=10s delta): {matched_count} / {len(photos)}")
    print(f"  In Gap 1 (83s):       {in_gap_1_count}")
    print(f"  In Gap 2 (685s):      {in_gap_2_count}")
    if valid_matches:
        print(f"  Sample matches (first 3 and last 3):")
        for f, diff, t_diff in valid_matches[:3] + valid_matches[-3:]:
            print(f"    {f}: delta={diff:.3f}s (aligned_photo - telemetry = {t_diff:+.3f}s)")
