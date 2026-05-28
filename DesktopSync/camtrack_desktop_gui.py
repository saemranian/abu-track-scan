import os
import sys
import subprocess
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
import math
import threading

# Auto-bootstrap necessary libraries for EXIF byte operations and 3D visualizer
try:
    from PIL import Image, ImageTk
    import piexif
except ImportError:
    print("Initializing industrial sync dependencies (pillow, piexif)...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pillow", "piexif"])
    from PIL import Image, ImageTk
    import piexif

try:
    import matplotlib
    matplotlib.use("TkAgg")
    import matplotlib.pyplot as plt
    from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
    from mpl_toolkits.mplot3d import Axes3D
except ImportError:
    print("Installing 3D visualizer dependencies (matplotlib)...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "matplotlib"])
    import matplotlib
    matplotlib.use("TkAgg")
    import matplotlib.pyplot as plt
    from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
    from mpl_toolkits.mplot3d import Axes3D

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
        self.root.title("CAMTRACK PRO // 3DGS & POSTSHOT PROCESSING SUITE")
        self.root.geometry("1100x760")
        self.root.configure(bg=BG_COLOR)
        
        # State variables
        self.photo_dir = tk.StringVar()
        self.csv_path = tk.StringVar()
        self.dx = tk.DoubleVar(value=0.0)
        self.dy = tk.DoubleVar(value=5.0)
        self.dz = tk.DoubleVar(value=12.0)
        self.time_offset = tk.DoubleVar(value=0.0)
        self.time_entry_var = tk.StringVar(value="0.00")
        self._updating_offset = False
        
        # 3D Visualizer State
        self.point_cloud = []      # List of (x, y, z) tuples from PLY
        self.trajectory_points = [] # List of matched camera records
        self.original_ply_path = None
        self.selected_camera_index = None
        
        self.time_offset.trace_add("write", self._on_slider_change)
        self.time_entry_var.trace_add("write", self._on_entry_change)
        
        self.setup_styles()
        self.build_ui()
        
    def setup_styles(self):
        style = ttk.Style()
        style.theme_use("clam")
        
        # Base backgrounds
        style.configure("TFrame", background=BG_COLOR)
        style.configure("Card.TFrame", background=CARD_BG, relief="flat", borderwidth=0)
        
        # Tab Notebook Style
        style.configure("TNotebook", background=BG_COLOR, borderwidth=0)
        style.configure("TNotebook.Tab", background=CARD_BG, foreground=TEXT_MUTED, borderwidth=1, bordercolor=BORDER_COLOR, font=("Consolas", 9, "bold"), padding=10)
        style.map("TNotebook.Tab", 
                  background=[("selected", FIELD_BG), ("active", ACCENT_CYAN)], 
                  foreground=[("selected", ACCENT_CYAN), ("active", BG_COLOR)])
        
        # Core Labels
        style.configure("TLabel", background=CARD_BG, foreground=TEXT_PRIMARY, font=("Consolas", 9))
        style.configure("Header.TLabel", background=CARD_BG, foreground=ACCENT_CYAN, font=("Consolas", 11, "bold"))
        style.configure("Muted.TLabel", background=CARD_BG, foreground=TEXT_MUTED, font=("Consolas", 8))
        
        # Sleek Minimal Buttons
        style.configure("TButton", background=FIELD_BG, foreground=TEXT_PRIMARY, borderwidth=0, relief="flat", font=("Consolas", 9, "bold"))
        style.map("TButton", 
                  background=[("active", ACCENT_CYAN), ("pressed", BORDER_COLOR)], 
                  foreground=[("active", BG_COLOR)])
        
        style.configure("Action.TButton", background=ACCENT_CYAN, foreground=BG_COLOR, font=("Consolas", 10, "bold"), borderwidth=0, relief="flat")
        style.map("Action.TButton", 
                  background=[("active", ACCENT_AMBER)], 
                  foreground=[("active", BG_COLOR)])
        
        style.configure("TEntry", fieldbackground=FIELD_BG, foreground=TEXT_PRIMARY, borderwidth=0, relief="flat", font=("Consolas", 10))
        style.configure("Horizontal.TProgressbar", thickness=8, troughcolor=BG_COLOR, background=ACCENT_CYAN, borderwidth=0)
        
    def build_ui(self):
        # Notebook Tabbed System
        self.notebook = ttk.Notebook(self.root)
        self.notebook.pack(fill="both", expand=True)
        
        # Tab 1: Sync and Console Logs
        self.tab_sync = ttk.Frame(self.notebook, padding=12)
        self.notebook.add(self.tab_sync, text="01 // CONSOLE LOGS & EXIF SYNC")
        
        # Tab 2: 3D Spatial Visualizer Tab
        self.tab_visualizer = ttk.Frame(self.notebook, padding=12)
        self.notebook.add(self.tab_visualizer, text="02 // 3D SPATIAL MAP (POSTSHOT SUITE)")
        
        # ----------------- TAB 1: SYNCHRONIZATION INTERFACE -----------------
        self.tab_sync.columnconfigure(0, weight=4) # Left Panel
        self.tab_sync.columnconfigure(1, weight=5) # Right Logs Panel
        self.tab_sync.rowconfigure(0, weight=1)
        
        left_panel = ttk.Frame(self.tab_sync, padding=10)
        left_panel.grid(row=0, column=0, sticky="nsew")
        left_panel.columnconfigure(0, weight=1)
        left_panel.rowconfigure(3, weight=1)
        
        # Title
        title_frame = ttk.Frame(left_panel)
        title_frame.grid(row=0, column=0, sticky="w", pady=(0, 15))
        ttk.Label(title_frame, text="CAMTRACK PRO // DESKTOP CORE", font=("Consolas", 13, "bold"), background=BG_COLOR, foreground=TEXT_PRIMARY).grid(row=0, column=0, sticky="w")
        ttk.Label(title_frame, text="Version 0.0.5 // Build 18 // 3DGS Postshot Engine Ready", font=("Consolas", 8), background=BG_COLOR, foreground=TEXT_MUTED).grid(row=1, column=0, sticky="w", pady=(2, 0))
        
        # Card 1: Data Directories
        io_card = ttk.Frame(left_panel, style="Card.TFrame", padding=12)
        io_card.grid(row=1, column=0, sticky="ew", pady=(0, 12))
        io_card.columnconfigure(1, weight=1)
        
        ttk.Label(io_card, text="01 // FILE SYSTEM INTERFACE", style="Header.TLabel").grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 10))
        
        ttk.Label(io_card, text="Image Folder:").grid(row=1, column=0, sticky="w", pady=4)
        photo_entry = ttk.Entry(io_card, textvariable=self.photo_dir)
        photo_entry.grid(row=1, column=1, sticky="ew", padx=8, pady=4)
        ttk.Button(io_card, text="Browse", command=self.browse_photos).grid(row=1, column=2, pady=4, ipady=2, ipadx=6)
        
        ttk.Label(io_card, text="Telemetry Log:").grid(row=2, column=0, sticky="w", pady=4)
        csv_entry = ttk.Entry(io_card, textvariable=self.csv_path)
        csv_entry.grid(row=2, column=1, sticky="ew", padx=8, pady=4)
        ttk.Button(io_card, text="Browse", command=self.browse_csv).grid(row=2, column=2, pady=4, ipady=2, ipadx=6)
        
        # Card 2: DSLR Calibrations
        rig_card = ttk.Frame(left_panel, style="Card.TFrame", padding=12)
        rig_card.grid(row=2, column=0, sticky="ew", pady=(0, 12))
        rig_card.columnconfigure(0, weight=1)
        rig_card.columnconfigure(1, weight=1)
        rig_card.columnconfigure(2, weight=1)
        
        ttk.Label(rig_card, text="02 // RIG LEVER-ARM OFFSET (cm)", style="Header.TLabel").grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 10))
        self.add_offset_input(rig_card, "dx (Lateral)", self.dx, 0)
        self.add_offset_input(rig_card, "dy (Vertical)", self.dy, 1)
        self.add_offset_input(rig_card, "dz (Depth)", self.dz, 2)
        
        # Card 3: Clock Sync + Sync Button
        action_card = ttk.Frame(left_panel, style="Card.TFrame", padding=12)
        action_card.grid(row=3, column=0, sticky="nsew")
        action_card.columnconfigure(0, weight=1)
        action_card.rowconfigure(3, weight=1)
        
        ttk.Label(action_card, text="03 // CLOCK OFFSET CORRECTION", style="Header.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 2))
        ttk.Label(action_card, text="Slide to synchronize DSLR shutter time with iPhone Epoch millisecond log.", style="Muted.TLabel").grid(row=1, column=0, sticky="w", pady=(0, 8))
        
        slider_frame = ttk.Frame(action_card)
        slider_frame.grid(row=2, column=0, sticky="ew", pady=(0, 10))
        slider_frame.columnconfigure(0, weight=1)
        
        slider = ttk.Scale(slider_frame, from_=-300.0, to=300.0, variable=self.time_offset, orient="horizontal")
        slider.grid(row=0, column=0, sticky="ew", padx=(0, 12))
        
        self.time_entry = ttk.Entry(slider_frame, textvariable=self.time_entry_var, font=("Consolas", 10), justify="center", width=8)
        self.time_entry.grid(row=0, column=1, padx=(8, 2))
        ttk.Label(slider_frame, text="sec", style="Muted.TLabel").grid(row=0, column=2, sticky="w")
        
        self.sync_btn = ttk.Button(action_card, text="INJECT EXIF & EXPORT REFERENCE METADATA", style="Action.TButton", command=self.run_synchronization)
        self.sync_btn.grid(row=3, column=0, sticky="ew", ipady=10, pady=(10, 0))
        
        self.progress = ttk.Progressbar(action_card, orient="horizontal", mode="determinate")
        self.progress.grid(row=4, column=0, sticky="ew", pady=(10, 0))
        
        # Right Terminal Logs
        right_panel = ttk.Frame(self.tab_sync, padding=10)
        right_panel.grid(row=0, column=1, sticky="nsew")
        right_panel.columnconfigure(0, weight=1)
        right_panel.rowconfigure(1, weight=1)
        
        ttk.Label(right_panel, text="CAMTRACK LOGS & MULTI-INTEGRITY ANALYSIS", font=("Consolas", 11, "bold"), background=BG_COLOR, foreground=ACCENT_CYAN).grid(row=0, column=0, sticky="w", pady=(0, 10))
        
        self.log_box = tk.Text(right_panel, wrap="word", bg=CARD_BG, fg=TEXT_PRIMARY, insertbackground=ACCENT_CYAN, font=("Consolas", 9), bd=0, highlightthickness=1, highlightbackground=BORDER_COLOR, highlightcolor=ACCENT_CYAN, padx=12, pady=12)
        self.log_box.grid(row=1, column=0, sticky="nsew")
        
        scroll = ttk.Scrollbar(right_panel, orient="vertical", command=self.log_box.yview)
        scroll.grid(row=1, column=1, sticky="ns")
        self.log_box.configure(yscrollcommand=scroll.set)
        
        self.log("SYSTEM ACTIVE // DESKTOP GEODETIC DATA SYNCHRONIZER ENGINE")
        self.log("Version: 0.0.5 // OS Platform: Windows")
        self.log("3DGS Postshot Processing Suite integrated...\n")
        
        # ----------------- TAB 2: 3D SPATIAL WORKSTATION -----------------
        self.tab_visualizer.columnconfigure(0, weight=5) # 3D Plot Canvas
        self.tab_visualizer.columnconfigure(1, weight=3) # Side photography controller
        self.tab_visualizer.rowconfigure(0, weight=1)
        
        # Left: Matplotlib 3D Viewport
        self.view_frame = ttk.Frame(self.tab_visualizer, style="Card.TFrame", padding=10)
        self.view_frame.grid(row=0, column=0, sticky="nsew", marginRight=10)
        self.view_frame.columnconfigure(0, weight=1)
        self.view_frame.rowconfigure(1, weight=1)
        
        ttk.Label(self.view_frame, text="04 // INTERACTIVE 3D SPATIAL MAP", style="Header.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 10))
        
        # Create empty Matplotlib figure inside Tkinter
        self.fig = plt.figure(facecolor=BG_COLOR)
        self.ax = self.fig.add_subplot(111, projection='3d', facecolor=BG_COLOR)
        self.fig.subplots_adjust(left=0, right=1, bottom=0, top=1)
        self.setup_3d_axes()
        
        self.canvas_3d = FigureCanvasTkAgg(self.fig, master=self.view_frame)
        self.canvas_3d.get_tk_widget().grid(row=1, column=0, sticky="nsew")
        
        # Right Control Panel
        side_panel = ttk.Frame(self.tab_visualizer, style="Card.TFrame", padding=15)
        side_panel.grid(row=0, column=1, sticky="nsew")
        side_panel.columnconfigure(0, weight=1)
        side_panel.rowconfigure(1, weight=1)
        
        ttk.Label(side_panel, text="05 // PHOTOGRAPHY CONTROLLER", style="Header.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 10))
        
        # Listbox containing photography frames
        self.photo_listbox = tk.Listbox(side_panel, bg=FIELD_BG, fg=TEXT_PRIMARY, font=("Consolas", 9), selectbackground=ACCENT_CYAN, selectforeground=BG_COLOR, highlightthickness=1, highlightbackground=BORDER_COLOR, bd=0)
        self.photo_listbox.grid(row=1, column=0, sticky="nsew", pady=(0, 10))
        self.photo_listbox.bind("<<ListboxSelect>>", self._on_listbox_select)
        
        scroll_list = ttk.Scrollbar(side_panel, orient="vertical", command=self.photo_listbox.yview)
        scroll_list.grid(row=1, column=1, sticky="ns", pady=(0, 10))
        self.photo_listbox.configure(yscrollcommand=scroll_list.set)
        
        # Processing Buttons
        btn_frame = ttk.Frame(side_panel)
        btn_frame.grid(row=2, column=0, columnspan=2, sticky="ew")
        btn_frame.columnconfigure(0, weight=1)
        btn_frame.columnconfigure(1, weight=1)
        
        self.clean_btn = ttk.Button(btn_frame, text="CLEAN POINT CLOUD (SOR)", command=self.clean_point_cloud_sor)
        self.clean_btn.grid(row=0, column=0, sticky="ew", padx=(0, 6), ipady=8)
        
        self.export_btn = ttk.Button(btn_frame, text="EXPORT FOR POSTSHOT (3DGS)", command=self.export_for_postshot)
        self.export_btn.grid(row=0, column=1, sticky="ew", padx=(6, 0), ipady=8)
        
    def setup_3d_axes(self):
        self.ax.clear()
        self.ax.set_facecolor(BG_COLOR)
        self.ax.grid(color=BORDER_COLOR, linestyle='--', linewidth=0.5)
        
        # Cyberpunk visual styles
        self.ax.xaxis.pane.fill = False
        self.ax.yaxis.pane.fill = False
        self.ax.zaxis.pane.fill = False
        
        self.ax.xaxis.pane.set_edgecolor(BORDER_COLOR)
        self.ax.yaxis.pane.set_edgecolor(BORDER_COLOR)
        self.ax.zaxis.pane.set_edgecolor(BORDER_COLOR)
        
        self.ax.set_xlabel("X (East)", color=TEXT_MUTED, fontname="Consolas")
        self.ax.set_ylabel("Y (North)", color=TEXT_MUTED, fontname="Consolas")
        self.ax.set_zlabel("Z (Up)", color=TEXT_MUTED, fontname="Consolas")
        
        self.ax.tick_params(colors=TEXT_MUTED, labelsize=8)
        self.ax.set_title("SPATIAL MAP RECONSTRUCTION CONSOLE", color=ACCENT_CYAN, fontsize=10, fontweight="bold", fontname="Consolas", pad=12)
        
    def format_epoch(self, epoch):
        from datetime import datetime
        return datetime.fromtimestamp(epoch).strftime('%Y-%m-%d %H:%M:%S')

    def _on_slider_change(self, *args):
        if self._updating_offset:
            return
        self._updating_offset = True
        try:
            val = self.time_offset.get()
            self.time_entry_var.set(f"{val:.2f}")
        except Exception:
            pass
        self._updating_offset = False

    def _on_entry_change(self, *args):
        if self._updating_offset:
            return
        self._updating_offset = True
        try:
            val_str = self.time_entry_var.get()
            if val_str == "" or val_str == "-" or val_str == "+":
                pass
            else:
                val = float(val_str)
                if val < -300.0:
                    val = -300.0
                elif val > 300.0:
                    val = 300.0
                self.time_offset.set(val)
        except ValueError:
            pass
        self._updating_offset = False
        
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
            
            # Check for Point Cloud coverage_cloud.ply automatically in same folder
            folder = os.path.dirname(f)
            ply_path = os.path.join(folder, "coverage_cloud.ply")
            if os.path.exists(ply_path):
                self.original_ply_path = ply_path
                self.log(f"AUTO-DETECTED LiDAR CLOUD // {ply_path}")
                self.load_point_cloud(ply_path)
            else:
                self.point_cloud = []
                self.setup_3d_axes()
                self.canvas_3d.draw()
                
    def load_point_cloud(self, path):
        self.log("Parsing sparse point cloud PLY...")
        self.point_cloud = []
        try:
            with open(path, "r") as f:
                lines = f.readlines()
            
            in_header = True
            for line in lines:
                line = line.strip()
                if in_header:
                    if line == "end_header":
                        in_header = False
                    continue
                parts = line.split()
                if len(parts) >= 3:
                    try:
                        self.point_cloud.append((float(parts[0]), float(parts[1]), float(parts[2])))
                    except ValueError:
                        continue
            self.log(f"Loaded point cloud: {len(self.point_cloud)} coordinate vertices.")
            self.render_3d_scene()
        except Exception as e:
            self.log(f"Failed to load point cloud: {str(e)}")
            
    def render_3d_scene(self):
        self.setup_3d_axes()
        
        # 1. Plot Point Cloud sparse vertices (small gray markers)
        # ARKit: X = right, Y = Up, Z = back
        # Visualizer: X = East (Right), Y = North (Back), Z = Up
        if self.point_cloud:
            xs = [p[0] for p in self.point_cloud]
            ys = [p[2] for p in self.point_cloud]  # Swap Y and Z for visual alignment
            zs = [p[1] for p in self.point_cloud]  # Swap Y and Z for visual alignment
            self.ax.scatter(xs, ys, zs, c='#3E4E63', s=0.75, alpha=0.5, depthshade=True, label="Point Cloud")
            
        # 2. Plot Camera Trajectory Path (Yellow line)
        if self.trajectory_points:
            tx = [p["local_x"] for p in self.trajectory_points]
            ty = [p["local_z"] for p in self.trajectory_points]  # Swap Y and Z for visual alignment
            tz = [p["local_y"] for p in self.trajectory_points]  # Swap Y and Z for visual alignment
            self.ax.plot(tx, ty, tz, color=ACCENT_AMBER, linewidth=1.5, label="Trajectory")
            
            # 3. Plot 3D wireframe camera pyramid at each camera position
            for i, p in enumerate(self.trajectory_points):
                color = ACCENT_CYAN if i != self.selected_camera_index else ACCENT_RED
                lw = 1.0 if i != self.selected_camera_index else 2.0
                self.plot_camera_pyramid(p["local_x"], p["local_y"], p["local_z"], p["q_w"], p["q_x"], p["q_y"], p["q_z"], color=color, linewidth=lw)
                
        # Set aspect limits automatically
        if self.point_cloud or self.trajectory_points:
            all_x = [p[0] for p in self.point_cloud] + [p["local_x"] for p in self.trajectory_points]
            all_y = [p[1] for p in self.point_cloud] + [p["local_y"] for p in self.trajectory_points]
            all_z = [p[2] for p in self.point_cloud] + [p["local_z"] for p in self.trajectory_points]
            
            if all_x:
                max_range = max(max(all_x) - min(all_x), max(all_y) - min(all_y), max(all_z) - min(all_z)) / 2.0
                mid_x = (max(all_x) + min(all_x)) / 2.0
                mid_y = (max(all_y) + min(all_y)) / 2.0
                mid_z = (max(all_z) + min(all_z)) / 2.0
                
                self.ax.set_xlim(mid_x - max_range, mid_x + max_range)
                self.ax.set_ylim(mid_z - max_range, mid_z + max_range)  # Swap Y and Z for visual alignment
                self.ax.set_zlim(mid_y - max_range, mid_y + max_range)  # Swap Y and Z for visual alignment
                
        self.canvas_3d.draw()

        
    def plot_camera_pyramid(self, px, py, pz, qw, qx, qy, qz, color=ACCENT_CYAN, linewidth=1.0):
        # Calculate local wireframe vertices shifted along forward axis
        scale = 0.15
        w = scale * 0.5
        h = scale * 0.375
        d = scale
        
        corners_local = [
            [-w, -h, -d], # BL
            [ w, -h, -d], # BR
            [ w,  h, -d], # TR
            [-w,  h, -d]  # TL
        ]
        
        # Quaternion rotation matrix conversion
        r00 = 1.0 - 2.0*(qy**2 + qz**2)
        r01 = 2.0*(qx*qy - qw*qz)
        r02 = 2.0*(qx*qz + qw*qy)
        
        r10 = 2.0*(qx*qy + qw*qz)
        r11 = 1.0 - 2.0*(qx**2 + qz**2)
        r12 = 2.0*(qy*qz - qw*qx)
        
        r20 = 2.0*(qx*qz - qw*qy)
        r21 = 2.0*(qy*qz + qw*qx)
        r22 = 1.0 - 2.0*(qx**2 + qy**2)
        
        R = [
            [r00, r01, r02],
            [r10, r11, r12],
            [r20, r21, r22]
        ]
        
        corners_world = []
        for c in corners_local:
            rx = R[0][0]*c[0] + R[0][1]*c[1] + R[0][2]*c[2]
            ry = R[1][0]*c[0] + R[1][1]*c[1] + R[1][2]*c[2]
            rz = R[2][0]*c[0] + R[2][1]*c[1] + R[2][2]*c[2]
            corners_world.append([px + rx, py + ry, pz + rz])
            
        # Draw 8 segments connecting wireframe
        # Apex lines
        # Swap Y and Z coordinate paths to match rendering mapping (X->X, Y->Z, Z->Y)
        for cw in corners_world:
            self.ax.plot([px, cw[0]], [pz, cw[2]], [py, cw[1]], color=color, linewidth=linewidth, alpha=0.8)
            
        # Base rectangle lines
        for i in range(4):
            c1 = corners_world[i]
            c2 = corners_world[(i+1)%4]
            self.ax.plot([c1[0], c2[0]], [c1[2], c2[2]], [c1[1], c2[1]], color=color, linewidth=linewidth, alpha=0.8)

            
    def _on_listbox_select(self, event):
        selection = self.photo_listbox.curselection()
        if selection:
            idx = selection[0]
            self.selected_camera_index = idx
            record = self.trajectory_points[idx]
            
            # Re-draw to highlight selected camera
            self.render_3d_scene()
            
            # Orbit/focus target visual view onto the selected camera
            self.ax.view_init(elev=30, azim=record["yaw"] - 90)
            self.canvas_3d.draw()
            
            # Trigger pop up dialog displaying thumbnail and georeferenced coordinates
            self.show_photo_dialog(record)
            
    def show_photo_dialog(self, record):
        photo_dir = self.photo_dir.get()
        p_path = os.path.join(photo_dir, record["label"])
        
        popup = tk.Toplevel(self.root)
        popup.title(f"CAMERA SNAPSHOT: {record['label']}")
        popup.geometry("380x480")
        popup.configure(bg=CARD_BG)
        popup.resizable(False, False)
        
        # Center popup relative to main window
        popup.transient(self.root)
        popup.grab_set()
        
        # Render image thumbnail using PIL
        canvas_w = 340
        canvas_h = 240
        
        if os.path.exists(p_path):
            try:
                img = Image.open(p_path)
                img.thumbnail((canvas_w, canvas_h))
                photo_img = ImageTk.PhotoImage(img)
                
                label_img = tk.Label(popup, image=photo_img, bg=FIELD_BG, width=canvas_w, height=canvas_h)
                label_img.image = photo_img # Keep reference!
                label_img.pack(pady=15, padx=20)
            except Exception as e:
                tk.Label(popup, text="Failed to load thumbnail preview", font=("Consolas", 8), bg=FIELD_BG, fg=ACCENT_RED, width=42, height=12).pack(pady=15)
        else:
            tk.Label(popup, text="No synced JPEG image found in folder", font=("Consolas", 8), bg=FIELD_BG, fg=TEXT_MUTED, width=42, height=12).pack(pady=15)
            
        # Metadata labels frame
        info_frame = tk.Frame(popup, bg=CARD_BG)
        info_frame.pack(fill="x", padx=25)
        
        def add_meta(lbl, val, val_color=ACCENT_CYAN):
            f = tk.Frame(info_frame, bg=CARD_BG)
            f.pack(fill="x", pady=2)
            tk.Label(f, text=lbl, font=("Consolas", 8, "bold"), fg=TEXT_MUTED, bg=CARD_BG).pack(side="left")
            tk.Label(f, text=val, font=("Consolas", 8.5, "bold"), fg=val_color, bg=CARD_BG).pack(side="right")
            
        add_meta("FILENAME:", record["label"], TEXT_PRIMARY)
        add_meta("LOCAL POS:", f"[{record['local_x']:+.3f}, {record['local_y']:+.3f}, {record['local_z']:+.3f}]")
        add_meta("GPS COORDS:", f"Lat: {record['gps_lat']:.6f}, Lon: {record['gps_lon']:.6f}")
        add_meta("BARO ALT:", f"{record['baro_alt']:.2f}m")
        add_meta("ATTITUDE:", f"P: {record['pitch']:+.1f}°, R: {record['roll']:+.1f}°, Y: {record['yaw']:+.1f}°", ACCENT_AMBER)
        add_meta("TIME SYNC:", self.format_epoch(record["epoch"]) + f" (dt: {record['time_diff']:+.3f}s)")
        
        # Sleek dismiss button
        ttk.Button(popup, text="DISMISS CONSOLE VIEW", command=popup.destroy).pack(pady=15, ipady=4, ipadx=12)

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
                
            photo_files = [f for f in os.listdir(photo_dir) if f.lower().endswith(('.jpg', '.jpeg', '.tiff', '.heic'))]
            self.log(f"Found {len(photo_files)} photos in directory.")
            
            if not photo_files:
                raise ValueError("No JPEGs, HEICs or TIFF structures found in photos folder!")
                
            lx = self.dx.get() / 100.0
            ly = self.dy.get() / 100.0
            lz = self.dz.get() / 100.0
            dt = self.time_offset.get()
            
            self.log(f"Configured 3D Lever-Arm: [{lx:+.3f}m, {ly:+.3f}m, {lz:+.3f}m]")
            self.log(f"Configured Temporal delta: {dt:+.2f}s")
            
            # Print diagnostic range info
            tel_start = telemetry[0]["epoch"]
            tel_end = telemetry[-1]["epoch"]
            self.log(f"Telemetry GPS track range: {self.format_epoch(tel_start)} to {self.format_epoch(tel_end)}")
            
            # Pre-scan the first photo's raw timestamp
            first_p_path = os.path.join(photo_dir, photo_files[0])
            first_p_time = self.get_photo_timestamp(first_p_path)
            self.log(f"First photo raw time:      {self.format_epoch(first_p_time)}")
            
            # Dynamic Hour Offset Alignment calculation
            time_diff_hours = round((first_p_time - tel_start) / 3600.0)
            auto_tz_offset = time_diff_hours * 3600.0
            
            if abs(time_diff_hours) >= 1.0:
                self.log(f"WARN // Large timezone/clock difference of {time_diff_hours:+.1f} hours detected.")
                self.log(f"WARN // Auto-aligning clocks by subtracting {time_diff_hours:+.1f} hours ({auto_tz_offset:+.0f}s).")
            else:
                auto_tz_offset = 0.0
                
            matched = 0
            self.trajectory_points = []
            self.photo_listbox.delete(0, tk.END)
            
            csv_lines = [
                "label,local_x,local_y,local_z,baro_altitude,gps_latitude,gps_longitude,gps_altitude,yaw,pitch,roll,time_diff"
            ]
            
            total = len(photo_files)
            for i, p_name in enumerate(photo_files):
                p_path = os.path.join(photo_dir, p_name)
                
                # Dynamic photo timestamp (EXIF -> Filename -> mtime)
                raw_time = self.get_photo_timestamp(p_path)
                p_epoch = raw_time - auto_tz_offset + dt
                
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
                    
                    # Binary EXIF Write injection (Skips if image is HEIC to prevent format block error)
                    if not p_name.lower().endswith('.heic'):
                        self.write_exif(p_path, lat, lon, alt + corrected[2])
                    
                    time_diff = p_epoch - record["epoch"]
                    csv_lines.append(f"{p_name},{corrected[0]:.4f},{corrected[1]:.4f},{corrected[2]:.4f},{record['baro_alt']:.2f},{lat:.8f},{lon:.8f},{alt:.3f},{record['yaw']:.2f},{record['pitch']:.2f},{record['roll']:.2f},{time_diff:.3f}")
                    
                    # Log to trajectories array for 3D graphics rendering
                    traj_pt = {
                        "label": p_name,
                        "local_x": corrected[0],
                        "local_y": corrected[1],
                        "local_z": corrected[2],
                        "epoch": p_epoch,
                        "time_diff": time_diff,
                        "baro_alt": record["baro_alt"],
                        "gps_lat": lat,
                        "gps_lon": lon,
                        "gps_alt": alt,
                        "yaw": record["yaw"],
                        "pitch": record["pitch"],
                        "roll": record["roll"],
                        "q_w": record["q_w"],
                        "q_x": record["q_x"],
                        "q_y": record["q_y"],
                        "q_z": record["q_z"]
                    }
                    self.trajectory_points.append(traj_pt)
                    self.photo_listbox.insert(tk.END, f"[{matched:03d}] // {p_name}")
                    
                    if matched % 15 == 0 or matched == total:
                        self.log(f"Sync Match // {p_name} -> Lat: {lat:.6f}, Lon: {lon:.6f}, Alt: {alt:.2f}m (dt: {time_diff:+.3f}s)")
                else:
                    if i < 3 or i == total - 1:
                        p_time_str = self.format_epoch(p_epoch)
                        closest_anyway = self.match_epoch_any(p_epoch, telemetry)
                        diff_sec = p_epoch - closest_anyway["epoch"] if closest_anyway else 999.0
                        self.log(f"Skip // {p_name} (Aligned time: {p_time_str} - nearest log is {diff_sec:+.2f}s away)")
                    elif i == 3:
                        self.log("Skip // ... [suppressing subsequent mismatch logs for brevity] ...")
                    
                self.progress["value"] = int(((i + 1) / total) * 100)
                
            out_csv = os.path.join(photo_dir, "georeferenced_metashape.csv")
            with open(out_csv, "w") as f:
                f.write("\n".join(csv_lines))
                
            self.log("\n----------------------------------------------------------------------")
            self.log(f"GEOREFERENCE SYNC SUCCESSFUL // {matched} / {total} photos synchronized.")
            self.log(f"High-Accuracy telemetry injected into image EXIF binary blocks.")
            self.log(f"CSV reference manifest written to: {out_csv}")
            
            # Redraw view with visual wireframe camera pyramids
            self.render_3d_scene()
            
            messagebox.showinfo("Complete", f"Synchronizer completed successfully.\nSynchronized photos: {matched}")
            
        except Exception as e:
            self.log(f"CRITICAL PIPELINE ERROR // {str(e)}")
            messagebox.showerror("Error", f"Synchronization failed:\n{str(e)}")
            
        finally:
            self.sync_btn.state(["!disabled"])
            
    def clean_point_cloud_sor(self):
        if not self.point_cloud:
            messagebox.showerror("Error", "No point cloud loaded to filter!")
            return
            
        self.clean_btn.state(["disabled"])
        self.log("----------------------------------------------------------------------")
        self.log("RUNNING OFFLINE STATISTICAL OUTLIER REMOVAL (SOR) FILTER...")
        
        # Run SOR filtering in background thread to keep UI completely interactive
        def run_sor_thread():
            points = self.point_cloud
            n = len(points)
            k = 6
            std_ratio = 1.0
            
            if n <= k:
                self.root.after(0, lambda: self.log("Point cloud size is too small for statistical neighbor checks."))
                self.root.after(0, lambda: self.clean_btn.state(["!disabled"]))
                return
                
            avg_dists = []
            for i in range(n):
                pi = points[i]
                dists = []
                for j in range(n):
                    if i == j:
                        continue
                    pj = points[j]
                    d = math.sqrt((pi[0]-pj[0])**2 + (pi[1]-pj[1])**2 + (pi[2]-pj[2])**2)
                    dists.append(d)
                dists.sort()
                avg_d = sum(dists[:k]) / k
                avg_dists.append(avg_d)
                
                if i % 150 == 0:
                    prog = int((i / n) * 100)
                    self.root.after(0, lambda p=prog: self.log(f"Analyzing neighbor distances: {p}%..."))
                    
            mean = sum(avg_dists) / n
            variance = sum((x - mean)**2 for x in avg_dists) / n
            std_dev = math.sqrt(variance)
            
            filtered = []
            for i in range(n):
                if avg_dists[i] <= mean + std_dev * std_ratio:
                    filtered.append(points[i])
                    
            removed = n - len(filtered)
            self.point_cloud = filtered
            
            self.root.after(0, lambda: self.log(f"SOR FILTER SUCCESSFUL // Removed {removed} noise points."))
            self.root.after(0, lambda: self.render_3d_scene())
            self.root.after(0, lambda: self.clean_btn.state(["!disabled"]))
            self.root.after(0, lambda: messagebox.showinfo("Filter Complete", f"Outlier filter successfully completed.\nRemoved noise points: {removed}"))
            
        threading.Thread(target=run_sor_thread, daemon=True).start()
        
    def export_for_postshot(self):
        if not self.point_cloud:
            messagebox.showerror("Error", "No point cloud loaded to export!")
            return
        if not self.trajectory_points:
            messagebox.showerror("Error", "No georeferenced camera positions synced! Run EXIF sync first!")
            return
            
        self.export_btn.state(["disabled"])
        self.log("----------------------------------------------------------------------")
        self.log("EXPORTING PERFECTLY SCALE-CALIBRATED PLY AND CSV FOR POSTSHOT TRAINING...")
        
        # Colorize and export package in background thread
        def run_export_thread():
            try:
                photo_dir = self.photo_dir.get()
                clean_ply_path = os.path.join(photo_dir, "clean_pointcloud.ply")
                alignment_csv_path = os.path.join(photo_dir, "cameras_alignment.csv")
                
                self.root.after(0, lambda: self.log("Projecting and colorizing points using closest synchronized photo viewports..."))
                
                # Proximity-based quick colorization: match each point to the closest camera view and sample image pixel
                points = self.point_cloud
                cameras = self.trajectory_points
                colorized_points = []
                
                # Cache PIL Image handles to prevent repeatedly opening the same file
                img_cache = {}
                
                n = len(points)
                for idx, pt in enumerate(points):
                    # 1. Locate closest camera in 3D distance
                    closest_cam = None
                    min_dist = float("inf")
                    
                    for cam in cameras:
                        d = math.sqrt((pt[0]-cam["local_x"])**2 + (pt[1]-cam["local_y"])**2 + (pt[2]-cam["local_z"])**2)
                        if d < min_dist:
                            min_dist = d
                            closest_cam = cam
                            
                    r, g, b = 180, 180, 180 # Default clean gray
                    
                    if closest_cam:
                        p_name = closest_cam["label"]
                        p_path = os.path.join(photo_dir, p_name)
                        
                        # Project the point onto camera sensor coordinate system
                        # Translate
                        tx = pt[0] - closest_cam["local_x"]
                        ty = pt[1] - closest_cam["local_y"]
                        tz = pt[2] - closest_cam["local_z"]
                        
                        # Rotate using inverse rotation matrix (transposed R)
                        qw, qx, qy, qz = closest_cam["q_w"], closest_cam["q_x"], closest_cam["q_y"], closest_cam["q_z"]
                        r00 = 1.0 - 2.0*(qy**2 + qz**2)
                        r01 = 2.0*(qx*qy - qw*qz)
                        r02 = 2.0*(qx*qz + qw*qy)
                        r10 = 2.0*(qx*qy + qw*qz)
                        r11 = 1.0 - 2.0*(qx**2 + qz**2)
                        r12 = 2.0*(qy*qz - qw*qx)
                        r20 = 2.0*(qx*qz - qw*qy)
                        r21 = 2.0*(qy*qz + qw*qx)
                        r22 = 1.0 - 2.0*(qx**2 + qy**2)
                        
                        # Local coords: Pc = R^T * T
                        lx = r00*tx + r10*ty + r20*tz
                        ly = r01*tx + r11*ty + r21*tz
                        lz = r02*tx + r12*ty + r22*tz
                        
                        # Project onto sensor plane if in front of camera
                        if lz < 0:
                            # Estimate camera intrinsics dynamically
                            # For binned 12MP: width 4032, height 3024, focal length ~3050px.
                            width, height = 4032, 3024
                            if p_name not in img_cache and os.path.exists(p_path):
                                try:
                                    img_cache[p_name] = Image.open(p_path)
                                except Exception:
                                    pass
                                    
                            if p_name in img_cache:
                                w_act, h_act = img_cache[p_name].size
                                width, height = w_act, h_act
                                
                            cx_s = width / 2.0
                            cy_s = height / 2.0
                            f_px = width * 0.75 # Dynamic focal estimation based on standard lens field of view
                            
                            u = cx_s + f_px * (lx / -lz)
                            v = cy_s - f_px * (ly / -lz)
                            
                            if 0 <= u < width and 0 <= v < height and p_name in img_cache:
                                try:
                                    pixel_val = img_cache[p_name].getpixel((int(u), int(v)))
                                    if isinstance(pixel_val, tuple) and len(pixel_val) >= 3:
                                        r, g, b = pixel_val[0], pixel_val[1], pixel_val[2]
                                except Exception:
                                    pass
                                    
                    colorized_points.append((pt[0], pt[1], pt[2], r, g, b))
                    
                    if idx % 200 == 0:
                        prog = int((idx / n) * 100)
                        self.root.after(0, lambda p=prog: self.log(f"Colorizing points: {p}%..."))
                        
                # 2. Write Point Cloud PLY
                ply_content = [
                    "ply",
                    "format ascii 1.0",
                    f"element vertex {len(colorized_points)}",
                    "property float x",
                    "property float y",
                    "property float z",
                    "property uchar red",
                    "property uchar green",
                    "property uchar blue",
                    "end_header"
                ]
                
                for p in colorized_points:
                    ply_content.append(f"{p[0]:.4f} {p[1]:.4f} {p[2]:.4f} {p[3]} {p[4]} {p[5]}")
                    
                with open(clean_ply_path, "w") as f:
                    f.write("\n".join(ply_content))
                    
                # 3. Write cameras_alignment.csv
                csv_headers = "filename,x,y,z,qw,qx,qy,qz,fx,fy,cx,cy,width,height,k1,k2,p1,p2"
                csv_rows = [csv_headers]
                
                for cam in cameras:
                    p_name = cam["label"]
                    width, height = 4032, 3024
                    if p_name in img_cache:
                        width, height = img_cache[p_name].size
                        
                    f_px = width * 0.75
                    cx_s = width / 2.0
                    cy_s = height / 2.0
                    
                    row = f"{p_name},{cam['local_x']:.5f},{cam['local_y']:.5f},{cam['local_z']:.5f},{cam['q_w']:.6f},{cam['q_x']:.6f},{cam['q_y']:.6f},{cam['q_z']:.6f},{f_px:.2f},{f_px:.2f},{cx_s:.1f},{cy_s:.1f},{width},{height},0,0,0,0"
                    csv_rows.append(row)
                    
                with open(alignment_csv_path, "w") as f:
                    f.write("\n".join(csv_rows))
                    
                # Clear PIL caches
                img_cache.clear()
                
                self.root.after(0, lambda: self.log(f"POSTSHOT SUCCESS // Saved colorized PLY: {clean_ply_path}"))
                self.root.after(0, lambda: self.log(f"POSTSHOT SUCCESS // Saved alignments CSV: {alignment_csv_path}"))
                self.root.after(0, lambda: self.export_btn.state(["!disabled"]))
                self.root.after(0, lambda: messagebox.showinfo("Export Successful", "Point cloud and Postshot georeferencing matrix alignments exported successfully!"))
                
            except Exception as e:
                self.root.after(0, lambda: self.log(f"EXPORT ERROR // {str(e)}"))
                self.root.after(0, lambda: self.export_btn.state(["!disabled"]))
                self.root.after(0, lambda: messagebox.showerror("Export Failed", f"Export execution failed:\n{str(e)}"))
                
        threading.Thread(target=run_export_thread, daemon=True).start()
        
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
                epoch = rec["timestamp_ms"]
            elif "epoch" in rec:
                epoch = rec["epoch"]
            else:
                continue
                
            if epoch > 1e11:
                epoch = epoch / 1000.0
                
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
        
    def match_epoch(self, target_epoch, records, max_delta=10.0):
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
        
    def match_epoch_any(self, target_epoch, records):
        if not records:
            return None
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
        return closest
        
    def apply_offsets(self, px, py, pz, qw, qx, qy, qz, lx, ly, lz):
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
        
    def get_photo_timestamp(self, p_path):
        try:
            exif_dict = piexif.load(p_path)
            date_str = None
            if "Exif" in exif_dict and 36867 in exif_dict["Exif"]:
                date_str = exif_dict["Exif"][36867].decode("utf-8")
            elif "0th" in exif_dict and 306 in exif_dict["0th"]:
                date_str = exif_dict["0th"][306].decode("utf-8")
                
            if date_str:
                from datetime import datetime
                dt = datetime.strptime(date_str, "%Y:%m:%d %H:%M:%S")
                epoch_sec = dt.timestamp()
                
                subsec = 0.0
                if "Exif" in exif_dict and 37521 in exif_dict["Exif"]:
                    sub_str = exif_dict["Exif"][37521].decode("utf-8")
                    if sub_str.isdigit():
                        subsec = float("0." + sub_str)
                return epoch_sec + subsec
        except Exception:
            pass
            
        p_name = os.path.basename(p_path)
        import re
        match = re.search(r'(\d{4})_(\d{2})_(\d{2})_(\d{2})_(\d{2})_(\d{2})?', p_name)
        if match:
            parts = match.groups()
            try:
                from datetime import datetime
                if parts[5]:
                    dt = datetime(int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4]), int(parts[5]))
                else:
                    dt = datetime(int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4]))
                return dt.timestamp()
            except ValueError:
                pass
                
        return os.path.getmtime(p_path)

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
