#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

# Find python file that owns rid_latest route
TARGET="$(python3 - <<'PY'
from pathlib import Path
root=Path(".")
cands=[]
for p in root.rglob("*.py"):
    if any(x in p.parts for x in ("out_ci","bin","static",".venv","node_modules","__pycache__")):
        continue
    try:
        t=p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if "/api/vsp/rid_latest" in t or "rid_latest" in t:
        cands.append(str(p))
print(cands[0] if cands else "")
PY
)"
[ -n "$TARGET" ] || { echo "[ERR] cannot find rid_latest route in *.py"; exit 2; }
echo "[INFO] patch target: $TARGET"

cp -f "$TARGET" "${TARGET}.bak_ridlatest_${TS}"
echo "[BACKUP] ${TARGET}.bak_ridlatest_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

target = Path("""'"$TARGET"'""")
s = target.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_RID_LATEST_NEVER_NONE_CACHE_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

# Locate route block: @app.route('/api/vsp/rid_latest'...) def ...
# Replace whole function block until next decorator or EOF.
pat = re.compile(r"(?ms)@app\.route\(\s*['\"]\/api\/vsp\/rid_latest['\"].*?\)\s*\n\s*def\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(.*?\)\s*:\s*\n(.*?)(?=\n@app\.route|\n@app\.get|\n@app\.post|\n@app\.put|\n@app\.delete|\nif\s+__name__\s*==\s*['\"]__main__['\"]|\Z)")
m = pat.search(s)
if not m:
    # some codebases use app.get("/api/vsp/rid_latest")
    pat2 = re.compile(r"(?ms)@app\.(get|route)\(\s*['\"]\/api\/vsp\/rid_latest['\"].*?\)\s*\n\s*def\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(.*?\)\s*:\s*\n(.*?)(?=\n@app\.route|\n@app\.get|\n@app\.post|\n@app\.put|\n@app\.delete|\nif\s+__name__\s*==\s*['\"]__main__['\"]|\Z)")
    m = pat2.search(s)

if not m:
    raise SystemExit("[ERR] cannot find rid_latest function block to replace")

func_name = m.group(1) if m.lastindex and isinstance(m.group(1), str) else "rid_latest"

replacement = textwrap.dedent(f"""
@app.route("/api/vsp/rid_latest", methods=["GET"])
def {func_name}():
    \"\"\"{MARK}
    Commercial-safe: never 500, never rid=None.
    Strategy:
    - scan multiple roots for run directories (VSP_CI_* / RUN_* / *_RUN_*)
    - pick newest by mtime
    - cache last-good RID to ui/out_ci/_rid_latest_cache.json
    - if scan fails, return cached rid (stale=true)
    \"\"\"
    try:
        import os, json, time
        from pathlib import Path

        def _is_rid(v: str) -> bool:
            if not v: return False
            v = str(v).strip()
            if len(v) < 6 or len(v) > 120: return False
            if any(c.isspace() for c in v): return False
            # allow letters digits _ . : -
            import re
            if not re.match(r"^[A-Za-z0-9][A-Za-z0-9_.:-]+$", v): return False
            if not any(ch.isdigit() for ch in v): return False
            return True

        # roots to scan
        roots = []
        roots += [
            Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
            Path("/home/test/Data/SECURITY_BUNDLE/out"),
            Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
            Path("/home/test/Data/SECURITY_BUNDLE/ui/out"),
        ]
        # add /home/test/Data/SECURITY*/out_ci|out (shallow)
        base = Path("/home/test/Data")
        if base.is_dir():
            try:
                for d in base.iterdir():
                    if not d.is_dir(): 
                        continue
                    n = d.name
                    if n.startswith("SECURITY"):
                        roots.append(d / "out_ci")
                        roots.append(d / "out")
            except Exception:
                pass

        # collect candidates
        cand = []  # (mtime, rid, path)
        def consider_dir(p: Path):
            try:
                if not p.is_dir(): return
                rid = p.name
                if not _is_rid(rid): return
                # accept typical patterns
                if not (rid.startswith("RUN_") or "VSP" in rid or "_RUN_" in rid):
                    return
                mt = p.stat().st_mtime
                cand.append((mt, rid, str(p)))
            except Exception:
                return

        for r in roots:
            try:
                if not r.is_dir(): 
                    continue
                # only one level deep: list dirs
                for x in r.iterdir():
                    consider_dir(x)
            except Exception:
                continue

        cand.sort(reverse=True, key=lambda t: t[0])
        best = cand[0] if cand else None

        cache_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/_rid_latest_cache.json")
        cache_path.parent.mkdir(parents=True, exist_ok=True)

        if best:
            mt, rid, pth = best
            try:
                cache_path.write_text(json.dumps({{"rid": rid, "path": pth, "mtime": mt, "ts": time.time()}}, ensure_ascii=False), encoding="utf-8")
            except Exception:
                pass
            return jsonify({{"ok": True, "rid": rid, "path": pth, "mtime": mt, "stale": False, "candidates": len(cand)}})

        # fallback to cache
        try:
            if cache_path.is_file():
                j = json.loads(cache_path.read_text(encoding="utf-8", errors="replace") or "{{}}")
                rid = (j.get("rid") or "").strip()
                if _is_rid(rid):
                    return jsonify({{"ok": True, "rid": rid, "path": j.get("path",""), "mtime": j.get("mtime",0), "stale": True, "candidates": 0}})
        except Exception:
            pass

        # no rid at all, but NEVER 500/None
        return jsonify({{"ok": False, "rid": "", "stale": False, "candidates": 0, "err": "no run dir found"}})

    except Exception as e:
        # NEVER 500
        return jsonify({{"ok": False, "rid": "", "stale": False, "candidates": 0, "err": str(e)[:180]}})
""").strip()+"\n"

# Replace old block
new_s = s[:m.start()] + replacement + s[m.end():]

target.write_text(new_s, encoding="utf-8")
print("[OK] patched rid_latest in", target, "marker:", MARK)
PY

python3 -m py_compile "$TARGET" && echo "[OK] py_compile: $TARGET" || { echo "[ERR] py_compile failed"; exit 3; }

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] rid_latest is commercial-safe (never None/500). Hard refresh /vsp5."
