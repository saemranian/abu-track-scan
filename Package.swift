// swift-tools-version: 5.8
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "CamTrackPro",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .iOSApplication(
            name: "CamTrack Pro",
            targets: ["App"],
            bundleIdentifier: "com.saemranian.camtrackpro",
            teamIdentifier: "",
            displayVersion: "0.0.3",
            bundleVersion: "15",
            appIcon: .placeholder(icon: .camera),
            accentColor: .presetColor(.cyan),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait
            ],
            capabilities: [
                .camera(purposeString: "CamTrack Pro uses the camera and LiDAR scanner to run real-time Visual-Inertial-LiDAR Odometry."),
                .locationAlwaysAndWhenInUse(purposeString: "CamTrack Pro requires always-on background location tracking to log GPS coordinates while the screen is off or while taking photos inside the default camera app."),
                .locationWhenInUse(purposeString: "CamTrack Pro requires GPS access to capture georeferencing coordinates alongside camera positions outdoors."),
                .motion(purposeString: "CamTrack Pro requires access to device motion sensors (gyroscope/accelerometer) to record precise camera attitudes and orientations."),
                .photoLibrary(purposeString: "CamTrack Pro requires access to your Photo Library to scan, match, and sync photos taken during the tracking session with logged coordinates.")
            ],
            additionalInfoPlistContentFilePath: "Info.plist"
        )
    ],
    targets: [
        .executableTarget(
            name: "App",
            path: "Sources"
        )
    ]
)
