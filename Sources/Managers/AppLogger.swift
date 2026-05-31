import Foundation
import UIKit

public final class AppLogger {
    public static let shared = AppLogger()
    
    private let fileManager = FileManager.default
    private let logQueue = DispatchQueue(label: "com.saemranian.abutrack.logger", qos: .utility)
    private var logFileUrl: URL?
    private let maxLogSize: UInt64 = 5 * 1024 * 1024 // 5 MB
    
    private init() {
        setupLogFile()
        logStartup()
    }
    
    private func setupLogFile() {
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("[CRITICAL] Could not locate Documents directory.")
            return
        }
        
        let logsFolder = documentsDirectory.appendingPathComponent("Logs", isDirectory: true)
        
        do {
            if !fileManager.fileExists(atPath: logsFolder.path) {
                try fileManager.createDirectory(at: logsFolder, withIntermediateDirectories: true, attributes: nil)
            }
            
            let fileUrl = logsFolder.appendingPathComponent("abu_track_ios.log")
            logFileUrl = fileUrl
            
            if !fileManager.fileExists(atPath: fileUrl.path) {
                fileManager.createFile(atPath: fileUrl.path, contents: nil, attributes: nil)
            } else {
                // Check and rotate size if necessary
                checkAndRotateLogFile(fileUrl)
            }
        } catch {
            print("[CRITICAL] Failed to setup local logging folder: \(error)")
        }
    }
    
    private func checkAndRotateLogFile(_ fileUrl: URL) {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileUrl.path)
            if let fileSize = attributes[.size] as? UInt64, fileSize > maxLogSize {
                let backupUrl = fileUrl.deletingLastPathComponent().appendingPathComponent("abu_track_ios_backup.log")
                if fileManager.fileExists(atPath: backupUrl.path) {
                    try? fileManager.removeItem(at: backupUrl)
                }
                try fileManager.moveItem(at: fileUrl, to: backupUrl)
                fileManager.createFile(atPath: fileUrl.path, contents: nil, attributes: nil)
                print("[INFO] Log file rotated successfully due to size: \(fileSize) bytes.")
            }
        } catch {
            print("[ERROR] Failed to verify/rotate log file size: \(error)")
        }
    }
    
    private func logStartup() {
        let device = UIDevice.current
        let model = device.model
        let sysName = device.systemName
        let sysVer = device.systemVersion
        
        log(level: "INFO", message: "============================================================")
        log(level: "INFO", message: "Abu Track iOS App Bootstrapped.")
        log(level: "INFO", message: "Version: \(VersionInfo.version), Build: \(VersionInfo.build), Built: \(VersionInfo.buildTime)")
        log(level: "INFO", message: "Device: \(model), OS: \(sysName) \(sysVer)")
        log(level: "INFO", message: "Log file path: \(logFileUrl?.path ?? "N/A")")
        log(level: "INFO", message: "============================================================")
    }
    
    public func log(level: String, message: String, file: String = #file, line: Int = #line, function: String = #function) {
        logQueue.async { [weak self] in
            guard let self = self, let url = self.logFileUrl else { return }
            
            let timestamp = self.getFormattedTimestamp()
            let fileName = URL(fileURLWithPath: file).lastPathComponent
            let logLine = "\(timestamp) [\(level)] [\(fileName):\(line) \(function)] - \(message)\n"
            
            // Console output
            print(logLine, terminator: "")
            
            // File output
            if let data = logLine.data(using: .utf8) {
                if let fileHandle = try? FileHandle(forWritingTo: url) {
                    defer {
                        try? fileHandle.close()
                    }
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                }
            }
        }
    }
    
    private func getFormattedTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
    
    // Convenience helper methods
    public static func info(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
        shared.log(level: "INFO", message: message, file: file, line: line, function: function)
    }
    
    public static func warning(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
        shared.log(level: "WARNING", message: message, file: file, line: line, function: function)
    }
    
    public static func error(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
        shared.log(level: "ERROR", message: message, file: file, line: line, function: function)
    }
    
    public static func critical(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
        shared.log(level: "CRITICAL", message: message, file: file, line: line, function: function)
    }
    
    // API to get log URL for sharing
    public func getLogFileUrl() -> URL? {
        return logFileUrl
    }
    
    // UI Sharing helper
    public func shareLogFile(from viewController: UIViewController, sender: Any?) {
        guard let url = logFileUrl, fileManager.fileExists(atPath: url.path) else {
            let alert = UIAlertController(title: "Log File Missing", message: "Could not find the local log file.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            viewController.present(alert, animated: true)
            return
        }
        
        // Ensure changes are flushed
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        
        if let popover = activityVC.popoverPresentationController {
            if let button = sender as? UIBarButtonItem {
                popover.barButtonItem = button
            } else if let view = sender as? UIView {
                popover.sourceView = view
                popover.sourceRect = view.bounds
            }
        }
        
        viewController.present(activityVC, animated: true)
    }
}
