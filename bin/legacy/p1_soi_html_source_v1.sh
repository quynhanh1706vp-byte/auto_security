#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need grep; need find; need sed; need awk; need sha256sum

BASE="http://127.0.0.1:8910"
WSGI="wsgi_vsp_ui_gateway.py"
NAME="vsp_5tabs_enterprise_v2.html"

tmp="/tmp/vsp_soi_html_$$"
mkdir -p "$tmp"

echo "== [A] Fetch raw HTML from /vsp5 and hash =="
curl -fsS "$BASE/vsp5" -o "$tmp/vsp5.html"
echo "[INFO] vsp5.html bytes=$(wc -c < "$tmp/vsp5.html") sha256=$(sha256sum "$tmp/vsp5.html" | awk '{print $1}')"
echo "--- head(40) ---"
sed -n '1,40p' "$tmp/vsp5.html"
echo "--- marker grep ---"
grep -nE 'data-testid="kpi_|id="vsp-(runs|data-source|settings|rule-overrides)-main"' "$tmp/vsp5.html" || echo "[INFO] (no required markers in response)"

echo
echo "== [B] Find all copies of $NAME and show whether they contain markers =="
find . -type f -name "$NAME" ! -path './.venv/*' ! -path './node_modules/*' ! -name '*.bak_*' ! -name '*.bak_markers_*' \
| sort | while read -r f; do
  has_kpi="$(grep -q 'data-testid="kpi_total"' "$f" && echo YES || echo NO)"
  has_runs="$(grep -q 'id="vsp-runs-main"' "$f" && echo YES || echo NO)"
  echo "[TPL] $f  kpi_total=$has_kpi  runs_main=$has_runs  sha256=$(sha256sum "$f" | awk '{print $1}')"
done

echo
echo "== [C] Try to locate the response source by searching a unique snippet in repo =="
python3 - "$tmp/vsp5.html" <<'PY'
import re, sys
html=open(sys.argv[1],encoding="utf-8",errors="replace").read()
# pick a stable snippet: title or first script src or first h1
m = re.search(r'<title>\s*([^<]{6,80})\s*</title>', html, re.I)
snippet = m.group(1) if m else None
if not snippet:
    m = re.search(r'<script[^>]+src="([^"]{10,120})"', html, re.I)
    snippet = m.group(1) if m else None
if not snippet:
    # fallback: any long-ish line
    for line in html.splitlines():
        if len(line.strip())>40 and "<" in line:
            snippet=line.strip()[:80]
            break
print(snippet or "")
PY
SNIP="$(tail -n 1 "$tmp/vsp5.html" 2>/dev/null || true)"
SNIP="$(python3 - <<'PY'
import re
html=open("/tmp/vsp_soi_html_%d/vsp5.html"%__import__("os").getpid(),encoding="utf-8",errors="replace").read()
m=re.search(r'<title>\s*([^<]{6,80})\s*</title>', html, re.I)
if m: print(m.group(1)); raise SystemExit
m=re.search(r'<script[^>]+src="([^"]{10,120})"', html, re.I)
if m: print(m.group(1)); raise SystemExit
for line in html.splitlines():
    t=line.strip()
    if len(t)>50 and "<" in t:
        print(t[:80]); break
PY
)"
echo "[INFO] snippet_for_grep=$SNIP"
if [ -n "$SNIP" ]; then
  echo "[INFO] grep -R (first 60 chars)"
  echo "$SNIP" | head -c 60; echo
  grep -RIn --line-number --exclude-dir '.venv' --exclude-dir 'node_modules' --exclude='*.bak_*' --exclude='*.bak_markers_*' \
    "$(echo "$SNIP" | head -c 60)" . | head -n 60 || true
fi

echo
echo "== [D] Show how Flask template folder/loader is configured in WSGI =="
grep -nE 'Flask\(|template_folder=|jinja_loader|ChoiceLoader|FileSystemLoader|PackageLoader|render_template\(' "$WSGI" | head -n 140 || true

echo
echo "== [E] Check for HOT CACHE / HTML cache middleware clues =="
grep -nEi 'hot_cache|cache|cached|memo|etag|if-none-match|304|last_modified' "$WSGI" | head -n 200 || true

echo
echo "[DONE] If you paste sections [D] and a few lines from [E], we can patch the *real* source (or disable cache) in 1 step."
