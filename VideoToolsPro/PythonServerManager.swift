import Foundation
import Combine

class PythonServerManager: ObservableObject {
    @Published var isServerRunning = false
    @Published var errorMessage: String?
    
    private var serverProcess: Process?
    private var cancellables = Set<AnyCancellable>()
    
    func startServer() {
        // Instead of starting our own server, just check if one is already running
        checkServerStatus()
    }
    
    func stopServer() {
        serverProcess?.terminate()
        serverProcess = nil
        
        DispatchQueue.main.async {
            self.isServerRunning = false
        }
    }
    
    func restartServer() {
        stopServer()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.startServer()
        }
    }
    
    
    
    private func checkServerStatus() {
        guard let url = URL(string: "http://127.0.0.1:8000/health") else { return }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    // This is the key part: capture the specific error
                    let detailedError = "Lỗi kết nối đến server: \(error.localizedDescription). Hãy chắc chắn server đang chạy và không bị tường lửa chặn."
                    print("❌ \(detailedError)")
                    self?.isServerRunning = false
                    self?.errorMessage = detailedError
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    print("✅ Server is running and healthy.")
                    self?.isServerRunning = true
                    self?.errorMessage = nil
                } else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    let detailedError = "Server có phản hồi nhưng không thành công (Mã lỗi: \(statusCode))."
                    print("❌ \(detailedError)")
                    self?.isServerRunning = false
                    self?.errorMessage = detailedError
                }
            }
        }.resume()
    }
    
    deinit {
        stopServer()
    }
}
