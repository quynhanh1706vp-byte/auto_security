#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_fill_real_data_5tabs_p1_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need cp; need mv; need mktemp
command -v node >/dev/null 2>&1 || { echo "[ERR] missing: node (need node --check)"; exit 2; }

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

BAK="${JS}.bak_p0jsv3_${TS}"
cp -f "$JS" "$BAK"
echo "[BACKUP] $BAK"

TMP="$(mktemp /tmp/vsp_fill_real_data_5tabs_p1_v1.XXXXXX.js)"
trap 'rm -f "$TMP" 2>/dev/null || true' EXIT

python3 - "$JS" "$TMP" <<'PY'
import re, sys

src_path, out_path = sys.argv[1], sys.argv[2]
s = open(src_path, "r", encoding="utf-8", errors="replace").read()
orig = s

# 0) Fix bug kiểu "const = (...)" -> "const rid = (...)"
s, n_const_blank = re.subn(r'(?m)^\s*const\s*=\s*\(', 'const rid = (', s)

# 1) Fix "rid = (...)" (không khai báo) -> "const rid = (...)"
s, n_rid_bare = re.subn(r'(?m)^\s*rid\s*=\s*\(', 'const rid = (', s)

# 2) Inject BASE nếu chưa có
has_base = bool(re.search(r'(?m)^\s*(const|let|var)\s+BASE\s*=', s))
if not has_base:
    inject = (
        "const BASE = (window.__VSP_UI_BASE || window.__VSP_UI_BASE_URL || location.origin);\n"
        "window.__VSP_UI_BASE = BASE;\n"
    )
    m = re.search(r'(?m)^[ \t]*[\'"]use strict[\'"];\s*$', s)
    if m:
        pos = m.end()
        s = s[:pos] + "\n" + inject + s[pos:]
    else:
        s = inject + s

# 3) Nếu code đang gọi /api/vsp/run_file?... gây 404 => đổi sang run_file_allow
# (ít rủi ro nhất: chỉ thay đúng path string)
s = s.replace("/api/vsp/run_file?", "/api/vsp/run_file_allow?")

# 4) Fix nút Open/SHA: đừng link vào run_file(_allow) kiểu directory -> hay dính "not allowed"
# Chuyển Open về trang Runs (UI) luôn cho chắc.
s = re.sub(
    r'href:\s*api\.runFile\(\s*rid\s*,\s*[\'"][^\'"]*[\'"]\s*\)',
    'href: (BASE + "/runs?rid=" + encodeURIComponent(rid))',
    s
)
s = re.sub(
    r'href:\s*api\.sha\(\s*rid\s*,\s*[\'"][^\'"]*[\'"]\s*\)',
    'href: (BASE + "/runs?rid=" + encodeURIComponent(rid) + "#sha")',
    s
)

open(out_path, "w", encoding="utf-8").write(s)

def has(pat, text): return bool(re.search(pat, text))
print("[PATCH] n_const_blank=", n_const_blank,
      "n_rid_bare=", n_rid_bare,
      "injected_BASE=", (not has(r'(?m)^\s*(const|let|var)\s+BASE\s*=', orig)) and has(r'(?m)^\s*(const|let|var)\s+BASE\s*=', s))
PY

echo "== [node --check] =="
node --check "$TMP" >/dev/null
echo "[OK] JS syntax OK"

mv -f "$TMP" "$JS"
echo "[OK] patched: $JS"
echo "[HINT] Reload browser hard (Ctrl+Shift+R) để hết cache."
