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
                                Text("CAMTRACK ACADEMY")
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
                                • **Foreground Tracking (ARKit VIO):** Uses your iPhone's camera and **LiDAR scanner** to track physical structures in the room. This calculates local metric (X, Y, Z) coordinates with sub-millimeter relative precision.
                                
                                • **Background Tracking (CoreMotion IMU):** When you lock your screen or switch to the default camera app, the app falls back to logging high-frequency gyroscope/accelerometer data to prevent iOS from terminating the sensor stream.
                                
                                • **Barometric Height Calibration:** Integrates the CMAltimeter to measure relative altitude changes using barometric pressure. This provides vertical centimeter-level height changes free of standard GPS vertical drift.
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
                                • **Timestamp Matching:** Every time you click a photo, the app syncs and matches DSLR or iPhone camera images to the logged spatial coordinates using sub-second epoch millisecond timestamps.
                                
                                • **In-App Photo Library Matcher:** Inside the "Sessions" tab, tap "SYNC CAMERA IMAGES" to match photos in your iPhone's photo library automatically.
                                
                                • **Desktop Post-Processing:** If using a DSLR/Mirrorless camera, copy the photos to your PC, get the `telemetry_log.csv` file, and run our standalone python script:
                                  python sync_photos.py --photos /path/to/photos --csv /path/to/telemetry_log.csv
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
                                  - Column 5: `baro_altitude` (Centimeter-precision relative altitude)
                                  - Columns 6-8: Absolute `gps_latitude`, `gps_longitude`, `gps_altitude` (GPS degrees)
                                  - Columns 9-11: Attitude `yaw`, `pitch`, `roll`
                                
                                • **CRITICAL Metashape Import Rules (Avoid Pitfalls!):**
                                  1. **Delimiter Mismatch:** In the Import CSV dialog, you MUST check **Comma** as the delimiter (uncheck Tab). Checking 'Tab' will fail to split columns, causing cameras to import in a single line.
                                  2. **Coordinate System Selection:** 
                                     - If you set X, Y, Z to local VIO columns (Columns 2, 3, 4), set the coordinate system to **Local Coordinates (m)**.
                                     - If you set X, Y, Z to GPS columns (Columns 6, 7, 8), you MUST set the coordinate system to **WGS 84 (EPSG::4326)**! Importing GPS degrees as meters will pack cameras into a single wrong spot.
                                """
                            )
                            
                            LessonDisclosureGroup(
                                title: "5. RealityScan & EXIF Metadata Injection",
                                icon: "circle.grid.3x3.fill",
                                color: .orange,
                                content: """
                                • **The Trajectory Import Error [err:18003]:** 
                                  Clicking 'Import Trajectory' in RealityScan/RealityCapture prompts for a proprietary alignment/flight-log format. Importing our metashape CSV directly here will fail.
                                
                                • **The EXIF Metadata Solution (Most Solid!):**
                                  The absolute bulletproof way is to inject high-precision VIO coordinates and orientation angles directly into the EXIF/XMP tags of the image files (using our Python desktop script).
                                
                                • **Why EXIF is Superior:**
                                  Once injected, you just drag and drop the photos folder directly into RealityScan or Metashape. The software reads the coordinates instantly without needing separate trajectory files or custom configuration settings!
                                """
                            )
                            
                            LessonDisclosureGroup(
                                title: "6. VIO Point Clouds vs. Dense LiDAR Scans",
                                icon: "square.stack.3d.up.fill",
                                color: .blue,
                                content: """
                                • **VIO Sparse Reference Point Cloud:**
                                  Our persistent point cloud (`coverage_cloud.ply`) is a **sparse visual-inertial tracking aid** composed of high-contrast texture anchors used by ARKit to track camera position. It is meant as an operator coverage diagnostic, not as a finished 3D mesh model.
                                
                                • **Why it Looks Messy/Spiky:**
                                  These points are back-projected visually based on parallax. Panning fast or passing low-texture, reflective, or plain surfaces creates "outliers" (messy floating points).
                                
                                • **Dot3D / LiDAR Meshing:**
                                  Apps like Dot3D build watertight, dense reconstructions by actively filtering continuous time-of-flight LiDAR depth frames, which is heavily GPU-intensive and not designed for sub-millimeter camera track logging.
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
