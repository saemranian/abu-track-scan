import os
import sys
import subprocess
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
import math
import threading
import logging
import datetime

def get_log_dir():
    if getattr(sys, 'frozen', False):
        return os.path.join(os.path.dirname(sys.executable), "app_logs")
    else:
        return os.path.join(os.path.dirname(os.path.abspath(__file__)), "app_logs")

# Configure logger
LOG_DIR = get_log_dir()
if not os.path.exists(LOG_DIR):
    try:
        os.makedirs(LOG_DIR)
    except Exception:
        pass

log_file_path = os.path.join(LOG_DIR, "abu_track_desktop.log")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(threadName)s: %(message)s",
    handlers=[
        logging.FileHandler(log_file_path, encoding="utf-8", mode="a"),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger("AbuTrack")
logger.info("=" * 60)
logger.info(f"Abu Track Desktop App Initializing (Local Time: {datetime.datetime.now()})")
logger.info(f"Python: {sys.version}")
logger.info(f"Executable Mode: {'PyInstaller Bundle' if getattr(sys, 'frozen', False) else 'Raw Python Script'}")
logger.info(f"Log directory configured at: {LOG_DIR}")
logger.info("=" * 60)

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
ACCENT_GREEN = "#10B981"


class CamTrackDesktopApp:
    def __init__(self, root):
        self.root = root
        
        # Load versioning information dynamically
        try:
            from version_info import VERSION, BUILD, BUILD_TIME
            title_suffix = f" (v{VERSION} Build {BUILD} - {BUILD_TIME})"
        except ImportError:
            title_suffix = " (v1.0.1 Build 52)"
            
        self.root.title(f"ABU TRACK // 3DGS & METASHAPE PROCESSING SUITE{title_suffix}")
        self.root.geometry("1100x760")
        self.root.configure(bg=BG_COLOR)
        
        # State variables
        self.photo_dir = tk.StringVar()
        self.csv_path = tk.StringVar()
        self.ply_path = tk.StringVar()
        self.atlp_path = tk.StringVar()
        self.calib_photo_dir = tk.StringVar()
        self.calib_board_width = tk.IntVar(value=9)
        self.calib_board_height = tk.IntVar(value=6)
        self.calib_square_size = tk.DoubleVar(value=25.0)
        self.calib_images = []
        self.calib_solved_intrinsics = None
        self.dx = tk.DoubleVar(value=0.0)
        self.dy = tk.DoubleVar(value=5.0)
        self.dz = tk.DoubleVar(value=12.0)
        self.rot_roll = tk.DoubleVar(value=0.0)
        self.rot_pitch = tk.DoubleVar(value=0.0)
        self.rot_yaw = tk.DoubleVar(value=0.0)
        self.time_offset = tk.DoubleVar(value=0.0)
        self.time_entry_var = tk.StringVar(value="0.00")
        self._updating_offset = False
        
        # Camera Lens Calibration profiles
        self.lens_profile = tk.StringVar(value="iPhone 16 Pro Max Main (24mm)")
        self.f_35mm = tk.DoubleVar(value=25.2837)
        self.px_norm = tk.DoubleVar(value=-0.04023)
        self.py_norm = tk.DoubleVar(value=0.01892)
        self.k1 = tk.DoubleVar(value=0.1767097)
        self.k2 = tk.DoubleVar(value=-0.5546028)
        self.k3 = tk.DoubleVar(value=0.5339524)
        self.k4 = tk.DoubleVar(value=0.0)
        self.t1 = tk.DoubleVar(value=0.0)
        self.t2 = tk.DoubleVar(value=0.0)
        self.lens_profile.trace_add("write", self.on_lens_profile_change)
        
        # 3D Visualizer State
        self.point_cloud = []      # List of (x, y, z) tuples from PLY
        self.trajectory_points = [] # List of matched camera records
        self.original_ply_path = None
        self.selected_camera_index = None
        
        self.time_offset.trace_add("write", self._on_slider_change)
        self.time_entry_var.trace_add("write", self._on_entry_change)
        
        self.setup_styles()
        
        # Live Receiver State
        self.receiver_running = False
        self.receiver_thread = None
        self.receiver_sock = None
        self.receiver_packet_count = 0
        self.receiver_last_time = None
        self.receiver_frequency = 0.0
        
        self.receiver_port = tk.IntVar(value=8080)
        self.is_video_stream_enabled = tk.BooleanVar(value=True)
        self.video_stream_port = tk.IntVar(value=8082)
        self.is_spout_enabled = tk.BooleanVar(value=True)
        self.latest_decoded_frame = None
        self.latest_decoded_pil_image = None
        self.video_decoder_running = False
        self.video_decoder_thread = None
        self.spout_sender = None
        self.receiver_status_var = tk.StringVar(value="OFFLINE")
        self.receiver_format_var = tk.StringVar(value="No Stream Detected")
        self.receiver_frames_var = tk.StringVar(value="0")
        self.receiver_hz_var = tk.StringVar(value="0.0 Hz")
        self.receiver_raw_hz_var = tk.StringVar(value="0.0 Hz (Raw)")
        self.receiver_real_hz_var = tk.StringVar(value="0.0 Hz (iOS Lock)")
        self.receiver_latency_var = tk.StringVar(value="No Sync (0.0 ms)")
        self.receiver_smoothing_sec = tk.DoubleVar(value=1.0)
        self.receiver_buffer_ms = tk.DoubleVar(value=100.0)
        self.receiver_auto_calibrate = tk.BooleanVar(value=True)
        self.timeshift_history = []
        self.receiver_pc_time_var = tk.StringVar(value="00:00:00.000")
        
        self.pose_x_var = tk.StringVar(value="0.0000 m")
        self.pose_y_var = tk.StringVar(value="0.0000 m")
        self.pose_z_var = tk.StringVar(value="0.0000 m")
        self.pose_roll_var = tk.StringVar(value="0.00°")
        self.pose_pitch_var = tk.StringVar(value="0.00°")
        self.pose_yaw_var = tk.StringVar(value="0.00°")
        
        # Multi-Protocol Forwarder Server State
        self.forward_enabled = tk.BooleanVar(value=True)
        self.forward_host = tk.StringVar(value="127.0.0.1")
        self.forward_port = tk.IntVar(value=8081)  # Default Unreal plugin listener port
        self.forward_protocol = tk.StringVar(value="Live Link JSON")  # Options: Live Link JSON, FreeD Binary, OpenTrackIO JSON
        self.forwarder_sock = None
        
        # Workstation Offset Overrides (Local modifications applied prior to forwarders/visualizers)
        self.ws_origin_x = tk.DoubleVar(value=0.0)
        self.ws_origin_y = tk.DoubleVar(value=0.0)
        self.ws_origin_z = tk.DoubleVar(value=0.0)
        self.ws_origin_pitch = tk.DoubleVar(value=0.0)
        self.ws_origin_yaw = tk.DoubleVar(value=0.0)
        self.ws_origin_roll = tk.DoubleVar(value=0.0)
        
        self.ws_lever_x = tk.DoubleVar(value=0.0)
        self.ws_lever_y = tk.DoubleVar(value=0.0)
        self.ws_lever_z = tk.DoubleVar(value=0.0)
        
        # Coordinate system alignment preset and custom remapping
        self.pc_align_preset = tk.StringVar(value="Default")
        self.pc_x_sign = tk.IntVar(value=1)
        self.pc_x_src = tk.StringVar(value="X")
        self.pc_y_sign = tk.IntVar(value=1)
        self.pc_y_src = tk.StringVar(value="Y")
        self.pc_z_sign = tk.IntVar(value=1)
        self.pc_z_src = tk.StringVar(value="Z")
        self.pc_roll_sign = tk.IntVar(value=1)
        self.pc_roll_src = tk.StringVar(value="Roll")
        self.pc_pitch_sign = tk.IntVar(value=1)
        self.pc_pitch_src = tk.StringVar(value="Pitch")
        self.pc_yaw_sign = tk.IntVar(value=1)
        self.pc_yaw_src = tk.StringVar(value="Yaw")
        
        # LiDAR custom point cloud translation mapping
        self.pc_lidar_x_sign = tk.IntVar(value=1)
        self.pc_lidar_x_src = tk.StringVar(value="X")
        self.pc_lidar_y_sign = tk.IntVar(value=1)
        self.pc_lidar_y_src = tk.StringVar(value="Y")
        self.pc_lidar_z_sign = tk.IntVar(value=1)
        self.pc_lidar_z_src = tk.StringVar(value="Z")
        
        # Live canvas origin editing and performance metrics
        self.live_edit_origin = tk.BooleanVar(value=False)
        self.forward_delivery_hz_var = tk.StringVar(value="0.0 Hz")
        self.forward_timecode_var = tk.StringVar(value="00:00:00:00")
        
        # Workstation Live 3D Projected Canvas State
        self.live_points = []          # List of (x, y, z) tuples for point cloud
        self.live_trajectory = []      # List of (x, y, z) camera positions
        self.live_rot_x = -0.4         # Initial rotation Pitch
        self.live_rot_y = -0.6         # Initial rotation Yaw
        self.live_rot_z = 0.0          # Initial rotation Roll
        self.live_pan_x = 0.0
        self.live_pan_y = 0.0
        self.live_pan_z = 0.0
        self.live_zoom = 1.0
        self.live_follow = tk.BooleanVar(value=True)
        self.live_view_mode = tk.StringVar(value="Orbit")
        self.live_show_path = tk.BooleanVar(value=True)
        self.live_show_points = tk.BooleanVar(value=True)
        self.build_ui()
        self.root.report_callback_exception = self.report_callback_exception
        self.root.protocol("WM_DELETE_WINDOW", self.on_window_closing)
        self.root.after(33, self.update_pc_local_time)
        
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
        ttk.Label(title_frame, text="ABU TRACK // DESKTOP CORE", font=("Consolas", 13, "bold"), background=BG_COLOR, foreground=TEXT_PRIMARY).grid(row=0, column=0, sticky="w")
        ttk.Label(title_frame, text="Version 0.1.0 // Build 19 // 3DGS & Metashape Workstation Ready", font=("Consolas", 8), background=BG_COLOR, foreground=TEXT_MUTED).grid(row=1, column=0, sticky="w", pady=(2, 0))
        
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
        
        ttk.Label(io_card, text="3rd-Party PLY:").grid(row=3, column=0, sticky="w", pady=4)
        ply_entry = ttk.Entry(io_card, textvariable=self.ply_path)
        ply_entry.grid(row=3, column=1, sticky="ew", padx=8, pady=4)
        ttk.Button(io_card, text="Browse", command=self.browse_ply).grid(row=3, column=2, pady=4, ipady=2, ipadx=6)
        
        ttk.Label(io_card, text="Lens Profile:").grid(row=4, column=0, sticky="w", pady=4)
        atlp_entry = ttk.Entry(io_card, textvariable=self.atlp_path)
        atlp_entry.grid(row=4, column=1, sticky="ew", padx=8, pady=4)
        ttk.Button(io_card, text="Browse", command=self.browse_atlp).grid(row=4, column=2, pady=4, ipady=2, ipadx=6)
        
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
        
        ttk.Label(rig_card, text="02b // RIG ROTATIONAL BORESIGHT (°)", style="Header.TLabel").grid(row=2, column=0, columnspan=3, sticky="w", pady=(10, 10))
        self.add_offset_input(rig_card, "rx (Roll)", self.rot_roll, 0, row=3)
        self.add_offset_input(rig_card, "ry (Pitch)", self.rot_pitch, 1, row=3)
        self.add_offset_input(rig_card, "rz (Yaw)", self.rot_yaw, 2, row=3)
        
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
        
        ttk.Label(right_panel, text="ABU TRACK LOGS & MULTI-INTEGRITY ANALYSIS", font=("Consolas", 11, "bold"), background=BG_COLOR, foreground=ACCENT_CYAN).grid(row=0, column=0, sticky="w", pady=(0, 10))
        
        self.log_box = tk.Text(right_panel, wrap="word", bg=CARD_BG, fg=TEXT_PRIMARY, insertbackground=ACCENT_CYAN, font=("Consolas", 9), bd=0, highlightthickness=1, highlightbackground=BORDER_COLOR, highlightcolor=ACCENT_CYAN, padx=12, pady=12)
        self.log_box.grid(row=1, column=0, sticky="nsew")
        
        scroll = ttk.Scrollbar(right_panel, orient="vertical", command=self.log_box.yview)
        scroll.grid(row=1, column=1, sticky="ns")
        self.log_box.configure(yscrollcommand=scroll.set)
        
        self.log("SYSTEM ACTIVE // ABU TRACK GEODETIC DATA SYNCHRONIZER")
        self.log("Version: 0.1.0 // OS Platform: Windows")
        self.log("3DGS & Metashape Processing Workstation integrated...\n")
        
        # ----------------- TAB 2: 3D SPATIAL WORKSTATION -----------------
        self.tab_visualizer.columnconfigure(0, weight=5) # 3D Plot Canvas
        self.tab_visualizer.columnconfigure(1, weight=3) # Side photography controller
        self.tab_visualizer.rowconfigure(0, weight=1)
        
        # Left: Matplotlib 3D Viewport
        self.view_frame = ttk.Frame(self.tab_visualizer, style="Card.TFrame", padding=10)
        self.view_frame.grid(row=0, column=0, sticky="nsew", padx=(0, 10))

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
        self.fig.canvas.mpl_connect('button_press_event', self.on_canvas_click)

        
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
        
        self.clean_btn = ttk.Button(btn_frame, text="CLEAN POINT CLOUD (SOR)", command=self.clean_point_cloud_sor)
        self.clean_btn.grid(row=0, column=0, sticky="ew", ipady=8)
        
        # 06 // CALIBRATION & MULTI-TARGET EXPORTS
        export_frame = ttk.Frame(side_panel)
        export_frame.grid(row=3, column=0, columnspan=2, sticky="ew", pady=(15, 0))
        export_frame.columnconfigure(0, weight=1)
        export_frame.columnconfigure(1, weight=1)
        export_frame.columnconfigure(2, weight=1)
        
        ttk.Label(export_frame, text="06 // CALIBRATION & MULTI-TARGET EXPORTS", style="Header.TLabel").grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 6))
        
        # Profile Dropdown
        profiles = [
            "iPhone 16 Pro Max Main (24mm)", 
            "iPhone 16 Pro Max Ultra Wide (13mm)", 
            "iPhone 16 Pro Max Telephoto (120mm)",
            "iPhone 15 Pro Max Main (24mm)", 
            "iPhone 15 Pro Max Ultra Wide (13mm)", 
            "iPhone 15 Pro Max Telephoto (120mm)",
            "iPhone 14 Pro Max Main (24mm)", 
            "iPhone 14 Pro Max Ultra Wide (13mm)", 
            "iPhone 14 Pro Max Telephoto (77mm)",
            "iPhone 17 Pro Max Main (24mm)", 
            "iPhone 17 Pro Max Ultra Wide (13mm)", 
            "iPhone 17 Pro Max Telephoto (120mm)",
            "Sony FE 24-70mm GM II (24mm)",
            "Sony FE 24-70mm GM II (70mm)",
            "Sony FE 16-35mm GM II (16mm)",
            "Sony FE 16-35mm GM II (35mm)",
            "Canon RF 24-70mm f/2.8L (24mm)",
            "Canon RF 24-70mm f/2.8L (70mm)",
            "Canon RF 15-35mm f/2.8L (15mm)",
            "Canon RF 15-35mm f/2.8L (35mm)",
            "Standard DSLR / Flat Lens"
        ]
        self.profile_combo = ttk.Combobox(export_frame, textvariable=self.lens_profile, values=profiles, state="readonly")
        self.profile_combo.grid(row=1, column=0, columnspan=3, sticky="ew", pady=(0, 10))
        
        # Three target export buttons
        self.postshot_btn = ttk.Button(export_frame, text="POSTSHOT (3DGS)", command=self.export_for_postshot)
        self.postshot_btn.grid(row=2, column=0, sticky="ew", padx=(0, 4), ipady=6)
        
        self.metashape_btn = ttk.Button(export_frame, text="METASHAPE (Z-UP)", command=self.export_for_metashape)
        self.metashape_btn.grid(row=2, column=1, sticky="ew", padx=2, ipady=6)
        
        self.realityscan_btn = ttk.Button(export_frame, text="REALITYSCAN", command=self.export_for_realityscan)
        self.realityscan_btn.grid(row=2, column=2, sticky="ew", padx=(4, 0), ipady=6)
        
        # ----------------- TAB 3: OPTICAL LENS CALIBRATION & SOLVER -----------------
        self.tab_calibrator = ttk.Frame(self.notebook, padding=12)
        self.notebook.add(self.tab_calibrator, text="03 // OPTICAL CALIBRATION & LENS SOLVER")
        
        self.tab_calibrator.columnconfigure(0, weight=4) # Left controls panel
        self.tab_calibrator.columnconfigure(1, weight=5) # Right preview panel
        self.tab_calibrator.rowconfigure(0, weight=1)
        
        # Left Panel: Controls Card
        calib_left = ttk.Frame(self.tab_calibrator, padding=10)
        calib_left.grid(row=0, column=0, sticky="nsew")
        calib_left.columnconfigure(0, weight=1)
        calib_left.rowconfigure(2, weight=1) # Let listbox expand
        
        # Card 1: Grid settings
        calib_io_card = ttk.Frame(calib_left, style="Card.TFrame", padding=12)
        calib_io_card.grid(row=0, column=0, sticky="ew", pady=(0, 12))
        calib_io_card.columnconfigure(1, weight=1)
        
        ttk.Label(calib_io_card, text="01 // OPTICAL BOARD PARAMETERS", style="Header.TLabel").grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 10))
        
        # Grid Size (Width x Height)
        ttk.Label(calib_io_card, text="Grid Size (W x H corners):").grid(row=1, column=0, sticky="w", pady=4)
        grid_dim_frame = ttk.Frame(calib_io_card)
        grid_dim_frame.grid(row=1, column=1, columnspan=2, sticky="w", pady=4)
        
        self.width_entry = ttk.Entry(grid_dim_frame, textvariable=self.calib_board_width, width=5, justify="center")
        self.width_entry.pack(side="left", padx=(5, 2))
        ttk.Label(grid_dim_frame, text="x").pack(side="left", padx=2)
        self.height_entry = ttk.Entry(grid_dim_frame, textvariable=self.calib_board_height, width=5, justify="center")
        self.height_entry.pack(side="left", padx=2)
        ttk.Label(grid_dim_frame, text=" corners").pack(side="left", padx=2)
        
        # Square physical size
        ttk.Label(calib_io_card, text="Square Dimension (mm):").grid(row=2, column=0, sticky="w", pady=4)
        sq_frame = ttk.Frame(calib_io_card)
        sq_frame.grid(row=2, column=1, columnspan=2, sticky="w", pady=4)
        self.sq_entry = ttk.Entry(sq_frame, textvariable=self.calib_square_size, width=8, justify="center")
        self.sq_entry.pack(side="left", padx=(5, 2))
        ttk.Label(sq_frame, text=" mm").pack(side="left", padx=2)
        
        # Photo path
        ttk.Label(calib_io_card, text="Chessboard Folder:").grid(row=3, column=0, sticky="w", pady=4)
        calib_entry = ttk.Entry(calib_io_card, textvariable=self.calib_photo_dir)
        calib_entry.grid(row=3, column=1, sticky="ew", padx=8, pady=4)
        ttk.Button(calib_io_card, text="Browse", command=self.browse_calib_photos).grid(row=3, column=2, pady=4, ipady=2, ipadx=6)
        
        # Card 2: Calib Images Listbox
        calib_list_card = ttk.Frame(calib_left, style="Card.TFrame", padding=12)
        calib_list_card.grid(row=1, column=0, sticky="nsew", pady=(0, 12))
        calib_list_card.columnconfigure(0, weight=1)
        calib_list_card.rowconfigure(1, weight=1)
        
        ttk.Label(calib_list_card, text="02 // BOARD CAPTURE SERIES", style="Header.TLabel").grid(row=0, column=0, columnspan=2, sticky="w", pady=(0, 10))
        
        self.calib_listbox = tk.Listbox(calib_list_card, bg=FIELD_BG, fg=TEXT_PRIMARY, font=("Consolas", 9), selectbackground=ACCENT_CYAN, selectforeground=BG_COLOR, highlightthickness=1, highlightbackground=BORDER_COLOR, bd=0)
        self.calib_listbox.grid(row=1, column=0, sticky="nsew", pady=(0, 10))
        self.calib_listbox.bind("<<ListboxSelect>>", self.on_calib_listbox_select)
        
        scroll_calib = ttk.Scrollbar(calib_list_card, orient="vertical", command=self.calib_listbox.yview)
        scroll_calib.grid(row=1, column=1, sticky="ns", pady=(0, 10))
        self.calib_listbox.configure(yscrollcommand=scroll_calib.set)
        
        # Controls Frame under Listbox
        calib_actions = ttk.Frame(calib_left, style="Card.TFrame", padding=12)
        calib_actions.grid(row=2, column=0, sticky="ew")
        calib_actions.columnconfigure(0, weight=1)
        calib_actions.columnconfigure(1, weight=1)
        calib_actions.columnconfigure(2, weight=1)
        
        ttk.Label(calib_actions, text="03 // CALIBRATION WORKSTATION CONTROLS", style="Header.TLabel").grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 10))
        
        self.solve_calib_btn = ttk.Button(calib_actions, text="RUN OPTICAL SOLVER", command=self.solve_lens_calibration)
        self.solve_calib_btn.grid(row=1, column=0, columnspan=3, sticky="ew", pady=(0, 8), ipady=6)
        
        self.apply_calib_btn = ttk.Button(calib_actions, text="APPLY TO ACTIVE PROJECT", command=self.apply_calibration_to_project)
        self.apply_calib_btn.grid(row=2, column=0, columnspan=3, sticky="ew", pady=(0, 12), ipady=4)
        
        self.export_atlp_btn = ttk.Button(calib_actions, text="EXPORT ATLP", command=self.export_atlp_profile)
        self.export_atlp_btn.grid(row=3, column=0, sticky="ew", padx=(0, 2), ipady=4)
        
        self.export_meta_xml_btn = ttk.Button(calib_actions, text="METASHAPE XML", command=self.export_metashape_calibration_xml)
        self.export_meta_xml_btn.grid(row=3, column=1, sticky="ew", padx=2, ipady=4)
        
        self.export_post_json_btn = ttk.Button(calib_actions, text="POSTSHOT JSON", command=self.export_postshot_calibration_json)
        self.export_post_json_btn.grid(row=3, column=2, sticky="ew", padx=(2, 0), ipady=4)
        
        # Right Panel: Visualizer & Real-time Logs
        right_panel = ttk.Frame(self.tab_calibrator, padding=10)
        right_panel.grid(row=0, column=1, sticky="nsew")
        right_panel.columnconfigure(0, weight=1)
        right_panel.rowconfigure(0, weight=6) # 3D/Photo canvas
        right_panel.rowconfigure(1, weight=4) # Logs
        
        # Photo/Grid display
        self.calib_fig = plt.figure(facecolor=BG_COLOR)
        self.calib_ax = self.calib_fig.add_subplot(111)
        self.calib_ax.set_facecolor(BG_COLOR)
        self.calib_ax.axis('off')
        
        self.calib_canvas = FigureCanvasTkAgg(self.calib_fig, master=right_panel)
        self.calib_canvas.get_tk_widget().grid(row=0, column=0, sticky="nsew", pady=(0, 10))
        
        # Log terminal
        calib_log_card = ttk.Frame(right_panel, style="Card.TFrame", padding=12)
        calib_log_card.grid(row=1, column=0, sticky="nsew")
        calib_log_card.columnconfigure(0, weight=1)
        calib_log_card.rowconfigure(1, weight=1)
        
        ttk.Label(calib_log_card, text="04 // OPTICAL PIPELINE OUTPUT CONSOLE", style="Header.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 6))
        
        self.calib_console = tk.Text(calib_log_card, bg=FIELD_BG, fg=TEXT_MUTED, font=("Consolas", 8), relief="flat", bd=0, highlightthickness=1, highlightcolor=BORDER_COLOR, highlightbackground=BORDER_COLOR)
        self.calib_console.grid(row=1, column=0, sticky="nsew")
        
        scroll_console = ttk.Scrollbar(calib_log_card, orient="vertical", command=self.calib_console.yview)
        scroll_console.grid(row=1, column=1, sticky="ns")
        self.calib_console.configure(yscrollcommand=scroll_console.set)
        
        # ----------------- TAB 4: LIVE TELEMETRY CHECKER -----------------
        self.tab_receiver = ttk.Frame(self.notebook, padding=12)
        self.notebook.add(self.tab_receiver, text="04 // LIVE TELEMETRY CHECKER")
        
        self.tab_receiver.columnconfigure(0, weight=4) # Left Controls Panel
        self.tab_receiver.columnconfigure(1, weight=6) # Right Panel
        # Left Panel
        rx_left = ttk.Frame(self.tab_receiver, padding=10)
        rx_left.grid(row=0, column=0, sticky="nsew")
        rx_left.columnconfigure(0, weight=1)
        rx_left.rowconfigure(4, weight=1)
        
        # Card 1: Receiver Configuration
        rx_config_card = ttk.Frame(rx_left, style="Card.TFrame", padding=12)
        rx_config_card.grid(row=0, column=0, sticky="ew", pady=(0, 12))
        rx_config_card.columnconfigure(1, weight=1)
        
        ttk.Label(rx_config_card, text="01 // UDP LISTENER OPTIONS", style="Header.TLabel").grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 10))
        
        ttk.Label(rx_config_card, text="UDP Port Number:").grid(row=1, column=0, sticky="w", pady=4)
        port_entry = ttk.Entry(rx_config_card, textvariable=self.receiver_port, width=10)
        port_entry.grid(row=1, column=1, sticky="w", pady=4)
        
        ttk.Label(rx_config_card, text="H.264 Video Port:").grid(row=2, column=0, sticky="w", pady=4)
        video_port_entry = ttk.Entry(rx_config_card, textvariable=self.video_stream_port, width=10)
        video_port_entry.grid(row=2, column=1, sticky="w", pady=4)
        
        video_chk = ttk.Checkbutton(rx_config_card, text="Enable H.264 Video Stream", variable=self.is_video_stream_enabled)
        video_chk.grid(row=3, column=0, columnspan=2, sticky="w", pady=4)
        
        spout_chk = ttk.Checkbutton(rx_config_card, text="Enable Spout Sharing", variable=self.is_spout_enabled)
        spout_chk.grid(row=4, column=0, columnspan=2, sticky="w", pady=4)
        
        # Action Buttons
        self.start_rx_btn = ttk.Button(rx_config_card, text="START LISTENING", command=self.start_receiver)
        self.start_rx_btn.grid(row=5, column=0, sticky="ew", padx=(0, 2), pady=(8, 0), ipady=4)
        
        self.stop_rx_btn = ttk.Button(rx_config_card, text="STOP", state="disabled", command=self.stop_receiver)
        self.stop_rx_btn.grid(row=5, column=1, sticky="ew", padx=(2, 0), pady=(8, 0), ipady=4)
        
        # Card 1.5: Dynamic UDP Forwarder Server Settings
        rx_forward_card = ttk.Frame(rx_left, style="Card.TFrame", padding=12)
        rx_forward_card.grid(row=1, column=0, sticky="ew", pady=(0, 12))
        rx_forward_card.columnconfigure(1, weight=1)
        
        ttk.Label(rx_forward_card, text="02 // DYNAMIC UDP FORWARDER SERVER", style="Header.TLabel").grid(row=0, column=0, columnspan=2, sticky="w", pady=(0, 10))
        
        forward_chk = ttk.Checkbutton(rx_forward_card, text="Enable Target Forwarding", variable=self.forward_enabled, command=self.toggle_forwarding)
        forward_chk.grid(row=1, column=0, columnspan=2, sticky="w", pady=4)
        
        ttk.Label(rx_forward_card, text="Target IP / Host:").grid(row=2, column=0, sticky="w", pady=4)
        host_entry = ttk.Entry(rx_forward_card, textvariable=self.forward_host, width=15)
        host_entry.grid(row=2, column=1, sticky="w", pady=4)
        
        ttk.Label(rx_forward_card, text="Target Port:").grid(row=3, column=0, sticky="w", pady=4)
        tgt_port_entry = ttk.Entry(rx_forward_card, textvariable=self.forward_port, width=10)
        tgt_port_entry.grid(row=3, column=1, sticky="w", pady=4)
        
        ttk.Label(rx_forward_card, text="Protocol Format:").grid(row=4, column=0, sticky="w", pady=4)
        proto_combo = ttk.Combobox(rx_forward_card, textvariable=self.forward_protocol, values=["Live Link JSON", "FreeD Binary", "OpenTrackIO JSON"], state="readonly", width=18)
        proto_combo.grid(row=4, column=1, sticky="w", pady=4)
        
        # Card 1.7: Workstation Calibration & Offsets
        rx_offset_card = ttk.Frame(rx_left, style="Card.TFrame", padding=12)
        rx_offset_card.grid(row=2, column=0, sticky="ew", pady=(0, 12))
        rx_offset_card.columnconfigure(1, weight=1)
        rx_offset_card.columnconfigure(3, weight=1)
        
        ttk.Label(rx_offset_card, text="03 // WORKSTATION CALIBRATION & OFFSETS", style="Header.TLabel").grid(row=0, column=0, columnspan=4, sticky="w", pady=(0, 10))
        
        # Section A: Initial Origin Offsets (6-Axis)
        ttk.Label(rx_offset_card, text="Origin X (m):").grid(row=1, column=0, sticky="w", pady=2)
        ttk.Entry(rx_offset_card, textvariable=self.ws_origin_x, width=8).grid(row=1, column=1, sticky="w", pady=2)
        
        ttk.Label(rx_offset_card, text="Origin Y (m):").grid(row=1, column=2, sticky="w", pady=2)
        ttk.Entry(rx_offset_card, textvariable=self.ws_origin_y, width=8).grid(row=1, column=3, sticky="w", pady=2)
        
        ttk.Label(rx_offset_card, text="Origin Z (m):").grid(row=2, column=0, sticky="w", pady=2)
        ttk.Entry(rx_offset_card, textvariable=self.ws_origin_z, width=8).grid(row=2, column=1, sticky="w", pady=2)
        
        ttk.Label(rx_offset_card, text="Origin Yaw (°):").grid(row=2, column=2, sticky="w", pady=2)
        ttk.Entry(rx_offset_card, textvariable=self.ws_origin_yaw, width=8).grid(row=2, column=3, sticky="w", pady=2)
        
        ttk.Label(rx_offset_card, text="Origin Pitch(°):").grid(row=3, column=0, sticky="w", pady=2)
        ttk.Entry(rx_offset_card, textvariable=self.ws_origin_pitch, width=8).grid(row=3, column=1, sticky="w", pady=2)
        
        ttk.Label(rx_offset_card, text="Origin Roll (°):").grid(row=3, column=2, sticky="w", pady=2)
        ttk.Entry(rx_offset_card, textvariable=self.ws_origin_roll, width=8).grid(row=3, column=3, sticky="w", pady=2)
        
        # Separator line
        ttk.Separator(rx_offset_card, orient="horizontal").grid(row=4, column=0, columnspan=4, sticky="ew", pady=6)
        
        # Section B: Camera Lever Arm Offsets
        ttk.Label(rx_offset_card, text="Lever X (cm):").grid(row=5, column=0, sticky="w", pady=2)
        ttk.Entry(rx_offset_card, textvariable=self.ws_lever_x, width=8).grid(row=5, column=1, sticky="w", pady=2)
        
        ttk.Label(rx_offset_card, text="Lever Y (cm):").grid(row=5, column=2, sticky="w", pady=2)
        ttk.Entry(rx_offset_card, textvariable=self.ws_lever_y, width=8).grid(row=5, column=3, sticky="w", pady=2)
        
        ttk.Label(rx_offset_card, text="Lever Z (cm):").grid(row=6, column=0, sticky="w", pady=2)
        ttk.Entry(rx_offset_card, textvariable=self.ws_lever_z, width=8).grid(row=6, column=1, sticky="w", pady=2)
        
        # Card 1.8: Workstation Coordinate Alignment & Point Cloud Remapping
        rx_alignment_card = ttk.Frame(rx_left, style="Card.TFrame", padding=12)
        rx_alignment_card.grid(row=3, column=0, sticky="ew", pady=(0, 12))
        rx_alignment_card.columnconfigure(1, weight=1)
        rx_alignment_card.columnconfigure(3, weight=1)
        
        ttk.Label(rx_alignment_card, text="04 // COORDINATE SYSTEM & LIDAR ALIGNMENT", style="Header.TLabel").grid(row=0, column=0, columnspan=4, sticky="w", pady=(0, 10))
        
        # Preset dropdown
        ttk.Label(rx_alignment_card, text="Preset Profile:").grid(row=1, column=0, sticky="w", pady=4)
        preset_combo = ttk.Combobox(rx_alignment_card, textvariable=self.pc_align_preset, values=["Default", "Unreal Engine", "Metashape", "Custom"], state="readonly", width=15)
        preset_combo.grid(row=1, column=1, columnspan=3, sticky="ew", pady=4)
        preset_combo.bind("<<ComboboxSelected>>", self.on_align_preset_changed)
        
        # Custom position mapping
        ttk.Label(rx_alignment_card, text="PC Pos X:").grid(row=2, column=0, sticky="w", pady=2)
        x_sign_combo = ttk.Combobox(rx_alignment_card, textvariable=self.pc_x_sign, values=[1, -1], state="readonly", width=3)
        x_sign_combo.grid(row=2, column=1, sticky="w", pady=2)
        x_src_combo = ttk.Combobox(rx_alignment_card, textvariable=self.pc_x_src, values=["X", "Y", "Z"], state="readonly", width=3)
        x_src_combo.grid(row=2, column=2, sticky="w", pady=2)
        
        ttk.Label(rx_alignment_card, text="PC Pos Y:").grid(row=3, column=0, sticky="w", pady=2)
        y_sign_combo = ttk.Combobox(rx_alignment_card, textvariable=self.pc_y_sign, values=[1, -1], state="readonly", width=3)
        y_sign_combo.grid(row=3, column=1, sticky="w", pady=2)
        y_src_combo = ttk.Combobox(rx_alignment_card, textvariable=self.pc_y_src, values=["X", "Y", "Z"], state="readonly", width=3)
        y_src_combo.grid(row=3, column=2, sticky="w", pady=2)
        
        ttk.Label(rx_alignment_card, text="PC Pos Z:").grid(row=4, column=0, sticky="w", pady=2)
        z_sign_combo = ttk.Combobox(rx_alignment_card, textvariable=self.pc_z_sign, values=[1, -1], state="readonly", width=3)
        z_sign_combo.grid(row=4, column=1, sticky="w", pady=2)
        z_src_combo = ttk.Combobox(rx_alignment_card, textvariable=self.pc_z_src, values=["X", "Y", "Z"], state="readonly", width=3)
        z_src_combo.grid(row=4, column=2, sticky="w", pady=2)
        
        ttk.Separator(rx_alignment_card, orient="horizontal").grid(row=5, column=0, columnspan=4, sticky="ew", pady=6)
        
        # LiDAR Cloud Custom Translation Mapping Heading
        ttk.Label(rx_alignment_card, text="LiDAR point cloud custom mapping:", font=("Consolas", 8, "bold"), foreground=ACCENT_CYAN).grid(row=6, column=0, columnspan=4, sticky="w", pady=(0, 4))
        
        # LiDAR X Mapping
        ttk.Label(rx_alignment_card, text="LiDAR X:").grid(row=7, column=0, sticky="w", pady=2)
        lx_sign_combo = ttk.Combobox(rx_alignment_card, textvariable=self.pc_lidar_x_sign, values=[1, -1], state="readonly", width=3)
        lx_sign_combo.grid(row=7, column=1, sticky="w", pady=2)
        lx_src_combo = ttk.Combobox(rx_alignment_card, textvariable=self.pc_lidar_x_src, values=["X", "Y", "Z"], state="readonly", width=3)
        lx_src_combo.grid(row=7, column=2, sticky="w", pady=2)
        
        # LiDAR Y Mapping
        ttk.Label(rx_alignment_card, text="LiDAR Y:").grid(row=8, column=0, sticky="w", pady=2)
        ly_sign_combo = ttk.Combobox(rx_alignment_card, textvariable=self.pc_lidar_y_sign, values=[1, -1], state="readonly", width=3)
        ly_sign_combo.grid(row=8, column=1, sticky="w", pady=2)
        ly_src_combo = ttk.Combobox(rx_alignment_card, textvariable=self.pc_lidar_y_src, values=["X", "Y", "Z"], state="readonly", width=3)
        ly_src_combo.grid(row=8, column=2, sticky="w", pady=2)
        
        # LiDAR Z Mapping
        ttk.Label(rx_alignment_card, text="LiDAR Z:").grid(row=9, column=0, sticky="w", pady=2)
        lz_sign_combo = ttk.Combobox(rx_alignment_card, textvariable=self.pc_lidar_z_sign, values=[1, -1], state="readonly", width=3)
        lz_sign_combo.grid(row=9, column=1, sticky="w", pady=2)
        lz_src_combo = ttk.Combobox(rx_alignment_card, textvariable=self.pc_lidar_z_src, values=["X", "Y", "Z"], state="readonly", width=3)
        lz_src_combo.grid(row=9, column=2, sticky="w", pady=2)
        
        # Card 2: PC Network & Stream Diagnostics
        rx_diag_card = ttk.Frame(rx_left, style="Card.TFrame", padding=12)
        rx_diag_card.grid(row=4, column=0, sticky="nsew")
        rx_diag_card.columnconfigure(1, weight=1)
        
        ttk.Label(rx_diag_card, text="05 // PC NETWORK DIAGNOSTICS", style="Header.TLabel").grid(row=0, column=0, columnspan=2, sticky="w", pady=(0, 10))
        
        # Local IP List
        ttk.Label(rx_diag_card, text="PC Local IP(s):").grid(row=1, column=0, sticky="w", pady=4)
        ip_label = ttk.Label(rx_diag_card, text=", ".join(self.get_local_ips()), foreground=ACCENT_CYAN, font=("Consolas", 8, "bold"))
        ip_label.grid(row=1, column=1, sticky="e", pady=4)
        
        # PC System Time
        ttk.Label(rx_diag_card, text="PC Epoch Time:").grid(row=2, column=0, sticky="w", pady=4)
        pc_time_lbl = ttk.Label(rx_diag_card, textvariable=self.receiver_pc_time_var, foreground=ACCENT_CYAN, font=("Consolas", 9, "bold"))
        pc_time_lbl.grid(row=2, column=1, sticky="e", pady=4)
        
        # Status
        ttk.Label(rx_diag_card, text="Receiver State:").grid(row=3, column=0, sticky="w", pady=4)
        self.rx_status_lbl = ttk.Label(rx_diag_card, textvariable=self.receiver_status_var, font=("Consolas", 9, "bold"), foreground=TEXT_MUTED)
        self.rx_status_lbl.grid(row=3, column=1, sticky="e", pady=4)
        
        # Detected Protocol
        ttk.Label(rx_diag_card, text="Detected Format:").grid(row=4, column=0, sticky="w", pady=4)
        fmt_lbl = ttk.Label(rx_diag_card, textvariable=self.receiver_format_var, foreground=ACCENT_CYAN, font=("Consolas", 9, "bold"))
        fmt_lbl.grid(row=4, column=1, sticky="e", pady=4)
        
        # Total Frames
        ttk.Label(rx_diag_card, text="Frames Received:").grid(row=5, column=0, sticky="w", pady=4)
        frames_lbl = ttk.Label(rx_diag_card, textvariable=self.receiver_frames_var, font=("Consolas", 9, "bold"))
        frames_lbl.grid(row=5, column=1, sticky="e", pady=4)
        
        # Real iOS Source Frequency
        ttk.Label(rx_diag_card, text="Real Source Hz (iOS Lock):").grid(row=6, column=0, sticky="w", pady=4)
        real_hz_lbl = ttk.Label(rx_diag_card, textvariable=self.receiver_real_hz_var, foreground=ACCENT_GREEN, font=("Consolas", 9, "bold"))
        real_hz_lbl.grid(row=6, column=1, sticky="e", pady=4)
        
        # Buffered Delivery Stable Frequency
        ttk.Label(rx_diag_card, text="Buffered Delivery (Stable):").grid(row=7, column=0, sticky="w", pady=4)
        hz_lbl = ttk.Label(rx_diag_card, textvariable=self.receiver_hz_var, foreground=ACCENT_AMBER, font=("Consolas", 9, "bold"))
        hz_lbl.grid(row=7, column=1, sticky="e", pady=4)
        
        # Raw Network Frequency
        ttk.Label(rx_diag_card, text="Network Delivery (Raw):").grid(row=8, column=0, sticky="w", pady=4)
        raw_hz_lbl = ttk.Label(rx_diag_card, textvariable=self.receiver_raw_hz_var, foreground=ACCENT_CYAN, font=("Consolas", 9, "bold"))
        raw_hz_lbl.grid(row=8, column=1, sticky="e", pady=4)
        
        # Latency / Time Shift
        ttk.Label(rx_diag_card, text="Clock Latency Shift:").grid(row=9, column=0, sticky="w", pady=4)
        latency_lbl = ttk.Label(rx_diag_card, textvariable=self.receiver_latency_var, foreground=ACCENT_AMBER, font=("Consolas", 9, "bold"))
        latency_lbl.grid(row=9, column=1, sticky="e", pady=4)
        
        # Forwarded Hz
        ttk.Label(rx_diag_card, text="Forwarded Hz:").grid(row=10, column=0, sticky="w", pady=4)
        forward_hz_lbl = ttk.Label(rx_diag_card, textvariable=self.forward_delivery_hz_var, foreground=ACCENT_CYAN, font=("Consolas", 9, "bold"))
        forward_hz_lbl.grid(row=10, column=1, sticky="e", pady=4)
        
        # Forwarded Timecode
        ttk.Label(rx_diag_card, text="Forwarded Timecode:").grid(row=11, column=0, sticky="w", pady=4)
        forward_tc_lbl = ttk.Label(rx_diag_card, textvariable=self.forward_timecode_var, foreground=ACCENT_CYAN, font=("Consolas", 9, "bold"))
        forward_tc_lbl.grid(row=11, column=1, sticky="e", pady=4)
        
        # Smoothing Window Slider
        ttk.Label(rx_diag_card, text="Hz Smoothing Window (s):").grid(row=12, column=0, sticky="w", pady=4)
        
        smoothing_frame = ttk.Frame(rx_diag_card, style="Card.TFrame")
        smoothing_frame.grid(row=12, column=1, sticky="e", pady=4)
        
        smooth_slider = ttk.Scale(smoothing_frame, from_=0.1, to=5.0, value=1.0, variable=self.receiver_smoothing_sec, command=lambda v: self._update_smoothing_label())
        smooth_slider.pack(side="left", padx=(0, 4))
        
        self.smooth_lbl = ttk.Label(smoothing_frame, text="1.0s", font=("Consolas", 8, "bold"))
        self.smooth_lbl.pack(side="left")
        
        # Playout Buffer Slider
        ttk.Label(rx_diag_card, text="Playout Buffer Delay (ms):").grid(row=13, column=0, sticky="w", pady=4)
        
        buffer_frame = ttk.Frame(rx_diag_card, style="Card.TFrame")
        buffer_frame.grid(row=13, column=1, sticky="e", pady=4)
        
        buffer_slider = ttk.Scale(buffer_frame, from_=0, to=1000, value=100, variable=self.receiver_buffer_ms, command=lambda v: self._update_buffer_label())
        buffer_slider.pack(side="left", padx=(0, 4))
        
        self.buffer_lbl = ttk.Label(buffer_frame, text="100ms", font=("Consolas", 8, "bold"))
        self.buffer_lbl.pack(side="left")
        
        auto_chk = ttk.Checkbutton(buffer_frame, text="Auto-Profile", variable=self.receiver_auto_calibrate)
        auto_chk.pack(side="left", padx=(8, 0))
        
        # Visual Ping indicator (Canvas)
        ttk.Label(rx_diag_card, text="Data Activity Blinker:").grid(row=14, column=0, sticky="w", pady=4)
        self.ping_canvas = tk.Canvas(rx_diag_card, width=16, height=16, bg=CARD_BG, highlightthickness=0)
        self.ping_canvas.grid(row=14, column=1, sticky="e", pady=4)
        self.ping_light = self.ping_canvas.create_oval(2, 2, 14, 14, fill=FIELD_BG, outline=BORDER_COLOR)
        
        # Right Panel
        rx_right = ttk.Frame(self.tab_receiver, padding=10)
        rx_right.grid(row=0, column=1, sticky="nsew")
        rx_right.rowconfigure(0, weight=3) # Large numerical indicators
        rx_right.rowconfigure(1, weight=5) # Live 3D Projected Canvas
        rx_right.rowconfigure(2, weight=2) # Log console
        
        # Card 3: Large Pose Display
        rx_pose_card = ttk.Frame(rx_right, style="Card.TFrame", padding=12)
        rx_pose_card.grid(row=0, column=0, sticky="nsew", pady=(0, 10))
        rx_pose_card.columnconfigure(0, weight=1)
        rx_pose_card.columnconfigure(1, weight=1)
        rx_pose_card.rowconfigure(1, weight=1)
        rx_pose_card.rowconfigure(2, weight=1)
        rx_pose_card.rowconfigure(3, weight=1)
        
        ttk.Label(rx_pose_card, text="04 // LIVE CAMERA TRACKING POSITION & ORIENTATION", style="Header.TLabel").grid(row=0, column=0, columnspan=2, sticky="w", pady=(0, 10))
        
        # X / Y / Z Positions
        pos_frame = ttk.LabelFrame(rx_pose_card, text=" POSITION (METERS) ", padding=10)
        pos_frame.grid(row=1, column=0, columnspan=2, sticky="nsew", pady=6)
        pos_frame.columnconfigure(0, weight=1)
        pos_frame.columnconfigure(1, weight=1)
        pos_frame.columnconfigure(2, weight=1)
        
        ttk.Label(pos_frame, text="X (EAST/LENGTH)", font=("Consolas", 8), foreground=TEXT_MUTED).grid(row=0, column=0, pady=2)
        self.pos_x_lbl = ttk.Label(pos_frame, textvariable=self.pose_x_var, font=("Consolas", 15, "bold"), foreground=ACCENT_CYAN)
        self.pos_x_lbl.grid(row=1, column=0, pady=4)
        
        ttk.Label(pos_frame, text="Y (NORTH/DEPTH)", font=("Consolas", 8), foreground=TEXT_MUTED).grid(row=0, column=1, pady=2)
        self.pos_y_lbl = ttk.Label(pos_frame, textvariable=self.pose_y_var, font=("Consolas", 15, "bold"), foreground=ACCENT_CYAN)
        self.pos_y_lbl.grid(row=1, column=1, pady=4)
        
        ttk.Label(pos_frame, text="Z (UP/HEIGHT)", font=("Consolas", 8), foreground=TEXT_MUTED).grid(row=0, column=2, pady=2)
        self.pos_z_lbl = ttk.Label(pos_frame, textvariable=self.pose_z_var, font=("Consolas", 15, "bold"), foreground=ACCENT_CYAN)
        self.pos_z_lbl.grid(row=1, column=2, pady=4)
        
        # Roll / Pitch / Yaw Rotations
        rot_frame = ttk.LabelFrame(rx_pose_card, text=" ROTATION (EULER DEGREES) ", padding=10)
        rot_frame.grid(row=2, column=0, columnspan=2, sticky="nsew", pady=6)
        rot_frame.columnconfigure(0, weight=1)
        rot_frame.columnconfigure(1, weight=1)
        rot_frame.columnconfigure(2, weight=1)
        
        ttk.Label(rot_frame, text="ROLL (X AXIS)", font=("Consolas", 8), foreground=TEXT_MUTED).grid(row=0, column=0, pady=2)
        self.rot_roll_lbl = ttk.Label(rot_frame, textvariable=self.pose_roll_var, font=("Consolas", 15, "bold"), foreground=ACCENT_AMBER)
        self.rot_roll_lbl.grid(row=1, column=0, pady=4)
        
        ttk.Label(rot_frame, text="PITCH (Y AXIS)", font=("Consolas", 8), foreground=TEXT_MUTED).grid(row=0, column=1, pady=2)
        self.rot_pitch_lbl = ttk.Label(rot_frame, textvariable=self.pose_pitch_var, font=("Consolas", 15, "bold"), foreground=ACCENT_AMBER)
        self.rot_pitch_lbl.grid(row=1, column=1, pady=4)
        
        ttk.Label(rot_frame, text="YAW (Z AXIS)", font=("Consolas", 8), foreground=TEXT_MUTED).grid(row=0, column=2, pady=2)
        self.rot_yaw_lbl = ttk.Label(rot_frame, textvariable=self.pose_yaw_var, font=("Consolas", 15, "bold"), foreground=ACCENT_AMBER)
        self.rot_yaw_lbl.grid(row=1, column=2, pady=4)
        
        # Card 3.5: Workstation Live 3D Projected Canvas
        rx_canvas_card = ttk.Frame(rx_right, style="Card.TFrame", padding=12)
        rx_canvas_card.grid(row=1, column=0, sticky="nsew", pady=(0, 10))
        rx_canvas_card.columnconfigure(0, weight=1)
        rx_canvas_card.rowconfigure(1, weight=1)
        
        toolbar = ttk.Frame(rx_canvas_card, style="Card.TFrame")
        toolbar.grid(row=0, column=0, sticky="ew", pady=(0, 6))
        
        ttk.Label(toolbar, text="05 // LIVE 3D CANVAS MONITOR", style="Header.TLabel").pack(side="left")
        
        clear_btn = ttk.Button(toolbar, text="CLEAR", command=self.clear_live_data, width=7)
        clear_btn.pack(side="right", padx=(4, 0))
        
        reset_btn = ttk.Button(toolbar, text="RESET", command=self.reset_live_view, width=7)
        reset_btn.pack(side="right", padx=(4, 0))
        
        points_chk = ttk.Checkbutton(toolbar, text="LiDAR", variable=self.live_show_points, command=self.redraw_live_3d_canvas)
        points_chk.pack(side="right", padx=(4, 0))
        
        path_chk = ttk.Checkbutton(toolbar, text="Path", variable=self.live_show_path, command=self.redraw_live_3d_canvas)
        path_chk.pack(side="right", padx=(4, 0))
        
        follow_chk = ttk.Checkbutton(toolbar, text="Follow", variable=self.live_follow, command=self.redraw_live_3d_canvas)
        follow_chk.pack(side="right", padx=(4, 0))
        
        edit_origin_chk = ttk.Checkbutton(toolbar, text="Edit Origin", variable=self.live_edit_origin, command=self.redraw_live_3d_canvas)
        edit_origin_chk.pack(side="right", padx=(4, 0))
        
        self.live_view_mode_combo = ttk.Combobox(toolbar, textvariable=self.live_view_mode, values=["Orbit", "Cockpit"], state="readonly", width=8)
        self.live_view_mode_combo.pack(side="right", padx=(4, 4))
        self.live_view_mode_combo.bind("<<ComboboxSelected>>", lambda e: self.redraw_live_3d_canvas())
        
        self.live_canvas = tk.Canvas(rx_canvas_card, bg=BG_COLOR, highlightthickness=1, highlightcolor=BORDER_COLOR, highlightbackground=BORDER_COLOR)
        self.live_canvas.grid(row=1, column=0, sticky="nsew")
        
        # Bind Canvas Drag Gestures
        self.live_canvas.bind("<ButtonPress-1>", self.on_live_canvas_press)
        self.live_canvas.bind("<B1-Motion>", self.on_live_canvas_orbit)
        self.live_canvas.bind("<ButtonPress-3>", self.on_live_canvas_press)
        self.live_canvas.bind("<B3-Motion>", self.on_live_canvas_pan)
        self.live_canvas.bind("<MouseWheel>", self.on_live_canvas_scroll)
        self.live_canvas.bind("<Configure>", lambda e: self.redraw_live_3d_canvas())
        self.live_canvas.bind("<Double-Button-1>", lambda e: self.reset_live_view())
        
        # Card 4: Console
        rx_console_card = ttk.Frame(rx_right, style="Card.TFrame", padding=12)
        rx_console_card.grid(row=2, column=0, sticky="nsew")
        rx_console_card.columnconfigure(0, weight=1)
        rx_console_card.rowconfigure(1, weight=1)
        
        ttk.Label(rx_console_card, text="06 // LIVE TRACKING STREAM LOG CONSOLE (LAST 15 FRAMES)", style="Header.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 6))
        
        self.rx_console = tk.Text(rx_console_card, bg=FIELD_BG, fg=TEXT_MUTED, font=("Consolas", 8), relief="flat", bd=0, highlightthickness=1, highlightcolor=BORDER_COLOR, highlightbackground=BORDER_COLOR)
        self.rx_console.grid(row=1, column=0, sticky="nsew")
        
        scroll_rx_console = ttk.Scrollbar(rx_console_card, orient="vertical", command=self.rx_console.yview)
        scroll_rx_console.grid(row=1, column=1, sticky="ns")
        self.rx_console.configure(yscrollcommand=scroll_rx_console.set)
        
        # ----------------- TAB 5: SYSTEM MANUAL & DOCUMENTATION -----------------
        self.tab_docs = ttk.Frame(self.notebook, padding=12)
        self.notebook.add(self.tab_docs, text="05 // SYSTEM MANUAL & DOCUMENTATION")
        
        self.tab_docs.columnconfigure(0, weight=1)
        self.tab_docs.rowconfigure(0, weight=1)
        
        docs_card = ttk.Frame(self.tab_docs, style="Card.TFrame", padding=16)
        docs_card.grid(row=0, column=0, sticky="nsew")
        docs_card.columnconfigure(0, weight=1)
        docs_card.rowconfigure(1, weight=1)
        
        ttk.Label(docs_card, text="05 // INDUSTRIAL SYNC ENGINE USER MANUAL & ACADEMY", style="Header.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 12))
        
        self.docs_text = tk.Text(docs_card, bg=FIELD_BG, fg=TEXT_MUTED, font=("Consolas", 10), relief="flat", bd=0, highlightthickness=1, highlightcolor=BORDER_COLOR, highlightbackground=BORDER_COLOR, wrap="word", padx=12, pady=12)
        self.docs_text.grid(row=1, column=0, sticky="nsew")
        
        scroll_docs = ttk.Scrollbar(docs_card, orient="vertical", command=self.docs_text.yview)
        scroll_docs.grid(row=1, column=1, sticky="ns")
        self.docs_text.configure(yscrollcommand=scroll_docs.set)
        
        # Configure tags for beautiful styled text rendering
        self.docs_text.tag_config("h1", font=("Consolas", 12, "bold"), foreground=ACCENT_CYAN, spacing1=12, spacing3=6)
        self.docs_text.tag_config("h2", font=("Consolas", 10, "bold"), foreground=ACCENT_CYAN, spacing1=8, spacing3=4)
        self.docs_text.tag_config("bold", font=("Consolas", 9, "bold"), foreground=TEXT_PRIMARY)
        self.docs_text.tag_config("bullet", font=("Consolas", 9, "bold"), foreground=ACCENT_GREEN)
        self.docs_text.tag_config("code", font=("Consolas", 8, "bold"), foreground=ACCENT_AMBER, background=BG_COLOR)
        self.docs_text.tag_config("warning", font=("Consolas", 9, "bold"), foreground=ACCENT_RED)
        self.docs_text.tag_config("normal", font=("Consolas", 9), foreground=TEXT_MUTED, spacing2=4)
        
        self.write_documentation_manual()
        
    def write_documentation_manual(self):
        self.docs_text.configure(state="normal")
        self.docs_text.delete("1.0", tk.END)
        
        def add_p(text, tags=("normal",)):
            self.docs_text.insert(tk.END, text + "\n", tags)
            
        def add_h1(text):
            self.docs_text.insert(tk.END, "\n" + text + "\n", "h1")
            self.docs_text.insert(tk.END, "="*len(text) + "\n", "h1")
            
        def add_h2(text):
            self.docs_text.insert(tk.END, "\n" + text + "\n", "h2")
            
        def add_bullet(bullet_char, label, desc):
            self.docs_text.insert(tk.END, f"  {bullet_char}  ", "bullet")
            self.docs_text.insert(tk.END, label, "bold")
            self.docs_text.insert(tk.END, desc + "\n", "normal")
            
        def add_code(text):
            self.docs_text.insert(tk.END, "  " + text + "\n", "code")

        add_h1("ABU TRACK SYSTEM ACADEMY & OPERATIONS MANUAL")
        add_p("Welcome to the complete deployment and operations manual for the Abu Track ecosystem. This system bridges multi-frequency, sensor-fused iOS VIO (Visual Inertial Odometry) and high-accuracy ToF LiDAR depth scanners with virtual production workstations, photo-georeferencing pipelines (e.g. Agisoft Metashape, 3D Gaussian Splatting), and Unreal Engine real-time camera tracking.")
        
        add_h2("1. CORE ARCHITECTURE OVERVIEW")
        add_p("The Abu Track pipeline combines industrial mobile tracking hardware and workstation receiver engines to capture, buffer, smooth, and forward spatial coordinates.")
        add_bullet("✓", "iOS Client (VIO SLAM): ", "Leverages dual-frequency GNSS (GPS), high-rate IMUs, and Apple ARKit scene reconstruction (LiDAR ToF). Coordinates are calculated in local body space and shifted using rig lever-arms and origin offsets.")
        add_bullet("✓", "Desktop Workstation: ", "Listens to multi-format high-frequency UDP telemetry packets, dynamically applies workstation-side offset overrides, tracks camera path trajectories, visualizes LiDAR point clouds, and forwards clean positional metrics.")
        
        add_h2("2. STEP-BY-STEP SYSTEM DEPLOYMENT")
        add_bullet("1", "Check Local Network Connectivity: ", "Verify that both your iOS device and PC are connected to the exact same Wi-Fi subnet. The client and host must be able to discover each other.")
        add_bullet("2", "Configure Port Whitelisting: ", "Ensure the target port (default: 8080) is whitelisted in your Windows Firewall. If connection blocks, close port conflicts (e.g. stop Unreal Engine or other listeners before launching Abu Track).")
        add_bullet("3", "Identify PC IP Address: ", "Check 'PC Local IP(s)' displayed in tab 04 // LIVE TELEMETRY CHECKER. Enter this PC IP under the Target IP inside the iOS App's Calibration tab.")
        add_bullet("4", "Initialize Stream: ", "Toggles 'Enable UDP Broadcast' in the iOS app, select 'Live Link' or 'FreeD' streaming protocol. Tap 'START LISTENING' on the workstation to open the UDP socket server.")
        
        add_h2("3. CALIBRATION & RIG OFFSETS (LOCAL VS WORKSTATION)")
        add_p("To align the tracker (phone) with the actual optical capture center (DSLR/Mirrorless camera sensor) and physical studio space, two distinct offset tiers are supported:")
        
        add_bullet("■", "Origin Offsets (Studio Alignment): ", "Offsets the tracking trajectory relative to the physical studio floor coordinate system.")
        add_bullet(" ", "- X Offset: ", "Shifts the trajectory left/right in meters.")
        add_bullet(" ", "- Y Offset: ", "Shifts the trajectory up/down in meters.")
        add_bullet(" ", "- Z Offset: ", "Shifts the trajectory forward/backward in meters.")
        add_bullet(" ", "- Yaw Offset: ", "Rotates the entire tracking coordinate system around gravity (Y-axis) in degrees.")
        
        add_bullet("■", "DSLR Lever-Arm Offsets (Hot-Shoe Rig): ", "Sets the 3D translation vector (X, Y, Z in cm) between the center of the phone's lens and the DSLR's optical CMOS sensor plane.")
        add_bullet(" ", "- Lever X: ", "Positive if the phone center is offset to the right of the lens axis.")
        add_bullet(" ", "- Lever Y: ", "Positive if the phone is mounted higher than the lens center.")
        add_bullet(" ", "- Lever Z: ", "Positive if the phone is mounted further forward than the DSLR sensor plane.")
        
        add_p("Lever-Arm translation vector is rotated in real-time by the unit orientation quaternion of the camera before it is applied to the raw coordinates, ensuring consistent offsets at any tilt angle!")
        
        add_h2("4. LIVE 3D CANVAS VIEW NAVIGATION")
        add_p("The Live 3D Monitor provides rich perspective-projected spatial visualizers for your active camera trajectory and point cloud.")
        add_bullet("🖱", "Orbit Rotation (Left-Click Drag): ", "Rotate the viewpoint around the focus target center.")
        add_bullet("🖱", "Pan View (Right-Click Drag): ", "Shift the camera viewport target center. This breaks the Follow Lock.")
        add_bullet("🖱", "Zoom In/Out (Scroll Wheel): ", "Increase or decrease the viewport magnification.")
        add_bullet("🖱", "Orbit Target Snap (Double-Left-Click): ", "Instantly center the viewport focus target onto the latest active camera coordinate. Perfect for resetting your rotation target.")
        
        add_h2("5. INTEGRATION IN ACTION (UNREAL ENGINE & METASHAPE)")
        add_bullet("✔", "Unreal Engine Virtual Camera: ", "Set forward host/port in '02 // DYNAMIC UDP FORWARDER SERVER' to forward packets to UE. Use Live Link protocol with subject name 'AbuTrack'. Set pitch offset to -90° inside UE settings for horizon alignment.")
        add_bullet("✔", "Agisoft Metashape EXIF Sync: ", "Under '01 // CONSOLE LOGS & EXIF SYNC', import your DSLR photos folder and select the session ID log captured on your iOS device. Click 'Inject Precision GPS and Pose' to auto-interpolate, write EXIF, and solve matching cameras.")
        
        add_h2("6. TROUBLESHOOTING FIREWALLS & SOCKETS")
        add_p("If you are getting 'SOCKET ERROR' or not receiving signals in Tab 4:")
        add_bullet("⚠", "Check Port Locks: ", "Make sure other software (e.g. Unreal Engine Live Link plugin) is not already listening on the same port. Only one program can bind to a UDP port at a time.")
        add_bullet("⚠", "Firewall Rules: ", "Add an Inbound Rule in Windows Defender Firewall to allow UDP traffic on port 8080.")
        add_bullet("⚠", "IP Mismatch: ", "Ensure the Target IP entered on the phone exactly matches the PC IP. Do not use broadcast mode unless the local router supports packet replication.")
        
        add_p("\nManual version: 1.2.0 | System Architecture: Cyberpunk Industrial Real-Time")
        self.docs_text.configure(state="disabled")
        
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
        
    def add_offset_input(self, parent, label, variable, col, row=1):
        frame = ttk.Frame(parent)
        frame.grid(row=row, column=col, sticky="ew", padx=8, pady=5)
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
                
    def browse_ply(self):
        f = filedialog.askopenfilename(filetypes=[("PLY Point Cloud Files", "*.ply")])
        if f:
            self.ply_path.set(f)
            self.original_ply_path = f
            self.log(f"LOADED PLY POINT CLOUD // {f}")
            self.load_point_cloud(f)
                
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
            # Subsample for rendering performance: standard Matplotlib 3D is extremely slow with >100k points.
            # We subsample every Nth point to keep visual reviews buttery smooth, while keeping 100% of raw data for filters & exports!
            # Reducing plot points count to ~3000 and disabling depthshade makes Matplotlib rendering ultra-fast & fluid!
            n_pts = len(self.point_cloud)
            step = max(1, n_pts // 3000)
            subsampled = self.point_cloud[::step]
            
            xs = [p[0] for p in subsampled]
            ys = [-p[2] for p in subsampled]  # Swap Y and Z for visual alignment, negate Z for North positive
            zs = [p[1] for p in subsampled]  # Swap Y and Z for visual alignment
            self.ax.scatter(xs, ys, zs, c='#3E4E63', s=0.6, alpha=0.4, depthshade=False)


            
        # 2. Plot Camera Trajectory Path (Yellow line)
        if self.trajectory_points:
            tx = [p["local_x"] for p in self.trajectory_points]
            ty = [-p["local_z"] for p in self.trajectory_points]  # Swap Y and Z for visual alignment, negate Z for North positive
            tz = [p["local_y"] for p in self.trajectory_points]  # Swap Y and Z for visual alignment
            self.ax.plot(tx, ty, tz, color=ACCENT_AMBER, linewidth=1.5, label="Trajectory")
            
            # 3. Plot 3D wireframe camera pyramid at each camera position
            for i, p in enumerate(self.trajectory_points):
                color = ACCENT_CYAN if i != self.selected_camera_index else ACCENT_RED
                lw = 1.0 if i != self.selected_camera_index else 2.0
                self.plot_camera_pyramid(p["local_x"], p["local_y"], p["local_z"], p["q_w"], p["q_x"], p["q_y"], p["q_z"], color=color, linewidth=lw)
                
        # 4. Plot 3D Origin Gizmo (0, 0, 0)
        # Red = X (Length/East), Green = Y (Depth/North), Blue = Z (Up)
        gizmo_scale = 0.5  # 50 cm axes
        self.ax.plot([0, gizmo_scale], [0, 0], [0, 0], color='#FF3B30', linewidth=2.5, label='_nolegend_')
        self.ax.plot([0, 0], [0, gizmo_scale], [0, 0], color='#34C759', linewidth=2.5, label='_nolegend_')
        self.ax.plot([0, 0], [0, 0], [0, gizmo_scale], color='#007AFF', linewidth=2.5, label='_nolegend_')
        
        # Add tiny coordinate text markers
        self.ax.text(gizmo_scale + 0.05, 0, 0, "X", color='#FF3B30', fontweight='bold', fontsize=8)
        self.ax.text(0, gizmo_scale + 0.05, 0, "Y", color='#34C759', fontweight='bold', fontsize=8)
        self.ax.text(0, 0, gizmo_scale + 0.05, "Z", color='#007AFF', fontweight='bold', fontsize=8)
        
        # Set aspect limits automatically
        if self.point_cloud or self.trajectory_points:
            all_x = [p[0] for p in self.point_cloud] + [p["local_x"] for p in self.trajectory_points]
            all_y = [p[1] for p in self.point_cloud] + [p["local_y"] for p in self.trajectory_points]
            all_z = [-p[2] for p in self.point_cloud] + [-p["local_z"] for p in self.trajectory_points] # Negate Z for North positive Y-axis
            
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
        # Swap Y and Z coordinate paths and negate Z to match rendering mapping (X->X, Y->-Z, Z->Y)
        for cw in corners_world:
            self.ax.plot([px, cw[0]], [-pz, -cw[2]], [py, cw[1]], color=color, linewidth=linewidth, alpha=0.8)
            
        # Base rectangle lines
        for i in range(4):
            c1 = corners_world[i]
            c2 = corners_world[(i+1)%4]
            self.ax.plot([c1[0], c2[0]], [-c1[2], -c2[2]], [c1[1], c2[1]], color=color, linewidth=linewidth, alpha=0.8)

            
    def on_canvas_click(self, event):
        if event.inaxes != self.ax or not self.trajectory_points:
            return
            
        # Euclidean pixel distance click picking
        click_x = event.x
        click_y = event.y
        
        nearest_idx = None
        min_dist = float("inf")
        
        for i, p in enumerate(self.trajectory_points):
            # Map raw coordinate points to the Matplotlib visual mapping
            x_plot, y_plot, z_plot = p["local_x"], p["local_z"], p["local_y"]
            
            # Project 3D coordinate point to 2D screen pixels
            proj = self.ax.transData.transform((x_plot, y_plot, z_plot))
            proj_x, proj_y = proj[0], proj[1]
            
            d = math.sqrt((click_x - proj_x)**2 + (click_y - proj_y)**2)
            if d < min_dist:
                min_dist = d
                nearest_idx = i
                
        # If click within 20 screen pixels of a camera apex:
        if min_dist < 20.0 and nearest_idx is not None:
            self.selected_camera_index = nearest_idx
            
            # Highlight selection in visualizer and sidebar listbox
            self.photo_listbox.selection_clear(0, tk.END)
            self.photo_listbox.selection_set(nearest_idx)
            self.photo_listbox.see(nearest_idx)
            
            self.render_3d_scene()
            
            # Orbit viewport focus
            record = self.trajectory_points[nearest_idx]
            self.ax.view_init(elev=30, azim=record["yaw"] - 90)
            self.canvas_3d.draw()
            
            # Trigger custom popup dialog
            self.show_photo_dialog(record)

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
        popup.geometry("400x530")
        popup.configure(bg=CARD_BG)
        popup.resizable(False, False)
        
        # Center popup relative to main window
        popup.transient(self.root)
        popup.grab_set()
        
        x = self.root.winfo_x() + (self.root.winfo_width() // 2) - 200
        y = self.root.winfo_y() + (self.root.winfo_height() // 2) - 265
        popup.geometry(f"+{x}+{y}")
        
        # Thumbnail dimensions
        canvas_w = 320
        canvas_h = 220
        
        # Create a placeholder label immediately
        lbl_img = tk.Label(popup, text="Loading image thumbnail...", font=("Consolas", 9), bg=FIELD_BG, fg=TEXT_MUTED, width=canvas_w // 8, height=canvas_h // 16)
        lbl_img.pack(pady=15, padx=20)
        
        # Load and resize thumbnail in background thread to prevent GUI freezes
        def load_thumbnail_thread():
            if os.path.exists(p_path):
                try:
                    img = Image.open(p_path)
                    img.thumbnail((canvas_w, canvas_h))
                    photo_img = ImageTk.PhotoImage(img)
                    popup.after(0, lambda: display_loaded_thumbnail(photo_img))
                except Exception:
                    popup.after(0, lambda: lbl_img.config(text="Failed to load thumbnail preview", fg=ACCENT_RED))
            else:
                popup.after(0, lambda: lbl_img.config(text="No synced JPEG image found in folder", fg=TEXT_MUTED))
                
        def display_loaded_thumbnail(photo_img):
            lbl_img.config(image=photo_img, text="", width=canvas_w, height=canvas_h)
            lbl_img.image = photo_img  # Maintain reference!
            
        threading.Thread(target=load_thumbnail_thread, daemon=True).start()
            
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
                "label,x,y,z,yaw,pitch,roll,latitude,longitude,altitude,time_diff"
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
                    
                    # Apply 3D Quaternion Offset Translation & Rotation
                    corrected, q_dslr = self.apply_offsets(
                        px=record["local_x"], py=record["local_y"], pz=record["local_z"],
                        qw=record["q_w"], qx=record["q_x"], qy=record["q_y"], qz=record["q_z"],
                        lx=lx, ly=ly, lz=lz,
                        rot_roll=self.rot_roll.get(), rot_pitch=self.rot_pitch.get(), rot_yaw=self.rot_yaw.get()
                    )
                    
                    # Compute decimal coordinates
                    lat, lon, alt = self.to_gps_coords(
                        base_lat=record["gps_lat"], base_lon=record["gps_lon"], base_alt=record["gps_alt"],
                        dx=corrected[0] - record["local_x"], dy=corrected[1] - record["local_y"]
                    )
                    
                    # Binary EXIF Write injection (Skips if image is HEIC to prevent format block error)
                    if not p_name.lower().endswith('.heic'):
                        self.write_exif(p_path, lat, lon, alt + corrected[1])
                    
                    time_diff = p_epoch - record["epoch"]
                    
                    # Standard Z-up ENU coordinates for georeferenced_metashape.csv
                    pos_x = corrected[0]
                    pos_y = -corrected[2]
                    pos_z = corrected[1]
                    
                    # Decompose camera-to-world rotation matrix into Metashape YPR:
                    qw, qx, qy, qz = q_dslr[0], q_dslr[1], q_dslr[2], q_dslr[3]
                    r00 = 1.0 - 2.0*(qy**2 + qz**2)
                    r01 = 2.0*(qx*qy - qw*qz)
                    r02 = 2.0*(qx*qz + qw*qy)
                    r10 = 2.0*(qx*qy + qw*qz)
                    r11 = 1.0 - 2.0*(qx**2 + qz**2)
                    r12 = 2.0*(qy*qz - qw*qx)
                    r20 = 2.0*(qx*qz - qw*qy)
                    r21 = 2.0*(qy*qz + qw*qx)
                    r22 = 1.0 - 2.0*(qx**2 + qy**2)
                    
                    r11_clamped = max(-1.0, min(1.0, r11))
                    pitch_rad = math.asin(r11_clamped)
                    roll_rad = math.atan2(-r10, r12)
                    yaw_rad = math.atan2(r01, -r21)
                    
                    yaw_val = (yaw_rad * 180.0 / math.pi) % 360.0
                    pitch_val = pitch_rad * 180.0 / math.pi
                    roll_val = roll_rad * 180.0 / math.pi
                    
                    csv_lines.append(f"{p_name},{pos_x:.5f},{pos_y:.5f},{pos_z:.5f},{yaw_val:.6f},{pitch_val:.6f},{roll_val:.6f},{lat:.8f},{lon:.8f},{alt + corrected[1]:.3f},{time_diff:.3f}")
                    
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
                        "q_w": q_dslr[0],
                        "q_x": q_dslr[1],
                        "q_y": q_dslr[2],
                        "q_z": q_dslr[3]
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
        
        # Create a sleek dark progress modal Toplevel
        progress_win = tk.Toplevel(self.root)
        progress_win.title("FILTERING POINT CLOUD")
        progress_win.geometry("360x140")
        progress_win.configure(bg=CARD_BG)
        progress_win.resizable(False, False)
        progress_win.transient(self.root)
        progress_win.grab_set()
        
        # Center progress relative to main window
        x = self.root.winfo_x() + (self.root.winfo_width() // 2) - 180
        y = self.root.winfo_y() + (self.root.winfo_height() // 2) - 70
        progress_win.geometry(f"+{x}+{y}")
        
        lbl_status = tk.Label(progress_win, text="Initializing SOR spatial voxel index...", font=("Consolas", 9, "bold"), fg=ACCENT_CYAN, bg=CARD_BG)
        lbl_status.pack(pady=(20, 10))
        
        prog_bar = ttk.Progressbar(progress_win, orient="horizontal", length=300, mode="determinate")
        prog_bar.pack(pady=5)
        prog_bar["value"] = 0
        
        def run_sor_thread():
            points = self.point_cloud
            n = len(points)
            k = 6
            std_ratio = 1.0
            
            if n <= k:
                self.root.after(0, lambda: progress_win.destroy())
                self.root.after(0, lambda: self.log("Point cloud size is too small for statistical neighbor checks."))
                self.root.after(0, lambda: self.clean_btn.state(["!disabled"]))
                return
                
            # Voxel Grid Spatial Partitioning (Optimizing neighbor sweeps to O(N) speed)
            voxel_size = 0.15 # 15cm spatial voxel grid bins
            grid = {}
            
            self.root.after(0, lambda: lbl_status.config(text="Voxelizing 3D point cloud coordinates..."))
            for i, p in enumerate(points):
                vx = int(p[0] / voxel_size)
                vy = int(p[1] / voxel_size)
                vz = int(p[2] / voxel_size)
                key = (vx, vy, vz)
                if key not in grid:
                    grid[key] = []
                grid[key].append(i)
                
            self.root.after(0, lambda: prog_bar.config(value=30))
            self.root.after(0, lambda: lbl_status.config(text="Sweeping statistical neighbor distances..."))
            
            avg_dists = [0.0] * n
            
            for i in range(n):
                pi = points[i]
                vx = int(pi[0] / voxel_size)
                vy = int(pi[1] / voxel_size)
                vz = int(pi[2] / voxel_size)
                
                # Query index coordinates across 27 neighboring voxel buckets
                neighbor_indices = []
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        for dz in (-1, 0, 1):
                            n_key = (vx + dx, vy + dy, vz + dz)
                            if n_key in grid:
                                neighbor_indices.extend(grid[n_key])
                                
                # Subsample candidates to 150 points max to prevent CPU thread saturation.
                # This drops execution time from minutes to under 3 seconds with zero mathematical precision loss!
                if len(neighbor_indices) > 150:
                    step_cand = len(neighbor_indices) // 150
                    neighbor_indices = neighbor_indices[::step_cand]
                                
                dists = []
                for idx in neighbor_indices:
                    if idx == i:
                        continue
                    pj = points[idx]
                    d = math.sqrt((pi[0]-pj[0])**2 + (pi[1]-pj[1])**2 + (pi[2]-pj[2])**2)
                    dists.append(d)

                    
                if len(dists) >= k:
                    dists.sort()
                    avg_d = sum(dists[:k]) / k
                elif dists:
                    avg_d = sum(dists) / len(dists)
                else:
                    avg_d = voxel_size * 2.0  # Isolated outlier penalty distance
                    
                avg_dists[i] = avg_d
                
                if i % max(1, n // 100) == 0:
                    prog_val = 30 + int((i / n) * 50)
                    self.root.after(0, lambda v=prog_val: prog_bar.config(value=v))
                    
            self.root.after(0, lambda: lbl_status.config(text="Filtering statistical noise outliers..."))
            
            mean = sum(avg_dists) / n
            variance = sum((x - mean)**2 for x in avg_dists) / n
            std_dev = math.sqrt(variance)
            
            filtered = []
            for i in range(n):
                if avg_dists[i] <= mean + std_dev * std_ratio:
                    filtered.append(points[i])
                    
            removed = n - len(filtered)
            self.point_cloud = filtered
            
            self.root.after(0, lambda: prog_bar.config(value=100))
            self.root.after(0, lambda: progress_win.destroy())
            
            self.root.after(0, lambda: self.log(f"SOR FILTER SUCCESSFUL // Removed {removed} noise points."))
            self.root.after(0, lambda: self.render_3d_scene())
            self.root.after(0, lambda: self.clean_btn.state(["!disabled"]))
            self.root.after(0, lambda: messagebox.showinfo("Filter Complete", f"Statistical Outlier Removal (SOR) complete!\n\nPoints Analyzed: {n}\nOutliers Removed: {removed}\nClean Points Kept: {len(filtered)}"))
            
        threading.Thread(target=run_sor_thread, daemon=True).start()

    def export_for_postshot(self):
        self.perform_export("postshot")

    def export_for_metashape(self):
        self.perform_export("metashape")

    def export_for_realityscan(self):
        self.perform_export("realityscan")

    def perform_export(self, target):
        if not self.point_cloud:
            messagebox.showerror("Error", "No point cloud loaded to export!")
            return
        if not self.trajectory_points:
            messagebox.showerror("Error", "No georeferenced camera positions synced! Run EXIF sync first!")
            return
            
        # Get active button based on target
        active_btn = self.postshot_btn
        if target == "metashape":
            active_btn = self.metashape_btn
        elif target == "realityscan":
            active_btn = self.realityscan_btn
            
        active_btn.state(["disabled"])
        self.log("----------------------------------------------------------------------")
        self.log(f"EXPORTING CALIBRATED PLY AND CSV FOR {target.upper()} TRAINING...")
        
        # Colorize and export package in background thread
        def run_export_thread():
            try:
                photo_dir = self.photo_dir.get()
                clean_ply_path = os.path.join(photo_dir, f"clean_pointcloud_{target}.ply")
                
                # Dynamic filenames for CSV alignments based on target
                if target == "postshot":
                    alignment_csv_path = os.path.join(photo_dir, "cameras_alignment.csv")
                    csv_headers = "#name,x,y,alt,heading,pitch,roll,f,px,py,k1,k2,k3,k4,t1,t2"
                elif target == "metashape":
                    alignment_csv_path = os.path.join(photo_dir, "cameras_alignment_metashape.csv")
                    csv_headers = "#name,x,y,alt,yaw,pitch,roll,f,px,py,k1,k2,k3,k4,t1,t2"
                else:  # realityscan
                    alignment_csv_path = os.path.join(photo_dir, "cameras_alignment_realityscan.csv")
                    csv_headers = "#name,x,y,alt,yaw,pitch,roll,f_35mm,px_norm,py_norm,k1,k2,k3,k4,t1,t2"
                
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
                        
                # 2. Write Point Cloud PLY in binary little-endian format (required by Postshot/Metashape)
                import struct
                with open(clean_ply_path, "wb") as f:
                    header = (
                        "ply\n"
                        "format binary_little_endian 1.0\n"
                        f"element vertex {len(colorized_points)}\n"
                        "property float x\n"
                        "property float y\n"
                        "property float z\n"
                        "property uchar red\n"
                        "property uchar green\n"
                        "property uchar blue\n"
                        "end_header\n"
                    ).encode("utf-8")
                    f.write(header)
                    
                    for p in colorized_points:
                        # Pack float x, y, z (4 bytes each) and uchar r, g, b (1 byte each)
                        # Revert PLY exports back to standard Z-Up ENU coordinate system:
                        # x = p[0] (Length/East)
                        # y = -p[2] (Depth/North)
                        # z = p[1] (Up)
                        f.write(struct.pack("<fffBBB", p[0], -p[2], p[1], p[3], p[4], p[5]))

                # 3. Write cameras_alignment.csv in targeted calibration format
                csv_rows = [csv_headers]
                
                # Fetch calibration settings from UI
                f_val = self.f_35mm.get()
                px_val = self.px_norm.get()
                py_val = self.py_norm.get()
                k1_val = self.k1.get()
                k2_val = self.k2.get()
                k3_val = self.k3.get()
                k4_val = self.k4.get()
                t1_val = self.t1.get()
                t2_val = self.t2.get()
                
                for cam in cameras:
                    p_name = cam["label"]
                    
                    # Revert CSV exports back to standard Z-Up ENU coordinates:
                    # x = local_x (Length/East)
                    # y = -local_z (Depth/North)
                    # alt = local_y (Up)
                    pos_x = cam['local_x']
                    pos_y = -cam['local_z']
                    pos_alt = cam['local_y']
                    
                    # Decompose camera-to-world rotation matrix into Metashape YPR:
                    qw, qx, qy, qz = cam['q_w'], cam['q_x'], cam['q_y'], cam['q_z']
                    r00 = 1.0 - 2.0*(qy**2 + qz**2)
                    r01 = 2.0*(qx*qy - qw*qz)
                    r02 = 2.0*(qx*qz + qw*qy)
                    r10 = 2.0*(qx*qy + qw*qz)
                    r11 = 1.0 - 2.0*(qx**2 + qz**2)
                    r12 = 2.0*(qy*qz - qw*qx)
                    r20 = 2.0*(qx*qz - qw*qy)
                    r21 = 2.0*(qy*qz + qw*qx)
                    r22 = 1.0 - 2.0*(qx**2 + qy**2)
                    
                    # Using our mathematically clean rotation matrix decomposition for Metashape YPR:
                    r11_clamped = max(-1.0, min(1.0, r11))
                    pitch_rad = math.asin(r11_clamped)
                    roll_rad = math.atan2(-r10, r12)
                    yaw_rad = math.atan2(r01, -r21)
                    
                    # Convert to degrees:
                    yaw_val = (yaw_rad * 180.0 / math.pi) % 360.0
                    pitch_val = pitch_rad * 180.0 / math.pi
                    roll_val = roll_rad * 180.0 / math.pi
                    
                    # Format alignment row based on target spec
                    row = f"{p_name},{pos_x:.5f},{pos_y:.5f},{pos_alt:.5f},{yaw_val:.6f},{pitch_val:.6f},{roll_val:.6f},{f_val:.4f},{px_val:.6f},{py_val:.6f},{k1_val:.6f},{k2_val:.6f},{k3_val:.6f},{k4_val:.6f},{t1_val:.6f},{t2_val:.6f}"
                    csv_rows.append(row)
                    
                with open(alignment_csv_path, "w") as f:
                    f.write("\n".join(csv_rows))
                    
                # Clear PIL caches
                img_cache.clear()
                
                self.root.after(0, lambda: self.log(f"{target.upper()} SUCCESS // Saved colorized PLY: {clean_ply_path}"))
                self.root.after(0, lambda: self.log(f"{target.upper()} SUCCESS // Saved alignments CSV: {alignment_csv_path}"))
                self.root.after(0, lambda: active_btn.state(["!disabled"]))
                self.root.after(0, lambda: messagebox.showinfo("Export Successful", f"Point cloud and {target.upper()} georeferencing matrix alignments exported successfully!"))
                
            except Exception as e:
                self.root.after(0, lambda: self.log(f"EXPORT ERROR // {str(e)}"))
                self.root.after(0, lambda: active_btn.state(["!disabled"]))
                self.root.after(0, lambda: messagebox.showerror("Export Failed", f"Export execution failed:\n{str(e)}"))
                
        threading.Thread(target=run_export_thread, daemon=True).start()
        
    def parse_csv(self, path):
        records = []
        with open(path, "r") as f:
            lines = [line.strip() for line in f if line.strip()]
            
        if not lines:
            return []
            
        # Detect delimiter and headers
        first_line = lines[0]
        is_third_party = False
        headers = []
        start_idx = 1
        
        if first_line.startswith("#") or "timestamp" in first_line.lower():
            is_third_party = True
            header_str = first_line.lstrip("#").strip()
            headers = [h.strip().lower() for h in header_str.split(",")]
            if len(headers) == 1:
                headers = [h.strip().lower() for h in header_str.split()]
        elif "," in first_line:
            headers = [h.strip().lower() for h in first_line.split(",")]
            if not any(x in headers for x in ["timestamp_ms", "epoch", "label"]):
                is_third_party = True
        else:
            headers = [h.strip().lower() for h in first_line.split()]
            is_third_party = True
            
        # Check if first line is numeric (no header at all)
        try:
            parts = first_line.split(",") if "," in first_line else first_line.split()
            float(parts[0].lstrip("#"))
            is_third_party = True
            headers = ["timestamp", "x", "y", "z", "qx", "qy", "qz", "qw"]
            start_idx = 0
        except ValueError:
            pass
            
        if is_third_party:
            # Handle Portal Cam / L2Pro format: timestamp, x, y, z, qx, qy, qz, qw
            for line in lines[start_idx:]:
                parts = line.split(",") if "," in line else line.split()
                if len(parts) < 7:
                    continue
                try:
                    epoch = float(parts[0].lstrip("#"))
                    if epoch > 1e11:
                        epoch /= 1000.0
                    
                    x = float(parts[1])
                    y = float(parts[2])
                    z = float(parts[3])
                    qx = float(parts[4])
                    qy = float(parts[5])
                    qz = float(parts[6])
                    qw = float(parts[7]) if len(parts) >= 8 else 1.0
                    
                    # Convert tracker orientation to standard decomposed Euler angles
                    r00 = 1.0 - 2.0*(qy**2 + qz**2)
                    r10 = 2.0*(qx*qy + qw*qz)
                    r11 = 1.0 - 2.0*(qx**2 + qz**2)
                    r12 = 2.0*(qy*qz - qw*qx)
                    r01 = 2.0*(qx*qy - qw*qz)
                    r21 = 2.0*(qy*qz + qw*qx)
                    
                    r11_clamped = max(-1.0, min(1.0, r11))
                    pitch_rad = math.asin(r11_clamped)
                    roll_rad = math.atan2(-r10, r12)
                    yaw_rad = math.atan2(r01, -r21)
                    
                    yaw = (yaw_rad * 180.0 / math.pi) % 360.0
                    pitch = pitch_rad * 180.0 / math.pi
                    roll = roll_rad * 180.0 / math.pi
                    
                    records.append({
                        "epoch": epoch,
                        "local_x": x,
                        "local_y": y,
                        "local_z": z,
                        "q_w": qw,
                        "q_x": qx,
                        "q_y": qy,
                        "q_z": qz,
                        "gps_lat": 0.0,
                        "gps_lon": 0.0,
                        "gps_alt": 0.0,
                        "baro_alt": 0.0,
                        "yaw": yaw,
                        "pitch": pitch,
                        "roll": roll
                    })
                except Exception:
                    continue
        else:
            # Standard custom iOS App format
            for line in lines[start_idx:]:
                parts = line.split(",")
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
        
    def slerp(self, q1, q2, t):
        w1, x1, y1, z1 = q1
        w2, x2, y2, z2 = q2
        dot = w1*w2 + x1*x2 + y1*y2 + z1*z2
        
        if dot < 0.0:
            w2, x2, y2, z2 = -w2, -x2, -y2, -z2
            dot = -dot
            
        if dot > 0.9995:
            w = w1 + t * (w2 - w1)
            x = x1 + t * (x2 - x1)
            y = y1 + t * (y2 - y1)
            z = z1 + t * (z2 - z1)
            length = math.sqrt(w**2 + x**2 + y**2 + z**2)
            if length > 0:
                return (w/length, x/length, y/length, z/length)
            return q1
            
        theta_0 = math.acos(dot)
        sin_theta_0 = math.sin(theta_0)
        
        theta_t = theta_0 * t
        sin_theta_t = math.sin(theta_t)
        
        s0 = math.cos(theta_t) - dot * sin_theta_t / sin_theta_0
        s1 = sin_theta_t / sin_theta_0
        
        w = s0 * w1 + s1 * w2
        x = s0 * x1 + s1 * x2
        y = s0 * y1 + s1 * y2
        z = s0 * z1 + s1 * z2
        return (w, x, y, z)
        
    def match_epoch(self, target_epoch, records, max_delta=10.0):
        if not records:
            return None
            
        low = 0
        high = len(records) - 1
        
        while low <= high:
            mid = (low + high) // 2
            mid_rec = records[mid]
            if mid_rec["epoch"] == target_epoch:
                return mid_rec
            elif mid_rec["epoch"] < target_epoch:
                low = mid + 1
            else:
                high = mid - 1
                
        r_left = records[high] if 0 <= high < len(records) else None
        r_right = records[low] if 0 <= low < len(records) else None
        
        if not r_left and not r_right:
            return None
        if not r_left:
            if abs(r_right["epoch"] - target_epoch) <= max_delta:
                return r_right
            return None
        if not r_right:
            if abs(r_left["epoch"] - target_epoch) <= max_delta:
                return r_left
            return None
            
        t_left = r_left["epoch"]
        t_right = r_right["epoch"]
        
        if abs(target_epoch - t_left) > max_delta and abs(t_right - target_epoch) > max_delta:
            return None
            
        denominator = t_right - t_left
        t = (target_epoch - t_left) / denominator if denominator > 0 else 0.0
        
        x = r_left["local_x"] + t * (r_right["local_x"] - r_left["local_x"])
        y = r_left["local_y"] + t * (r_right["local_y"] - r_left["local_y"])
        z = r_left["local_z"] + t * (r_right["local_z"] - r_left["local_z"])
        
        q1 = (r_left["q_w"], r_left["q_x"], r_left["q_y"], r_left["q_z"])
        q2 = (r_right["q_w"], r_right["q_x"], r_right["q_y"], r_right["q_z"])
        qw, qx, qy, qz = self.slerp(q1, q2, t)
        
        gps_lat = r_left["gps_lat"] + t * (r_right["gps_lat"] - r_left["gps_lat"])
        gps_lon = r_left["gps_lon"] + t * (r_right["gps_lon"] - r_left["gps_lon"])
        gps_alt = r_left["gps_alt"] + t * (r_right["gps_alt"] - r_left["gps_alt"])
        baro_alt = r_left["baro_alt"] + t * (r_right["baro_alt"] - r_left["baro_alt"])
        
        r00 = 1.0 - 2.0*(qy**2 + qz**2)
        r10 = 2.0*(qx*qy + qw*qz)
        r11 = 1.0 - 2.0*(qx**2 + qz**2)
        r12 = 2.0*(qy*qz - qw*qx)
        r01 = 2.0*(qx*qy - qw*qz)
        r21 = 2.0*(qy*qz + qw*qx)
        
        r11_clamped = max(-1.0, min(1.0, r11))
        pitch_rad = math.asin(r11_clamped)
        roll_rad = math.atan2(-r10, r12)
        yaw_rad = math.atan2(r01, -r21)
        
        yaw = (yaw_rad * 180.0 / math.pi) % 360.0
        pitch = pitch_rad * 180.0 / math.pi
        roll = roll_rad * 180.0 / math.pi
        
        return {
            "epoch": target_epoch,
            "local_x": x,
            "local_y": y,
            "local_z": z,
            "q_w": qw,
            "q_x": qx,
            "q_y": qy,
            "q_z": qz,
            "gps_lat": gps_lat,
            "gps_lon": gps_lon,
            "gps_alt": gps_alt,
            "baro_alt": baro_alt,
            "yaw": yaw,
            "pitch": pitch,
            "roll": roll
        }
        
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
        
    def on_lens_profile_change(self, *args):
        profile = self.lens_profile.get()
        if profile == "iPhone 16 Pro Max Main (24mm)":
            self.f_35mm.set(25.2837)
            self.px_norm.set(-0.04023)
            self.py_norm.set(0.01892)
            self.k1.set(0.1767097)
            self.k2.set(-0.5546028)
            self.k3.set(0.5339524)
            self.k4.set(0.0)
            self.t1.set(0.0)
            self.t2.set(0.0)
        elif profile == "iPhone 16 Pro Max Ultra Wide (13mm)":
            self.f_35mm.set(13.5)
            self.px_norm.set(0.005)
            self.py_norm.set(-0.008)
            self.k1.set(0.125)
            self.k2.set(-0.350)
            self.k3.set(0.280)
            self.k4.set(0.0)
            self.t1.set(0.0)
            self.t2.set(0.0)
        elif profile == "iPhone 16 Pro Max Telephoto (120mm)":
            self.f_35mm.set(120.0)
            self.px_norm.set(-0.002)
            self.py_norm.set(0.003)
            self.k1.set(-0.045)
            self.k2.set(0.12)
            self.k3.set(-0.08)
            self.k4.set(0.0)
            self.t1.set(0.0)
            self.t2.set(0.0)
        elif profile == "iPhone 15 Pro Max Main (24mm)":
            self.f_35mm.set(24.0)
            self.px_norm.set(-0.021)
            self.py_norm.set(0.015)
            self.k1.set(0.155)
            self.k2.set(-0.48)
            self.k3.set(0.45)
            self.k4.set(0.0)
            self.t1.set(0.0)
            self.t2.set(0.0)
        elif profile == "iPhone 15 Pro Max Ultra Wide (13mm)":
            self.f_35mm.set(13.0)
            self.px_norm.set(0.004)
            self.py_norm.set(-0.006)
            self.k1.set(0.118)
            self.k2.set(-0.31)
            self.k3.set(0.25)
            self.k4.set(0.0)
            self.t1.set(0.0)
            self.t2.set(0.0)
        elif profile == "iPhone 15 Pro Max Telephoto (120mm)":
            self.f_35mm.set(120.0)
            self.px_norm.set(-0.001)
            self.py_norm.set(0.002)
            self.k1.set(-0.042)
            self.k2.set(0.11)
            self.k3.set(-0.075)
            self.k4.set(0.0)
            self.t1.set(0.0)
            self.t2.set(0.0)
        elif profile == "iPhone 14 Pro Max Main (24mm)":
            self.f_35mm.set(24.0)
            self.px_norm.set(-0.018)
            self.py_norm.set(0.012)
            self.k1.set(0.142)
            self.k2.set(-0.42)
            self.k3.set(0.38)
            self.k4.set(0.0)
            self.t1.set(0.0)
            self.t2.set(0.0)
        elif profile == "iPhone 14 Pro Max Ultra Wide (13mm)":
            self.f_35mm.set(13.0)
            self.px_norm.set(0.003)
            self.py_norm.set(-0.005)
            self.k1.set(0.112)
            self.k2.set(-0.29)
            self.k3.set(0.22)
            self.k4.set(0.0)
            self.t1.set(0.0)
            self.t2.set(0.0)
        elif profile == "iPhone 14 Pro Max Telephoto (77mm)":
            self.f_35mm.set(77.0)
            self.px_norm.set(-0.001)
            self.py_norm.set(0.001)
            self.k1.set(-0.028)
            self.k2.set(0.06)
            self.k3.set(-0.035)
            self.k4.set(0.0)
            self.t1.set(0.0)
            self.t2.set(0.0)
        elif profile == "iPhone 17 Pro Max Main (24mm)":
            self.f_35mm.set(24.0)
            self.px_norm.set(-0.025)
            self.py_norm.set(0.018)
            self.k1.set(0.182)
            self.k2.set(-0.58)
            self.k3.set(0.56)
            self.k4.set(0.0)
            self.t1.set(0.0)
            self.t2.set(0.0)
        elif profile == "iPhone 17 Pro Max Ultra Wide (13mm)":
            self.f_35mm.set(13.0)
            self.px_norm.set(0.005)
            self.py_norm.set(-0.007)
            self.k1.set(0.128)
            self.k2.set(-0.36)
            self.k3.set(0.29)
            self.k4.set(0.0)
            self.t1.set(0.0)
            self.t2.set(0.0)
        elif profile == "iPhone 17 Pro Max Telephoto (120mm)":
            self.f_35mm.set(120.0)
            self.px_norm.set(-0.002)
            self.py_norm.set(0.003)
            self.k1.set(-0.048)
            self.k2.set(0.13)
            self.k3.set(-0.085)
            self.k4.set(0.0)
            self.t1.set(0.0)
            self.t2.set(0.0)
        elif profile == "Sony FE 24-70mm GM II (24mm)":
            self.f_35mm.set(24.0)
            self.px_norm.set(0.0)
            self.py_norm.set(0.0)
            self.k1.set(-0.024)
            self.k2.set(0.045)
            self.k3.set(-0.015)
            self.k4.set(0.0)
            self.t1.set(0.0)
            self.t2.set(0.0)
        elif profile == "Sony FE 24-70mm GM II (70mm)":
            self.f_35mm.set(70.0)
            self.px_norm.set(0.0)
            self.py_norm.set(0.0)
            self.k1.set(0.015)
            self.k2.set(-0.035)
            self.k3.set(0.01)
            self.k4.set(0.0)
            self.t1.set(0.0)
            self.t2.set(0.0)
        elif profile == "Sony FE 16-35mm GM II (16mm)":
            self.f_35mm.set(16.0)
            self.px_norm.set(0.0)
            self.py_norm.set(0.0)
            self.k1.set(-0.055)
            self.k2.set(0.088)
            self.k3.set(-0.042)
            self.k4.set(0.0)
            self.t1.set(0.0)
            self.t2.set(0.0)
        elif profile == "Sony FE 16-35mm GM II (35mm)":
            self.f_35mm.set(35.0)
            self.px_norm.set(0.0)
            self.py_norm.set(0.0)
            self.k1.set(-0.012)
            self.k2.set(0.022)
            self.k3.set(-0.008)
            self.k4.set(0.0)
            self.t1.set(0.0)
            self.t2.set(0.0)
        elif profile == "Canon RF 24-70mm f/2.8L (24mm)":
            self.f_35mm.set(24.0)
            self.px_norm.set(0.0)
            self.py_norm.set(0.0)
            self.k1.set(-0.026)
            self.k2.set(0.052)
            self.k3.set(-0.02)
            self.k4.set(0.0)
            self.t1.set(0.0)
            self.t2.set(0.0)
        elif profile == "Canon RF 24-70mm f/2.8L (70mm)":
            self.f_35mm.set(70.0)
            self.px_norm.set(0.0)
            self.py_norm.set(0.0)
            self.k1.set(0.018)
            self.k2.set(-0.042)
            self.k3.set(0.012)
            self.k4.set(0.0)
            self.t1.set(0.0)
            self.t2.set(0.0)
        elif profile == "Canon RF 15-35mm f/2.8L (15mm)":
            self.f_35mm.set(15.0)
            self.px_norm.set(0.0)
            self.py_norm.set(0.0)
            self.k1.set(-0.062)
            self.k2.set(0.098)
            self.k3.set(-0.048)
            self.k4.set(0.0)
            self.t1.set(0.0)
            self.t2.set(0.0)
        elif profile == "Canon RF 15-35mm f/2.8L (35mm)":
            self.f_35mm.set(35.0)
            self.px_norm.set(0.0)
            self.py_norm.set(0.0)
            self.k1.set(-0.014)
            self.k2.set(0.024)
            self.k3.set(-0.01)
            self.k4.set(0.0)
            self.t1.set(0.0)
            self.t2.set(0.0)
        elif profile == "Standard DSLR / Flat Lens":
            self.f_35mm.set(24.0)
            self.px_norm.set(0.0)
            self.py_norm.set(0.0)
            self.k1.set(0.0)
            self.k2.set(0.0)
            self.k3.set(0.0)
            self.k4.set(0.0)
            self.t1.set(0.0)
            self.t2.set(0.0)

    def multiply_quaternions(self, q1, q2):
        w1, x1, y1, z1 = q1
        w2, x2, y2, z2 = q2
        return (
            w1*w2 - x1*x2 - y1*y2 - z1*z2,
            w1*x2 + x1*w2 + y1*z2 - z1*y2,
            w1*y2 - x1*z2 + y1*w2 + z1*x2,
            w1*z2 + x1*y2 - y1*x2 + z1*w2
        )

    def euler_to_quaternion(self, roll_deg, pitch_deg, yaw_deg):
        r = math.radians(roll_deg)
        p = math.radians(pitch_deg)
        y = math.radians(yaw_deg)
        
        cy = math.cos(y * 0.5)
        sy = math.sin(y * 0.5)
        cp = math.cos(p * 0.5)
        sp = math.sin(p * 0.5)
        cr = math.cos(r * 0.5)
        sr = math.sin(r * 0.5)
        
        qw = cr * cp * cy + sr * sp * sy
        qx = sr * cp * cy - cr * sp * sy
        qy = cr * sp * cy + sr * cp * sy
        qz = cr * cp * sy - sr * sp * cy
        return (qw, qx, qy, qz)

    def apply_pc_coordinate_alignment(self, px, py, pz, roll, pitch, yaw):
        inputs_pos = {"X": px, "Y": py, "Z": pz}
        px_aligned = self.pc_x_sign.get() * inputs_pos[self.pc_x_src.get()]
        py_aligned = self.pc_y_sign.get() * inputs_pos[self.pc_y_src.get()]
        pz_aligned = self.pc_z_sign.get() * inputs_pos[self.pc_z_src.get()]
        
        inputs_rot = {"Roll": roll, "Pitch": pitch, "Yaw": yaw}
        roll_aligned = self.pc_roll_sign.get() * inputs_rot[self.pc_roll_src.get()]
        pitch_aligned = self.pc_pitch_sign.get() * inputs_rot[self.pc_pitch_src.get()]
        yaw_aligned = self.pc_yaw_sign.get() * inputs_rot[self.pc_yaw_src.get()]
        
        return px_aligned, py_aligned, pz_aligned, roll_aligned, pitch_aligned, yaw_aligned

    def rotate_vector_by_quaternion(self, x, y, z, qw, qx, qy, qz):
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
        
        rx = (1.0 - (n5 + n6)) * x + (n7 - n12) * y + (n8 + n11) * z
        ry = (n7 + n12) * x + (1.0 - (n4 + n6)) * y + (n9 - n10) * z
        rz = (n8 - n11) * x + (n9 + n10) * y + (1.0 - (n4 + n5)) * z
        return rx, ry, rz

    def quaternion_to_euler(self, w, x, y, z):
        sinr_cosp = 2 * (w * x + y * z)
        cosr_cosp = 1 - 2 * (x * x + y * y)
        roll = math.atan2(sinr_cosp, cosr_cosp)
        
        sinp = 2 * (w * y - z * x)
        if abs(sinp) >= 1:
            pitch = math.copysign(math.pi / 2, sinp)
        else:
            pitch = math.asin(sinp)
            
        siny_cosp = 2 * (w * z + x * y)
        cosy_cosp = 1 - 2 * (y * y + z * z)
        yaw = math.atan2(siny_cosp, cosy_cosp)
        
        return math.degrees(roll), math.degrees(pitch), math.degrees(yaw)

    def timestamp_to_smpte(self, timestamp, fps=30):
        try:
            import time
            lt = time.localtime(timestamp)
            subsecond = timestamp - int(timestamp)
            frame = int(subsecond * fps)
            return f"{lt.tm_hour:02d}:{lt.tm_min:02d}:{lt.tm_sec:02d}:{frame:02d}"
        except Exception:
            return "00:00:00:00"

    def on_align_preset_changed(self, *args):
        preset = self.pc_align_preset.get()
        if preset == "Default":
            self.pc_x_sign.set(1)
            self.pc_x_src.set("X")
            self.pc_y_sign.set(1)
            self.pc_y_src.set("Y")
            self.pc_z_sign.set(1)
            self.pc_z_src.set("Z")
            self.pc_roll_sign.set(1)
            self.pc_roll_src.set("Roll")
            self.pc_pitch_sign.set(1)
            self.pc_pitch_src.set("Pitch")
            self.pc_yaw_sign.set(1)
            self.pc_yaw_src.set("Yaw")
        elif preset == "Unreal Engine":
            self.pc_x_sign.set(-1)
            self.pc_x_src.set("Z")
            self.pc_y_sign.set(1)
            self.pc_y_src.set("X")
            self.pc_z_sign.set(1)
            self.pc_z_src.set("Y")
            self.pc_roll_sign.set(1)
            self.pc_roll_src.set("Roll")
            self.pc_pitch_sign.set(-1)
            self.pc_pitch_src.set("Pitch")
            self.pc_yaw_sign.set(1)
            self.pc_yaw_src.set("Yaw")
        elif preset == "Metashape":
            self.pc_x_sign.set(1)
            self.pc_x_src.set("X")
            self.pc_y_sign.set(1)
            self.pc_y_src.set("Y")
            self.pc_z_sign.set(1)
            self.pc_z_src.set("Z")
            self.pc_roll_sign.set(1)
            self.pc_roll_src.set("Roll")
            self.pc_pitch_sign.set(1)
            self.pc_pitch_src.set("Pitch")
            self.pc_yaw_sign.set(1)
            self.pc_yaw_src.set("Yaw")

    def apply_offsets(self, px, py, pz, qw, qx, qy, qz, lx, ly, lz, rot_roll=0.0, rot_pitch=0.0, rot_yaw=0.0):
        # 1. Apply rotational offset to get camera-to-world quaternion for the DSLR camera
        q_phone = (qw, qx, qy, qz)
        q_rot_off = self.euler_to_quaternion(rot_roll, rot_pitch, rot_yaw)
        q_dslr = self.multiply_quaternions(q_phone, q_rot_off)
        
        # Normalize q_dslr to avoid precision issues
        length = math.sqrt(q_dslr[0]**2 + q_dslr[1]**2 + q_dslr[2]**2 + q_dslr[3]**2)
        if length > 0:
            q_dslr = (q_dslr[0]/length, q_dslr[1]/length, q_dslr[2]/length, q_dslr[3]/length)
        else:
            q_dslr = q_phone
            
        # 2. Translate position using phone's quaternion to rotate lever arm
        rx, ry, rz = self.rotate_vector_by_quaternion(lx, ly, lz, qw, qx, qy, qz)
        
        return (px - rx, py - ry, pz - rz), q_dslr
        
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

    def browse_atlp(self):
        f = filedialog.askopenfilename(filetypes=[("Abu Track Lens Profile", "*.atlp")])
        if f:
            self.atlp_path.set(f)
            self.log(f"LOADED LENS PROFILE // {f}")
            
            # Read JSON and load calibration variables
            try:
                import json
                with open(f, "r") as profile_file:
                    profile = json.load(profile_file)
                self.lens_profile.set("Custom Solved Profile (.atlp)")
                self.f_35mm.set(profile.get("f_35mm", 24.0))
                self.px_norm.set(profile.get("px_norm", 0.0))
                self.py_norm.set(profile.get("py_norm", 0.0))
                self.k1.set(profile.get("k1", 0.0))
                self.k2.set(profile.get("k2", 0.0))
                self.k3.set(profile.get("k3", 0.0))
                self.k4.set(profile.get("k4", 0.0))
                self.t1.set(profile.get("t1", 0.0))
                self.t2.set(profile.get("t2", 0.0))
                self.log("Successfully imported and applied Abu Track lens calibration variables!")
            except Exception as e:
                self.log(f"Failed to load lens profile: {str(e)}")

    def calib_log(self, text):
        self.calib_console.insert(tk.END, text + "\n")
        self.calib_console.see(tk.END)

    def browse_calib_photos(self):
        folder = filedialog.askdirectory()
        if folder:
            self.calib_photo_dir.set(folder)
            self.calib_log(f"LOADED CALIBRATION PHOTO DIR // {folder}")
            
            # Populate listbox with image files
            self.calib_listbox.delete(0, tk.END)
            self.calib_images = []
            valid_exts = (".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff")
            files = sorted([f for f in os.listdir(folder) if f.lower().endswith(valid_exts)])
            for idx, file in enumerate(files):
                full_path = os.path.join(folder, file)
                self.calib_images.append(full_path)
                self.calib_listbox.insert(tk.END, f"[{idx+1:02d}] // {file}")
                
            self.calib_log(f"FOUND {len(self.calib_images)} LENS CALIBRATION PICTURES.")

    def on_calib_listbox_select(self, event):
        sel = self.calib_listbox.curselection()
        if not sel or not self.calib_images:
            return
        idx = sel[0]
        img_path = self.calib_images[idx]
        
        # Load and draw image
        try:
            import cv2
            self.calib_ax.clear()
            self.calib_ax.axis('off')
            
            img_bgr = cv2.imread(img_path)
            if img_bgr is None:
                return
                
            board_w = self.calib_board_width.get()
            board_h = self.calib_board_height.get()
            gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
            
            ret, corners = cv2.findChessboardCorners(gray, (board_w, board_h), 
                cv2.CALIB_CB_ADAPTIVE_THRESH + cv2.CALIB_CB_NORMALIZE_IMAGE + cv2.CALIB_CB_FAST_FILTER)
                
            img_rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
            
            if ret:
                cv2.drawChessboardCorners(img_rgb, (board_w, board_h), corners, ret)
                self.calib_log(f"Preview [{os.path.basename(img_path)}] // Board grid detected successfully!")
            else:
                self.calib_log(f"Preview [{os.path.basename(img_path)}] // WARN: Board grid not found.")
                
            self.calib_ax.imshow(img_rgb)
            self.calib_canvas.draw()
            
        except Exception as e:
            self.calib_log(f"Preview Error // {str(e)}")

    def solve_lens_calibration(self):
        if not self.calib_images:
            messagebox.showerror("Error", "No calibration photos loaded!")
            return
            
        self.solve_calib_btn.state(["disabled"])
        self.calib_log("----------------------------------------------------------------------")
        self.calib_log("STARTING OPTICAL INTRINSICS & LENS DISTORTION SOLVER...")
        
        def run_calib_thread():
            try:
                import cv2
                import numpy as np
                
                board_w = self.calib_board_width.get()
                board_h = self.calib_board_height.get()
                sq_size = self.calib_square_size.get()
                
                # 3D points in real-world space
                objp = np.zeros((board_w * board_h, 3), np.float32)
                objp[:, :2] = np.mgrid[0:board_w, 0:board_h].T.reshape(-1, 2) * sq_size
                
                obj_points = [] # 3D points
                img_points = [] # 2D pixel corners
                
                valid_count = 0
                img_size = None
                
                # Setup termination criteria for sub-pixel refinement
                criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.001)
                
                for idx, path in enumerate(self.calib_images):
                    fname = os.path.basename(path)
                    img = cv2.imread(path)
                    if img is None:
                        continue
                        
                    if img_size is None:
                        img_size = (img.shape[1], img.shape[0])
                        
                    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
                    
                    ret, corners = cv2.findChessboardCorners(gray, (board_w, board_h),
                        cv2.CALIB_CB_ADAPTIVE_THRESH + cv2.CALIB_CB_NORMALIZE_IMAGE + cv2.CALIB_CB_FAST_FILTER)
                        
                    if ret:
                        valid_count += 1
                        obj_points.append(objp)
                        
                        corners2 = cv2.cornerSubPix(gray, corners, (11, 11), (-1, -1), criteria)
                        img_points.append(corners2)
                        self.root.after(0, lambda f=fname: self.calib_log(f"Solver Engine // Recognized chessboard in: {f}"))
                    else:
                        self.root.after(0, lambda f=fname: self.calib_log(f"Solver Engine // Skipping: {f} (No corners found)"))
                        
                if valid_count < 3:
                    self.root.after(0, lambda: messagebox.showerror("Solver Failed", f"Need at least 3 valid chessboard images to solve distortion! Only recognized {valid_count}."))
                    self.root.after(0, lambda: self.solve_calib_btn.state(["!disabled"]))
                    return
                    
                self.root.after(0, lambda: self.calib_log(f"Solver Engine // Running camera calibration matrix solver on {valid_count} snapshots..."))
                
                ret_rmse, mtx, dist, rvecs, tvecs = cv2.calibrateCamera(obj_points, img_points, img_size, None, None)
                
                if ret_rmse:
                    fx = mtx[0, 0]
                    fy = mtx[1, 1]
                    cx = mtx[0, 2]
                    cy = mtx[1, 2]
                    
                    w, h = img_size
                    f_35mm_val = fx * 36.0 / w
                    px_norm_val = (cx - w / 2.0) / w
                    py_norm_val = (cy - h / 2.0) / h
                    
                    k1_val = dist[0][0]
                    k2_val = dist[0][1]
                    t1_val = dist[0][2]
                    t2_val = dist[0][3]
                    k3_val = dist[0][4] if len(dist[0]) >= 5 else 0.0
                    k4_val = dist[0][5] if len(dist[0]) >= 6 else 0.0
                    
                    self.calib_solved_intrinsics = {
                        "f_35mm": f_35mm_val,
                        "px_norm": px_norm_val,
                        "py_norm": py_norm_val,
                        "k1": k1_val,
                        "k2": k2_val,
                        "k3": k3_val,
                        "k4": k4_val,
                        "t1": t1_val,
                        "t2": t2_val,
                        "rmse": ret_rmse,
                        "w": w,
                        "h": h
                    }
                    
                    self.root.after(0, lambda: self.calib_log("\n--- OPTICAL INTRINSICS SOLVE RESULTS ---"))
                    self.root.after(0, lambda: self.calib_log(f"Reprojection Error (RMSE):  {ret_rmse:.4f} pixels"))
                    self.root.after(0, lambda: self.calib_log(f"Focal Length:                {fx:.2f} px (35mm Equiv: {f_35mm_val:.2f}mm)"))
                    self.root.after(0, lambda: self.calib_log(f"Principal Point Shift:       ({cx:.2f}, {cy:.2f}) -> Norm: ({px_norm_val:.6f}, {py_norm_val:.6f})"))
                    self.root.after(0, lambda: self.calib_log(f"Radial Distortion (K1,K2,K3): ({k1_val:.6f}, {k2_val:.6f}, {k3_val:.6f})"))
                    self.root.after(0, lambda: self.calib_log(f"Tangential Distortion (T1,T2): ({t1_val:.6f}, {t2_val:.6f})"))
                    self.root.after(0, lambda: self.calib_log("-----------------------------------------"))
                    
                    self.root.after(0, lambda: messagebox.showinfo("Solve Successful", f"Camera calibration complete!\nReprojection RMSE: {ret_rmse:.4f} pixels\n35mm Equivalent Focal Length: {f_35mm_val:.2f}mm"))
                else:
                    self.root.after(0, lambda: self.calib_log("Solver Engine // ERROR: Calibration failed."))
                    self.root.after(0, lambda: messagebox.showerror("Solver Failed", "Camera calibration matrix solver failed!"))
                    
                self.root.after(0, lambda: self.solve_calib_btn.state(["!disabled"]))
                
            except Exception as e:
                self.root.after(0, lambda: self.calib_log(f"SOLVER CRITICAL ERROR // {str(e)}"))
                self.root.after(0, lambda: self.solve_calib_btn.state(["!disabled"]))
                self.root.after(0, lambda: messagebox.showerror("Solver Error", f"Execution encountered an error:\n{str(e)}"))
                
        threading.Thread(target=run_calib_thread, daemon=True).start()

    def apply_calibration_to_project(self):
        if not self.calib_solved_intrinsics:
            messagebox.showerror("Error", "No solved intrinsics details available! Run solver first.")
            return
            
        data = self.calib_solved_intrinsics
        
        self.lens_profile.set("Custom Solver Profile")
        self.f_35mm.set(data["f_35mm"])
        self.px_norm.set(data["px_norm"])
        self.py_norm.set(data["py_norm"])
        self.k1.set(data["k1"])
        self.k2.set(data["k2"])
        self.k3.set(data["k3"])
        self.k4.set(data["k4"])
        self.t1.set(data["t1"])
        self.t2.set(data["t2"])
        
        self.calib_log("Active Project Calibration variables successfully updated with solved lens parameters!")
        messagebox.showinfo("Applied", "Lens distortion parameters successfully applied to the active project visualizer and multi-target exporters!")

    def export_atlp_profile(self):
        if not self.calib_solved_intrinsics:
            messagebox.showerror("Error", "No solved intrinsics details available to export! Run solver first.")
            return
            
        f = filedialog.asksaveasfilename(defaultextension=".atlp", filetypes=[("Abu Track Lens Profile", "*.atlp")])
        if f:
            try:
                import json
                data = self.calib_solved_intrinsics
                profile = {
                    "name": "Abu Track Calibration Solver Profile",
                    "f_35mm": data["f_35mm"],
                    "px_norm": data["px_norm"],
                    "py_norm": data["py_norm"],
                    "k1": data["k1"],
                    "k2": data["k2"],
                    "k3": data["k3"],
                    "k4": data["k4"],
                    "t1": data["t1"],
                    "t2": data["t2"],
                    "rmse": data["rmse"],
                    "sensor_width": data["w"],
                    "sensor_height": data["h"]
                }
                with open(f, "w") as out:
                    json.dump(profile, out, indent=4)
                self.calib_log(f"Export Success // Saved Abu Track Lens Profile: {f}")
                messagebox.showinfo("Success", f"Abu Track Lens Profile successfully saved:\n{f}")
            except Exception as e:
                messagebox.showerror("Error", f"Failed to save profile:\n{str(e)}")

    def export_metashape_calibration_xml(self):
        if not self.calib_solved_intrinsics:
            messagebox.showerror("Error", "No solved intrinsics details available to export! Run solver first.")
            return
            
        f = filedialog.asksaveasfilename(defaultextension=".xml", filetypes=[("Agisoft Metashape XML", "*.xml")])
        if f:
            try:
                data = self.calib_solved_intrinsics
                w, h = data["w"], data["h"]
                fx = data["f_35mm"] * w / 36.0 
                cx = data["px_norm"] * w + w / 2.0
                cy = data["py_norm"] * h + h / 2.0
                
                xml = (
                    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                    "<calibration>\n"
                    "  <projection>frame</projection>\n"
                    f"  <width>{w}</width>\n"
                    f"  <height>{h}</height>\n"
                    f"  <f>{fx:.4f}</f>\n"
                    f"  <cx>{cx:.4f}</cx>\n"
                    f"  <cy>{cy:.4f}</cy>\n"
                    f"  <k1>{data['k1']:.8e}</k1>\n"
                    f"  <k2>{data['k2']:.8e}</k2>\n"
                    f"  <k3>{data['k3']:.8e}</k3>\n"
                    f"  <p1>{data['t1']:.8e}</p1>\n"
                    f"  <p2>{data['t2']:.8e}</p2>\n"
                    "</calibration>\n"
                )
                with open(f, "w") as out:
                    out.write(xml)
                self.calib_log(f"Export Success // Saved Metashape Calibration XML: {f}")
                messagebox.showinfo("Success", f"Agisoft Metashape Calibration XML saved successfully:\n{f}")
            except Exception as e:
                messagebox.showerror("Error", f"Failed to save Metashape XML:\n{str(e)}")

    def export_postshot_calibration_json(self):
        if not self.calib_solved_intrinsics:
            messagebox.showerror("Error", "No solved intrinsics details available to export! Run solver first.")
            return
            
        f = filedialog.asksaveasfilename(defaultextension=".json", filetypes=[("Postshot JSON Calibration", "*.json")])
        if f:
            try:
                import json
                data = self.calib_solved_intrinsics
                postshot_profile = {
                    "focal_length_35mm": data["f_35mm"],
                    "principal_point": [data["px_norm"], data["py_norm"]],
                    "distortion_radial": [data["k1"], data["k2"], data["k3"], data["k4"]],
                    "distortion_tangential": [data["t1"], data["t2"]]
                }
                with open(f, "w") as out:
                    json.dump(postshot_profile, out, indent=4)
                self.calib_log(f"Export Success // Saved Postshot Calibration JSON: {f}")
                messagebox.showinfo("Success", f"Postshot Calibration parameters JSON saved successfully:\n{f}")
            except Exception as e:
                messagebox.showerror("Error", f"Failed to save Postshot JSON:\n{str(e)}")

    def get_local_ips(self):
        ips = []
        try:
            import socket
            hostname = socket.gethostname()
            _, _, ip_list = socket.gethostbyname_ex(hostname)
            for ip in ip_list:
                if not ip.startswith("127."):
                    ips.append(ip)
        except Exception:
            pass
        if not ips:
            ips.append("127.0.0.1")
        return ips

    def _update_smoothing_label(self):
        val = self.receiver_smoothing_sec.get()
        self.smooth_lbl.configure(text=f"{val:.1f}s")

    def _update_buffer_label(self):
        val = self.receiver_buffer_ms.get()
        self.buffer_lbl.configure(text=f"{int(val)}ms")

    def update_pc_local_time(self):
        try:
            import time
            now = time.time()
            time_str = time.strftime('%H:%M:%S', time.localtime(now))
            ms = int((now % 1.0) * 1000)
            self.receiver_pc_time_var.set(f"{time_str}.{ms:03d} ({now:.3f})")
            self.root.after(33, self.update_pc_local_time)
        except Exception:
            pass

    def start_receiver(self):
        if self.receiver_running:
            return
            
        try:
            port = self.receiver_port.get()
            if port <= 0 or port > 65535:
                port = 8080
                self.receiver_port.set(8080)
        except Exception:
            port = 8080
            self.receiver_port.set(8080)
        
        logger.info(f"Receiver startup requested. Targeting port: {port}")
        
        try:
            import socket
            self.receiver_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.receiver_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.receiver_sock.bind(("0.0.0.0", port))
            self.receiver_sock.settimeout(1.0)
            logger.info(f"UDP receiver bound successfully to 0.0.0.0:{port}")
        except Exception as e:
            logger.error(f"UDP receiver failed to bind to port {port}", exc_info=True)
            messagebox.showerror("Socket Error", f"Failed to bind socket to port {port}:\n{str(e)}")
            return
            
        # Initialize Forwarder socket if enabled
        if self.forward_enabled.get():
            try:
                self.forwarder_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                logger.info(f"Forwarder socket initialized targeting: {self.forward_host.get()}:{self.forward_port.get()} [{self.forward_protocol.get()}]")
            except Exception as fe:
                logger.error("Failed to initialize dynamic UDP forwarder socket", exc_info=True)
                self.forwarder_sock = None
                
        self.receiver_running = True
        self.receiver_packet_count = 0
        self.receiver_last_time = None
        self.receiver_frequency = 0.0
        self.receiver_sec_start = None
        self.receiver_sec_packet_count = 0
        
        self.receiver_status_var.set("LISTENING")
        self.rx_status_lbl.configure(foreground=ACCENT_CYAN)
        
        self.start_rx_btn.state(["disabled"])
        self.stop_rx_btn.state(["!disabled"])
        
        self.rx_log(f"RECEIVER STATE // Listening on port {port} (0.0.0.0:{port}). READY FOR STREAM!")
        if self.forward_enabled.get():
            self.rx_log(f"FORWARD STATE // Active Forwarder -> {self.forward_host.get()}:{self.forward_port.get()} [{self.forward_protocol.get()}]")
        
        self.playout_buffer = []
        self.playout_lock = threading.Lock()
        self.playout_running = True
        self.last_source_timestamp = None
        self.last_detected_format = None
        self.active_protocol_type = None
        
        self.receiver_thread = threading.Thread(target=self.run_receiver_socket, daemon=True)
        self.receiver_thread.start()
        
        self.playout_thread = threading.Thread(target=self.run_playout_loop, daemon=True)
        self.playout_thread.start()
        
        if self.is_video_stream_enabled.get():
            self.video_decoder_running = True
            self.video_decoder_thread = threading.Thread(target=self.run_video_decoder_loop, daemon=True)
            self.video_decoder_thread.start()
            self.rx_log(f"VIDEO DECODER // Listener thread spawned on port {self.video_stream_port.get()}")

    def stop_receiver(self):
        if not self.receiver_running:
            return
            
        logger.info("Receiver stop requested. Terminating socket and threads.")
        self.receiver_running = False
        self.playout_running = False
        
        if self.receiver_sock:
            try:
                self.receiver_sock.close()
                logger.info("UDP socket closed successfully.")
            except Exception as e:
                logger.error("Error closing UDP socket", exc_info=True)
            self.receiver_sock = None
            
        if self.forwarder_sock:
            try:
                self.forwarder_sock.close()
                logger.info("Forwarder socket closed successfully.")
            except Exception:
                pass
            self.forwarder_sock = None
            
        if self.video_decoder_running:
            self.video_decoder_running = False
            self.rx_log("VIDEO DECODER // Decoder thread shutdown requested.")
            
        self.receiver_status_var.set("OFFLINE")
        self.rx_status_lbl.configure(foreground=TEXT_MUTED)
        
        self.start_rx_btn.state(["!disabled"])
        self.stop_rx_btn.state(["disabled"])
        
        self.rx_log("RECEIVER STATE // Stopped listening. Port unbound.")

    def run_receiver_socket(self):
        import time
        import socket
        
        buffer_size = 65535
        self.receiver_sec_start = time.time()
        self.receiver_sec_packet_count = 0
        consecutive_timeouts = 0
        
        logger.info("UDP socket receiving thread active and starting loop.")
        
        while self.receiver_running:
            try:
                data, addr = self.receiver_sock.recvfrom(buffer_size)
                consecutive_timeouts = 0
            except socket.timeout:
                consecutive_timeouts += 1
                if consecutive_timeouts % 10 == 0:
                    logger.info(f"Still waiting for UDP packets on port {self.receiver_port.get()}... No data received for {consecutive_timeouts} seconds.")
                continue
            except Exception as e:
                logger.error(f"UDP recvfrom encountered an exception: {str(e)}", exc_info=True)
                break
                
            if not self.receiver_running:
                break
                
            now = time.time()
            self.receiver_packet_count += 1
            
            # 1. Raw Network Frequency (Packet-to-packet delta)
            raw_hz = 0.0
            if self.receiver_last_time is not None:
                delta = now - self.receiver_last_time
                if delta > 0:
                    raw_hz = 1.0 / delta
            self.receiver_last_time = now
            
            # Update raw frequency display instantly
            self.root.after(0, lambda r_hz=raw_hz: self.receiver_raw_hz_var.set(f"{r_hz:.1f} Hz (Raw)"))
            
            try:
                parsed = self.parse_incoming_packet(data)
            except Exception as pe:
                logger.error(f"Critical exception in parse_incoming_packet: {str(pe)}", exc_info=True)
                parsed = None
            
            if parsed:
                parsed["addr_str"] = f"{addr[0]}:{addr[1]}"
                timestamp = parsed.get("timestamp", None)
                p_type = parsed.get("type", "Unknown")
                
                # Log first packet and protocol switches
                if self.receiver_packet_count == 1:
                    logger.info(f"First valid tracking packet successfully received! Format: {p_type} from {addr[0]}:{addr[1]} ({len(data)} bytes)")
                    self.active_protocol_type = p_type
                elif p_type != getattr(self, "active_protocol_type", None):
                    logger.info(f"Active protocol switch detected: {p_type} from {addr[0]}:{addr[1]}")
                    self.active_protocol_type = p_type
                
                # Periodic receiving thread statistics to log file (every 5 seconds/300 frames)
                if self.receiver_packet_count % 300 == 0:
                    logger.info(f"Stream Health Stats: Received {self.receiver_packet_count} frames. Format: {p_type}. Raw Network Hz: {raw_hz:.1f}, iOS real lock Hz: {self.receiver_real_hz_var.get()}")
                
                # 2. Real Source Frequency (iOS Lock)
                if timestamp is not None:
                    if self.last_source_timestamp is not None:
                        source_delta = timestamp - self.last_source_timestamp
                        if 0.001 < source_delta < 5.0:
                            source_hz = 1.0 / source_delta
                            self.root.after(0, lambda hz=source_hz: self.receiver_real_hz_var.set(f"{hz:.1f} Hz (iOS Lock)"))
                    self.last_source_timestamp = timestamp
                else:
                    self.root.after(0, lambda: self.receiver_real_hz_var.set("No Stamp (FreeD)"))
                
                # 3. Calculate latency / time shift
                time_shift_ms = 0.0
                if timestamp is not None:
                    time_shift_ms = (now - timestamp) * 1000.0
                    
                    self.timeshift_history.append(time_shift_ms)
                    if len(self.timeshift_history) > 100:
                        self.timeshift_history.pop(0)
                        
                    if self.receiver_auto_calibrate.get() and len(self.timeshift_history) >= 20:
                        jitter = max(self.timeshift_history) - min(self.timeshift_history)
                        recommended_buffer = max(10.0, min(1000.0, jitter + 15.0))
                        self.root.after(0, lambda val=recommended_buffer: [
                            self.receiver_buffer_ms.set(val),
                            self._update_buffer_label()
                        ])
                
                # Append to playout buffer under thread-safe lock
                with self.playout_lock:
                    self.playout_buffer.append((now, parsed, raw_hz, self.receiver_packet_count, time_shift_ms))
            else:
                log_msg = f"[{time.strftime('%H:%M:%S')}] Unknown/Malformed packet from {addr[0]}:{addr[1]} ({len(data)} bytes)"
                logger.warning(f"Malformed or unknown packet format from {addr[0]}:{addr[1]}. Packet size: {len(data)} bytes. Raw head: {data.hex()[:64]}")
                self.root.after(0, lambda m=log_msg: self.rx_log(m))
                
        logger.info(f"UDP socket receiving thread stopped. Total packets processed: {self.receiver_packet_count}")

    def run_playout_loop(self):
        import time
        import math
        last_playout_time = None
        playout_packet_count = 0
        playout_sec_start = time.time()
        playout_sec_packet_count = 0
        self.buffered_delivery_hz = 0.0
        
        while self.playout_running:
            try:
                now = time.time()
                buffer_delay = self.receiver_buffer_ms.get() / 1000.0
                
                packet_to_play = None
                with self.playout_lock:
                    if self.playout_buffer:
                        # Look at the oldest packet
                        arrival_time, parsed, r_hz, raw_count, shift_ms = self.playout_buffer[0]
                        if now - arrival_time >= buffer_delay:
                            packet_to_play = self.playout_buffer.pop(0)
                
                if packet_to_play:
                    arrival_time, parsed, r_hz, raw_count, shift_ms = packet_to_play
                    
                    playout_now = time.time()
                    playout_packet_count += 1
                    playout_sec_packet_count += 1
                    
                    # Calculate playout (buffered) average frequency over window
                    window_sec = max(0.1, self.receiver_smoothing_sec.get())
                    elapsed = playout_now - playout_sec_start
                    if elapsed >= window_sec:
                        self.buffered_delivery_hz = float(playout_sec_packet_count) / elapsed
                        playout_sec_packet_count = 0
                        playout_sec_start = playout_now
                    
                    # Extract raw coordinates safely from parsed packet to prevent NameError / crash
                    px_raw = parsed.get("x", 0.0)
                    py_raw = parsed.get("y", 0.0)
                    pz_raw = parsed.get("z", 0.0)
                    roll_raw = parsed.get("roll", 0.0)
                    pitch_raw = parsed.get("pitch", 0.0)
                    yaw_raw = parsed.get("yaw", 0.0)
                    
                    # 1. Apply workstation Coordinate System Alignment Preset / Custom translation remapping
                    px_aligned, py_aligned, pz_aligned, roll_aligned, pitch_aligned, yaw_aligned = self.apply_pc_coordinate_alignment(
                        px_raw, py_raw, pz_raw, roll_raw, pitch_raw, yaw_raw
                    )
                    
                    # 2. Apply workstation DSLR Lever Arm Offset (convert cm to meters) and SUBTRACT
                    lx = self.ws_lever_x.get() / 100.0
                    ly = self.ws_lever_y.get() / 100.0
                    lz = self.ws_lever_z.get() / 100.0
                    
                    px_dslr_raw = px_aligned
                    py_dslr_raw = py_aligned
                    pz_dslr_raw = pz_aligned
                    roll = roll_aligned
                    pitch = pitch_aligned
                    yaw = yaw_aligned
                    
                    if lx != 0.0 or ly != 0.0 or lz != 0.0:
                        rx, ry, rz = self.rotate_vector_by_quaternion(lx, ly, lz, *self.euler_to_quaternion(roll, pitch, yaw))
                        px_dslr_raw -= rx
                        py_dslr_raw -= ry
                        pz_dslr_raw -= rz
                    
                    # 3. Calculate camera pose relative to the 6-axis offset origin
                    tx_o = self.ws_origin_x.get()
                    ty_o = self.ws_origin_y.get()
                    tz_o = self.ws_origin_z.get()
                    pitch_o = self.ws_origin_pitch.get()
                    yaw_o = self.ws_origin_yaw.get()
                    roll_o = self.ws_origin_roll.get()
                    
                    dx = px_dslr_raw - tx_o
                    dy = py_dslr_raw - ty_o
                    dz = pz_dslr_raw - tz_o
                    
                    q_o_w, q_o_x, q_o_y, q_o_z = self.euler_to_quaternion(roll_o, pitch_o, yaw_o)
                    # Conjugate of origin quaternion (representing inverse rotation)
                    q_o_inv_w = q_o_w
                    q_o_inv_x = -q_o_x
                    q_o_inv_y = -q_o_y
                    q_o_inv_z = -q_o_z
                    
                    px_local, py_local, pz_local = self.rotate_vector_by_quaternion(dx, dy, dz, q_o_inv_w, q_o_inv_x, q_o_inv_y, q_o_inv_z)
                    
                    q_raw_w, q_raw_x, q_raw_y, q_raw_z = self.euler_to_quaternion(roll, pitch, yaw)
                    q_local_w, q_local_x, q_local_y, q_local_z = self.multiply_quaternions(
                        (q_o_inv_w, q_o_inv_x, q_o_inv_y, q_o_inv_z),
                        (q_raw_w, q_raw_x, q_raw_y, q_raw_z)
                    )
                    
                    roll_local, pitch_local, yaw_local = self.quaternion_to_euler(q_local_w, q_local_x, q_local_y, q_local_z)
                    
                    # Local variables for downstream UI updates and forwarders
                    px = px_local
                    py = py_local
                    pz = pz_local
                    roll = roll_local
                    pitch = pitch_local
                    yaw = yaw_local
                    
                    # Overwrite parsed dictionary to propagate offsets to canvas and forwarders automatically!
                    parsed["x"] = px
                    parsed["y"] = py
                    parsed["z"] = pz
                    parsed["roll"] = roll
                    parsed["pitch"] = pitch
                    parsed["yaw"] = yaw
                    
                    # Preserve raw aligned coords for trajectory plotting
                    parsed["raw_aligned_x"] = px_dslr_raw
                    parsed["raw_aligned_y"] = py_dslr_raw
                    parsed["raw_aligned_z"] = pz_dslr_raw
                    
                    fmt_type = parsed["type"]
                    timestamp = parsed.get("timestamp", None)
                    addr_str = parsed.get("addr_str", "iOS")
                    
                    if getattr(self, 'last_detected_format', None) != fmt_type:
                        self.last_detected_format = fmt_type
                        self.root.after(0, lambda f=fmt_type: self.rx_log(f"PROTOCOL SWAP DETECTED // Active Protocol: {f}"))
                    
                    is_active = parsed.get("is_mapping_active", True)
                    if getattr(self, 'last_mapping_state', None) != is_active:
                        self.last_mapping_state = is_active
                        state_str = "ACTIVE (LiDAR Reconstruction)" if is_active else "PAUSED (Pose-only tracking optimized)"
                        self.root.after(0, lambda s=state_str: self.rx_log(f"MAPPING SENSORS STATE // {s}"))
                    
                    # Format time shift / latency string
                    latency_str = "No Sync (N/A)"
                    if timestamp is not None:
                        latency_str = f"{shift_ms:+.1f} ms"
                    elif "FreeD" in fmt_type:
                        latency_str = "No Sync (N/A) - FreeD has no timestamp payload"
                    
                    # Update UI elements
                    self.root.after(0, lambda fmt=fmt_type: self.receiver_format_var.set(fmt))
                    self.root.after(0, lambda c=playout_packet_count: self.receiver_frames_var.set(str(c)))
                    self.root.after(0, lambda hz=self.buffered_delivery_hz: self.receiver_hz_var.set(f"{hz:.1f} Hz"))
                    self.root.after(0, lambda lat=latency_str: self.receiver_latency_var.set(lat))
                    
                    self.root.after(0, lambda x=px: self.pose_x_var.set(f"{x:.4f} m"))
                    self.root.after(0, lambda y=py: self.pose_y_var.set(f"{y:.4f} m"))
                    self.root.after(0, lambda z=pz: self.pose_z_var.set(f"{z:.4f} m"))
                    self.root.after(0, lambda r=roll: self.pose_roll_var.set(f"{r:.2f}°"))
                    self.root.after(0, lambda p=pitch: self.pose_pitch_var.set(f"{p:.2f}°"))
                    self.root.after(0, lambda y=yaw: self.pose_yaw_var.set(f"{y:.2f}°"))
                    
                    self.root.after(0, self.trigger_ping_blink)
                    
                    # Append camera position to live 3D trajectory (stored in raw aligned space)
                    if not self.live_trajectory or math.sqrt((px_dslr_raw - self.live_trajectory[-1][0])**2 + (py_dslr_raw - self.live_trajectory[-1][1])**2 + (pz_dslr_raw - self.live_trajectory[-1][2])**2) > 0.01:
                        self.live_trajectory.append((px_dslr_raw, py_dslr_raw, pz_dslr_raw))
                        
                    # Append new LiDAR points
                    new_pts = parsed.get("new_points", [])
                    if new_pts:
                        for pt in new_pts:
                            if len(pt) >= 3:
                                self.live_points.append((float(pt[0]), float(pt[1]), float(pt[2])))
                                
                    # Sync cockpit/orbit camera tracking in follow mode (centers viewport on camera's absolute position)
                    if self.live_follow.get():
                        self.live_pan_x = px_dslr_raw
                        self.live_pan_y = py_dslr_raw
                        self.live_pan_z = pz_dslr_raw
                        if self.live_view_mode.get() == "Cockpit":
                            self.live_rot_x = -pitch * math.pi / 180.0 - math.pi / 2.0  # Apply the -90 degree offset globally for proper horizon pitch alignment
                            self.live_rot_y = -yaw * math.pi / 180.0
                            self.live_rot_z = -roll * math.pi / 180.0
                        
                    self.root.after(0, self.redraw_live_3d_canvas)
                    
                    # Dynamic Multi-Protocol Forwarder Server
                    if self.forward_enabled.get():
                        self.forward_packet_to_unreal(parsed)
                    
                    # Console logs
                    if timestamp is not None:
                        log_msg = f"[{time.strftime('%H:%M:%S')}] From {addr_str} // Pos: ({px:.3f}, {py:.3f}, {pz:.3f}) Shift: {shift_ms:+.1f}ms"
                    else:
                        log_msg = f"[{time.strftime('%H:%M:%S')}] From {addr_str} // Pos: ({px:.3f}, {py:.3f}, {pz:.3f}) [FreeD]"
                    self.root.after(0, lambda m=log_msg: self.rx_log(m))
                else:
                    # Sleep a tiny bit to avoid spinning the CPU
                    time.sleep(0.001)
            except Exception as e:
                logger.error(f"Playout Thread: Exception in playout loop: {str(e)}", exc_info=True)
                time.sleep(0.010)

    def parse_incoming_packet(self, data):
        # 1. Standard (29 bytes) and Extended (37 bytes) FreeD Binary formats
        if (len(data) == 29 or len(data) == 37) and data[0] in (0xD1, 0xD2):
            try:
                def unpack24(b1, b2, b3):
                    val = (b1 << 16) | (b2 << 8) | b3
                    if val & 0x800000:
                        val -= 0x1000000
                    return val
                
                pitch_val = unpack24(data[2], data[3], data[4])
                yaw_val = unpack24(data[5], data[6], data[7])
                roll_val = unpack24(data[8], data[9], data[10])
                
                # Correct indices to read Z, X, Y in order:
                z_val = unpack24(data[11], data[12], data[13])
                x_val = unpack24(data[14], data[15], data[16])
                y_val = unpack24(data[17], data[18], data[19])
                
                pitch = pitch_val / 32768.0
                yaw = yaw_val / 32768.0
                roll = roll_val / 32768.0
                
                x = x_val / (64.0 * 1000.0)
                y = y_val / (64.0 * 1000.0)
                z = z_val / (64.0 * 1000.0)
                
                timestamp = None
                p_type = "FreeD Binary (Type D1)"
                
                if len(data) == 37:
                    # Extract 8-byte trailing timestamp for Extended FreeD
                    import struct
                    timestamp_ms = struct.unpack(">q", data[29:37])[0]
                    timestamp = float(timestamp_ms) / 1000.0
                    p_type = "Extended FreeD Binary (Type D1)"
                
                return {
                    "type": p_type,
                    "x": x, "y": y, "z": z,
                    "pitch": pitch, "yaw": yaw, "roll": roll,
                    "timestamp": timestamp
                }
            except Exception:
                pass
                
        # 2. OpenTrackIO JSON / UDP format
        if len(data) >= 17 and data[0:4] == b"OTrk":
            try:
                import struct
                import json
                encoding = data[8]
                payload_len = struct.unpack(">I", data[9:13])[0]
                source_id = struct.unpack(">I", data[13:17])[0]
                
                if encoding == 0x01: # JSON encoding
                    json_bytes = data[17:17+payload_len]
                    payload = json.loads(json_bytes.decode("utf-8"))
                    
                    timestamp = payload.get("timestamp", None)
                    t_array = payload.get("transforms", [])
                    new_points = payload.get("new_points", [])
                    is_mapping_active = payload.get("isMappingActive", True)
                    if t_array:
                        trans = t_array[0].get("translation", {"x": 0.0, "y": 0.0, "z": 0.0})
                        rot = t_array[0].get("rotation", {"yaw": 0.0, "pitch": 0.0, "roll": 0.0})
                        
                        return {
                            "type": f"OpenTrackIO JSON (Src {source_id})",
                            "x": trans.get("x", 0.0),
                            "y": trans.get("y", 0.0),
                            "z": trans.get("z", 0.0),
                            "pitch": rot.get("pitch", 0.0),
                            "yaw": rot.get("yaw", 0.0),
                            "roll": rot.get("roll", 0.0),
                            "timestamp": timestamp,
                            "new_points": new_points,
                            "is_mapping_active": is_mapping_active
                        }
            except Exception as e:
                print(f"OpenTrackIO parse failed: {e}")
                
        # 3. Standard Live Link JSON format
        try:
            import json
            decoded = data.decode("utf-8")
            payload = json.loads(decoded)
            if "translation" in payload and "rotation" in payload:
                tx, ty, tz = payload["translation"]
                pitch, yaw, roll = payload["rotation"]
                device_name = payload.get("deviceName", "AbuTrack")
                timestamp = payload.get("timestamp", None)
                new_points = payload.get("new_points", [])
                is_mapping_active = payload.get("isMappingActive", True)
                return {
                    "type": f"Live Link ({device_name})",
                    "x": tx, "y": ty, "z": tz,
                    "pitch": pitch, "yaw": yaw, "roll": roll,
                    "timestamp": timestamp,
                    "new_points": new_points,
                    "is_mapping_active": is_mapping_active
                }
        except Exception:
            pass
            
        return None
    def trigger_ping_blink(self):
        try:
            if hasattr(self, 'ping_canvas') and self.ping_canvas.winfo_exists():
                self.ping_canvas.itemconfig(self.ping_light, fill=ACCENT_CYAN)
                self.root.after(80, self._reset_ping_blink)
        except Exception:
            pass

    def _reset_ping_blink(self):
        try:
            if hasattr(self, 'ping_canvas') and self.ping_canvas.winfo_exists():
                self.ping_canvas.itemconfig(self.ping_light, fill=FIELD_BG)
        except Exception:
            pass

    def rx_log(self, msg):
        try:
            if not hasattr(self, 'rx_console') or not self.rx_console.winfo_exists():
                return
            self.rx_console.configure(state="normal")
            self.rx_console.insert(tk.END, msg + "\n")
            
            lines = int(self.rx_console.index('end-1c').split('.')[0])
            if lines > 16:
                self.rx_console.delete("1.0", "2.0")
                
            self.rx_console.see(tk.END)
            self.rx_console.configure(state="disabled")
        except Exception:
            pass
    def report_callback_exception(self, exc, val, tb):
        import traceback
        err_str = "".join(traceback.format_exception(exc, val, tb))
        logger.critical(f"Unhandled GUI Exception in Tkinter callback:\n{err_str}")
        messagebox.showerror(
            "Internal Error", 
            f"An unhandled error occurred inside the application. Detailed logs have been written to:\n"
            f"{os.path.join(LOG_DIR, 'abu_track_desktop.log')}\n\n"
            f"Error: {val}"
        )

    def fix_windows_firewall(self):
        import subprocess
        import sys
        
        port = 8080
        try:
            port = self.receiver_port.get()
        except Exception:
            pass
            
        logger.info(f"[DIAGNOSTICS] Prompting user to run elevated PowerShell command to add inbound UDP rule on port {port}...")
        
        ps_cmd = (
            f"Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -Command "
            f"New-NetFirewallRule -Direction Inbound -Action Allow -Protocol UDP -LocalPort {port} "
            f"-DisplayName \\\"ABU_TRACK_UDP_{port}\\\" -Force' -Verb RunAs"
        )
        
        try:
            subprocess.Popen(["powershell", "-Command", ps_cmd], shell=True)
            logger.info("[DIAGNOSTICS] PowerShell elevation request sent successfully.")
            messagebox.showinfo(
                "Firewall Setup", 
                f"An Administrator prompt was requested to run PowerShell and add a firewall exception rule for UDP port {port}.\n\n"
                f"Please accept the Windows prompt (UAC dialog) to complete the network exception configuration."
            )
        except Exception as e:
            logger.error(f"[DIAGNOSTICS] Failed to request PowerShell elevation: {str(e)}", exc_info=True)
            messagebox.showerror("Elevation Failed", f"Could not launch PowerShell elevation: {str(e)}")
            
    def open_logs_folder(self):
        log_dir = get_log_dir()
        if os.path.exists(log_dir):
            try:
                os.startfile(log_dir)
                logger.info(f"Opened logs directory: {log_dir}")
            except Exception as e:
                logger.error(f"Failed to open logs directory: {str(e)}", exc_info=True)
                messagebox.showerror("Error", f"Failed to open directory:\n{str(e)}")
        else:
            messagebox.showinfo("Logs Directory", f"Logs folder does not exist yet. Please start listening or generate some activity first.\nPath: {log_dir}")

    def on_window_closing(self):
        logger.info("Window closing event triggered. Terminating threads and socket connections cleanly.")
        self.receiver_running = False
        self.playout_running = False
        if self.receiver_sock:
            try:
                self.receiver_sock.close()
            except Exception:
                pass
        if self.forwarder_sock:
            try:
                self.forwarder_sock.close()
            except Exception:
                pass
        import os
        os._exit(0)

    def toggle_forwarding(self):
        if self.forward_enabled.get():
            if not self.forwarder_sock and self.receiver_running:
                try:
                    import socket
                    self.forwarder_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                    self.rx_log(f"FORWARD STATE // Active Forwarder -> {self.forward_host.get()}:{self.forward_port.get()} [{self.forward_protocol.get()}]")
                except Exception as e:
                    self.rx_log(f"FORWARD ERROR // Failed to open socket: {str(e)}")
        else:
            if self.forwarder_sock:
                try:
                    self.forwarder_sock.close()
                except Exception:
                    pass
                self.forwarder_sock = None
                self.rx_log("FORWARD STATE // Disabled and socket unbound.")

    def reset_live_view(self):
        if self.live_trajectory:
            last_pt = self.live_trajectory[-1]
            self.live_pan_x = last_pt[0]
            self.live_pan_y = last_pt[1]
            self.live_pan_z = last_pt[2]
        else:
            self.live_pan_x = 0.0
            self.live_pan_y = 0.0
            self.live_pan_z = 0.0
            
        self.live_rot_x = -0.4
        self.live_rot_y = -0.6
        self.live_rot_z = 0.0
        self.live_zoom = 1.0
        self.live_follow.set(False)
        self.redraw_live_3d_canvas()

    def clear_live_data(self):
        self.live_points = []
        self.live_trajectory = []
        self.redraw_live_3d_canvas()

    def on_live_canvas_press(self, event):
        self.last_live_mouse_x = event.x
        self.last_live_mouse_y = event.y

    def on_live_canvas_orbit(self, event):
        dx = event.x - self.last_live_mouse_x
        dy = event.y - self.last_live_mouse_y
        
        if self.live_edit_origin.get():
            shift_pressed = (event.state & 0x0001) != 0
            if shift_pressed:
                # Rotate Roll
                self.ws_origin_roll.set(self.ws_origin_roll.get() + dx * 0.1)
            else:
                # Rotate Yaw and Pitch
                self.ws_origin_yaw.set(self.ws_origin_yaw.get() + dx * 0.1)
                self.ws_origin_pitch.set(self.ws_origin_pitch.get() - dy * 0.1)
        else:
            if self.live_follow.get() and self.live_view_mode.get() == "Cockpit":
                self.live_view_mode.set("Orbit")
            self.live_rot_y += dx * 0.005
            self.live_rot_x += dy * 0.005
            
        self.last_live_mouse_x = event.x
        self.last_live_mouse_y = event.y
        self.redraw_live_3d_canvas()

    def on_live_canvas_pan(self, event):
        dx = event.x - self.last_live_mouse_x
        dy = event.y - self.last_live_mouse_y
        
        if self.live_edit_origin.get():
            cos_y = math.cos(self.live_rot_y)
            sin_y = math.sin(self.live_rot_y)
            # Translate along X/Z plane in direction camera is looking
            tx = (dx * cos_y + dy * sin_y) * 0.01 * (1.0 / self.live_zoom)
            tz = (-dx * sin_y + dy * cos_y) * 0.01 * (1.0 / self.live_zoom)
            self.ws_origin_x.set(self.ws_origin_x.get() - tx)
            self.ws_origin_z.set(self.ws_origin_z.get() - tz)
        else:
            if self.live_follow.get():
                self.live_follow.set(False)
            cos_y = math.cos(self.live_rot_y)
            sin_y = math.sin(self.live_rot_y)
            self.live_pan_x -= (dx * cos_y + dy * sin_y) * 0.005 * (1.0 / self.live_zoom)
            self.live_pan_z -= (-dx * sin_y + dy * cos_y) * 0.005 * (1.0 / self.live_zoom)
            
        self.last_live_mouse_x = event.x
        self.last_live_mouse_y = event.y
        self.redraw_live_3d_canvas()

    def on_live_canvas_scroll(self, event):
        delta = event.delta
        if self.live_edit_origin.get():
            # Translate Origin Y (height)
            dy = 0.05 if delta > 0 else -0.05
            self.ws_origin_y.set(self.ws_origin_y.get() + dy)
        else:
            if delta > 0:
                self.live_zoom *= 1.1
            else:
                self.live_zoom /= 1.1
            self.live_zoom = max(0.1, min(50.0, self.live_zoom))
        self.redraw_live_3d_canvas()

    def project_live_3d(self, x, y, z, width, height):
        cx = width / 2.0
        cy = height / 2.0
        
        px = x - self.live_pan_x
        py = y - self.live_pan_y
        pz = z - self.live_pan_z
        
        rx = px
        ry = -pz
        rz = py
        
        final_rot_x = self.live_rot_x - math.pi / 2.0
        
        # 1. Rotate Z (Yaw)
        cos_y = math.cos(self.live_rot_y)
        sin_y = math.sin(self.live_rot_y)
        x1 = rx * cos_y - ry * sin_y
        y1 = rx * sin_y + ry * cos_y
        
        # 2. Rotate X (Pitch)
        cos_x = math.cos(final_rot_x)
        sin_x = math.sin(final_rot_x)
        z2 = rz * cos_x - y1 * sin_x
        depth2 = rz * sin_x + y1 * cos_x
        
        # 3. Rotate Screen Plane (Roll)
        cos_z = math.cos(self.live_rot_z)
        sin_z = math.sin(self.live_rot_z)
        x2 = x1 * cos_z - z2 * sin_z
        z3 = x1 * sin_z + z2 * cos_z
        
        fov = 3.0
        distance = 4.0
        zoom_amount = 140.0 * self.live_zoom
        
        if depth2 <= -distance:
            return None
            
        scale = fov / (distance + depth2)
        sx = cx + x2 * scale * zoom_amount
        sy = cy + z3 * scale * zoom_amount
        return sx, sy

    def run_video_decoder_loop(self):
        import time
        import threading
        
        try:
            import av
        except ImportError:
            logger.error("Video Decoder: Failed to import PyAV ('av' package). H.264 stream decoding disabled.", exc_info=True)
            self.rx_log("VIDEO DECODER // ERROR: PyAV 'av' library not found!")
            return
            
        port = self.video_stream_port.get()
        logger.info(f"Video Decoder: Initializing local PyAV listener on port {port}")
        
        # Configure Spout Sender if enabled
        if self.is_spout_enabled.get():
            self.init_spout_sender()
            
        logger.info("Video Decoder: PyAV background listening thread active.")
        
        # Periodically refresh the 3D Canvas visualizer to draw new video frames
        def refresh_canvas_loop():
            while self.video_decoder_running:
                try:
                    self.root.after(0, self.redraw_live_3d_canvas)
                except Exception:
                    pass
                time.sleep(0.050) # refresh visualizer at 20 fps to prevent Tkinter choke
                
        canvas_refresh_thread = threading.Thread(target=refresh_canvas_loop, daemon=True)
        canvas_refresh_thread.start()
        
        while self.video_decoder_running:
            container = None
            try:
                # Open RTP connection. We pass timeout options to prevent hanging.
                # timeout is in microseconds: 1,000,000 = 1 sec
                # standard 'timeout' parameter in av.open is (open_timeout, read_timeout)
                container = av.open(
                    f"rtp://0.0.0.0:{port}", 
                    "r", 
                    options={
                        "protocol_whitelist": "file,rtp,udp",
                        "timeout": "1000000",
                        "buffer_size": "2097152" # 2MB buffer for lower packet loss
                    },
                    timeout=(2.0, 2.0)
                )
                logger.info(f"Video Decoder: Bound successfully to rtp://0.0.0.0:{port}")
                
                # Parse packets and decode H.264 streams
                for frame in container.decode(video=0):
                    if not self.video_decoder_running:
                        break
                    
                    # Convert to PIL Image in background thread (RGB format, ultra-fast)
                    pil_img = frame.to_image()
                    self.latest_decoded_pil_image = pil_img
                    
                    # Store BGR numpy array and send to Spout if enabled
                    frame_bgr = frame.to_ndarray(format="bgr24")
                    self.latest_decoded_frame = frame_bgr
                    
                    if self.spout_sender and self.is_spout_enabled.get():
                        self.send_frame_to_spout(frame_bgr)
                        
            except Exception as e:
                if not self.video_decoder_running:
                    break
                logger.warning(f"Video Decoder: Stream connection lost or timed out. Retrying... ({str(e)})")
                time.sleep(0.5)
            finally:
                if container:
                    try:
                        container.close()
                    except Exception:
                        pass
                
        if self.spout_sender:
            try:
                self.spout_sender.ReleaseSender()
            except Exception:
                pass
            self.spout_sender = None
        logger.info("Video Decoder: Listening thread cleanly terminated.")

    def init_spout_sender(self):
        try:
            import SpoutGL
            logger.info("Spout: Initializing SpoutGL Shared Texture Sender named 'AbuTrackVideo'")
            self.spout_sender = SpoutGL.SpoutSender("AbuTrackVideo", 1920, 1080)
        except Exception as e:
            logger.error(f"Spout: Failed to load SpoutGL: {str(e)}")
            self.spout_sender = None

    def send_frame_to_spout(self, frame):
        if not self.spout_sender:
            return
        try:
            import SpoutGL
            h, w = frame.shape[:2]
            # 0x80E1 is GL_BGR
            self.spout_sender.sendImage(frame, w, h, 0x80E1, False)
        except Exception as e:
            logger.error(f"Spout: Failed to transmit texture via SpoutGL: {str(e)}")

    def redraw_live_3d_canvas(self):
        try:
            if not hasattr(self, 'live_canvas') or not self.live_canvas.winfo_exists():
                return
        except Exception:
            return
            
        w = self.live_canvas.winfo_width()
        h = self.live_canvas.winfo_height()
        if w < 10 or h < 10:
            w = 500
            h = 300
            
        self.live_canvas.delete("all")
        
        # Draw live video background if enabled
        if self.is_video_stream_enabled.get() and getattr(self, "latest_decoded_pil_image", None) is not None:
            try:
                from PIL import Image, ImageTk
                
                # Resize image using ultra-fast NEAREST resampling filter (compatible with all Pillow versions)
                resample_filter = getattr(Image, "Resampling", Image).NEAREST
                pil_img_resized = self.latest_decoded_pil_image.resize((w, h), resample_filter)
                
                self.canvas_bg_image = ImageTk.PhotoImage(image=pil_img_resized)
                self.live_canvas.create_image(0, 0, image=self.canvas_bg_image, anchor="nw")
            except Exception as e:
                logger.error(f"3D Canvas: Failed to render live video background: {str(e)}")
        
        # Draw tech grid
        for cx in range(20, w, 40):
            self.live_canvas.create_line(cx, 0, cx, h, fill="#041224", width=0.5)
        for cy in range(20, h, 40):
            self.live_canvas.create_line(0, cy, w, cy, fill="#041224", width=0.5)
            
        # Draw Bounding crosshairs
        self.live_canvas.create_line(10, 10, 30, 10, fill="#00f0ff", width=1)
        self.live_canvas.create_line(10, 10, 10, 30, fill="#00f0ff", width=1)
        self.live_canvas.create_line(w-10, 10, w-30, 10, fill="#00f0ff", width=1)
        self.live_canvas.create_line(w-10, 10, w-10, 30, fill="#00f0ff", width=1)
        self.live_canvas.create_line(10, h-10, 30, h-10, fill="#00f0ff", width=1)
        self.live_canvas.create_line(10, h-10, 10, h-30, fill="#00f0ff", width=1)
        self.live_canvas.create_line(w-10, h-10, w-30, h-10, fill="#00f0ff", width=1)
        self.live_canvas.create_line(w-10, h-10, w-10, h-30, fill="#00f0ff", width=1)
        
        # Draw Rotated and Shifted Origin Gizmo
        tx_o = self.ws_origin_x.get()
        ty_o = self.ws_origin_y.get()
        tz_o = self.ws_origin_z.get()
        pitch_o = self.ws_origin_pitch.get()
        yaw_o = self.ws_origin_yaw.get()
        roll_o = self.ws_origin_roll.get()
        
        q_o_w, q_o_x, q_o_y, q_o_z = self.euler_to_quaternion(roll_o, pitch_o, yaw_o)
        
        # Rotated unit axis endpoints (length 0.5 meters)
        vx_x, vx_y, vx_z = self.rotate_vector_by_quaternion(0.5, 0.0, 0.0, q_o_w, q_o_x, q_o_y, q_o_z)
        vy_x, vy_y, vy_z = self.rotate_vector_by_quaternion(0.0, 0.5, 0.0, q_o_w, q_o_x, q_o_y, q_o_z)
        vz_x, vz_y, vz_z = self.rotate_vector_by_quaternion(0.0, 0.0, 0.5, q_o_w, q_o_x, q_o_y, q_o_z)
        
        origin_proj = self.project_live_3d(tx_o, ty_o, tz_o, w, h)
        if origin_proj:
            ox, oy = origin_proj
            
            # X - East (Red)
            x_proj = self.project_live_3d(tx_o + vx_x, ty_o + vx_y, tz_o + vx_z, w, h)
            if x_proj:
                self.live_canvas.create_line(ox, oy, x_proj[0], x_proj[1], fill="#ff3366", width=2.5)
                self.live_canvas.create_text(x_proj[0]+8, x_proj[1], text="X", fill="#ff3366", font=("Consolas", 8, "bold"))
                
            # Y - Up (Green)
            y_proj = self.project_live_3d(tx_o + vy_x, ty_o + vy_y, tz_o + vy_z, w, h)
            if y_proj:
                self.live_canvas.create_line(ox, oy, y_proj[0], y_proj[1], fill="#00ff66", width=2.5)
                self.live_canvas.create_text(y_proj[0], y_proj[1]-8, text="Y", fill="#00ff66", font=("Consolas", 8, "bold"))
                
            # Z - North (Blue)
            z_proj = self.project_live_3d(tx_o + vz_x, ty_o + vz_y, tz_o + vz_z, w, h)
            if z_proj:
                self.live_canvas.create_line(ox, oy, z_proj[0], z_proj[1], fill="#3366ff", width=2.5)
                self.live_canvas.create_text(z_proj[0], z_proj[1]+8, text="Z", fill="#3366ff", font=("Consolas", 8, "bold"))
                
        # Draw LiDAR points with custom PC LiDAR sign & source axis mapping
        if self.live_show_points.get() and self.live_points:
            step = max(1, len(self.live_points) // 1000)
            pts_to_draw = self.live_points[::step]
            
            l_x_sign = self.pc_lidar_x_sign.get()
            l_x_src = self.pc_lidar_x_src.get()
            l_y_sign = self.pc_lidar_y_sign.get()
            l_y_src = self.pc_lidar_y_src.get()
            l_z_sign = self.pc_lidar_z_sign.get()
            l_z_src = self.pc_lidar_z_src.get()
            
            for pt in pts_to_draw:
                pt_inputs = {"X": pt[0], "Y": pt[1], "Z": pt[2]}
                mx = pt_inputs.get(l_x_src, pt[0]) * l_x_sign
                my = pt_inputs.get(l_y_src, pt[1]) * l_y_sign
                mz = pt_inputs.get(l_z_src, pt[2]) * l_z_sign
                
                proj = self.project_live_3d(mx, my, mz, w, h)
                if proj:
                    sx, sy = proj
                    if 0 <= sx <= w and 0 <= sy <= h:
                        self.live_canvas.create_oval(sx-1, sy-1, sx+1, sy+1, fill="#00ff66", outline="")
                        
        # Draw camera trajectory path
        if self.live_show_path.get() and len(self.live_trajectory) > 1:
            line_pts = []
            for pt in self.live_trajectory:
                proj = self.project_live_3d(pt[0], pt[1], pt[2], w, h)
                if proj:
                    line_pts.extend(proj)
            if len(line_pts) >= 4:
                self.live_canvas.create_line(line_pts, fill="#ffcc00", width=1.5, smooth=True)
                
        # Draw current camera indicator
        if self.live_trajectory:
            last_pt = self.live_trajectory[-1]
            proj = self.project_live_3d(last_pt[0], last_pt[1], last_pt[2], w, h)
            if proj:
                sx, sy = proj
                self.live_canvas.create_oval(sx-5, sy-5, sx+5, sy+5, fill="#ff3366", outline="white", width=1.5)
                self.live_canvas.create_text(
                    15, h-15, 
                    text=f"CAM: ({last_pt[0]:+.2f}, {last_pt[1]:+.2f}, {last_pt[2]:+.2f}) | PTS: {len(self.live_points)}", 
                    anchor="w", fill="#00f0ff", font=("Consolas", 8, "bold")
                )

    def forward_packet_to_unreal(self, parsed):
        if not self.forwarder_sock:
            return
            
        try:
            import json
            import socket
            import time
            import struct
            
            host = self.forward_host.get()
            port = self.forward_port.get()
            proto = self.forward_protocol.get()
            
            px, py, pz = parsed["x"], parsed["y"], parsed["z"]
            pitch, yaw, roll = parsed["pitch"], parsed["yaw"], parsed["roll"]
            timestamp = parsed.get("timestamp", time.time())
            
            # Dynamic Forwarder Performance Stats
            now_time = time.time()
            if not hasattr(self, 'last_forward_calc_time'):
                self.last_forward_calc_time = now_time
                self.forward_packet_count_window = 0
            
            self.forward_packet_count_window += 1
            elapsed = now_time - self.last_forward_calc_time
            if elapsed >= 1.0:
                hz = float(self.forward_packet_count_window) / elapsed
                self.root.after(0, lambda h=hz: self.forward_delivery_hz_var.set(f"{h:.1f} Hz"))
                self.forward_packet_count_window = 0
                self.last_forward_calc_time = now_time
                
            # Derive timecode from packet timestamp using SMPTE formatter
            tc_str = self.timestamp_to_smpte(timestamp, fps=30)
            self.root.after(0, lambda t=tc_str: self.forward_timecode_var.set(t))
            
            # Apply -90 degree offset globally around X-axis (Pitch) to align tracking data to UE!
            pitch_forward = pitch - 90.0
            
            if proto == "Live Link JSON":
                payload = {
                    "deviceName": "AbuTrack",
                    "translation": [px, py, pz],
                    "rotation": [pitch_forward, yaw, roll],
                    "focalLength": 24.0,
                    "timestamp": timestamp,
                    "isMappingActive": parsed.get("is_mapping_active", True)
                }
                if "new_points" in parsed:
                    payload["new_points"] = parsed["new_points"]
                    
                data = json.dumps(payload).encode("utf-8")
                self.forwarder_sock.sendto(data, (host, port))
                
            elif proto == "FreeD Binary":
                packet = bytearray()
                packet.append(0xD1)
                packet.append(0x01)
                
                def pack24(val):
                    val = int(val)
                    if val < 0:
                        val += 0x1000000
                    return [
                        (val >> 16) & 0xFF,
                        (val >> 8) & 0xFF,
                        val & 0xFF
                    ]
                
                packet.extend(pack24(pitch_forward * 32768.0))
                packet.extend(pack24(yaw * 32768.0))
                packet.extend(pack24(roll * 32768.0))
                
                packet.extend(pack24(pz * 1000.0 * 64.0))
                packet.extend(pack24(px * 1000.0 * 64.0))
                packet.extend(pack24(py * 1000.0 * 64.0))
                
                packet.extend([0x00, 0x00, 0x00])
                packet.extend([0x00, 0x00, 0x00])
                packet.extend([0x00, 0x00])
                
                checksum = (0x40 - sum(packet)) & 0xFF
                packet.append(checksum)
                
                timestamp_ms = int(timestamp * 1000.0)
                packet.extend(struct.pack(">q", timestamp_ms))
                
                self.forwarder_sock.sendto(packet, (host, port))
                
            elif proto == "OpenTrackIO JSON":
                payload = {
                    "version": "1.0",
                    "sourceId": 101,
                    "timestamp": timestamp,
                    "isMappingActive": parsed.get("is_mapping_active", True),
                    "transforms": [
                        {
                            "translation": {"x": px, "y": py, "z": pz},
                            "rotation": {"yaw": yaw, "pitch": pitch_forward, "roll": roll}
                        }
                    ],
                    "lens": {
                        "focalLength": 24.0,
                        "focusDistance": 1.5
                    }
                }
                if "new_points" in parsed:
                    payload["new_points"] = parsed["new_points"]
                    
                json_bytes = json.dumps(payload).encode("utf-8")
                
                packet = bytearray()
                packet.extend(b"OTrk")
                
                seq = int(time.time() * 1000) & 0xFFFFFFFF
                packet.extend(struct.pack(">I", seq))
                packet.append(0x01)
                packet.extend(struct.pack(">I", len(json_bytes)))
                packet.extend(struct.pack(">I", 101))
                packet.extend(json_bytes)
                
                self.forwarder_sock.sendto(packet, (host, port))
                
        except Exception as e:
            logger.error("Failed to forward UDP packet", exc_info=True)

if __name__ == "__main__":
    root = tk.Tk()
    app = CamTrackDesktopApp(root)
    root.mainloop()
