#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import http.server
import socketserver
import json
import subprocess
import os
import threading
import time
import re
import shlex
import sys
import queue
from math import ceil

# --- BƯỚC 1: CÀI ĐẶT THƯ VIỆN (NẾU CHƯA CÓ) ---
try:
    import google.generativeai as genai
except ImportError:
    print("❌ Thư viện google-generativeai chưa được cài đặt.")
    print("👉 Mở Terminal hoặc Command Prompt, gõ lệnh: pip3 install google-generativeai")
    sys.exit()

# --- BƯỚC 2: CẤU HÌNH API KEY CỦA MÀY ---
API_KEYS = [
    "AIzaSyACi9OiKAOcaZdJaRvlz_lMFBQpzgHhepI",
    "AIzaSyA2jHB9dhzbPhbMbylIQkdgm63UhgLAgvU", 
]

# --- CONFIGURATION ---
DEFAULT_DOWNLOAD_PATH = os.path.expanduser("~/Downloads/dlp")
PORT = 8000

# ==============================================================================
# PHẦN LOGIC DỊCH THUẬT & SÁNG TẠO NỘI DUNG (TỪ SCRIPT CỦA MÀY)
# ==============================================================================

def parse_srt(srt_content):
    if srt_content.startswith('\ufeff'): srt_content = srt_content[1:]
    srt_content = srt_content.replace('\r\n', '\n').strip()
    pattern = re.compile(r'(\d+)\n(\d{2}:\d{2}:\d{2}[,.]\d{1,3}\s*-->\s*\d{2}:\d{2}:\d{2}[,.]\d{1,3})\n([\s\S]+?)(?=\n\n|\Z)', re.MULTILINE)
    return pattern.findall(srt_content)

def parse_capcut_json_to_srt(json_content):
    try:
        data = json.loads(json_content)
        if "materials" not in data or "texts" not in data["materials"]:
             raise ValueError("Không tìm thấy key 'materials' hoặc 'texts' trong file JSON.")

        texts = data["materials"]["texts"]
        srt_lines = []
        
        sorted_texts = sorted(texts, key=lambda x: x.get('start_time', 0))

        for index, text_info in enumerate(sorted_texts):
            content = text_info.get("content", "").strip()
            if not content:
                continue

            start_us = text_info.get("start_time", 0)
            end_us = text_info.get("end_time", 0)

            start_s = start_us / 1_000_000
            end_s = end_us / 1_000_000

            start_time = time.strftime('%H:%M:%S', time.gmtime(start_s)) + f",{int((start_s % 1) * 1000):03d}"
            end_time = time.strftime('%H:%M:%S', time.gmtime(end_s)) + f",{int((end_s % 1) * 1000):03d}"
            
            srt_lines.append(str(index + 1))
            srt_lines.append(f"{start_time} --> {end_time}")
            srt_lines.append(content)
            srt_lines.append("")

        if not srt_lines:
            raise ValueError("Không tìm thấy dữ liệu phụ đề nào trong file CapCut JSON.")
            
        return "\n".join(srt_lines)
    except json.JSONDecodeError:
        raise ValueError("File không phải là định dạng JSON hợp lệ.")
    except Exception as e:
        print(f"Lỗi khi xử lý file CapCut JSON: {e}")
        raise

def count_words(text):
    chinese_chars = len(re.findall(r'[\u4e00-\u9fff]', text))
    vietnamese_words = len(re.findall(r'[a-zA-ZÀ-ỹ]+', text))
    return chinese_chars + vietnamese_words

def get_content_summary(translated_subtitles):
    total_lines = len(translated_subtitles)
    start_section = translated_subtitles[:int(total_lines * 0.3)]
    start_text = " ".join([sub[2] for sub in start_section])
    middle_start = int(total_lines * 0.35)
    middle_end = int(total_lines * 0.65)
    middle_section = translated_subtitles[middle_start:middle_end]
    middle_text = " ".join([sub[2] for sub in middle_section])
    end_start = int(total_lines * 0.7)
    end_section = translated_subtitles[end_start:]
    end_text = " ".join([sub[2] for sub in end_section])
    return {"start": start_text[:500], "middle": middle_text[:500], "end": end_text[:500]}

def generate_caption_and_thumbnail(content_summary):
    caption_prompt = f"""
Mày là một Copywriter chuyên nghiệp, có khả năng viết nhiều style caption khác nhau cho video review phim trên YouTube/TikTok.
Dựa vào nội dung phim được tóm tắt bên dưới, hãy tạo cho tao **3 LỰA CHỌN CAPTION** với 3 phong cách riêng biệt.
**NỘI DUNG PHIM:**
- Phần đầu: {content_summary['start']}
- Phần giữa: {content_summary['middle']}
- Phần cuối: {content_summary['end']}
**YÊU CẦU CHUNG:**
- Mỗi caption phải có hashtag và emoji phù hợp.
- Ngôn ngữ tự nhiên, hấp dẫn, đúng chất GenZ.
**3 PHONG CÁCH BẮT BUỘC MÀY PHẢI VIẾT:**
1.  **CAPTION TÒ MÒ:** Tập trung đặt câu hỏi, tạo ra một bí ẩn lớn.
2.  **CAPTION GIẬT TÍT:** Dùng từ ngữ mạnh, gây sốc, đôi khi hơi "lươn lẹo" để câu view.
3.  **CAPTION HÀI HƯỚC / CÀ KHỊA:** Nhìn vào một góc độ hài hước, vô lý hoặc "tấu hài" của phim.
**FORMAT TRẢ VỀ (CỰC KỲ QUAN TRỌNG, PHẢI THEO ĐÚNG 100%):**
=== CAPTION TÒ MÒ ===
[Nội dung caption 1]
#hashtag #hashtag

=== CAPTION GIẬT TÍT ===
[Nội dung caption 2]
#hashtag #hashtag

=== CAPTION HÀI HƯỚC / CÀ KHỊA ===
[Nội dung caption 3]
#hashtag #hashtag
"""
    thumbnail_prompt = f"""
Mày là designer thumbnail YouTube/TikTok chuyên nghiệp, biết cách tạo text hút mắt.
Dựa vào nội dung phim sau, tạo cho tao text ngắn gọn để làm thumbnail:
**NỘI DUNG PHIM:**
- Phần đầu: {content_summary['start']}
- Phần giữa: {content_summary['middle']}
- Phần cuối: {content_summary['end']}
**YÊU CẦU TEXT THUMBNAIL:**
1. ĐỘ DÀI: Tối đa 5 TỪ (words), tuyệt đối không viết dài hơn.
2. Phải shock, gây tò mò.
3. Dùng từ mạnh, có tác động.
**FORMAT:**
[TEXT DÒNG 1]
[TEXT DÒNG 2] (nếu cần)
Chỉ trả text thôi, không giải thích gì thêm.
"""
    try:
        genai.configure(api_key=API_KEYS[0])
        model = genai.GenerativeModel('gemini-1.5-flash')
        caption_response = model.generate_content(caption_prompt, request_options={'timeout': 180})
        caption_text = caption_response.text.strip()
        thumbnail_response = model.generate_content(thumbnail_prompt, request_options={'timeout': 120})
        thumbnail_text = thumbnail_response.text.strip()
        return caption_text, thumbnail_text
    except Exception as e:
        return f"Tạo caption lỗi: {e}", "PHIM HAY"

def get_translation_prompt(is_intro=False):
    if is_intro:
        return """
Mày là Biên Kịch Mặn Mòi của kênh Đầy Bụng Review, một bậc thầy giật tít chuyên viết kịch bản intro. Nhiệm vụ của mày là biến một đoạn kịch bản gốc nhàm chán thành một cái intro 30 giây có cái hook BÉN NHƯ DAO CẠO, khiến người xem phải dừng lại ngay lập tức.
⚠️ LUẬT VÀNG PHẢI THEO:
1.  **Dịch Thoát Ý & Sáng Tạo:** Bịa thêm thắt thoải mái để tạo sự hài hước, bất ngờ.
2.  **TẠO HOOK CỰC MẠNH:** Vài câu đầu tiên phải đặt ra một vấn đề gây sốc, một câu hỏi lớn, hoặc một lời cà khịa thông minh.
3.  **CÀI CẮM THƯƠNG HIỆU:** Trong khoảng 50 dòng đầu, phải khéo léo nhét tên kênh "**Đầy Bụng Review**" vào một cách tự nhiên. Cấm giả trân.
4.  **SIÊU LUẬT VỀ ĐỘ DÀI (CẤM CÃI):** Câu dịch tiếng Việt PHẢI có số từ ÍT HƠN hoặc BẰNG câu gốc.
5.  **Xưng Hô Thân Thiện:** Dùng "tao - mày", "tui - mấy bà", "anh em mình".
6.  **Giữ Format SRT:** Giữ nguyên cấu trúc [Số] - [Timestamp] - [Câu dịch 1 dòng].
"""
    else:
        return """
Mày là một Biên Kịch Chính có duyên, chuyên viết lời thoại cho video YouTube của kênh Đầy Bụng Review.
⚠️ LUẬT VÀNG PHẢI THEO:
1.  **XÂY DỰNG CÁ TÍNH:** Tạo ra một "cá tính" nhất quán cho người dịch/lồng tiếng (lạc quan tếu, 'ông cụ non', bạn thân nhiều chuyện...).
2.  **Kể Chuyện Có Nhịp Điệu:** Phải biết lúc nào cần tấu hài, lúc nào cần sâu lắng để đẩy cảm xúc.
3.  **SIÊU LUẬT VỀ ĐỘ DÀI (CẤM CÃI):** Câu dịch tiếng Việt PHẢI có số từ ÍT HƠN hoặc BẰNG câu gốc.
4.  **Bình Luận Duyên Dáng:** Thỉnh thoảng chèn thêm những câu bình luận ngắn gọn, hài hước.
5.  **Giữ Format SRT:** Giữ nguyên cấu trúc [Số] - [Timestamp] - [Câu dịch 1 dòng].
"""

def translate_text(model_instance, text_to_translate, is_batch=False, num_items=1, is_intro=False, previous_context=None):
    if is_batch:
        indexed_texts = [f"[{i+1}] {text.replace(chr(10), ' ').strip()} (Số từ gốc: {count_words(text)})" for i, text in enumerate(text_to_translate)]
        joined_text = "\n".join(indexed_texts)
        prompt_body = f"Văn bản cần dịch:\n---\n{joined_text}\n---"
    else:
        processed_text = text_to_translate.replace('\n', ' ').strip()
        word_count = count_words(processed_text)
        prompt_body = f"Câu cần dịch:\n---\n{processed_text} (Số từ gốc: {word_count})\n---"
    
    prompt_template = get_translation_prompt(is_intro)
    context_prompt = f"<ngu_canh>\n{previous_context}\n</ngu_canh>\n\n" if previous_context else ""
    full_prompt = f"""{prompt_template}\n\n{context_prompt}**QUY TẮC ĐỊNH DẠNG (BẮT BUỘC):**\n- Mày PHẢI trả lời bằng một danh sách được đánh số y hệt như mày đã nhận (nếu có).\n- Ví dụ: Nếu nhận "[1] text1\\n[2] text2", mày phải trả lời "[1] dịch_câu_1\\n[2] dịch_câu_2".\n- TUYỆT ĐỐI không thêm bất kỳ ký tự nào khác.\n- Không được ghi số từ hoặc ghi chú gì thêm.\n\n{prompt_body}"""
    
    response = model_instance.generate_content(full_prompt, request_options={'timeout': 180})
    if not response.parts: raise ValueError(f"AI từ chối dịch. Lý do: {getattr(response.prompt_feedback, 'block_reason', 'Không rõ')}")
    
    raw_text = response.text.strip()
    
    if is_batch:
        pattern = re.compile(r'\[(\d+)\]\s*(.*)')
        matches = pattern.findall(raw_text)
        
        translated_dict = {}
        for match in matches:
            index = int(match[0])
            text_content = match[1].strip()
            # Dọn dẹp mạnh tay hơn
            cleaned_text = re.sub(r'^\d{1,2}:\d{2}:\d{2}[,.]\d{1,3}\s*-->\s*\d{1,2}:\d{2}:\d{2}[,.]\d{1,3}\s*', '', text_content).strip()
            cleaned_text = re.sub(r'^\d{1,2}:\d{2}:\d{2}\s*', '', cleaned_text).strip()
            cleaned_text = re.sub(r'^\d+\s', '', cleaned_text).strip()
            translated_dict[index] = cleaned_text

        if len(translated_dict) == num_items:
            return [translated_dict.get(i + 1, "") for i in range(num_items)]
        else:
            lines = raw_text.split('\n')
            lines = [re.sub(r'^\[?\d+\]?\.?\s*', '', line).strip() for line in lines if line.strip()]
            if len(lines) == num_items:
                return lines
            raise ValueError(f"AI trả về sai số lượng dòng ({len(translated_dict)} vs {num_items}). Raw: {raw_text}")
    else:
        return [raw_text]

def shorten_text_aggressively(model_instance, original_text, long_translation, max_attempts=3):
    original_word_count = count_words(original_text)
    current_translation = long_translation
    for attempt in range(max_attempts):
        current_word_count = count_words(current_translation)
        if current_word_count <= original_word_count: return current_translation
        
        shorten_prompt = f"""Rút gọn câu dịch sau cho số từ ≤ {original_word_count} từ mà vẫn giữ ý chính.
- Câu gốc (tiếng Trung): "{original_text}" ({original_word_count} từ)
- Câu dịch hiện tại: "{current_translation}" ({current_word_count} từ)
Chỉ trả về câu đã rút gọn, không giải thích:"""
        try:
            response = model_instance.generate_content(shorten_prompt, request_options={'timeout': 60})
            if not response.parts: break
            current_translation = response.text.strip()
        except Exception: break
    
    if count_words(current_translation) > original_word_count:
        words = current_translation.split()
        if len(words) > original_word_count: current_translation = ' '.join(words[:original_word_count])
    return current_translation

class ProgressTracker:
    def __init__(self, total_items, task_dict, task_id):
        self.total = total_items; self.count = 0; self.lock = threading.Lock()
        self.task_dict = task_dict; self.task_id = task_id
    def update(self, num_items=1):
        with self.lock:
            self.count += num_items
            percentage = (self.count / self.total) * 100
            self.task_dict[self.task_id]['progress'] = percentage
            self.task_dict[self.task_id]['status_text'] = f"Đang dịch... {self.count}/{self.total}"

def translation_worker(thread_id, task_queue, results_dict, lock, progress_tracker):
    key_index = thread_id
    previous_batch_context = None
    while not task_queue.empty():
        try:
            batch_num, batch = task_queue.get_nowait()
            original_texts = [sub[2] for sub in batch]
            translated_texts = None
            is_intro_batch = (batch_num == 1)
            
            model = None
            for attempt in range(2):
                try:
                    api_key_to_use = API_KEYS[key_index % len(API_KEYS)]
                    genai.configure(api_key=api_key_to_use)
                    model = genai.GenerativeModel('gemini-1.5-flash')
                    translated_texts = translate_text(model, original_texts, is_batch=True, num_items=len(original_texts), is_intro=is_intro_batch, previous_context=previous_batch_context)
                    if translated_texts and len(translated_texts) == len(original_texts): break
                    else: raise ValueError("Số lượng dòng trả về không khớp.")
                except Exception as e:
                    print(f"Lỗi luồng #{thread_id}, lô {batch_num}: {e}. Đổi key và thử lại...")
                    key_index += 1
                    if attempt == 1: translated_texts = None

            previous_batch_context = " ".join(original_texts)
            if translated_texts is None: translated_texts = ["LỖI DỊCH"] * len(original_texts)

            final_texts = []
            if model:
                for i, translated_line in enumerate(translated_texts):
                    original_line = original_texts[i]
                    if count_words(translated_line) > count_words(original_line):
                        shortened_line = shorten_text_aggressively(model, original_line, translated_line)
                        final_texts.append(shortened_line)
                    else:
                        final_texts.append(translated_line)
            else:
                final_texts = translated_texts

            with lock:
                for j, sub in enumerate(batch):
                    results_dict[int(sub[0])] = (sub[1], final_texts[j])
                progress_tracker.update(len(batch))
            task_queue.task_done()
        except queue.Empty: break
        except Exception as e: print(f"Lỗi không xác định trong luồng #{thread_id}: {e}"); break

# ==============================================================================
# HTTP SERVER LOGIC
# ==============================================================================

class YouTubeDownloaderHandler(http.server.SimpleHTTPRequestHandler):
    download_tasks = {}
    translation_tasks = {}

    def do_GET(self):
        if self.path == '/health':
            self._send_json_response({'status': 'ok'})
            return
        if self.path == '/': self.path = '/index.html'
        return http.server.SimpleHTTPRequestHandler.do_GET(self)

    def do_OPTIONS(self):
        self.send_response(200, "ok")
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, GET, OPTIONS')
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)
        try: data = json.loads(post_data.decode('utf-8'))
        except json.JSONDecodeError: self._send_json_response({'success': False, 'error': 'Invalid JSON'}, status_code=400); return

        if self.path == '/download': self.handle_download_request(data)
        elif self.path == '/progress': self.handle_progress_request(data)
        elif self.path == '/info': self.handle_info_request(data)
        elif self.path == '/super-translate': self.handle_super_translate_request(data)
        elif self.path == '/super-translate-progress': self.handle_super_translate_progress(data)
        elif self.path == '/context-translate': self.handle_context_translate_request(data)
        else: self._send_json_response({'success': False, 'error': 'Endpoint not found'}, status_code=404)

    def handle_context_translate_request(self, data):
        content = data.get('content')
        # Dummy response for now
        response = {"success": True, "translated_content": content}
        self._send_json_response(response)

    def _send_json_response(self, data, status_code=200):
        self.send_response(status_code)
        self.send_header('Content-type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode('utf-8'))

    def handle_download_request(self, data):
        url = data.get('url')
        if not url: self._send_json_response({'success': False, 'error': 'URL is required'}, status_code=400); return
        download_id = str(int(time.time() * 1000))
        self.download_tasks[download_id] = {'status': 'starting', 'progress': 0}
        thread = threading.Thread(target=self._execute_download, args=(download_id, data))
        thread.daemon = True; thread.start()
        self._send_json_response({'success': True, 'download_id': download_id})

    def handle_progress_request(self, data):
        download_id = data.get('download_id')
        progress_info = self.download_tasks.get(download_id, {'status': 'not_found'})
        self._send_json_response(progress_info)

    def handle_info_request(self, data):
        url = data.get('url')
        if not url: self._send_json_response({'success': False, 'error': 'URL is required'}, status_code=400); return
        try:
            cmd = ['yt-dlp', '--dump-json', '--no-playlist', url]
            result = subprocess.run(cmd, capture_output=True, text=True, check=True, encoding='utf-8')
            info = json.loads(result.stdout)
            response_data = {'title': info.get('title', 'N/A'), 'uploader': info.get('uploader', 'N/A'), 'duration': info.get('duration', 0), 'view_count': info.get('view_count', 0)}
            self._send_json_response({'success': True, 'data': response_data})
        except Exception as e: self._send_json_response({'success': False, 'error': str(e)}, status_code=500)

    def _execute_download(self, download_id, data):
        url = data.get('url'); quality = data.get('quality', 'best'); save_path = data.get('save_path', DEFAULT_DOWNLOAD_PATH); options = data.get('options', {})
        os.makedirs(save_path, exist_ok=True)
        try:
            cmd = ['yt-dlp', '-P', save_path, '--merge-output-format', 'mp4', '--progress']
            if quality == 'audio': cmd.extend(['-x', '--audio-format', 'mp3'])
            elif quality != 'best': cmd.extend(['-f', f"bv[height<=?{quality.replace('p', '')}][vcodec^=avc1]+ba/b[height<=?{quality.replace('p', '')}]/best"])
            if options.get('subtitles'): cmd.extend(['--write-subs', '--all-subs'])
            if options.get('thumbnail'): cmd.append('--write-thumbnail')
            if options.get('metadata'): cmd.append('--add-metadata')
            if options.get('playlist'): cmd.append('--yes-playlist')
            else: cmd.append('--no-playlist')
            cmd.append(url)
            self.download_tasks[download_id].update({'status': 'downloading'})
            process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8', bufsize=1)
            full_output = []
            for line in iter(process.stdout.readline, ''):
                clean_line = line.strip()
                full_output.append(clean_line)
                self._parse_progress(clean_line, download_id)
            process.stdout.close()
            if process.wait() == 0: self.download_tasks[download_id].update({'status': 'finished', 'progress': 100})
            else: 
                error_line = next((l for l in reversed(full_output) if 'error' in l.lower()), "Process failed")
                raise RuntimeError(error_line)
        except Exception as e: self.download_tasks[download_id].update({'status': 'error', 'error': str(e)})

    def _parse_progress(self, line, download_id):
        task = self.download_tasks.get(download_id)
        if not task: return
        if '[download]' in line and '%' in line:
            match = re.search(r'(\d+\.\d+)% of\s+(?:~)?([\d.]+[KMGTP]iB)\s+at\s+(.*?)\s+ETA\s+(.*)', line)
            if match: task.update({'progress': float(match.group(1)), 'size': match.group(2).strip(), 'speed': match.group(3).strip(), 'eta': match.group(4).strip()})
        elif 'Destination:' in line: task['filename'] = os.path.basename(line.split('Destination:')[-1].strip())
        elif 'Merging formats into' in line: task['status'] = 'processing'

    def handle_super_translate_request(self, data):
        content = data.get('content')
        is_json = data.get('is_json', False)
        
        if not content: self._send_json_response({'success': False, 'error': 'Content is required'}, status_code=400); return
        
        cleaned_keys = [key for key in API_KEYS if "YOUR_API_KEY" not in key]
        if not cleaned_keys: self._send_json_response({'success': False, 'error': 'Chưa điền API Key trong file server.py'}, status_code=500); return

        try:
            if is_json:
                srt_text = parse_capcut_json_to_srt(content)
            else:
                srt_text = content
        except Exception as e:
            self._send_json_response({'success': False, 'error': f"Lỗi xử lý file: {e}"}, status_code=400)
            return

        task_id = str(int(time.time() * 1000))
        self.translation_tasks[task_id] = {'status': 'starting', 'progress': 0, 'status_text': 'Bắt đầu...'}
        
        thread = threading.Thread(target=self._execute_super_translation, args=(task_id, srt_text, cleaned_keys))
        thread.daemon = True; thread.start()
        self._send_json_response({'success': True, 'task_id': task_id})

    def handle_super_translate_progress(self, data):
        task_id = data.get('task_id')
        progress_info = self.translation_tasks.get(task_id, {'status': 'not_found'})
        self._send_json_response(progress_info)

    def _execute_super_translation(self, task_id, srt_text, api_keys):
        try:
            subtitles = parse_srt(srt_text)
            if not subtitles: raise ValueError("Không đọc được file SRT. Định dạng có thể bị lỗi.")
            task_queue = queue.Queue()
            BATCH_SIZE = 15
            total_batches = ceil(len(subtitles) / BATCH_SIZE)
            for i in range(total_batches):
                task_queue.put((i + 1, subtitles[i * BATCH_SIZE:(i + 1) * BATCH_SIZE]))
            results_dict = {}; lock = threading.Lock(); threads = []
            num_threads = len(api_keys)
            progress_tracker = ProgressTracker(len(subtitles), self.translation_tasks, task_id)
            self.translation_tasks[task_id]['status_text'] = f"Chạy {num_threads} luồng dịch..."
            for i in range(num_threads):
                thread = threading.Thread(target=translation_worker, args=(i, task_queue, results_dict, lock, progress_tracker))
                threads.append(thread); thread.start()
            for thread in threads: thread.join()
            self.translation_tasks[task_id]['status_text'] = "Đang ghép file..."
            final_srt_content = ""
            translated_subtitles = []
            for index in sorted(results_dict.keys()):
                timestamp, text = results_dict[index]
                final_srt_content += f"{index}\n{timestamp.replace('.', ',')}\n{text.strip()}\n\n"
                translated_subtitles.append((index, timestamp, text))
            self.translation_tasks[task_id]['status_text'] = "Đang tạo caption..."
            content_summary = get_content_summary(translated_subtitles)
            raw_caption_text, thumbnail_text = generate_caption_and_thumbnail(content_summary)
            prefix = "(Full Version) "; suffix = " - Mắm rieview"
            branded_captions_list = []
            for block in raw_caption_text.split('==='):
                if not block.strip(): continue
                lines = block.strip().split('\n')
                title = "=== " + lines[0]
                content = lines[1] if len(lines) > 1 else ""
                hashtags = '\n'.join(lines[2:]) if len(lines) > 2 else ""
                branded_content = f"{prefix}{content}{suffix}"
                full_block = f"{title}\n{branded_content}"
                if hashtags: full_block += f"\n{hashtags}"
                branded_captions_list.append(full_block)
            final_caption_text = "\n\n".join(branded_captions_list)
            self.translation_tasks[task_id].update({
                'status': 'finished', 'progress': 100, 'status_text': 'Hoàn thành!',
                'translated_srt': final_srt_content, 'captions': final_caption_text,
                'thumbnail_text': thumbnail_text
            })
        except Exception as e:
            print(f"Lỗi khi thực thi Super Translate: {e}")
            self.translation_tasks[task_id].update({'status': 'error', 'error': str(e)})


if __name__ == '__main__':
    cleaned_keys = [key for key in API_KEYS if "YOUR_API_KEY" not in key]
    if not cleaned_keys:
        print("❌ Mày chưa điền API Key. Tìm danh sách 'API_KEYS' trong code và dán key của mày vào.")
        sys.exit()
    print(f"✅ Đã nhận {len(cleaned_keys)} API Key. Sẵn sàng chiến đấu.")
    try:
        os.chdir(os.path.dirname(os.path.abspath(__file__)))
        with socketserver.TCPServer(("", PORT), YouTubeDownloaderHandler) as httpd:
            print("="*50)
            print(f"🚀 Server đã sẵn sàng!")
            print(f"   Mở trình duyệt và truy cập: http://localhost:{PORT}")
            print(f"📂 Tải về mặc định tại: {DEFAULT_DOWNLOAD_PATH}")
            print("   Nhấn Ctrl+C để dừng server.")
            print("="*50)
            httpd.serve_forever()
    except OSError as e:
        print(f"💥 LỖI: Không thể khởi động server ở cổng {PORT}. Cổng này đang được dùng?")
        print(f"   Chi tiết: {e}")
    except KeyboardInterrupt:
        print("\n👋 Server đã dừng. Tạm biệt!")
