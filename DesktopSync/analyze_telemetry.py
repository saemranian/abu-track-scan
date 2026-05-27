import csv
from datetime import datetime

csv_path = r"C:\Users\USer\Documents\Works\Apps\CamTrack Pro 01\Exports\02\telemetry_log.csv"

def format_epoch(epoch):
    return datetime.fromtimestamp(epoch).strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]

with open(csv_path, 'r') as f:
    reader = csv.DictReader(f)
    records = []
    for r in reader:
        epoch = float(r['timestamp_ms'])
        records.append(epoch)

records.sort()
print(f"Total records: {len(records)}")
print(f"Start: {records[0]} ({format_epoch(records[0]/1000.0)})")
print(f"End:   {records[-1]} ({format_epoch(records[-1]/1000.0)})")
print(f"Duration: {(records[-1] - records[0]) / 1000.0:.2f} seconds")

# Calculate gaps
gaps = []
for i in range(len(records) - 1):
    diff = records[i+1] - records[i]
    if diff > 1000.0:  # gap larger than 1 second
        gaps.append((i, records[i], records[i+1], diff / 1000.0))

print(f"\nGaps larger than 1 second (Total {len(gaps)}):")
for idx, t1, t2, sec in sorted(gaps, key=lambda x: x[3], reverse=True)[:20]:
    print(f"  Line {idx+2}: {format_epoch(t1/1000.0)} to {format_epoch(t2/1000.0)} - Gap: {sec:.3f}s")
