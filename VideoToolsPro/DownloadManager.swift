import Foundation
import Combine

class DownloadManager: ObservableObject {
    @Published var isDownloading = false
    @Published var progress: Double = 0.0
    @Published var status = ""
    @Published var filename = ""
    @Published var errorMessage: String?
    
    private var downloadId: String?
    private var timer: Timer?
    
    func startDownload(url: String, quality: String) {
        guard !isDownloading else { return }
        
        isDownloading = true
        progress = 0.0
        status = "Đang bắt đầu..."
        errorMessage = nil
        
        let payload: [String: Any] = [
            "url": url,
            "quality": quality,
            "options": [
                "subtitles": false,
                "thumbnail": false,
                "metadata": false,
                "playlist": false
            ]
        ]
        
        sendRequest(endpoint: "/download", payload: payload) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    if let success = data["success"] as? Bool, success,
                       let downloadId = data["download_id"] as? String {
                        self?.downloadId = downloadId
                        self?.startProgressMonitoring()
                    } else {
                        let error = data["error"] as? String ?? "Unknown error"
                        self?.handleError(error)
                    }
                case .failure(let error):
                    self?.handleError(error.localizedDescription)
                }
            }
        }
    }
    
    private func startProgressMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkProgress()
        }
    }
    
    private func checkProgress() {
        guard let downloadId = downloadId else { return }
        
        let payload = ["download_id": downloadId]
        
        sendRequest(endpoint: "/progress", payload: payload) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    self?.updateProgress(from: data)
                case .failure(let error):
                    self?.handleError(error.localizedDescription)
                }
            }
        }
    }
    
    private func updateProgress(from data: [String: Any]) {
        if let progressValue = data["progress"] as? Double {
            progress = progressValue / 100.0
        }
        
        if let statusText = data["status"] as? String {
            status = statusText
        }
        
        if let filenameText = data["filename"] as? String {
            filename = filenameText
        }
        
        if status == "finished" {
            finishDownload()
        } else if status == "error" {
            let error = data["error"] as? String ?? "Download failed"
            handleError(error)
        }
    }
    
    private func finishDownload() {
        timer?.invalidate()
        timer = nil
        downloadId = nil
        isDownloading = false
        progress = 1.0
        status = "Hoàn thành!"
    }
    
    private func handleError(_ message: String) {
        timer?.invalidate()
        timer = nil
        downloadId = nil
        isDownloading = false
        errorMessage = message
        status = "Lỗi"
    }
    
    private func sendRequest(endpoint: String, payload: [String: Any], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:8000\(endpoint)") else {
            completion(.failure(NSError(domain: "Invalid URL", code: 0, userInfo: nil)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "No data", code: 0, userInfo: nil)))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    completion(.success(json))
                } else {
                    completion(.failure(NSError(domain: "Invalid JSON", code: 0, userInfo: nil)))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}
