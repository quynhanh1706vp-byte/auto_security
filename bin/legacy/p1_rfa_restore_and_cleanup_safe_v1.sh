#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

echo "== [1] pick last good backup (py_compile OK) =="
cands=()
while IFS= read -r f; do cands+=("$f"); done < <(ls -1t \
  "${W}.bak_rfa_cleanup_"* \
  "${W}.bak_rfa_wsgimw_v3b_"* \
  "${W}.bak_rfa_wsgimw_v2fix_"* \
  "${W}.bak_rfa_wsgimw_v2_"* \
  "${W}.bak_rfa_wsgimw_"* \
  "${W}.bak_rfa_after_"* \
  2>/dev/null || true)

good=""
tmp="/tmp/wsgi_restore_test_$$.py"
for f in "${cands[@]}"; do
  cp -f "$f" "$tmp" 2>/dev/null || true
  if python3 -m py_compile "$tmp" >/dev/null 2>&1; then
    good="$f"
    break
  fi
done

if [ -z "$good" ]; then
  echo "[ERR] cannot find a compilable backup. You may need to restore manually."
  echo "Candidates were: ${#cands[@]}"
  exit 2
fi

echo "[OK] restore from: $good"
cp -f "$good" "$W"

echo "== [2] safe cleanup: remove V1/V2 blocks; keep V3B; disable DBG/ERR; remove rogue '\\n' lines =="
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_rfa_restore_before_cleanup_${TS}"
echo "[BACKUP] ${W}.bak_rfa_restore_before_cleanup_${TS}"

python3 - "$W" <<'PY'
import sys
from pathlib import Path

p=Path(sys.argv[1])
lines=p.read_text(encoding="utf-8", errors="replace").splitlines(True)

# 1) remove rogue lines that are literally "\n" or "\\n"
def is_rogue(line:str)->bool:
    t=line.strip()
    return t in (r"\n", r"\\n")

lines=[ln for ln in lines if not is_rogue(ln)]

# 2) drop whole blocks by markers (safe, line-based)
drop_tags = [
  "VSP_P0_WSGIGW_RFA_AFTER_REQUEST_PROMOTE_V1",
  "VSP_P0_WSGIGW_RFA_WSGI_MW_PROMOTE_V1",
  "VSP_P0_WSGIGW_RFA_WSGI_MW_PROMOTE_V2_FORCE_DBG",
  "VSP_P0_WSGIGW_RFA_WSGI_MW_PROMOTE_V2_FORCE_DBG_FIX_V1",
]
def drop_block(tag, L):
    start = f"# --- {tag} ---"
    end   = f"# --- /{tag} ---"
    out=[]
    skipping=False
    for ln in L:
        if not skipping and start in ln:
            skipping=True
            continue
        if skipping:
            if end in ln:
                skipping=False
            continue
        out.append(ln)
    return out

for t in drop_tags:
    lines = drop_block(t, lines)

# 3) keep V3B but disable DBG/ERR by commenting those set_header lines (don’t delete)
out=[]
for ln in lines:
    if 'X-VSP-RFA-PROMOTE-DBG' in ln or 'X-VSP-RFA-PROMOTE-ERR' in ln:
        # comment out while preserving indent
        if ln.lstrip().startswith("#"):
            out.append(ln)
        else:
            out.append((" " * (len(ln) - len(ln.lstrip()))) + "# " + ln.lstrip())
    else:
        out.append(ln)

p.write_text("".join(out), encoding="utf-8")
print("[OK] safe cleanup applied")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC" 2>/dev/null || systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted (if service exists)"
