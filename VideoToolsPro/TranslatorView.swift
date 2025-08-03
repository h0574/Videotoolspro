import SwiftUI
import UniformTypeIdentifiers

struct TranslatorView: View {
    @ObservedObject var translationManager: TranslationManager
    
    @State private var selectedFile: URL?
    @State private var isShowingFilePicker = false
    @State private var animateProgress = false
    
    var body: some View {
        ZStack {
            // Background gradient with animation
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.3),
                    Color.purple.opacity(0.2),
                    Color.pink.opacity(0.1),
                    Color.orange.opacity(0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: animateProgress)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Title Card
                    VStack {
                        Text("🎬 Video Translator Pro")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple, .pink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .scaleEffect(animateProgress ? 1.05 : 1.0)
                            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: animateProgress)
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(LinearGradient(
                                colors: [.white.opacity(0.3), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                    
                    // File Selection
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "folder.badge.plus").font(.title2).foregroundColor(.blue)
                            Text("Chọn file phụ đề").font(.headline).fontWeight(.semibold)
                            Spacer()
                        }
                        
                        Button(action: { isShowingFilePicker = true }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Chọn file (.srt hoặc .json)").fontWeight(.medium)
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        
                        if let file = selectedFile {
                            HStack {
                                Image(systemName: "doc.text.fill").foregroundColor(.green)
                                VStack(alignment: .leading) {
                                    Text(file.lastPathComponent).fontWeight(.medium)
                                    Text("Sẵn sàng để dịch").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            }
                            .padding()
                            .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.3), lineWidth: 1))
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: 8)
                    
                    // Translate Button
                    Button(action: startTranslation) {
                        HStack {
                            if translationManager.isTranslating {
                                ProgressView().scaleEffect(0.8).tint(.white)
                            } else {
                                Image(systemName: "wand.and.stars").font(.title3)
                            }
                            Text(translationManager.isTranslating ? translationManager.statusText : "🚀 Dịch & Sáng tạo")
                                .fontWeight(.semibold)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(
                                colors: translationManager.isTranslating ? [.orange, .red] : [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    }
                    .disabled(selectedFile == nil || translationManager.isTranslating)
                    .buttonStyle(.plain)
                    .animation(.easeInOut, value: translationManager.isTranslating)
                    
                    // Progress View
                    if translationManager.isTranslating {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tiến độ dịch").font(.headline)
                            ProgressView(value: translationManager.progress)
                                .progressViewStyle(LinearProgressViewStyle(tint: .orange))
                            HStack {
                                Text(translationManager.statusText).font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(translationManager.progress * 100))%").font(.caption).fontWeight(.bold)
                            }
                        }
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    // Error Message
                    if let errorMessage = translationManager.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                            Text(errorMessage).font(.body)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.2))
                        .cornerRadius(12)
                    }
                    
                    // Results Section
                    if !translationManager.translatedSubtitle.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Kết quả").font(.title2).bold()
                            
                            TabView {
                                resultTab("Phụ đề", icon: "text.bubble", content: translationManager.translatedSubtitle)
                                resultTab("Caption", icon: "quote.bubble", content: translationManager.captionText)
                                thumbnailTab("Thumbnail", icon: "photo", content: translationManager.thumbnailText)
                            }
                            .frame(height: 350)
                            // .tabViewStyle(PageTabViewStyle()) // This style is not available on macOS
                            // .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
                        }
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    }
                }
                .padding()
            }
        }
        .onAppear { animateProgress = true }
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.init(filenameExtension: "srt")!, .init(filenameExtension: "json")!],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let files):
                if let file = files.first {
                    if file.startAccessingSecurityScopedResource() {
                        selectedFile = file
                    } else {
                        translationManager.errorMessage = "Không thể truy cập file đã chọn."
                    }
                }
            case .failure(let error):
                translationManager.errorMessage = "Lỗi chọn file: \(error.localizedDescription)"
            }
        }
    }
    
    private func startTranslation() {
        guard let file = selectedFile else { return }
        translationManager.translateFile(url: file)
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    @ViewBuilder
    private func resultTab( _ title: String, icon: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                Text(title).font(.headline)
                Spacer()
                Button("Copy") { copyToClipboard(content) }.buttonStyle(.bordered)
            }
            TextEditor(text: .constant(content))
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
        }
        .padding()
    }
    
    @ViewBuilder
    private func thumbnailTab(_ title: String, icon: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                Text(title).font(.headline)
                Spacer()
                Button("Copy") { copyToClipboard(content) }.buttonStyle(.bordered)
            }
            Text(content)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .foregroundColor(.white)
                .cornerRadius(12)
        }
        .padding()
    }
}

struct TranslatorView_Previews: PreviewProvider {
    static var previews: some View {
        TranslatorView(translationManager: TranslationManager())
    }
}
