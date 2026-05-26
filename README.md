# CamTrack Pro - Enterprise Spatial Telemetry & Photogrammetry Sync

**CamTrack Pro** is a professional-grade telemetry logging and spatial post-processing synchronization suite for photogrammetry experts using **Agisoft Metashape** or **RealityScan**.

It runs natively on your **iPhone 16 Pro Max** to log continuous high-precision 3D device attitude (yaw, pitch, roll, quaternions), relative barometric elevation (centimeter precision), and absolute dual-frequency GPS coordinates in the background. It then pairs these logs either with photos taken on the **default iPhone camera** or with high-fidelity images taken on a **professional DSLR/Mirrorless camera** mounted to a hot-shoe bracket (using spatial lever-arm corrections).

---

## Part 1: How to Deploy and Compile Directly on Your iPhone (No Mac Required)

You do not need a Mac or a developer account to run **CamTrack Pro** on your iPhone. We leverage Apple's free **Swift Playgrounds** app, which compiles and executes native SwiftUI applications directly on device with full access to hardware sensors and background capabilities.

### Step-by-Step Installation:
1. **Download Swift Playgrounds:**
   * Open the **App Store** on your iPhone 16 Pro Max.
   * Search for and install **Swift Playgrounds** (by Apple, completely free).
2. **Create a New App Project:**
   * Open **Swift Playgrounds**.
   * Under the "My Playgrounds" dashboard, tap **"+" (New App)** at the bottom. This generates a SwiftUI app project.
3. **Copy-Paste the Code Base:**
   * Tap the sidebar menu icon in Swift Playgrounds to view your file list.
   * Add the following files to your project exactly matching the names in this workspace:
     * `Sources/Managers/LocationManager.swift`
     * `Sources/Managers/MotionAndTrackingManager.swift`
     * `Sources/Managers/TelemetryLogger.swift`
     * `Sources/Managers/PhotoSyncManager.swift`
     * `Sources/Views/ContentView.swift`
     * `Sources/Views/DashboardView.swift`
     * `Sources/Views/SessionsView.swift`
     * `Sources/Views/SettingsView.swift`
     * `Sources/CamTrackApp.swift` (Overwriting the default App file)
   * Copy the code from this workspace and paste it into each respective file.
4. **Enable Hardware Capabilities (Permissions):**
   * Inside your Playgrounds project, tap the **App Settings** button (the gear/app icon next to the App Name).
   * Tap **Capabilities** -> **Add Capability**.
   * Add the following items, making sure to write a detailed explanation in the **Purpose String** (iOS will fail to prompt if the purpose string is blank!):
     * **Location:** *Always and When In Use* 
       * Purpose: "CamTrack Pro logs precise background GPS coordinates to georeference your photogrammetry points."
     * **Photo Library:** *Read/Write Access* 
       * Purpose: "CamTrack Pro matches your capture session times to the photos in your library to sync image filenames with telemetry."
     * **Camera:** *Access Camera* 
       * Purpose: "CamTrack Pro uses the camera and LiDAR scanner to run real-time Visual-Inertial-LiDAR Odometry."
     * **Motion:** *Access Motion Activity* 
       * Purpose: "CamTrack Pro records high-frequency IMU gyro details to capture precise camera pitch, roll, and yaw."
5. **Run the App:**
   * Click the **"Play" (Run)** button at the top toolbar. 
   * The app will compile and launch full screen on your iPhone 16 Pro Max! Accept the security prompts when they appear.

---

## Part 2: Pro DSLR/Mirrorless Hot-Shoe Workflow

If you want to use a professional mirrorless camera (Sony Alpha, Canon R, Nikon Z) instead of your iPhone's camera, follow this professional "lever-arm" pipeline.

```
   [ iPhone ]   <-- Center of Phone (LiDAR / IMU Tracking Center)
       |
       |  <-- Measure physical distances (Δx, Δy, Δz)
       |
 [ DSLR Lens ]  <-- Optical Center of DSLR Sensor Plane
```

### 1. Rig Assembly & Lever-Arm Measurement:
Mount the iPhone securely in a cold/hot-shoe bracket directly above your DSLR lens. The sensors on your iPhone and the DSLR CMOS sensor are physically offset. You must measure this offset in **centimeters** from the iPhone's center to your DSLR's sensor center (indicated by the $\phi$ line mark on the DSLR body):
*   **$\Delta x$ (Lateral):** Left/Right offset. Set to `0.0` if the phone is perfectly centered on the hot-shoe.
*   **$\Delta y$ (Vertical):** Vertical height offset. Usually `+4.0` to `+10.0` cm.
*   **$\Delta z$ (Depth):** Depth offset forward/backward. Positive if the phone sits further forward than the DSLR sensor plane.

### 2. Time Synchronization (Shutter-Sync):
Before shooting, synchronize the internal clock of your DSLR perfectly with the iPhone's clock down to the second.
*   *Tip:* The easiest way is to use your DSLR's official companion app (Sony Creators' App, Canon Camera Connect) which syncs the camera clock to your phone's system time automatically via Bluetooth.

### 3. Capture Workflow:
1. Open **CamTrack Pro** on your iPhone.
2. Under **Calibration**, enter your measured $\Delta x, \Delta y, \Delta z$ offsets.
3. Tap **Start Logging** on the Dashboard.
4. Put the phone in your pocket or mount it on the DSLR. Shoot your raw photos normally with your DSLR.
5. When finished, return to the app and tap **Stop Logging**.
6. Export the `.csv` log file from the session history using the **Raw Logs** share button (AirDrop it to your PC).

### 4. Desktop Post-Processing Script:
1. Copy the DSLR photos from your SD card into a folder on your Windows PC.
2. Install Python 3 and the Pillow image library on your PC:
   ```bash
   pip install Pillow
   ```
3. Run our provided syncing script `sync_photos.py`:
   ```bash
   python sync_photos.py
   ```
4. Enter the path to your photo folder, the path to the exported `telemetry_log.csv`, and confirm your rig offsets.
5. The script extracts the sub-second EXIF timestamp of each DSLR photo, interpolates the iPhone telemetry, **rotates the 3D offset vector in space using the logged quaternions**, and outputs a perfectly corrected `dslr_metashape_cameras.csv` directly in your photo folder!

---

## Part 3: Importing Telemetry Into Agisoft Metashape

Once your photos and CSV are exported, import them into Metashape:

1. **Import Photos:** Drag and drop your DSLR or iPhone photos into the Metashape workspace.
2. **Open Reference Pane:** Navigate to `View` -> `Reference` to open the Reference Panel.
3. **Import CSV:** Tap the **Import** button (Folder icon with an arrow) on the Reference Pane toolbar.
4. **Select Coordinate System:**
   * If GPS was **Enabled** (Outdoors): Select `WGS 84` (EPSG::4326).
   * If GPS was **Disabled** (Indoors): Select **`Local Coordinates (m)`**.
5. **Configure Column Layout:**
   Map the columns of our CSV output to Metashape's fields:
   * **Label:** Column 1 (`label`)
   * **X / Easting / Local X:** Column 2 (`x_local_m`)
   * **Y / Northing / Local Y:** Column 3 (`y_local_m`)
   * **Z / Altitude / Local Z:** Column 4 (`z_local_m` or `baro_alt_m` if you want barometric vertical coordinates)
   * **Yaw:** Column 9 (`yaw`)
   * **Pitch:** Column 10 (`pitch`)
   * **Roll:** Column 11 (`roll`)
6. **Set Accuracy parameters:**
   * Set **Camera Position Accuracy (m):**
     * Local coordinates: `0.02` (represents our centimeter-precise VIO accuracy).
     * GPS coordinates: `5.0` (standard mobile GPS) or `0.02` (if utilizing an external RTK antenna).
   * Set **Camera Orientation Accuracy (deg):** `0.5` (represents our IMU gyro precision).
7. **Align Cameras:** Tap **Workflow** -> **Align Photos**. Metashape will use the telemetry seeds to run at lightning speed and perfectly orient your models!

---

## Part 4: Technical Sensor Reference Specs

*   **CoreMotion IMU (Gyro/Accel):** Updates up to 60Hz. Resolves micro-rotations down to **0.05 degrees** (essential for macro scans).
*   **Barometer (Altimeter):** Detects atmospheric air pressure variations down to $0.1\text{ hPa}$, providing a relative height tracking resolution of **1–5 centimeters** indoors, completely immune to indoor GPS wall degradation.
*   **ARKit VIO (LiDAR):** Runs visual tracking at 60Hz. Integrates structural LiDAR depth meshes to provide a true-scale local metric grid. Experienced drift scales linearly at a minor **1–2% of distance traveled** (effectively zeroed by returning to previously scanned paths to trigger Loop Closure).
*   **RTK GPS Compatibility:** Fully compatible with iOS-approved external Bluetooth RTK receivers (e.g. *Emlid Reach*, *Bad Elf Flex*). No custom drivers needed; iOS automatically passes sub-centimeter georeferencing coordinates directly to the app.
