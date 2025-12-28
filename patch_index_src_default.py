from pathlib import Path

path = Path("app.py")
text = path.read_text()

marker = "def index("
i = text.find(marker)
if i == -1:
    print("[ERR] Không tìm thấy def index trong app.py")
    raise SystemExit(1)

line_end = text.find("\n", i)

insert = '''
    # Cập nhật DEFAULT_SRC theo ?src=... để ô SRC trên UI luôn hiển thị last run
    global DEFAULT_SRC
    src_from_query = request.args.get("src")
    if src_from_query:
        DEFAULT_SRC = src_from_query
'''

new_text = text[:line_end + 1] + insert + text[line_end + 1:]
path.write_text(new_text)
print("[OK] Đã chèn logic update DEFAULT_SRC trong index().")
