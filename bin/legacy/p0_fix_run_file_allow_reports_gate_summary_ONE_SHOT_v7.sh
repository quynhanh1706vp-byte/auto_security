#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="vsp-ui-8910.service"
W="wsgi_vsp_ui_gateway.py"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_runfileallow_gate_v7_${TS}"
echo "[BACKUP] ${W}.bak_runfileallow_gate_v7_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Chỉ patch các ALLOW list/set đúng “family” run_file_allow:
# phải có run_gate_summary.json + findings_unified.json (match đúng allowlist bạn thấy trong response 403)
tok_a = "run_gate_summary.json"
tok_b = "findings_unified.json"
need_add = "reports/run_gate_summary.json"

pat = re.compile(r'(?ms)^[ \t]*ALLOW\s*=\s*(\{.*?\}|\[.*?\])', re.M)

changed_blocks = 0
added = 0

def add_item(block: str) -> str:
    global added
    if tok_a not in block or tok_b not in block:
        return block
    if need_add in block:
        return block

    # detect quote style
    q = '"' if '"' + tok_a + '"' in block else "'"
    ins = f'{q}{need_add}{q},'

    # insert right after run_gate_summary.json (first occurrence)
    block2, n = re.subn(
        rf'({re.escape(q)}{re.escape(tok_a)}{re.escape(q)}\s*,\s*)',
        r'\1        ' + ins + '\n',
        block,
        count=1
    )
    if n == 0:
        # fallback: insert before closing brace/bracket
        block2, n2 = re.subn(r'(\n\s*[}\]])', f'\n        {ins}\n\\1', block, count=1)
        block2 = block2

    if block2 != block:
        added += 1
    return block2

def repl(m: re.Match) -> str:
    global changed_blocks
    block = m.group(0)
    block2 = add_item(block)
    if block2 != block:
        changed_blocks += 1
    return block2

s2 = pat.sub(repl, s)

if s2 == s:
    print("[WARN] no ALLOW=... blocks changed. We'll still continue (maybe ALLOW named differently).")
else:
    p.write_text(s2, encoding="utf-8")
    print(f"[OK] patched ALLOW blocks: changed_blocks={changed_blocks} added_items={added}")
PY

echo "== py_compile =="
python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" || true
sleep 0.8

echo "== sanity =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j["items"][0]["run_id"])')"
echo "[RID]=$RID"

# Expect: 200 OK (hoặc 404 nếu file thiếu), nhưng KHÔNG được 403 not allowed
STATUS="$(curl -sS -o /tmp/_runfileallow_resp.txt -w "%{http_code}" \
  "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" || true)"
echo "[HTTP]=$STATUS"
head -c 240 /tmp/_runfileallow_resp.txt; echo

if [ "$STATUS" = "403" ]; then
  echo "[ERR] still 403. Dump allowlist returned:"
  cat /tmp/_runfileallow_resp.txt | python3 -c 'import sys,json; j=json.load(sys.stdin); print("\n".join(j.get("allow",[])))' || true
  exit 3
fi

echo "[DONE] Hard reload /runs (Ctrl+Shift+R). 403 spam should stop."
