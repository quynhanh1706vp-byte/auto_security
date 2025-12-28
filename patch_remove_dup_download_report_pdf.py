import pathlib, sys

path = pathlib.Path("app.py")
txt = path.read_text(encoding="utf-8")
lines = txt.splitlines(keepends=True)

out = []
seen = 0
i = 0
n = len(lines)

def indent_of(s: str) -> int:
    return len(s) - len(s.lstrip(" \t"))

while i < n:
    line = lines[i]
    if "def download_report_pdf" in line:
        seen += 1
        if seen == 2:
            # Comment decorator ngay phía trên (nếu có)
            j = len(out) - 1
            while j >= 0 and out[j].strip() == "":
                j -= 1
            if j >= 0 and out[j].lstrip().startswith("@app.route") and "report/<run_id>/pdf" in out[j]:
                out[j] = "# " + out[j]

            base_indent = indent_of(line)
            out.append("# " + line)  # comment dòng def

            i += 1
            # Comment toàn bộ thân hàm cho tới khi ra khỏi block
            while i < n:
                ln = lines[i]
                if ln.strip() == "":
                    out.append("# " + ln)
                    i += 1
                    continue
                ind = indent_of(ln)
                if ind <= base_indent and (ln.lstrip().startswith("def ") or ln.lstrip().startswith("@app.route")):
                    break
                out.append("# " + ln)
                i += 1
            continue
    out.append(line)
    i += 1

path.write_text("".join(out), encoding="utf-8")
print("[OK] Đã comment bỏ bản thứ 2 của download_report_pdf (nếu có).")
