import Foundation
import Combine
import SwiftUI

class VideoDownloadManager: ObservableObject {
    @Published var isDownloading = false
    @Published var progress: Double = 0.0
    @Published var fileName = ""
    @Published var errorMessage: String?
    @Published var completedFile: URL?

    private var downloadProcess: Process?
    private let ytdlpPath = "/opt/homebrew/bin/yt-dlp"

    // Helper to create a shell process that mimics the Terminal environment
    private func createShellProcess(command: String) -> Process {
        let process = Process()
        // We will execute the command using the user's default shell (zsh on modern macOS)
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // The "-c" argument tells the shell to execute the following command string
        process.arguments = ["-c", command]
        
        var environment = ProcessInfo.processInfo.environment
        // CRITICAL: We provide a standard PATH that includes Homebrew's location.
        // This ensures the shell can find `yt-dlp` and its dependencies like `ffmpeg`.
        environment["PATH"] = "/opt/homebrew/bin:" + (environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin")
        process.environment = environment
        
        return process
    }

    func getVideoInfo(url: String, completion: @escaping (Result<VideoInfo, Error>) -> Void) {
        // Quote the URL to handle special characters like '&'
        let safeURL = url.replacingOccurrences(of: "'", with: "'\\''")
        let command = "\(ytdlpPath) --dump-json --no-playlist '\(safeURL)'"
        
        print("[Info] Executing command: \(command)")
        let process = createShellProcess(command: command)
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                print("[Info] Success.")
                let decoder = JSONDecoder()
                let info = try decoder.decode(VideoInfo.self, from: outputData)
                DispatchQueue.main.async { completion(.success(info)) }
            } else {
                let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown yt-dlp error"
                print("[Info] Failed with status \(process.terminationStatus): \(errorString)")
                throw NSError(domain: "VideoDownloadManager", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorString])
            }
        } catch {
            print("[Info] Caught exception: \(error.localizedDescription)")
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }

    func downloadVideo(url: String, quality: VideoQuality, options: DownloadOptions) {
        DispatchQueue.main.async {
            print("1. downloadVideo called.")
            self.isDownloading = true
            self.progress = 0.0
            self.fileName = ""
            self.errorMessage = nil
            self.completedFile = nil
        }

        let tempDir: URL
        do {
            tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("VideoToolsPro-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            print("2. Created temp directory: \(tempDir.path)")
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Lỗi: Không thể tạo thư mục tạm: \(error.localizedDescription)"
                self.isDownloading = false
            }
            return
        }

        // Build command parts, ensuring paths and URLs with spaces or special chars are quoted
        var commandParts: [String] = [ytdlpPath]
        commandParts.append(contentsOf: ["-P", "'\(tempDir.path)'"])
        commandParts.append(contentsOf: ["--merge-output-format", "mp4"])
        commandParts.append("--progress")

        switch quality {
        case .audio: commandParts.append(contentsOf: ["-x", "--audio-format", "mp3"])
        case .p1080: commandParts.append(contentsOf: ["-f", "'bv[height<=?1080][vcodec^=avc1]+ba/b[height<=?1080]/best'"])
        case .p720: commandParts.append(contentsOf: ["-f", "'bv[height<=?720][vcodec^=avc1]+ba/b[height<=?720]/best'"])
        case .best: break
        }

        if options.subtitles { commandParts.append(contentsOf: ["--write-subs", "--all-subs"]) }
        if options.thumbnail { commandParts.append("--write-thumbnail") }
        if options.metadata { commandParts.append("--add-metadata") }
        if options.playlist { commandParts.append("--yes-playlist") } else { commandParts.append("--no-playlist") }
        
        let safeURL = url.replacingOccurrences(of: "'", with: "'\\''")
        commandParts.append("'\(safeURL)'")

        let commandString = commandParts.joined(separator: " ")
        
        DispatchQueue.main.async { print("3. Prepared command: \(commandString)") }

        downloadProcess = createShellProcess(command: commandString)
        
        let pipe = Pipe()
        downloadProcess?.standardOutput = pipe
        let errorPipe = Pipe()
        downloadProcess?.standardError = errorPipe
        
        var finalFilePath: String?

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            if let output = String(data: handle.availableData, encoding: .utf8) {
                // Print raw output to see everything, including control characters
                print(output, terminator: "")
                DispatchQueue.main.async {
                    self?.parseYtdlpOutput(output, finalFilePath: &finalFilePath)
                }
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            if let errorOutput = String(data: handle.availableData, encoding: .utf8), !errorOutput.isEmpty {
                print("[stderr] \(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        downloadProcess?.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                print("5. Process terminated with status: \(process.terminationStatus)")
                self?.isDownloading = false
                if process.terminationStatus == 0, let finalPath = finalFilePath {
                    self?.progress = 1.0
                    self?.completedFile = URL(fileURLWithPath: finalPath)
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorString = String(data: errorData, encoding: .utf8)
                    self?.errorMessage = "Lỗi tải về. Chi tiết: \(errorString ?? "Không rõ")"
                }
            }
        }

        do {
            print("4. Starting process...")
            try downloadProcess?.run()
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Lỗi nghiêm trọng: Không thể khởi động tiến trình: \(error.localizedDescription)"
                self.isDownloading = false
            }
        }
    }

    private func parseYtdlpOutput(_ output: String, finalFilePath: inout String?) {
        // Regex to find the percentage value from the standard yt-dlp progress line
        let downloadRegex = try! NSRegularExpression(pattern: #"\s([\d\.]+)%"#)
        let matches = downloadRegex.matches(in: output, range: NSRange(output.startIndex..., in: output))
        if let lastMatch = matches.last,
           let range = Range(lastMatch.range(at: 1), in: output),
           let percentage = Double(output[range]) {
            self.progress = percentage / 100.0
        }

        // Regex for the final merged file path
        let mergeRegex = try! NSRegularExpression(pattern: #"[Merger] Merging formats into \"(.*)\""#)
        if let match = mergeRegex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
           let range = Range(match.range(at: 1), in: output) {
            let path = String(output[range])
            self.fileName = URL(fileURLWithPath: path).lastPathComponent
            finalFilePath = path
        }
        
        // Regex for the final destination (for non-merged files like audio)
        let destRegex = try! NSRegularExpression(pattern: #"[ExtractAudio] Destination: (.*)|Destination: (.*)"#)
        if let match = destRegex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) {
            // Check which capture group matched
            let range = Range(match.range(at: 1), in: output) ?? Range(match.range(at: 2), in: output)
            if let r = range {
                let path = String(output[r])
                self.fileName = URL(fileURLWithPath: path).lastPathComponent
                finalFilePath = path
            }
        }
    }

    func cancelDownload() {
        downloadProcess?.terminate()
        isDownloading = false
    }
}
