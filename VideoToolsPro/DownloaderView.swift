import SwiftUI

struct DownloaderView: View {
    @ObservedObject var downloadManager: VideoDownloadManager
    
    @State private var videoURL = ""
    @State private var selectedQuality = VideoQuality.best
    @State private var downloadOptions = DownloadOptions()
    @State private var videoInfo: VideoInfo?
    @State private var isLoadingInfo = false
    
    // State for the save panel
    @State private var isShowingSavePanel = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.green.opacity(0.2), Color.yellow.opacity(0.2), Color.orange.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 24) {
                // Title Card
                Text("📥 Video Downloader")
                    .font(.largeTitle).fontWeight(.bold)
                    .foregroundStyle(LinearGradient(colors: [.green, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                
                // URL and Quality
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "link.circle.fill").font(.title2).foregroundColor(.blue)
                        TextField("Paste YouTube URL...", text: $videoURL, onCommit: loadVideoInfo)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Picker("Quality", selection: $selectedQuality) {
                            ForEach(VideoQuality.allCases) { quality in
                                Text(quality.displayName).tag(quality)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 150)
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: 8)
                
                // Download Options
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "gearshape.fill").font(.title2).foregroundColor(.orange)
                        Text("Tuỳ chọn tải xuống").font(.headline).fontWeight(.semibold)
                    }
                    VStack(spacing: 12) {
                        HStack {
                            Toggle("📝 Phụ đề", isOn: $downloadOptions.subtitles)
                            Spacer()
                            Toggle("🖼️ Thumbnail", isOn: $downloadOptions.thumbnail)
                        }
                        HStack {
                            Toggle("📊 Metadata", isOn: $downloadOptions.metadata)
                            Spacer()
                            Toggle("📂 Playlist", isOn: $downloadOptions.playlist)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .orange))
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .shadow(color: .orange.opacity(0.1), radius: 15, x: 0, y: 8)
                
                // Video Info Preview
                if let info = videoInfo {
                    videoInfoView(info)
                        .transition(.scale.combined(with: .opacity))
                }
                
                // Download Button
                Button(action: startDownload) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Bắt đầu tải").fontWeight(.semibold)
                    }
                    .padding().frame(maxWidth: .infinity)
                    .background(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                    .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                }
                .disabled(videoURL.isEmpty || downloadManager.isDownloading)
                .buttonStyle(.plain)
                
                // Progress View
                if downloadManager.isDownloading {
                    progressView
                }
                
                // Error Message Display
                if let errorMessage = downloadManager.errorMessage {
                    errorMessageView(errorMessage)
                }
                
                Spacer()
            }
            .padding()
        }
        .onChange(of: downloadManager.completedFile) { newFile in
            if newFile != nil {
                isShowingSavePanel = true
            }
        }
        .sheet(isPresented: $isShowingSavePanel) {
            if let tempURL = downloadManager.completedFile {
                SavePanel(temporaryURL: tempURL) {
                    // Reset after panel is dismissed
                    downloadManager.completedFile = nil
                }
            }
        }
    }
    
    private func startDownload() {
        guard !videoURL.isEmpty else { return }
        downloadManager.downloadVideo(url: videoURL, quality: selectedQuality, options: downloadOptions)
    }
    
    private func loadVideoInfo() {
        guard !videoURL.isEmpty else { return }
        isLoadingInfo = true
        downloadManager.getVideoInfo(url: videoURL) { result in
            DispatchQueue.main.async {
                self.isLoadingInfo = false
                switch result {
                case .success(let info):
                    withAnimation(.easeInOut) { self.videoInfo = info }
                case .failure(let error):
                    downloadManager.errorMessage = "Lỗi lấy thông tin video: \(error.localizedDescription)"
                    self.videoInfo = nil
                }
            }
        }
    }

    // MARK: - Subviews
    private var progressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Đang tải: \(downloadManager.fileName.isEmpty ? "..." : downloadManager.fileName)")
                    .font(.footnote).foregroundColor(.secondary)
                Spacer()
                Text("\(Int(downloadManager.progress * 100))%").font(.footnote.bold()).foregroundColor(.blue)
            }
            ProgressView(value: downloadManager.progress).progressViewStyle(LinearProgressViewStyle())
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private func errorMessageView(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
            Text(message).font(.callout)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.2))
        .cornerRadius(12)
        .padding(.top)
        .transition(.opacity)
    }
    
    private func videoInfoView(_ info: VideoInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle.fill").font(.title2).foregroundColor(.green)
                Text("Thông tin video").font(.headline).fontWeight(.semibold)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(info.title).font(.subheadline).fontWeight(.medium).lineLimit(2)
                HStack {
                    if let uploader = info.uploader {
                        Label(uploader, systemImage: "person.circle").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    if let duration = info.duration {
                        Label(formatDuration(duration), systemImage: "clock").font(.caption).foregroundColor(.secondary)
                    }
                }
                if let viewCount = info.view_count {
                    Label("\(viewCount) views", systemImage: "eye").font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}

// A new helper view to wrap NSOpenPanel
struct SavePanel: NSViewRepresentable {
    let temporaryURL: URL
    let onDismiss: () -> Void

    func makeNSView(context: Context) -> NSView {
        return NSView() // A dummy view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // This is called when the sheet is presented.
        // We use a coordinator to avoid presenting the panel multiple times.
        if !context.coordinator.isPanelPresented {
            context.coordinator.isPanelPresented = true
            
            let savePanel = NSSavePanel()
            savePanel.canCreateDirectories = true
            savePanel.nameFieldStringValue = temporaryURL.lastPathComponent
            
            savePanel.begin { response in
                if response == .OK, let finalURL = savePanel.url {
                    do {
                        // If a file already exists, remove it.
                        if FileManager.default.fileExists(atPath: finalURL.path) {
                            try FileManager.default.removeItem(at: finalURL)
                        }
                        // Move the downloaded file from the temp location to the final destination
                        try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
                    } catch {
                        // Handle error, maybe show an alert
                        print("Error saving file: \(error.localizedDescription)")
                    }
                }
                // Clean up the temp directory
                try? FileManager.default.removeItem(at: temporaryURL.deletingLastPathComponent())
                self.onDismiss()
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: SavePanel
        var isPanelPresented = false
        
        init(_ parent: SavePanel) {
            self.parent = parent
        }
    }
}


struct DownloaderView_Previews: PreviewProvider {
    static var previews: some View {
        DownloaderView(downloadManager: VideoDownloadManager())
    }
}