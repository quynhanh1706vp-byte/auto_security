from pathlib import Path

path = Path("app.py")
text = path.read_text()

snippet = '''
    # Cập nhật DEFAULT_SRC theo ?src=... để ô SRC trên UI luôn hiển thị last run
    global DEFAULT_SRC
    src_from_query = request.args.get("src")
    if src_from_query:
        DEFAULT_SRC = src_from_query
'''

if snippet not in text:
    print("[WARN] Không tìm thấy snippet cần xóa (có thể đã khác rồi).")
else:
    text = text.replace(snippet, "\n")
    path.write_text(text)
    print("[OK] Đã xóa snippet update DEFAULT_SRC trong index().")
