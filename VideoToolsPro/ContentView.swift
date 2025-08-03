import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    // No longer need PythonServerManager
    @StateObject private var downloadManager = VideoDownloadManager()
    @StateObject private var translationManager = TranslationManager()
    
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Main Content
            TabView(selection: $selectedTab) {
                // Pass the managers to the views
                DownloaderView(downloadManager: downloadManager)
                    .tabItem {
                        Image(systemName: "play.rectangle")
                        Text("Tải Video")
                    }
                    .tag(0)
                
                TranslatorView(translationManager: translationManager)
                    .tabItem {
                        Image(systemName: "text.bubble.rtl")
                        Text("Dịch Phụ Đề")
                    }
                    .tag(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // No longer need to manage the server on appear or show alerts for it
    }
}

// HeaderView and LoadingView are no longer needed as they were server-dependent.
// We can remove them to clean up the file.

#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
