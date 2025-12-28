#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
APP="$ROOT/app.py"

echo "[i] ROOT = $ROOT"
cd "$ROOT"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP" >&2
  exit 1
fi

cp "$APP" "${APP}.bak_dedupe_datasource_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup app.py."

python3 - << 'PY'
from pathlib import Path

path = Path("app.py")
lines = path.read_text(encoding="utf-8").splitlines(keepends=True)

out = []
found_first = False
i = 0
n = len(lines)

while i < n:
    line = lines[i]
    if '"/datasource"' in line.replace("'", '"') and "@app.route" in line:
        if not found_first:
            # giữ lại route /datasource đầu tiên
            found_first = True
            out.append(line)
            i += 1
            continue
        else:
            # comment route /datasource thừa
            base_indent = len(line) - len(line.lstrip(" "))
            print(f"[INFO] Comment extra /datasource route tại line {i+1}")
            # comment decorator + toàn bộ function body tới khi gặp block top-level mới
            while i < n:
                l = lines[i]
                if not l.lstrip().startswith("#"):
                    out.append("# EXTRA_DATASOURCE_REMOVED " + l)
                else:
                    out.append(l)
                i += 1
                if i >= n:
                    break
                nxt = lines[i]
                stripped = nxt.strip()
                indent = len(nxt) - len(nxt.lstrip(" "))
                if (
                    indent <= base_indent
                    and (
                        stripped.startswith("@app.route(")
                        or stripped.startswith("def ")
                        or stripped.startswith("if __name__")
                    )
                ):
                    # dừng ở block mới, đừng nuốt dòng này
                    break
            continue
    else:
        out.append(line)
        i += 1

path.write_text("".join(out), encoding="utf-8")
PY

echo "[DONE] patch_dedupe_datasource_route.sh hoàn thành."
