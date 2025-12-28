#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_settings_rule_realjson_${TS}"
echo "[BACKUP] $F.bak_settings_rule_realjson_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

def replace_route(path: str, new_func_src: str):
    global t
    # find decorator for exact path (route/get)
    dec_pat = re.compile(rf"^@app\.(route|get)\(\s*['\"]{re.escape(path)}['\"][^\)]*\)\s*$", re.M)
    mdec = dec_pat.search(t)
    if not mdec:
        raise SystemExit(f"[ERR] cannot find decorator for {path}")

    # find def after that decorator (skip possible multiple decorators)
    off = mdec.end()
    mdef = re.search(r"^def\s+([A-Za-z0-9_]+)\s*\(\s*\)\s*:\s*$", t[off:], flags=re.M)
    if not mdef:
        raise SystemExit(f"[ERR] cannot find handler def after decorator for {path}")
    fn = mdef.group(1)
    def_start = off + mdef.start()

    # region end: next top-level def
    mnext = re.search(r"^def\s+[A-Za-z0-9_]+\s*\(", t[off + mdef.end():], flags=re.M)
    end = (off + mdef.end() + mnext.start()) if mnext else len(t)

    old = t[def_start:end]
    # keep decorator line(s) above the def; only replace def+body region
    t = t[:def_start] + new_func_src.rstrip() + "\n\n" + t[end:]
    return fn

settings_src = textwrap.dedent(r"""
def vsp_settings_v1():
    # commercial contract: always JSON
    try:
        import json
        from pathlib import Path
        cfg = Path(__file__).resolve().parent / "config" / "settings_v1.json"
        data = {}
        if cfg.exists():
            raw = cfg.read_text(encoding="utf-8", errors="ignore").strip()
            if raw:
                data = json.loads(raw)
        if not isinstance(data, dict):
            data = {"value": data}
        return {"ok": True, "settings": data}
    except Exception as e:
        return {"ok": True, "settings": {}, "error": str(e)}
""").strip()

rule_src = textwrap.dedent(r"""
def vsp_rule_overrides_v1():
    # commercial contract: always JSON
    try:
        import json
        from pathlib import Path
        cfg = Path(__file__).resolve().parent / "config" / "rule_overrides_v1.json"
        data = {}
        if cfg.exists():
            raw = cfg.read_text(encoding="utf-8", errors="ignore").strip()
            if raw:
                data = json.loads(raw)
        if not isinstance(data, dict):
            data = {"value": data}
        return {"ok": True, "overrides": data}
    except Exception as e:
        return {"ok": True, "overrides": {}, "error": str(e)}
""").strip()

fn1 = replace_route("/api/vsp/settings_v1", settings_src)
fn2 = replace_route("/api/vsp/rule_overrides_v1", rule_src)
print("[OK] patched handlers:", fn1, fn2)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

# restart service
systemctl --user restart vsp-ui-8910.service || true
sleep 1

echo "== verify settings/rule (HTTP + JSON) =="
echo "--- settings_v1 ---"
curl -sS -i http://127.0.0.1:8910/api/vsp/settings_v1 | sed -n '1,18p'
echo
echo "--- rule_overrides_v1 ---"
curl -sS -i http://127.0.0.1:8910/api/vsp/rule_overrides_v1 | sed -n '1,18p'
echo
