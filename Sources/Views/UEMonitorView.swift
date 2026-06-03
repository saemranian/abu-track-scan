import SwiftUI
import WebKit

struct UEMonitorView: View {
    @State private var urlString: String = RigSettings.ueMonitorURL
    @State private var webViewID = UUID() // Force reload by changing ID
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Title
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("UNREAL ENGINE MONITOR")
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .foregroundColor(.cyan)
                    Text("ULTRA-LOW LATENCY WEBRTC PIXEL STREAMING")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.gray)
                }
                Spacer()
                
                // Status Beacon
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .shadow(color: .green, radius: 3)
                    Text("READY")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.1))
                .cornerRadius(4)
            }
            .padding()
            .background(Color(red: 0.02, green: 0.03, blue: 0.08))
            
            // Connection panel
            HStack(spacing: 8) {
                Text("URL:")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.gray)
                
                TextField("http://<UE-IP-Address>:80", text: $urlString, onCommit: {
                    saveURL()
                })
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .padding(6)
                .background(Color.black.opacity(0.4))
                .cornerRadius(4)
                .foregroundColor(.white)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                
                Button(action: {
                    saveURL()
                    // Recreate WebView to force fresh load
                    webViewID = UUID()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("LOAD")
                    }
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.cyan.opacity(0.15))
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.cyan.opacity(0.4), lineWidth: 0.5))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(red: 0.03, green: 0.04, blue: 0.10))
            
            // WebView container
            ZStack {
                Color.black
                
                if let url = URL(string: urlString) {
                    WebViewContainer(url: url)
                        .id(webViewID)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("INVALID MONITOR URL")
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.red)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(red: 0.01, green: 0.02, blue: 0.05))
    }
    
    private func saveURL() {
        RigSettings.ueMonitorURL = urlString
    }
}

// SwiftUI web kit wrapper
struct WebViewContainer: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Allow inline media playback and audio autoplay for WebRTC
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.isOpaque = false
        
        // Disable scroll bouncing for viewport monitoring
        webView.scrollView.bounces = false
        
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        webView.load(request)
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Leave empty
    }
}
