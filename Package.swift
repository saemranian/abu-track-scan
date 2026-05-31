// swift-tools-version: 5.8
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "AbuTrack",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .iOSApplication(
            name: "Abu Track",
            targets: ["App"],
            bundleIdentifier: "com.saemranian.abutrack",
            teamIdentifier: "",
            displayVersion: "0.0.7",
            bundleVersion: "61",
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
                .camera(purposeString: "Abu Track uses the camera and LiDAR scanner to run real-time Visual-Inertial-LiDAR Odometry."),
                .locationAlwaysAndWhenInUse(purposeString: "Abu Track requires always-on background location tracking to log GPS coordinates while the screen is off or while taking photos inside the default camera app."),
                .locationWhenInUse(purposeString: "Abu Track requires GPS access to capture georeferencing coordinates alongside camera positions outdoors."),
                .motion(purposeString: "Abu Track requires access to device motion sensors (gyroscope/accelerometer) to record precise camera attitudes and orientations."),
                .photoLibrary(purposeString: "Abu Track requires access to your Photo Library to scan, match, and sync photos taken during the tracking session with logged coordinates.")
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
