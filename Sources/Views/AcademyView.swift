import SwiftUI

struct AcademyView: View {
    var body: some View {
        NavigationView {
            ZStack {
                // Background dark theme
                Color(red: 0.02, green: 0.03, blue: 0.08)
                    .ignoresSafeArea()
                
                RadialGradient(
                    gradient: Gradient(colors: [Color(red: 0.0, green: 0.15, blue: 0.25), Color.clear]),
                    center: .top,
                    startRadius: 50,
                    endRadius: 500
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Academy Welcome Banner
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "graduationcap.fill")
                                    .font(.title2)
                                    .foregroundColor(.cyan)
                                Text("ABU TRACK ACADEMY")
                                    .font(.system(.title3, design: .monospaced))
                                    .fontWeight(.black)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            
                            Text("Your high-precision photogrammetry and spatial tracking training hub. Master coordinate translations and reality-capture pipelines.")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .lineSpacing(3)
                        }
                        .padding()
                        .background(Color(red: 0.05, green: 0.08, blue: 0.18))
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cyan.opacity(0.2), lineWidth: 1))
                        .padding(.horizontal)
                        .padding(.top, 15)
                        
                        // Lesson Topics List
                        VStack(spacing: 15) {
                            LessonDisclosureGroup(
                                title: "1. Core VIO & IMU Sensor Fusion",
                                icon: "gyroscope",
                                color: .cyan,
                                content: """
                                • **Foreground VIO (Maximum Precision):** ARKit Visual-Inertial-LiDAR Odometry tracks visual anchors and fuses them with high-frequency IMU sensors to provide sub-millimeter tracking accuracy. For maximum results, keep the app in the foreground.
                                
                                • **The App-Switching Conflict:** iOS suspends visual camera polling when switching to the native Camera app. Although we fall back to IMU dead-reckoning, tracking will slowly drift.
                                
                                • **Solutions to Eliminate Drift:**
                                  1. **Hot-Shoe Rig Mounting:** Mount the phone on your DSLR. Leave Abu Track active in the foreground while you shoot with the DSLR normally.
                                  2. **In-App Shutter Shutter:** In our upcoming version, shoot photos directly inside Abu Track using the ARKit high-res shutter—retaining absolute VIO truth!
                                """
                            )
                            
                            LessonDisclosureGroup(
                                title: "2. DSLR Lever-Arm Offset Calibration",
                                icon: "camera.aperture",
                                color: .yellow,
                                content: """
                                • **The Problem:** When mounting your iPhone onto a mirrorless/DSLR hot-shoe, the iPhone sensor and the DSLR lens center reside at different coordinates.
                                
                                • **The 3D Quaternion Formula:** The app rotates your physical offset vector (dx, dy, dz) dynamically using the iPhone's unit quaternion rotation matrix:
                                  P_corrected = P_phone + Q * d_offset * Q_inverse
                                
                                • **Measuring Offsets (Calibration Tab):**
                                  1. **dx (Lateral):** Measured from the phone's center axis to the DSLR lens center (Positive = Right).
                                  2. **dy (Vertical):** Measured from the phone's center to the DSLR lens center (Positive = Up).
                                  3. **dz (Longitudinal):** Measured from the phone's center to the DSLR lens node center (Positive = Forward).
                                """
                            )
                            
                            LessonDisclosureGroup(
                                title: "3. Image Syncing & Post-Processing",
                                icon: "arrow.triangle.2.circlepath.camera",
                                color: .green,
                                content: """
                                • **Timestamp Matching:** Matches DSLR or iPhone camera images to the logged spatial coordinates using sub-second epoch millisecond timestamps.
                                
                                • **In-App Photo Library Matcher:** Inside the "Sessions" tab, tap "SYNC CAMERA IMAGES" to match photos in your iPhone's photo library automatically.
                                
                                • **Desktop Post-Processing (New GUI):** Run our standalone GUI desktop control panel (`DesktopSync/camtrack_desktop_gui.py`) on Windows to browse directories, set clock offsets, and georeference raw DSLR images instantly!
                                """
                            )
                            
                            LessonDisclosureGroup(
                                title: "4. Agisoft Metashape Reference Import",
                                icon: "arrow.up.doc.fill",
                                color: .purple,
                                content: """
                                • **CSV Column Layout:** The exported `metashape_cameras.csv` contains:
                                  - Column 1: `label` (Matched image filename)
                                  - Columns 2-4: Metric coordinate `local_x`, `local_y`, `local_z` (VIO meters)
                                  - Column 5: `baro_altitude` (Barometric altitude)
                                  - Columns 6-8: Absolute `gps_latitude`, `gps_longitude`, `gps_altitude` (GPS degrees)
                                  - Columns 9-11: Attitude `yaw`, `pitch`, `roll`
                                
                                • **Crucial Rules for Metashape Import:**
                                  1. **Delimiter:** In the Import CSV window, choose **Comma** (uncheck Tab).
                                  2. **If GPS is ENABLED:** Set the Coordinate System to **WGS 84 (EPSG::4326)** and map X, Y, Z coordinates to columns 6, 7, and 8.
                                  3. **If GPS is DISABLED (Indoor Mode):** The CSV still prints GPS headers, but holds dummy values. You **MUST** select **Local Coordinates (m)** and map X, Y, and Z to columns 2, 3, and 4 (`local_x`, `local_y`, `local_z` VIO meters)!
                                """
                            )
                            
                            LessonDisclosureGroup(
                                title: "5. RealityScan & EXIF Metadata Injection",
                                icon: "circle.grid.3x3.fill",
                                color: .orange,
                                content: """
                                • **The Trajectory Import Error [err:18003]:**
                                  Clicking 'Import Trajectory' in RealityScan expects a proprietary binary trajectory format. Selecting our CSV file here will fail.
                                
                                • **How to Import CSV trajectories regardless of EXIF:**
                                  In **RealityCapture (the PC app)**, select **Alignment > Import > Flight Log**. Load the CSV and map: Column 1 to Name, Column 2 to X (local) or Column 6 to Lon (GPS), Column 3 to Y (local) or Column 7 to Lat (GPS), Column 4 to Z (local) or Column 8 to Alt (GPS).
                                
                                • **The Bulletproof EXIF Method:**
                                  Use our new Desktop GUI tool to inject VIO coordinates directly into your photos' EXIF tags. Then drag and drop the folder into RealityScan. It reads the trajectory natively without needing CSV files!
                                """
                            )
                            
                            LessonDisclosureGroup(
                                title: "6. Dense ToF/LiDAR Depth Point Clouds",
                                icon: "square.stack.3d.up.fill",
                                color: .blue,
                                content: """
                                • **LiDAR Back-Projection Engine:**
                                  Starting in version **0.0.5**, Abu Track now captures high-accuracy active depth maps (`frame.sceneDepth`) from the iPhone's **ToF LiDAR scanner**.
                                
                                • **How it Works:**
                                  We back-project depth pixels using the camera intrinsics and 3D transform into world space coordinates. Decimation filters are applied to decimate points (e.g. sampling grids) to keep performance high and fluid.
                                
                                • **The Result:**
                                  You get a dense, watertight 3D surface point cloud (previewed live and exported as `.ply`) showing real geometry (walls, tables, objects) completely free of visual-inertial parallax noise and spikes!
                                """
                            )
                            
                            LessonDisclosureGroup(
                                title: "7. Custom Initial Origin Overrides",
                                icon: "arrow.triangle.branch",
                                color: .purple,
                                content: """
                                • **Origin Offset Overrides (meters):**
                                  Allows virtual production supervisors to offset and re-orient the initial tracking coordinates `(0, 0, 0)` dynamically using settings inputs for translation (X, Y, and Z in meters) and Yaw rotation (degrees).
                                
                                • **Dynamic Rotation Math:**
                                  P_corrected = P_phone + T_offset
                                  We automatically rotate double-precision quaternions using a custom yaw offset rotation matrix, ensuring absolute pose parity across network streams and 3D UI visualizers.
                                
                                • **Point Cloud Alignment:**
                                  Applies the identical translation and yaw rotation transformation to all voxelized LiDAR point cloud coordinates in real-time, keeping the scanned tracking space perfectly aligned.
                                """
                            )
                            
                            LessonDisclosureGroup(
                                title: "8. Live Telemetry & Firewall Configuration",
                                icon: "network",
                                color: .red,
                                content: """
                                • **Dynamic Live Sockets:**
                                  Broadcasts live telemetry frames at up to 60Hz. Standard socket receivers must bind to port 8080 to listen for incoming tracking packets.
                                
                                • **Windows Defender Firewall Exception:**
                                  Every compiled binary requires separate whitelisting. Click the 'FIX WINDOWS FIREWALL (8080)' button in the Windows app to add inbound rules automatically.
                                
                                • **Socket Buffer Requirements:**
                                  LiDAR depth mesh scans package and transmit hundreds of active points per frame. The workstation receiver socket buffer is maximized to 65535 bytes to prevent packet drops (WinError 10040).
                                """
                            )
                        }
                        .padding(.horizontal)
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("ACADEMY HUB")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// Custom disclosure group styling for premium sci-fi design
struct LessonDisclosureGroup: View {
    let title: String
    let icon: String
    let color: Color
    let content: String
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(color)
                    }
                    
                    Text(title)
                        .font(.footnote)
                        .fontWeight(.black)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.gray)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding()
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                        .background(Color.gray.opacity(0.2))
                        .padding(.horizontal)
                    
                    Text(content)
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .lineSpacing(4)
                        .padding()
                }
                .background(Color.black.opacity(0.15))
            }
        }
        .background(Color(red: 0.04, green: 0.06, blue: 0.12))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isExpanded ? color.opacity(0.3) : Color.gray.opacity(0.15), lineWidth: 1)
        )
    }
}
