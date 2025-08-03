import Foundation

struct GeminiAPI {
    // IMPORTANT: Replace with your actual Google AI API keys
    static let apiKeys = [
        "AIzaSyACi9OiKAOcaZdJaRvlz_lMFBQpzgHhepI",
        "AIzaSyA2jHB9dhzbPhbMbylIQkdgm63UhgLAgvU"
    ]
    
    static let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"
    
    private static var currentKeyIndex = 0
    
    static func getNextKey() -> String {
        let key = apiKeys[currentKeyIndex]
        currentKeyIndex = (currentKeyIndex + 1) % apiKeys.count
        return key
    }
}
