import os
import sys
import subprocess
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
import math

# Auto-bootstrap necessary libraries for EXIF byte operations
try:
    from PIL import Image, ImageTk
    import piexif
except ImportError:
    print("Initializing industrial sync dependencies (pillow, piexif)...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pillow", "piexif"])
    from PIL import Image
    import piexif

# Pro Minimal Slate Dark Palette
BG_COLOR = "#05070B"
CARD_BG = "#0D1017"
FIELD_BG = "#131722"
BORDER_COLOR = "#1D2333"
TEXT_PRIMARY = "#FFFFFF"
TEXT_MUTED = "#828F9F"
ACCENT_CYAN = "#00F0FF"
ACCENT_AMBER = "#FFC400"
ACCENT_RED = "#FF3366"

class CamTrackDesktopApp:
    def __init__(self, root):
        self.root = root
        self.root.title("CAMTRACK PRO // DESKTOP CORE")
        self.root.geometry("1020x700")
        self.root.configure(bg=BG_COLOR)
        
        # State variables
        self.photo_dir = tk.StringVar()
        self.csv_path = tk.StringVar()
        self.dx = tk.DoubleVar(value=0.0)
        self.dy = tk.DoubleVar(value=5.0)
        self.dz = tk.DoubleVar(value=12.0)
        self.time_offset = tk.DoubleVar(value=0.0)
        
        self.setup_styles()
        self.build_ui()
        
    def setup_styles(self):
        style = ttk.Style()
        style.theme_use("clam")
        
        # Base backgrounds
        style.configure("TFrame", background=BG_COLOR)
        style.configure("Card.TFrame", background=CARD_BG, relief="flat", borderwidth=0)
        
        # Core Labels (Unified clean typography)
        style.configure("TLabel", background=CARD_BG, foreground=TEXT_PRIMARY, font=("Consolas", 9))
        style.configure("Header.TLabel", background=CARD_BG, foreground=ACCENT_CYAN, font=("Consolas", 11, "bold"))
        style.configure("Muted.TLabel", background=CARD_BG, foreground=TEXT_MUTED, font=("Consolas", 8))
        
        # Sleek Minimal Buttons
        style.configure("TButton", background=FIELD_BG, foreground=TEXT_PRIMARY, borderwidth=0, relief="flat", font=("Consolas", 9, "bold"))
        style.map("TButton", 
                  background=[("active", ACCENT_CYAN), ("pressed", BORDER_COLOR)], 
                  foreground=[("active", BG_COLOR)])
        
        # Main georeference button
        style.configure("Action.TButton", background=ACCENT_CYAN, foreground=BG_COLOR, font=("Consolas", 10, "bold"), borderwidth=0, relief="flat")
        style.map("Action.TButton", 
                  background=[("active", ACCENT_AMBER)], 
                  foreground=[("active", BG_COLOR)])
        
        # Sleek entry fields
        style.configure("TEntry", fieldbackground=FIELD_BG, foreground=TEXT_PRIMARY, borderwidth=0, relief="flat", font=("Consolas", 10))
        
        # Minimal progress bar
        style.configure("Horizontal.TProgressbar", thickness=8, troughcolor=BG_COLOR, background=ACCENT_CYAN, borderwidth=0)
        
    def build_ui(self):
        # 2-Column Master grid
        self.root.columnconfigure(0, weight=4) # Parameters Panel (Left)
        self.root.columnconfigure(1, weight=5) # Logs Console (Right)
        self.root.rowconfigure(0, weight=1)
        
        # ----------------- LEFT: PARAMETERS PANEL -----------------
        left_panel = ttk.Frame(self.root, padding=20)
        left_panel.grid(row=0, column=0, sticky="nsew")
        left_panel.columnconfigure(0, weight=1)
        left_panel.rowconfigure(0, weight=0)
        left_panel.rowconfigure(1, weight=0)
        left_panel.rowconfigure(2, weight=0)
        left_panel.rowconfigure(3, weight=1)
        
        # Title Card
        title_frame = ttk.Frame(left_panel)
        title_frame.grid(row=0, column=0, sticky="w", pady=(0, 20))
        ttk.Label(title_frame, text="CAMTRACK PRO // DESKTOP CONSOLE", font=("Consolas", 13, "bold"), background=BG_COLOR, foreground=TEXT_PRIMARY).grid(row=0, column=0, sticky="w")
        ttk.Label(title_frame, text="Version 0.0.3 // Build 1 // Active Release", font=("Consolas", 8), background=BG_COLOR, foreground=TEXT_MUTED).grid(row=1, column=0, sticky="w", pady=(2, 0))
        
        # Card 1: Data Directories
        io_card = ttk.Frame(left_panel, style="Card.TFrame", padding=15)
        io_card.grid(row=1, column=0, sticky="ew", pady=(0, 15))
        io_card.columnconfigure(1, weight=1)
        
        ttk.Label(io_card, text="01 // FILE SYSTEM INTERFACE", style="Header.TLabel").grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 12))
        
        # Photos folder row
        ttk.Label(io_card, text="Image Folder:").grid(row=1, column=0, sticky="w", pady=6)
        photo_entry = ttk.Entry(io_card, textvariable=self.photo_dir)
        photo_entry.grid(row=1, column=1, sticky="ew", padx=10, pady=6)
        ttk.Button(io_card, text="Browse", command=self.browse_photos).grid(row=1, column=2, pady=6, ipady=3, ipadx=8)
        
        # CSV file row
        ttk.Label(io_card, text="Telemetry Log:").grid(row=2, column=0, sticky="w", pady=6)
        csv_entry = ttk.Entry(io_card, textvariable=self.csv_path)
        csv_entry.grid(row=2, column=1, sticky="ew", padx=10, pady=6)
        ttk.Button(io_card, text="Browse", command=self.browse_csv).grid(row=2, column=2, pady=6, ipady=3, ipadx=8)
        
        # Card 2: DSLR Calibrations
        rig_card = ttk.Frame(left_panel, style="Card.TFrame", padding=15)
        rig_card.grid(row=2, column=0, sticky="ew", pady=(0, 15))
        rig_card.columnconfigure(0, weight=1)
        rig_card.columnconfigure(1, weight=1)
        rig_card.columnconfigure(2, weight=1)
        
        ttk.Label(rig_card, text="02 // RIG LEVER-ARM OFFSET (cm)", style="Header.TLabel").grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 12))
        
        # Numeric offset entries
        self.add_offset_input(rig_card, "dx (Lateral)", self.dx, 0)
        self.add_offset_input(rig_card, "dy (Vertical)", self.dy, 1)
        self.add_offset_input(rig_card, "dz (Depth)", self.dz, 2)
        
        # Card 3: Clock Sync + Big Button
        action_card = ttk.Frame(left_panel, style="Card.TFrame", padding=15)
        action_card.grid(row=3, column=0, sticky="nsew")
        action_card.columnconfigure(0, weight=1)
        action_card.rowconfigure(3, weight=1)
        
        ttk.Label(action_card, text="03 // CLOCK OFFSET CORRECTION", style="Header.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 4))
        ttk.Label(action_card, text="Slide to synchronize DSLR shutter time with iPhone Epoch millisecond log.", style="Muted.TLabel").grid(row=1, column=0, sticky="w", pady=(0, 10))
        
        slider_frame = ttk.Frame(action_card)
        slider_frame.grid(row=2, column=0, sticky="ew", pady=(0, 15))
        slider_frame.columnconfigure(0, weight=1)
        
        slider = ttk.Scale(slider_frame, from_=-30.0, to=30.0, variable=self.time_offset, orient="horizontal")
        slider.grid(row=0, column=0, sticky="ew", padx=(0, 15))
        
        self.time_lbl = ttk.Label(slider_frame, text="0.00s", style="Header.TLabel")
        self.time_lbl.grid(row=0, column=1)
        self.time_offset.trace_add("write", lambda *args: self.time_lbl.configure(text=f"{self.time_offset.get():+.2f}s"))
        
        # Giant Sync Trigger
        self.sync_btn = ttk.Button(action_card, text="INJECT EXIF & EXPORT REFERENCE METADATA", style="Action.TButton", command=self.run_synchronization)
        self.sync_btn.grid(row=3, column=0, sticky="ew", ipady=12, pady=(15, 0))
        
        self.progress = ttk.Progressbar(action_card, orient="horizontal", mode="determinate")
        self.progress.grid(row=4, column=0, sticky="ew", pady=(12, 0))
        
        # ----------------- RIGHT: TERMINAL LOGS PANEL -----------------
        right_panel = ttk.Frame(self.root, padding=20)
        right_panel.grid(row=0, column=1, sticky="nsew")
        right_panel.columnconfigure(0, weight=1)
        right_panel.rowconfigure(1, weight=1)
        
        ttk.Label(right_panel, text="CAMTRACK LOGS & MULTI-INTEGRITY ANALYSIS", font=("Consolas", 11, "bold"), background=BG_COLOR, foreground=ACCENT_CYAN).grid(row=0, column=0, sticky="w", pady=(0, 15))
        
        # Text box custom formatted to look like a high-end console
        self.log_box = tk.Text(right_panel, wrap="word", bg=CARD_BG, fg=TEXT_PRIMARY, insertbackground=ACCENT_CYAN, font=("Consolas", 9), bd=0, highlightthickness=1, highlightbackground=BORDER_COLOR, highlightcolor=ACCENT_CYAN, padx=15, pady=15)
        self.log_box.grid(row=1, column=0, sticky="nsew")
        
        scroll = ttk.Scrollbar(right_panel, orient="vertical", command=self.log_box.yview)
        scroll.grid(row=1, column=1, sticky="ns")
        self.log_box.configure(yscrollcommand=scroll.set)
        
        # System Banner
        self.log("SYSTEM ACTIVE // DESKTOP GEODETIC DATA SYNCHRONIZER ENGINE")
        self.log("Version: 0.0.3 // Build: 1 // OS Platform: Windows")
        self.log("Standalone georeferencing suite ready for Metashape & RealityCapture...\n")
        
    def add_offset_input(self, parent, label, variable, col):
        frame = ttk.Frame(parent)
        frame.grid(row=1, column=col, sticky="ew", padx=8, pady=5)
        frame.columnconfigure(0, weight=1)
        
        ttk.Label(frame, text=label, style="Muted.TLabel").grid(row=0, column=0, pady=(0, 4))
        entry = ttk.Entry(frame, textvariable=variable, font=("Consolas", 10), justify="center", width=8)
        entry.grid(row=1, column=0, pady=2, ipady=3)
        
    def log(self, msg):
        self.log_box.insert(tk.END, f"{msg}\n")
        self.log_box.see(tk.END)
        self.root.update_idletasks()
        
    def browse_photos(self):
        folder = filedialog.askdirectory()
        if folder:
            self.photo_dir.set(folder)
            self.log(f"LOADED PHOTO DIR // {folder}")
            
    def browse_csv(self):
        f = filedialog.askopenfilename(filetypes=[("CSV Log Files", "*.csv")])
        if f:
            self.csv_path.set(f)
            self.log(f"LOADED CSV LOG // {f}")
            
    def run_synchronization(self):
        photo_dir = self.photo_dir.get()
        csv_path = self.csv_path.get()
        
        if not photo_dir or not os.path.exists(photo_dir):
            messagebox.showerror("IO Error", "Select a valid directory containing camera photos!")
            return
        if not csv_path or not os.path.exists(csv_path):
            messagebox.showerror("IO Error", "Select a valid session telemetry CSV log file!")
            return
            
        self.sync_btn.state(["disabled"])
        self.progress["value"] = 0
        self.log("----------------------------------------------------------------------")
        self.log("STARTING CONSOLIDATED SPATIAL TELEMETRY SYNCHRONIZER INTEGRATION...")
        
        try:
            self.log("Parsing continuous telemetry csv buffer...")
            telemetry = self.parse_csv(csv_path)
            self.log(f"Logged track size: {len(telemetry)} discrete coordinate instances.")
            
            if not telemetry:
                raise ValueError("Parsed CSV contains no geodetic tracking rows!")
                
            photo_files = [f for f in os.listdir(photo_dir) if f.lower().endswith(('.jpg', '.jpeg', '.tiff'))]
            self.log(f"Found {len(photo_files)} photos in directory.")
            
            if not photo_files:
                raise ValueError("No JPEGs or TIFF structures found in photos folder!")
                
            lx = self.dx.get() / 100.0
            ly = self.dy.get() / 100.0
            lz = self.dz.get() / 100.0
            dt = self.time_offset.get()
            
            self.log(f"Configured 3D Lever-Arm: [{lx:+.3f}m, {ly:+.3f}m, {lz:+.3f}m]")
            self.log(f"Configured Temporal delta: {dt:+.2f}s")
            
            matched = 0
            csv_lines = [
                "label,local_x,local_y,local_z,baro_altitude,gps_latitude,gps_longitude,gps_altitude,yaw,pitch,roll,time_diff"
            ]
            
            total = len(photo_files)
            for i, p_name in enumerate(photo_files):
                p_path = os.path.join(photo_dir, p_name)
                
                # Image shutter creation timestamp + slider correction
                p_epoch = os.path.getmtime(p_path) + dt
                
                # Locate nearest spatial odometry packet
                record = self.match_epoch(p_epoch, telemetry)
                
                if record:
                    matched += 1
                    
                    # Apply 3D Quaternion Offset Translation
                    corrected = self.apply_offsets(
                        px=record["local_x"], py=record["local_y"], pz=record["local_z"],
                        qw=record["q_w"], qx=record["q_x"], qy=record["q_y"], qz=record["q_z"],
                        lx=lx, ly=ly, lz=lz
                    )
                    
                    # Compute decimal coordinates
                    lat, lon, alt = self.to_gps_coords(
                        base_lat=record["gps_lat"], base_lon=record["gps_lon"], base_alt=record["gps_alt"],
                        dx=corrected[0] - record["local_x"], dy=corrected[1] - record["local_y"]
                    )
                    
                    # Binary EXIF Write injection
                    self.write_exif(p_path, lat, lon, alt + corrected[2])
                    
                    time_diff = p_epoch - record["epoch"]
                    csv_lines.append(f"{p_name},{corrected[0]:.4f},{corrected[1]:.4f},{corrected[2]:.4f},{record['baro_alt']:.2f},{lat:.8f},{lon:.8f},{alt:.3f},{record['yaw']:.2f},{record['pitch']:.2f},{record['roll']:.2f},{time_diff:.3f}")
                    
                    if matched % 15 == 0 or matched == total:
                        self.log(f"Sync Match // {p_name} -> Lat: {lat:.6f}, Lon: {lon:.6f}, Alt: {alt:.2f}m (dt: {time_diff:+.3f}s)")
                else:
                    self.log(f"Skip // {p_name} [No matching telemetry epoch inside tolerance]")
                    
                self.progress["value"] = int(((i + 1) / total) * 100)
                
            out_csv = os.path.join(photo_dir, "georeferenced_metashape.csv")
            with open(out_csv, "w") as f:
                f.write("\n".join(csv_lines))
                
            self.log("\n----------------------------------------------------------------------")
            self.log(f"GEOREFERENCE SYNC SUCCESSFUL // {matched} / {total} photos synchronized.")
            self.log(f"High-Accuracy telemetry injected into image EXIF binary blocks.")
            self.log(f"CSV reference manifest written to: {out_csv}")
            messagebox.showinfo("Complete", f"Synchronizer completed successfully.\nSynchronized photos: {matched}")
            
        except Exception as e:
            self.log(f"CRITICAL PIPELINE ERROR // {str(e)}")
            messagebox.showerror("Error", f"Synchronization failed:\n{str(e)}")
            
        finally:
            self.sync_btn.state(["!disabled"])
            
    def parse_csv(self, path):
        records = []
        with open(path, "r") as f:
            lines = f.readlines()
            
        if not lines:
            return []
            
        headers = [h.strip().lower() for h in lines[0].split(",")]
        
        for line in lines[1:]:
            parts = line.strip().split(",")
            if len(parts) < len(headers):
                continue
            rec = {}
            for i, h in enumerate(headers):
                val = parts[i].strip()
                try:
                    rec[h] = float(val) if val else 0.0
                except ValueError:
                    rec[h] = val
                    
            epoch = 0.0
            if "timestamp_ms" in rec:
                epoch = rec["timestamp_ms"] / 1000.0
            elif "epoch" in rec:
                epoch = rec["epoch"]
            else:
                continue
                
            records.append({
                "epoch": epoch,
                "local_x": rec.get("local_x_m", rec.get("local_x", 0.0)),
                "local_y": rec.get("local_y_m", rec.get("local_y", 0.0)),
                "local_z": rec.get("local_z_m", rec.get("local_z", 0.0)),
                "q_w": rec.get("q_w", 1.0),
                "q_x": rec.get("q_x", 0.0),
                "q_y": rec.get("q_y", 0.0),
                "q_z": rec.get("q_z", 0.0),
                "gps_lat": rec.get("gps_lat", rec.get("gps_latitude", 0.0)),
                "gps_lon": rec.get("gps_lon", rec.get("gps_longitude", 0.0)),
                "gps_alt": rec.get("gps_alt_m", rec.get("gps_altitude", 0.0)),
                "baro_alt": rec.get("baro_alt_m", rec.get("baro_altitude", 0.0)),
                "yaw": rec.get("yaw_deg", rec.get("yaw", 0.0)),
                "pitch": rec.get("pitch_deg", rec.get("pitch", 0.0)),
                "roll": rec.get("roll_deg", rec.get("roll", 0.0))
            })
        return sorted(records, key=lambda x: x["epoch"])
        
    def match_epoch(self, target_epoch, records, max_delta=2.0):
        low = 0
        high = len(records) - 1
        closest = None
        min_diff = float("inf")
        
        while low <= high:
            mid = (low + high) // 2
            mid_rec = records[mid]
            diff = abs(mid_rec["epoch"] - target_epoch)
            
            if diff < min_diff:
                min_diff = diff
                closest = mid_rec
                
            if mid_rec["epoch"] < target_epoch:
                low = mid + 1
            else:
                high = mid - 1
                
        if min_diff <= max_delta:
            return closest
        return None
        
    def apply_offsets(self, px, py, pz, qw, qx, qy, qz, lx, ly, lz):
        # 3D Quaternion Rotation offset correction
        n1 = qx * 2.0
        n2 = qy * 2.0
        n3 = qz * 2.0
        n4 = qx * n1
        n5 = qy * n2
        n6 = qz * n3
        n7 = qx * n2
        n8 = qx * n3
        n9 = qy * n3
        n10 = qw * n1
        n11 = qw * n2
        n12 = qw * n3
        
        rx = (1.0 - (n5 + n6)) * lx + (n7 - n12) * ly + (n8 + n11) * lz
        ry = (n7 + n12) * lx + (1.0 - (n4 + n6)) * ly + (n9 - n10) * lz
        rz = (n8 - n11) * lx + (n9 + n10) * ly + (1.0 - (n4 + n5)) * lz
        
        return (px + rx, py + ry, pz + rz)
        
    def to_gps_coords(self, base_lat, base_lon, base_alt, dx, dy):
        if base_lat == 0.0 or base_lon == 0.0:
            return 0.0, 0.0, base_alt
            
        lat_offset = dy / 111111.0
        lon_offset = dx / (111111.0 * math.cos(math.radians(base_lat)))
        return base_lat + lat_offset, base_lon + lon_offset, base_alt
        
    def write_exif(self, img_path, latitude, longitude, altitude):
        def to_rational(val):
            abs_val = abs(val)
            deg = int(abs_val)
            m = int((abs_val - deg) * 60)
            s = int(((abs_val - deg) * 60 - m) * 6000)
            return ((deg, 1), (m, 1), (s, 100))
            
        try:
            if latitude == 0.0 and longitude == 0.0:
                return
                
            img = Image.open(img_path)
            exif_dict = piexif.load(img.info.get('exif', b''))
            
            exif_dict["GPS"] = {
                piexif.GPSIFD.GPSLatitudeRef: b'N' if latitude >= 0 else b'S',
                piexif.GPSIFD.GPSLatitude: to_rational(latitude),
                piexif.GPSIFD.GPSLongitudeRef: b'E' if longitude >= 0 else b'W',
                piexif.GPSIFD.GPSLongitude: to_rational(longitude),
                piexif.GPSIFD.GPSAltitudeRef: 0 if altitude >= 0 else 1,
                piexif.GPSIFD.GPSAltitude: (int(abs(altitude) * 1000), 1000)
            }
            
            exif_bytes = piexif.dump(exif_dict)
            img.save(img_path, exif=exif_bytes)
        except Exception as e:
            raise IOError(f"EXIF payload insertion failed: {str(e)}")

if __name__ == "__main__":
    root = tk.Tk()
    app = CamTrackDesktopApp(root)
    root.mainloop()
