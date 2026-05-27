import os
import sys
import subprocess
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
import math

# Auto-install required image metadata processing libraries
try:
    from PIL import Image
    import piexif
except ImportError:
    print("Installing missing dependencies (pillow, piexif)...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pillow", "piexif"])
    from PIL import Image
    import piexif

# Dark Sci-Fi Theme Color Palette
BG_COLOR = "#040712"
CARD_BG = "#0B1124"
TEXT_COLOR = "#FFFFFF"
MUTED_TEXT = "#8B9BB4"
ACCENT_CYAN = "#00E5FF"
ACCENT_YELLOW = "#FFD600"
ACCENT_RED = "#FF1744"
BORDER_COLOR = "#1B2644"

class CamTrackDesktopApp:
    def __init__(self, root):
        self.root = root
        self.root.title("CamTrack Pro - Desktop Sync Control")
        self.root.geometry("980x680")
        self.root.configure(bg=BG_COLOR)
        
        # Paths and state variables
        self.photo_dir = tk.StringVar()
        self.csv_path = tk.StringVar()
        self.dx = tk.DoubleVar(value=0.0)
        self.dy = tk.DoubleVar(value=5.0)
        self.dz = tk.DoubleVar(value=12.0)
        self.time_offset = tk.DoubleVar(value=0.0) # in seconds
        
        # Setup UI
        self.setup_styles()
        self.build_ui()
        
    def setup_styles(self):
        style = ttk.Style()
        style.theme_use("clam")
        
        style.configure("TFrame", background=BG_COLOR)
        style.configure("Card.TFrame", background=CARD_BG, relief="flat")
        
        style.configure("TLabel", background=CARD_BG, foreground=TEXT_COLOR, font=("Courier", 10))
        style.configure("Header.TLabel", background=CARD_BG, foreground=ACCENT_CYAN, font=("Courier", 12, "bold"))
        style.configure("Muted.TLabel", background=CARD_BG, foreground=MUTED_TEXT, font=("Courier", 9))
        
        style.configure("TButton", background=BORDER_COLOR, foreground=TEXT_COLOR, borderwidth=1, relief="flat", font=("Courier", 10, "bold"))
        style.map("TButton", background=[("active", ACCENT_CYAN), ("pressed", CARD_BG)], foreground=[("active", BG_COLOR)])
        
        style.configure("Action.TButton", background=ACCENT_CYAN, foreground=BG_COLOR, font=("Courier", 11, "bold"))
        style.map("Action.TButton", background=[("active", ACCENT_YELLOW)], foreground=[("active", BG_COLOR)])
        
        style.configure("Horizontal.TProgressbar", thickness=15, troughcolor=BG_COLOR, background=ACCENT_CYAN)
        
    def build_ui(self):
        # Master Grid Layout
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)
        
        main_frame = ttk.Frame(self.root, padding=20)
        main_frame.grid(row=0, column=0, sticky="nsew")
        main_frame.columnconfigure(0, weight=4) # Parameters Frame
        main_frame.columnconfigure(1, weight=5) # Terminal Logs Frame
        main_frame.rowconfigure(0, weight=1)
        
        # ----------------- LEFT: PARAMETERS FRAME -----------------
        left_frame = ttk.Frame(main_frame)
        left_frame.grid(row=0, column=0, sticky="nsew", padx=(0, 10))
        left_frame.columnconfigure(0, weight=1)
        left_frame.rowconfigure(0, weight=0)
        left_frame.rowconfigure(1, weight=0)
        left_frame.rowconfigure(2, weight=0)
        left_frame.rowconfigure(3, weight=1)
        
        # Section A: IO Directories
        io_card = ttk.Frame(left_frame, style="Card.TFrame", padding=15)
        io_card.grid(row=0, column=0, sticky="ew", pady=(0, 15))
        io_card.columnconfigure(1, weight=1)
        
        ttk.Label(io_card, text="1. INPUT DIRECTORIES", style="Header.TLabel").grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 10))
        
        # Photos folder
        ttk.Label(io_card, text="Photos Folder:").grid(row=1, column=0, sticky="w", pady=5)
        ttk.Entry(io_card, textvariable=self.photo_dir, font=("Courier", 9), background=BG_COLOR, foreground=TEXT_COLOR).grid(row=1, column=1, sticky="ew", padx=10, pady=5)
        ttk.Button(io_card, text="Browse", command=self.browse_photos).grid(row=1, column=2, pady=5)
        
        # Telemetry file
        ttk.Label(io_card, text="CSV Log File:").grid(row=2, column=0, sticky="w", pady=5)
        ttk.Entry(io_card, textvariable=self.csv_path, font=("Courier", 9), background=BG_COLOR, foreground=TEXT_COLOR).grid(row=2, column=1, sticky="ew", padx=10, pady=5)
        ttk.Button(io_card, text="Browse", command=self.browse_csv).grid(row=2, column=2, pady=5)
        
        # Section B: Lever-Arm DSLR Rig Calibration offsets
        rig_card = ttk.Frame(left_frame, style="Card.TFrame", padding=15)
        rig_card.grid(row=1, column=0, sticky="ew", pady=(0, 15))
        rig_card.columnconfigure(0, weight=1)
        rig_card.columnconfigure(1, weight=1)
        rig_card.columnconfigure(2, weight=1)
        
        ttk.Label(rig_card, text="2. DSLR RIG LEVER-ARM CALIBRATION (cm)", style="Header.TLabel").grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 10))
        
        # X Offset
        ttk.Label(rig_card, text="dx (Lateral):").grid(row=1, column=0, pady=2)
        ttk.Entry(rig_card, textvariable=self.dx, width=8, font=("Courier", 10), justify="center").grid(row=2, column=0, pady=5)
        
        # Y Offset
        ttk.Label(rig_card, text="dy (Vertical):").grid(row=1, column=1, pady=2)
        ttk.Entry(rig_card, textvariable=self.dy, width=8, font=("Courier", 10), justify="center").grid(row=2, column=1, pady=5)
        
        # Z Offset
        ttk.Label(rig_card, text="dz (Longitudinal):").grid(row=1, column=2, pady=2)
        ttk.Entry(rig_card, textvariable=self.dz, width=8, font=("Courier", 10), justify="center").grid(row=2, column=2, pady=5)
        
        # Offset visual text
        guide_text = "• dx: Phone center to DSLR lens axis (Positive = Right)\n• dy: Phone center to DSLR lens axis (Positive = Up)\n• dz: Phone center to DSLR sensor node (Positive = Forward)"
        ttk.Label(rig_card, text=guide_text, style="Muted.TLabel", justify="left").grid(row=3, column=0, columnspan=3, sticky="w", pady=(5, 0))
        
        # Section C: Clock Offset Slider
        clock_card = ttk.Frame(left_frame, style="Card.TFrame", padding=15)
        clock_card.grid(row=2, column=0, sticky="ew", pady=(0, 15))
        clock_card.columnconfigure(0, weight=1)
        
        ttk.Label(clock_card, text="3. DSLR-TO-IPHONE CLOCK DELTA (Seconds)", style="Header.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 5))
        ttk.Label(clock_card, text="Adjust to align DSLR image timestamps with iPhone Epoch clocks.", style="Muted.TLabel").grid(row=1, column=0, sticky="w", pady=(0, 10))
        
        # Slider + Value indicator
        slider_frame = ttk.Frame(clock_card)
        slider_frame.grid(row=2, column=0, sticky="ew")
        slider_frame.columnconfigure(0, weight=1)
        
        slider = ttk.Scale(slider_frame, from_=-60.0, to=60.0, variable=self.time_offset, orient="horizontal")
        slider.grid(row=0, column=0, sticky="ew", padx=(0, 15))
        
        self.time_val_lbl = ttk.Label(slider_frame, text="0.00s", style="Header.TLabel")
        self.time_val_lbl.grid(row=0, column=1)
        
        # Update label dynamically
        self.time_offset.trace_add("write", lambda *args: self.time_val_lbl.configure(text=f"{self.time_offset.get():+.2f}s"))
        
        # Section D: Big Action Trigger
        action_card = ttk.Frame(left_frame, style="Card.TFrame", padding=20)
        action_card.grid(row=3, column=0, sticky="nsew")
        action_card.columnconfigure(0, weight=1)
        action_card.rowconfigure(0, weight=1)
        
        self.sync_btn = ttk.Button(action_card, text="GEOREFERENCE EXIF & SYNC", style="Action.TButton", command=self.run_synchronization)
        self.sync_btn.grid(row=0, column=0, sticky="ew", ipady=15)
        
        # Progress Bar
        self.progress = ttk.Progressbar(action_card, orient="horizontal", mode="determinate")
        self.progress.grid(row=1, column=0, sticky="ew", pady=(15, 0))
        
        # ----------------- RIGHT: TERMINAL LOGS FRAME -----------------
        right_frame = ttk.Frame(main_frame, style="Card.TFrame", padding=15)
        right_frame.grid(row=0, column=1, sticky="nsew", padx=(10, 0))
        right_frame.columnconfigure(0, weight=1)
        right_frame.rowconfigure(1, weight=1)
        
        ttk.Label(right_frame, text="LOGS & REALTIME MATCHING ANALYSIS", style="Header.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 10))
        
        # Log Text Box
        self.log_box = tk.Text(right_frame, wrap="word", bg=BG_COLOR, fg=ACCENT_CYAN, insertbackground=ACCENT_CYAN, font=("Courier", 9.5), bd=1, relief="solid", highlightcolor=BORDER_COLOR)
        self.log_box.grid(row=1, column=0, sticky="nsew")
        
        # Add Scrollbar
        scrollbar = ttk.Scrollbar(right_frame, orient="vertical", command=self.log_box.yview)
        scrollbar.grid(row=1, column=1, sticky="ns")
        self.log_box.configure(yscrollcommand=scrollbar.set)
        
        self.log("System initialized. Version 0.0.5 Desktop Sync engine active.\nReady for reality capture telemetry georeferencing...")
        
    def log(self, message):
        self.log_box.insert(tk.END, f"{message}\n")
        self.log_box.see(tk.END)
        self.root.update_idletasks()
        
    def browse_photos(self):
        folder = filedialog.askdirectory()
        if folder:
            self.photo_dir.set(folder)
            self.log(f"Selected Photos Folder: {folder}")
            
    def browse_csv(self):
        file_path = filedialog.askopenfilename(filetypes=[("CSV files", "*.csv")])
        if file_path:
            self.csv_path.set(file_path)
            self.log(f"Selected Telemetry CSV Log: {file_path}")
            
    def run_synchronization(self):
        photo_dir = self.photo_dir.get()
        csv_path = self.csv_path.get()
        
        if not photo_dir or not os.path.exists(photo_dir):
            messagebox.showerror("Error", "Please select a valid Photos Directory!")
            return
        if not csv_path or not os.path.exists(csv_path):
            messagebox.showerror("Error", "Please select a valid Telemetry CSV log file!")
            return
            
        self.sync_btn.state(["disabled"])
        self.progress["value"] = 0
        self.log("\n-----------------------------------------------------")
        self.log("INITIATING METADATA GEOREFERENCE SYNC PIPELINE...")
        
        try:
            # 1. Parse Telemetry CSV Logs
            self.log("Loading telemetry log entries...")
            telemetry_data = self.parse_telemetry_csv(csv_path)
            self.log(f"Successfully parsed {len(telemetry_data)} tracking coordinates from log.")
            
            if not telemetry_data:
                raise ValueError("No tracking points found in CSV file!")
                
            # 2. Get list of Photos
            all_photos = [f for f in os.listdir(photo_dir) if f.lower().endswith(('.jpg', '.jpeg', '.tiff'))]
            self.log(f"Found {len(all_photos)} images inside photo folder.")
            
            if not all_photos:
                raise ValueError("No JPEG/JPG/TIFF images found inside photo directory!")
                
            # Rig Constants in meters
            lx = self.dx.get() / 100.0
            ly = self.dy.get() / 100.0
            lz = self.dz.get() / 100.0
            t_offset = self.time_offset.get()
            
            self.log(f"Applying Rig Lever-Arm: [{lx:+.3f}m, {ly:+.3f}m, {lz:+.3f}m]")
            self.log(f"Adjusting Clock Delta: {t_offset:+.2f}s")
            
            matched_count = 0
            unmatched_count = 0
            
            # Formatted CSV data container for Agisoft Metashape import references
            metashape_csv_lines = [
                "label,local_x,local_y,local_z,baro_altitude,gps_latitude,gps_longitude,gps_altitude,yaw,pitch,roll,time_diff"
            ]
            
            total_photos = len(all_photos)
            for idx, photo_name in enumerate(all_photos):
                photo_path = os.path.join(photo_dir, photo_name)
                
                # Extract image creation epoch time
                img_epoch = os.path.getmtime(photo_path) + t_offset
                
                # Find closest matching record in telemetry data
                matched_record = self.find_closest_telemetry(img_epoch, telemetry_data)
                
                if matched_record:
                    matched_count += 1
                    
                    # Apply dynamic 3D Lever-Arm Quaternion offset
                    corrected_coords = self.apply_lever_arm(
                        px=matched_record["local_x"],
                        py=matched_record["local_y"],
                        pz=matched_record["local_z"],
                        qw=matched_record["q_w"],
                        qx=matched_record["q_x"],
                        qy=matched_record["q_y"],
                        qz=matched_record["q_z"],
                        lx=lx, ly=ly, lz=lz
                    )
                    
                    # Convert to GPS georeferenced coordinates
                    lat, lon, alt = self.calculate_georeference_gps(
                        base_lat=matched_record["gps_lat"],
                        base_lon=matched_record["gps_lon"],
                        base_alt=matched_record["gps_alt"],
                        local_dx=corrected_coords[0] - matched_record["local_x"],
                        local_dy=corrected_coords[1] - matched_record["local_y"]
                    )
                    
                    # Write High-Accuracy Coordinates directly to image EXIF!
                    self.write_exif_gps(
                        image_path=photo_path,
                        latitude=lat,
                        longitude=lon,
                        altitude=alt + corrected_coords[2] # Combine relative heights
                    )
                    
                    # Add line for reference CSV
                    time_diff = img_epoch - matched_record["epoch"]
                    csv_line = f"{photo_name},{corrected_coords[0]:.4f},{corrected_coords[1]:.4f},{corrected_coords[2]:.4f},{matched_record['baro_alt']:.2f},{lat:.8f},{lon:.8f},{alt:.3f},{matched_record['yaw']:.2f},{matched_record['pitch']:.2f},{matched_record['roll']:.2f},{time_diff:.3f}"
                    metashape_csv_lines.append(csv_line)
                    
                    if matched_count % 10 == 0 or matched_count == total_photos:
                        self.log(f"Sync matched: {photo_name} -> Lat: {lat:.6f}, Lon: {lon:.6f}, Alt: {alt:.2f}m (Diff: {time_diff:+.3f}s)")
                else:
                    unmatched_count += 1
                    self.log(f"WARNING: No matching telemetry found for photo {photo_name}!")
                    
                # Update progress bar
                self.progress["value"] = int(((idx + 1) / total_photos) * 100)
                
            # Write out Georeferenced Metashape cameras CSV file
            output_csv_path = os.path.join(photo_dir, "georeferenced_metashape.csv")
            with open(output_csv_path, "w") as f:
                f.write("\n".join(metashape_csv_lines))
                
            self.log("-----------------------------------------------------")
            self.log(f"SUCCESS: Synchronized {matched_count} / {total_photos} photos.")
            self.log(f"Written high-accuracy georeferences directly inside EXIF tags.")
            self.log(f"Exported reference CSV log to: {output_csv_path}")
            messagebox.showinfo("Success", f"EXIF Sync Complete!\nSuccessfully Georeferenced: {matched_count} images.")
            
        except Exception as e:
            self.log(f"ERROR: Georeference pipeline failed: {str(e)}")
            messagebox.showerror("Error", f"Synchronization failed:\n{str(e)}")
            
        finally:
            self.sync_btn.state(["!disabled"])
            
    def parse_telemetry_csv(self, file_path):
        records = []
        with open(file_path, "r") as f:
            lines = f.readlines()
            
        if not lines:
            return []
            
        headers = [h.strip().lower() for h in lines[0].split(",")]
        
        for line in lines[1:]:
            parts = line.strip().split(",")
            if len(parts) < len(headers):
                continue
                
            rec = {}
            for idx, h in enumerate(headers):
                val = parts[idx].strip()
                try:
                    rec[h] = float(val) if val else 0.0
                except ValueError:
                    rec[h] = val
                    
            # Ensure key coordinates and orientation properties exist
            if "epoch" in rec:
                records.append({
                    "epoch": rec.get("epoch", 0.0),
                    "local_x": rec.get("local_x", 0.0),
                    "local_y": rec.get("local_y", 0.0),
                    "local_z": rec.get("local_z", 0.0),
                    "q_w": rec.get("q_w", 1.0),
                    "q_x": rec.get("q_x", 0.0),
                    "q_y": rec.get("q_y", 0.0),
                    "q_z": rec.get("q_z", 0.0),
                    "gps_lat": rec.get("gps_latitude", 0.0),
                    "gps_lon": rec.get("gps_longitude", 0.0),
                    "gps_alt": rec.get("gps_altitude", 0.0),
                    "baro_alt": rec.get("baro_altitude", 0.0),
                    "yaw": rec.get("yaw", 0.0),
                    "pitch": rec.get("pitch", 0.0),
                    "roll": rec.get("roll", 0.0)
                })
        return sorted(records, key=lambda x: x["epoch"])
        
    def find_closest_telemetry(self, target_epoch, telemetry_records, max_delta=2.0):
        # Perform binary search to find closest tracking epoch
        low = 0
        high = len(telemetry_records) - 1
        closest_record = None
        min_diff = float("inf")
        
        while low <= high:
            mid = (low + high) // 2
            mid_rec = telemetry_records[mid]
            diff = abs(mid_rec["epoch"] - target_epoch)
            
            if diff < min_diff:
                min_diff = diff
                closest_record = mid_rec
                
            if mid_rec["epoch"] < target_epoch:
                low = mid + 1
            else:
                high = mid - 1
                
        if min_diff <= max_delta:
            return closest_record
        return None
        
    def apply_lever_arm(self, px, py, pz, qw, qx, qy, qz, lx, ly, lz):
        # 3D Quaternion Rotation formula: Corrects camera offset coordinate center
        # rotated_offset = Q * d_offset * Q_inverse
        
        # 3D quaternion vector product implementation
        num1 = qx * 2.0
        num2 = qy * 2.0
        num3 = qz * 2.0
        num4 = qx * num1
        num5 = qy * num2
        num6 = qz * num3
        num7 = qx * num2
        num8 = qx * num3
        num9 = qy * num3
        num10 = qw * num1
        num11 = qw * num2
        num12 = qw * num3
        
        rx = (1.0 - (num5 + num6)) * lx + (num7 - num12) * ly + (num8 + num11) * lz
        ry = (num7 + num12) * lx + (1.0 - (num4 + num6)) * ly + (num9 - num10) * lz
        rz = (num8 - num11) * lx + (num9 + num10) * ly + (1.0 - (num4 + num5)) * lz
        
        return (px + rx, py + ry, pz + rz)
        
    def calculate_georeference_gps(self, base_lat, base_lon, base_alt, local_dx, local_dy):
        # Convert metric offsets to GPS decimal degree coordinates
        if base_lat == 0.0 or base_lon == 0.0:
            # Fallback for indoor settings without GPS active
            return 0.0, 0.0, base_alt
            
        lat_offset = local_dy / 111111.0
        lon_offset = local_dx / (111111.0 * math.cos(math.radians(base_lat)))
        
        return base_lat + lat_offset, base_lon + lon_offset, base_alt
        
    def write_exif_gps(self, image_path, latitude, longitude, altitude):
        # Convert float coordinates to EXIF rational format
        def to_rational(val):
            abs_val = abs(val)
            deg = int(abs_val)
            min_val = int((abs_val - deg) * 60)
            sec = int(((abs_val - deg) * 60 - min_val) * 6000)
            return ((deg, 1), (min_val, 1), (sec, 100))
            
        try:
            # Skip if coords are invalid/empty
            if latitude == 0.0 and longitude == 0.0:
                return
                
            img = Image.open(image_path)
            
            # Load existing EXIF or create blank
            exif_dict = piexif.load(img.info.get('exif', b''))
            
            # Setup GPS data blocks
            gps_ifd = {
                piexif.GPSIFD.GPSLatitudeRef: b'N' if latitude >= 0 else b'S',
                piexif.GPSIFD.GPSLatitude: to_rational(latitude),
                piexif.GPSIFD.GPSLongitudeRef: b'E' if longitude >= 0 else b'W',
                piexif.GPSIFD.GPSLongitude: to_rational(longitude),
                piexif.GPSIFD.GPSAltitudeRef: 0 if altitude >= 0 else 1,
                piexif.GPSIFD.GPSAltitude: (int(abs(altitude) * 1000), 1000)
            }
            
            exif_dict["GPS"] = gps_ifd
            exif_bytes = piexif.dump(exif_dict)
            img.save(image_path, exif=exif_bytes)
            
        except Exception as e:
            # Raise to top-level runner
            raise IOError(f"EXIF write failed for image {os.path.basename(image_path)}: {str(e)}")

if __name__ == "__main__":
    root = tk.Tk()
    app = CamTrackDesktopApp(root)
    root.mainloop()
