#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed; need curl

TS="$(date +%Y%m%d_%H%M%S)"

echo "== locate backend python containing run_file_allow allowlist =="
# ưu tiên các file runtime thật; né out_ci và bin/
CANDS=()
while IFS= read -r f; do CANDS+=("$f"); done < <(
  grep -RIl --exclude='*.bak_*' --exclude-dir='out_ci' --exclude-dir='bin' --include='*.py' \
    -e "run_file_allow" -e "/api/vsp/run_file_allow" -e "VSP_RUN_FILE_ALLOW" . 2>/dev/null | sort -u
)

if [ "${#CANDS[@]}" -eq 0 ]; then
  echo "[ERR] cannot find python files mentioning run_file_allow"
  exit 2
fi

# chọn file “có vẻ” chứa allowlist (dựa trên dấu hiệu string reports/findings_unified.csv hoặc '"allow": [')
TARGET=""
for f in "${CANDS[@]}"; do
  if grep -q "reports/findings_unified.csv" "$f" || grep -q "\"allow\"\\s*:\\s*\\[" "$f"; then
    TARGET="$f"; break
  fi
done
# fallback: file đầu tiên
[ -n "$TARGET" ] || TARGET="${CANDS[0]}"

[ -f "$TARGET" ] || { echo "[ERR] missing $TARGET"; exit 2; }
cp -f "$TARGET" "${TARGET}.bak_gate_allow_strict_${TS}"
echo "[BACKUP] ${TARGET}.bak_gate_allow_strict_${TS}"
echo "[INFO] patch target: $TARGET"

python3 - "$TARGET" <<'PY'
import sys, re
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P1_RUN_FILE_ALLOW_GATE_ALLOWLIST_AND_STRICT_V1"
if marker in s:
    print("[OK] already patched:", p)
    sys.exit(0)

gate_entries = [
    "run_gate_summary.json",
    "run_gate.json",
    "reports/run_gate_summary.json",
    "reports/run_gate.json",
]

def inject_allowlist(text: str) -> tuple[str,int]:
    n_total = 0
    # case A: ALLOW = [...] or ALLOWED = set([...]) containing reports/findings_unified.csv
    def _inject_after_anchor(anchor_pat: str, text: str) -> tuple[str,int]:
        nonlocal n_total
        # find an anchor string inside a list/set literal; add missing gate entries right after anchor line
        lines = text.splitlines(True)
        out=[]
        injected=False
        for ln in lines:
            out.append(ln)
            if (not injected) and re.search(anchor_pat, ln):
                # check if any gate entry already exists in whole file
                missing=[g for g in gate_entries if g not in text]
                if missing:
                    for g in missing:
                        out.append(re.sub(r'(\S.*)$', r'\1', ""))  # no-op
                        out.append(f'    "{g}",\n')
                    injected=True
                    n_total += len(missing)
        return ("".join(out), (1 if injected else 0))

    # try anchor: reports/findings_unified.csv
    t2, ok = _inject_after_anchor(r'"reports/findings_unified\.csv"', text)
    text = t2

    # case B: allowlist is returned directly in 403 response dict: {"allow":[...]}
    # inject into the literal array if present
    if n_total == 0:
        m = re.search(r'("allow"\s*:\s*\[)([^\]]*)(\])', text, flags=re.S)
        if m:
            body = m.group(2)
            for g in gate_entries:
                if g not in body:
                    body = body.rstrip() + ("" if body.rstrip().endswith(",") or body.strip()=="" else ",") + f'\n    "{g}",'
                    n_total += 1
            text = text[:m.start(2)] + body + text[m.end(2):]

    return text, n_total

s2, n_ins = inject_allowlist(s)

# strict: nếu backend có fallback SUMMARY cho json gate, chặn riêng cho gate-json
# (patch “nhẹ” dựa trên heuristics: tìm đoạn set fallback_path="SUMMARY.txt" hoặc header X-VSP-Fallback-Path)
if "X-VSP-Fallback-Path" in s2 or "SUMMARY.txt" in s2:
    # chèn guard ở đầu hàm run_file_allow nếu thấy def run_file_allow(
    m = re.search(r'\ndef\s+run_file_allow\s*\(', s2)
    if m:
        # tìm vị trí sau dòng def ...: và sau vài dòng đầu (docstring optional)
        start = m.start()
        # tìm block indent đầu tiên sau def
        head_end = s2.find("\n", m.end())
        insert_at = head_end + 1
        guard = f'''  # {marker}
  _gate_strict_paths = {set(gate_entries)!r}
  try:
    _req_path = (path or "").strip()
  except Exception:
    _req_path = ""
  _is_gate_json = _req_path in _gate_strict_paths
'''
        if marker not in s2:
            s2 = s2[:insert_at] + guard + s2[insert_at:]

        # tắt fallback nếu có biến/flag allow_fallback/fallback_ok
        s2 = re.sub(r'(\n\s*)(allow_fallback|fallback_ok)\s*=\s*True\b',
                    r'\1\2 = (False if _is_gate_json else True)', s2, count=1)
        # hoặc nếu có đoạn “if not found: fallback to SUMMARY.txt” thì bọc điều kiện
        s2 = re.sub(r'(\n\s*if\s+)([^:\n]+)(:\s*\n\s*#?\s*fallback[^\\n]*SUMMARY\.txt)',
                    r'\1(_is_gate_json is False and (\2))\3', s2, count=1)

# add top marker comment
s2 = s2.replace("\n", f"\n# {marker}\n", 1)

p.write_text(s2, encoding="utf-8")
print(f"[OK] patched {p}: allow_inserts={n_ins}")
PY

echo "== py_compile =="
python3 -m py_compile "$TARGET"

echo "== restart 8910 =="
sudo systemctl restart vsp-ui-8910.service || true
sleep 0.8

echo "== detect latest RID =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
print(j["items"][0]["run_id"])
PY
)"
echo "[RID]=$RID"

echo "== verify gate paths via run_file_allow (expect 200 JSON, NOT 403/404, NOT text/plain) =="
for p in run_gate_summary.json reports/run_gate_summary.json run_gate.json reports/run_gate.json; do
  echo "-- $p"
  curl -sS -D /tmp/h -o /tmp/b -w "[HTTP]=%{http_code} [SIZE]=%{size_download}\n" \
    "$BASE/api/vsp/run_file_allow?rid=$RID&path=$p" || echo "[curl rc=$?]"
  grep -iE 'HTTP/|Content-Type|X-VSP-Fallback-Path' /tmp/h | sed 's/\r$//'
  head -c 140 /tmp/b; echo; echo
done

echo "[DONE] HARD refresh /vsp5 (Ctrl+Shift+R)"
