#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep; need sed; need find; need ls

APP="vsp_demo_app.py"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_rundirfix_${TS}"
echo "[BACKUP] ${APP}.bak_rundirfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

helper_marker = "VSP_P1_EXPORT_RUNDIR_RESOLVE_FALLBACK_V1"
inject_marker = "VSP_P1_EXPORT_RUNDIR_FALLBACK_IN_HANDLER_V1"

# ---------- (A) add helper once (insert right after V4 block if possible; else append) ----------
if helper_marker not in s:
    helper = textwrap.dedent(r"""
    # ===================== VSP_P1_EXPORT_RUNDIR_RESOLVE_FALLBACK_V1 =====================
    # Resolve RID -> existing run directory on disk (ui/out_ci, ui/out, bundle/out_ci, bundle/out)
    from pathlib import Path as _vsp_rd_Path
    import re as _vsp_rd_re

    def _vsp__resolve_run_dir_for_export(_rid: str, _rid_norm: str = "") -> str:
        try:
            rid = (_rid or "").strip()
        except Exception:
            rid = ""
        try:
            rid_norm = (_rid_norm or "").strip()
        except Exception:
            rid_norm = ""

        if not rid_norm:
            try:
                m = _vsp_rd_re.search(r'(\d{8}_\d{6})', rid)
                rid_norm = m.group(1) if m else rid.replace("VSP_CI_RUN_","").replace("VSP_CI_","").replace("RUN_","")
                rid_norm = (rid_norm or "").strip()
            except Exception:
                rid_norm = ""

        ui_root = _vsp_rd_Path(__file__).resolve().parent
        bundle_root = ui_root.parent

        roots = [ui_root/"out_ci", ui_root/"out", bundle_root/"out_ci", bundle_root/"out"]

        names = []
        for x in [rid, rid_norm]:
            if x and x not in names:
                names.append(x)
        if rid_norm:
            for pref in ["RUN_", "VSP_CI_RUN_", "VSP_CI_"]:
                n = pref + rid_norm
                if n not in names:
                    names.append(n)

        # exact matches
        for root in roots:
            try:
                if not root.exists():
                    continue
                for nm in names:
                    cand = root / nm
                    if cand.exists() and cand.is_dir():
                        return str(cand)
            except Exception:
                continue

        # bounded glob by rid_norm, choose newest
        best = None
        best_m = -1.0
        pats = [f"*{rid_norm}*", f"RUN*{rid_norm}*", f"VSP_CI*{rid_norm}*"] if rid_norm else []
        for root in roots:
            try:
                if not root.exists():
                    continue
                for pat in pats:
                    c = 0
                    for cand in root.glob(pat):
                        if not cand.is_dir():
                            continue
                        c += 1
                        try:
                            mt = cand.stat().st_mtime
                        except Exception:
                            mt = 0.0
                        if mt > best_m:
                            best, best_m = cand, mt
                        if c >= 80:
                            break
            except Exception:
                continue

        return str(best) if best else ""
    # ===================== /VSP_P1_EXPORT_RUNDIR_RESOLVE_FALLBACK_V1 =====================
    """).rstrip() + "\n"

    # try insert after V4 marker end
    m_end = s.find("# ===================== /VSP_P1_EXPORT_FILENAME_WITH_RELEASE_V4")
    if m_end != -1:
        insert_at = s.find("\n", m_end)
        if insert_at != -1:
            s = s[:insert_at+1] + helper + s[insert_at+1:]
        else:
            s = s + "\n" + helper
    else:
        s = s.rstrip() + "\n\n" + helper

    print("[OK] added helper:", helper_marker)
else:
    print("[OK] helper already exists:", helper_marker)

# ---------- (B) inject fallback inside export handler right before the IF-not that triggers RUN_DIR_NOT_FOUND ----------
fn = "api_vsp_run_export_v3_commercial_real_v1"
m = re.search(r'^(?P<ind>\s*)def\s+' + re.escape(fn) + r'\s*\([^)]*\)\s*:\s*$', s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find export handler: " + fn)

start = m.start()
rest = s[m.end():]
m2 = re.search(r'^\s*def\s+\w+\s*\([^)]*\)\s*:\s*$', rest, flags=re.M)
end = m.end() + (m2.start() if m2 else len(rest))
blk = s[start:end]

if inject_marker in blk:
    print("[OK] handler already injected:", inject_marker)
else:
    lines = blk.splitlines(True)
    # find RUN_DIR_NOT_FOUND line
    idx = None
    for i, line in enumerate(lines):
        if "RUN_DIR_NOT_FOUND" in line:
            idx = i
            break
    if idx is None:
        raise SystemExit("[ERR] RUN_DIR_NOT_FOUND not found inside export handler block")

    # find nearest preceding "if not VAR:" line
    if_i = None
    var = None
    ind = ""
    for j in range(idx, -1, -1):
        mm = re.match(r'^(\s*)if\s+not\s+([A-Za-z_]\w*)\s*:\s*$', lines[j])
        if mm:
            if_i = j
            ind = mm.group(1)
            var = mm.group(2)
            break
    if if_i is None:
        raise SystemExit("[ERR] cannot find preceding 'if not <var>:' before RUN_DIR_NOT_FOUND")

    inj = []
    inj.append(f"{ind}# --- {inject_marker} ---\n")
    inj.append(f"{ind}try:\n")
    inj.append(f"{ind}    __rid = ''\n")
    inj.append(f"{ind}    __rid_norm = ''\n")
    inj.append(f"{ind}    if 'rid' in locals(): __rid = str(rid)\n")
    inj.append(f"{ind}    elif '_rid' in locals(): __rid = str(_rid)\n")
    inj.append(f"{ind}    if 'rid_norm' in locals(): __rid_norm = str(rid_norm)\n")
    inj.append(f"{ind}    __cand = _vsp__resolve_run_dir_for_export(__rid, __rid_norm)\n")
    inj.append(f"{ind}    if __cand:\n")
    inj.append(f"{ind}        # set common names used in code\n")
    inj.append(f"{ind}        run_dir = __cand\n")
    inj.append(f"{ind}        ci_dir = __cand\n")
    inj.append(f"{ind}        RUN_DIR = __cand\n")
    if var not in ("run_dir","ci_dir","RUN_DIR"):
        inj.append(f"{ind}        {var} = __cand\n")
    inj.append(f"{ind}except Exception:\n")
    inj.append(f"{ind}    pass\n")
    inj.append(f"{ind}# --- /{inject_marker} (var={var}) ---\n")

    lines[if_i:if_i] = inj
    blk2 = "".join(lines)
    s = s[:start] + blk2 + s[end:]
    print(f"[OK] injected fallback before `if not {var}:`")

p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] py_compile OK")
PY

echo "== restart UI =="
systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 1

echo "== sanity /runs =="
curl -sS -I "$BASE/runs" | head -n 8

echo "== pick RID from disk (dir only) =="
RID="$(find /home/test/Data/SECURITY_BUNDLE/ui/out_ci \
           /home/test/Data/SECURITY_BUNDLE/ui/out \
           /home/test/Data/SECURITY_BUNDLE/out_ci \
           /home/test/Data/SECURITY_BUNDLE/out \
           -maxdepth 1 -type d 2>/dev/null \
    | egrep '/(RUN_|VSP_CI_|VSP_CI_RUN_)' \
    | xargs -r ls -1dt 2>/dev/null | head -n1 | xargs -r basename)"
echo "[RID]=$RID"

echo "== test export TGZ =="
curl -sS -L -D /tmp/vsp_exp_hdr.txt -o /tmp/vsp_exp_body.bin \
  "$BASE/api/vsp/run_export_v3?rid=$RID&fmt=tgz" \
  -w "\nHTTP=%{http_code}\n"

echo "== Content-Disposition =="
grep -i '^Content-Disposition:' /tmp/vsp_exp_hdr.txt || true
echo "== Body head =="
head -c 220 /tmp/vsp_exp_body.bin; echo

echo "[DONE] rundir fallback patch applied"
