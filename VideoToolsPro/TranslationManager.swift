import Foundation
import Combine
import SwiftUI

// MARK: - Translation Manager
class TranslationManager: ObservableObject {
    @Published var isTranslating = false
    @Published var progress: Double = 0.0
    @Published var statusText: String = "Sẵn sàng"
    
    // Final results
    @Published var translatedSubtitle: String = ""
    @Published var captionText: String = ""
    @Published var thumbnailText: String = ""
    @Published var errorMessage: String?

    // Main function to start the translation process
    func translateFile(url: URL) {
        guard !isTranslating else { return }

        // Reset state
        DispatchQueue.main.async {
            self.isTranslating = true
            self.progress = 0.0
            self.statusText = "Bắt đầu..."
            self.errorMessage = nil
            self.translatedSubtitle = ""
            self.captionText = ""
            self.thumbnailText = ""
        }

        Task {
            do {
                // 1. Read and Parse File
                let fileContent = try String(contentsOf: url, encoding: .utf8)
                let srtText = try parseInputToSRT(content: fileContent, isJson: url.pathExtension.lowercased() == "json")
                let subtitles = try parseSRT(srtText)
                guard !subtitles.isEmpty else {
                    throw TranslationError.parsingFailed("Không tìm thấy phụ đề nào trong file.")
                }
                await updateStatus("Đã phân tích xong file SRT.", progress: 0.1)

                // 2. Translate Subtitles in Batches
                let translatedSubs = try await translateAllSubtitles(subtitles)
                
                // 3. Generate Creative Content
                await updateStatus("Đang tạo nội dung sáng tạo...", progress: 0.85)
                let (captions, thumbnail) = try await generateCreativeContent(from: translatedSubs)
                
                // 4. Assemble Final Results
                await updateStatus("Hoàn tất!", progress: 1.0)
                let finalSRT = translatedSubs.map { "\($0.index)\n\($0.timestamp)\n\($0.text)" }.joined(separator: "\n\n")
                
                DispatchQueue.main.async {
                    self.translatedSubtitle = finalSRT
                    self.captionText = captions
                    self.thumbnailText = thumbnail
                    self.isTranslating = false
                }

            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Lỗi: \(error.localizedDescription)"
                    self.isTranslating = false
                }
            }
        }
    }
    
    private func updateStatus(_ text: String, progress: Double) async {
        await MainActor.run {
            self.statusText = text
            self.progress = progress
        }
    }
}

// MARK: - SRT & JSON Parsing
extension TranslationManager {
    
    struct Subtitle {
        let index: Int
        let timestamp: String
        let text: String
    }

    private func parseInputToSRT(content: String, isJson: Bool) throws -> String {
        if !isJson { return content }
        
        // JSON Parsing Logic from server.py
        guard let data = content.data(using: .utf8) else {
            throw TranslationError.parsingFailed("Không thể chuyển đổi JSON content sang data.")
        }
        
        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let materials = jsonObject["materials"] as? [String: Any],
              let texts = materials["texts"] as? [[String: Any]] else {
            throw TranslationError.parsingFailed("Cấu trúc JSON không hợp lệ.")
        }
        
        let sortedTexts = texts.sorted { ($0["start_time"] as? Int ?? 0) < ($1["start_time"] as? Int ?? 0) }
        
        var srtLines: [String] = []
        for (index, textInfo) in sortedTexts.enumerated() {
            guard let content = textInfo["content"] as? String, !content.isEmpty else { continue }
            
            let startTimeUs = textInfo["start_time"] as? Int ?? 0
            let endTimeUs = textInfo["end_time"] as? Int ?? 0
            
            func formatTime(_ timeUs: Int) -> String {
                let timeS = Double(timeUs) / 1_000_000.0
                let hours = Int(timeS) / 3600
                let minutes = (Int(timeS) % 3600) / 60
                let seconds = Int(timeS) % 60
                let milliseconds = Int((timeS.truncatingRemainder(dividingBy: 1)) * 1000)
                return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
            }
            
            let startTime = formatTime(startTimeUs)
            let endTime = formatTime(endTimeUs)
            
            srtLines.append("\(index + 1)")
            srtLines.append("\(startTime) --> \(endTime)")
            srtLines.append(content)
            srtLines.append("")
        }
        
        return srtLines.joined(separator: "\n")
    }

    private func parseSRT(_ srtContent: String) throws -> [Subtitle] {
        let pattern = #/(\d+)\n(\d{2}:\d{2}:\d{2},\d{3}\s*-->\s*\d{2}:\d{2}:\d{2},\d{3})\n([\s\S]+?)(?=\n\n|\Z)/#
        let cleanedContent = srtContent.replacing("\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        
        return try cleanedContent.matches(of: pattern).map {
            guard let index = Int($0.1) else {
                throw TranslationError.parsingFailed("Invalid subtitle index.")
            }
            let timestamp = String($0.2)
            let text = String($0.3).trimmingCharacters(in: .whitespaces)
            return Subtitle(index: index, timestamp: timestamp, text: text)
        }
    }
}

// MARK: - Gemini API Communication
extension TranslationManager {
    
    private func translateAllSubtitles(_ subtitles: [Subtitle]) async throws -> [Subtitle] {
        let batchSize = 15
        let batches = subtitles.chunked(into: batchSize)
        var translatedSubtitles: [Subtitle] = []
        var previousContext: String? = nil
        
        for (batchIndex, batch) in batches.enumerated() {
            let progress = 0.1 + (Double(batchIndex) / Double(batches.count)) * 0.75
            await updateStatus("Đang dịch lô \(batchIndex + 1)/\(batches.count)...", progress: progress)
            
            let originalTexts = batch.map { $0.text }
            let isIntro = (batchIndex == 0)
            
            let translatedTexts = try await callGeminiForTranslation(
                texts: originalTexts,
                isIntro: isIntro,
                previousContext: previousContext
            )
            
            guard translatedTexts.count == batch.count else {
                throw TranslationError.apiError("Số lượng dòng dịch thuật trả về không khớp.")
            }
            
            for (i, originalSub) in batch.enumerated() {
                translatedSubtitles.append(Subtitle(
                    index: originalSub.index,
                    timestamp: originalSub.timestamp,
                    text: translatedTexts[i]
                ))
            }
            
            previousContext = originalTexts.joined(separator: " ")
        }
        
        return translatedSubtitles
    }
    
    private func generateCreativeContent(from subtitles: [Subtitle]) async throws -> (captions: String, thumbnail: String) {
        // Create a summary of the translated content
        let fullText = subtitles.map { $0.text }.joined(separator: " ")
        let summaryPrompt = "Tóm tắt nội dung sau thành 3 phần (đầu, giữa, cuối) để chuẩn bị viết caption: \(fullText.prefix(2000))"
        let summary = try await callGemini(prompt: summaryPrompt)
        
        await updateStatus("Đang tạo captions...", progress: 0.9)
        let captionPrompt = PromptFactory.captionPrompt(summary: summary)
        let captions = try await callGemini(prompt: captionPrompt)
        
        await updateStatus("Đang tạo text thumbnail...", progress: 0.95)
        let thumbnailPrompt = PromptFactory.thumbnailPrompt(summary: summary)
        let thumbnail = try await callGemini(prompt: thumbnailPrompt)
        
        return (captions, thumbnail)
    }

    private func callGeminiForTranslation(texts: [String], isIntro: Bool, previousContext: String?) async throws -> [String] {
        let prompt = PromptFactory.translationPrompt(texts: texts, isIntro: isIntro, previousContext: previousContext)
        let rawResponse = try await callGemini(prompt: prompt)
        
        // Parse the numbered list response from Gemini
        let lines = rawResponse.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let translatedTexts = lines.map {
            if let match = $0.firstMatch(of: #/^\(?\d+\)?\.?\s*(.*)/#) {
                return String(match.1)
            }
            return String($0)
        }
        
        return translatedTexts
    }
    
    private func callGemini(prompt: String) async throws -> String {
        guard let url = URL(string: "\(GeminiAPI.endpoint)?key=\(GeminiAPI.getNextKey())") else {
            throw TranslationError.apiError("Invalid Gemini API URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": prompt]]]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw TranslationError.apiError("Lỗi API, mã trạng thái: \(statusCode). Phản hồi: \(String(data: data, encoding: .utf8) ?? "")")
        }
        
        // Parse the response
        guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = jsonResponse["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw TranslationError.parsingFailed("Không thể phân tích phản hồi từ Gemini API.")
        }
        
        return text
    }
}

// MARK: - Helper Structures and Extensions
enum TranslationError: Error, LocalizedError {
    case parsingFailed(String)
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .parsingFailed(let reason): return "Lỗi phân tích file: \(reason)"
        case .apiError(let reason): return "Lỗi API: \(reason)"
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}