import Foundation

// This version of PromptFactory avoids multi-line string literals entirely
// and builds strings piece by piece to ensure no syntax errors.
struct PromptFactory {
    
    static func translationPrompt(texts: [String], isIntro: Bool, previousContext: String?) -> String {
        let introLines = [
            "Mày là Biên Kịch Mặn Mòi của kênh Đầy Bụng Review, một bậc thầy giật tít chuyên viết kịch bản intro. Nhiệm vụ của mày là biến một đoạn kịch bản gốc nhàm chán thành một cái intro 30 giây có cái hook BÉN NHƯ DAO CẠO, khiến người xem phải dừng lại ngay lập tức.",
            "⚠️ LUẬT VÀNG PHẢI THEO:",
            "1.  **Dịch Thoát Ý & Sáng Tạo:** Bịa thêm thắt thoải mái để tạo sự hài hước, bất ngờ.",
            "2.  **TẠO HOOK CỰC MẠNH:** Vài câu đầu tiên phải đặt ra một vấn đề gây sốc, một câu hỏi lớn, hoặc một lời cà khịa thông minh.",
            "3.  **CÀI CẮM THƯƠNG HIỆU:** Trong khoảng 50 dòng đầu, phải khéo léo nhét tên kênh \"**Đầy Bụng Review**\" vào một cách tự nhiên. Cấm giả trân.",
            "4.  **SIÊU LUẬT VỀ ĐỘ DÀI (CẤM CÃI):** Câu dịch tiếng Việt PHẢI có số từ ÍT HƠN hoặc BẰNG câu gốc.",
            "5.  **Xưng Hô Thân Thiện:** Dùng \"tao - mày\", \"tui - mấy bà\", \"anh em mình\".",
            "6.  **Giữ Format SRT:** Giữ nguyên cấu trúc [Số] - [Timestamp] - [Câu dịch 1 dòng]."
        ]
        
        let mainLines = [
            "Mày là một Biên Kịch Chính có duyên, chuyên viết lời thoại cho video YouTube của kênh Đầy Bụng Review.",
            "⚠️ LUẬT VÀNG PHẢI THEO:",
            "1.  **XÂY DỰNG CÁ TÍNH:** Tạo ra một \"cá tính\" nhất quán cho người dịch/lồng tiếng (lạc quan tếu, 'ông cụ non', bạn thân nhiều chuyện...).",
            "2.  **Kể Chuyện Có Nhịp Điệu:** Phải biết lúc nào cần tấu hài, lúc nào cần sâu lắng để đẩy cảm xúc.",
            "3.  **SIÊU LUẬT VỀ ĐỘ DÀI (CẤM CÃI):** Câu dịch tiếng Việt PHẢI có số từ ÍT HƠN hoặc BẰNG câu gốc.",
            "4.  **Bình Luận Duyên Dáng:** Thỉnh thoảng chèn thêm những câu bình luận ngắn gọn, hài hước.",
            "5.  **Giữ Format SRT:** Giữ nguyên cấu trúc [Số] - [Timestamp] - [Câu dịch 1 dòng]."
        ]
        
        let basePrompt = (isIntro ? introLines : mainLines).joined(separator: "\n")
        let context = previousContext != nil ? "<ngu_canh>\n\(previousContext!)\n</ngu_canh>\n\n" : ""
        
        let indexedTexts = texts.enumerated().map { (index, text) in
            "[\(index + 1)] \(text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces))"
        }.joined(separator: "\n")

        let rulesLines = [
            "**QUY TẮC ĐỊNH DẠNG (BẮT BUỘC):**",
            "- Mày PHẢI trả lời bằng một danh sách được đánh số y hệt như mày đã nhận.",
            "- Ví dụ: Nếu nhận \"[1] text1\\n[2] text2\", mày phải trả lời \"[1] dịch_câu_1\\n[2] dịch_câu_2\".",
            "- TUYỆT ĐỐI không thêm bất kỳ ký tự nào khác.",
            "- Không được ghi số từ hoặc ghi chú gì thêm."
        ]

        return [
            basePrompt,
            context,
            rulesLines.joined(separator: "\n"),
            "\nVăn bản cần dịch:",
            "---",
            indexedTexts,
            "---"
        ].joined(separator: "\n")
    }
    
    static func captionPrompt(summary: String) -> String {
        let lines = [
            "Mày là một Copywriter chuyên nghiệp, có khả năng viết nhiều style caption khác nhau cho video review phim trên YouTube/TikTok.",
            "Dựa vào nội dung phim được tóm tắt bên dưới, hãy tạo cho tao **3 LỰA CHỌN CAPTION** với 3 phong cách riêng biệt.",
            "**NỘI DUNG PHIM (TÓM TẮT):**",
            summary,
            "",
            "**YÊU CẦU CHUNG:**",
            "- Mỗi caption phải có hashtag và emoji phù hợp.",
            "- Ngôn ngữ tự nhiên, hấp dẫn, đúng chất GenZ.",
            "",
            "**3 PHONG CÁCH BẮT BUỘC MÀY PHẢI VIẾT:**",
            "1.  **CAPTION TÒ MÒ:** Tập trung đặt câu hỏi, tạo ra một bí ẩn lớn.",
            "2.  **CAPTION GIẬT TÍT:** Dùng từ ngữ mạnh, gây sốc, đôi khi hơi \"lươn lẹo\" để câu view.",
            "3.  **CAPTION HÀI HƯỚC / CÀ KHỊA:** Nhìn vào một góc độ hài hước, vô lý hoặc \"tấu hài\" của phim.",
            "",
            "**FORMAT TRẢ VỀ (CỰC KỲ QUAN TRỌNG, PHẢI THEO ĐÚNG 100%):**",
            "=== CAPTION TÒ MÒ ===",
            "[Nội dung caption 1]",
            "#hashtag #hashtag",
            "",
            "=== CAPTION GIẬT TÍT ===",
            "[Nội dung caption 2]",
            "#hashtag #hashtag",
            "",
            "=== CAPTION HÀI HƯỚC / CÀ KHỊA ===",
            "[Nội dung caption 3]",
            "#hashtag #hashtag"
        ]
        return lines.joined(separator: "\n")
    }
    
    static func thumbnailPrompt(summary: String) -> String {
        let lines = [
            "Mày là designer thumbnail YouTube/TikTok chuyên nghiệp, biết cách tạo text hút mắt.",
            "Dựa vào nội dung phim sau, tạo cho tao text ngắn gọn để làm thumbnail:",
            "**NỘI DUNG PHIM (TÓM TẮT):**",
            summary,
            "",
            "**YÊU CẦU TEXT THUMBNAIL:**",
            "1. ĐỘ DÀI: Tối đa 5 TỪ (words), tuyệt đối không viết dài hơn.",
            "2. Phải shock, gây tò mò.",
            "3. Dùng từ mạnh, có tác động.",
            "",
            "**FORMAT:**",
            "[TEXT DÒNG 1]",
            "[TEXT DÒNG 2] (nếu cần)",
            "Chỉ trả text thôi, không giải thích gì thêm."
        ]
        return lines.joined(separator: "\n")
    }
}