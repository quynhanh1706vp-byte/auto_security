#!/usr/bin/env bash
set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SPEC="${VSP_UI_SPEC:-/home/test/Data/SECURITY_BUNDLE/ui/spec/ui_spec_2025.json}"

[ -f "$SPEC" ] || { echo "[ERR] missing SPEC: $SPEC"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "[ERR] missing python3"; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "[ERR] missing curl"; exit 2; }

python3 - "$BASE" "$SPEC" <<'PY'
import json, re, sys, subprocess

BASE = sys.argv[1].rstrip("/")
SPEC = sys.argv[2]

OK = 0
WARN = 0
ERR = 0

def ok(msg):
    global OK
    OK += 1
    print(f"[OK] {msg}")

def warn(msg):
    global WARN
    WARN += 1
    print(f"[WARN] {msg}", file=sys.stderr)

def err(msg):
    global ERR
    ERR += 1
    print(f"[ERR] {msg}", file=sys.stderr)

def curl_get(url: str) -> str | None:
    try:
        p = subprocess.run(
            ["curl", "-fsS", "-L", url],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
    except Exception as e:
        return None
    if p.returncode != 0:
        return None
    return p.stdout

def extract_assets(html: str):
    js = re.findall(r'/static/[^"\']+\.js(?:\?v=\d+)?', html)
    css = re.findall(r'/static/[^"\']+\.css(?:\?v=\d+)?', html)
    def strip_q(x): return x.split("?", 1)[0]
    return [strip_q(x) for x in js], [strip_q(x) for x in css]

def dup_list(items):
    seen = {}
    for it in items:
        seen[it] = seen.get(it, 0) + 1
    return [k for k,v in seen.items() if v > 1]

def check_markers(html: str, required: list[str], optional: list[str], tab: str, required_tab: bool):
    missing_req = [m for m in required if m not in html]
    if missing_req:
        if required_tab:
            err(f"{tab}: missing required markers: {missing_req[:20]}")
        else:
            warn(f"{tab}: missing required markers (optional tab): {missing_req[:20]}")
    else:
        ok(f"{tab}: required markers present ({len(required)})")

    missing_opt = [m for m in optional if m not in html]
    if missing_opt:
        warn(f"{tab}: missing optional markers: {missing_opt[:20]}")
    else:
        ok(f"{tab}: optional markers present ({len(optional)})")

def check_api(url: str, required: bool, keys_any: list[str]):
    body = curl_get(url)
    if body is None:
        if required:
            err(f"API required but not reachable: {url}")
        else:
            warn(f"API optional not reachable: {url}")
        return
    try:
        j = json.loads(body or "{}")
    except Exception as e:
        if required:
            err(f"API invalid JSON: {url} ({e})")
        else:
            warn(f"API invalid JSON (optional): {url} ({e})")
        return
    present = [k for k in keys_any if k in j]
    if not present:
        if required:
            err(f"API missing all expected keys: {url} expected any of {keys_any}")
        else:
            warn(f"API (optional) missing keys: {url} expected any of {keys_any}")
    else:
        ok(f"API schema keys ok: {url} present_any={present}")

# Load spec
with open(SPEC, "r", encoding="utf-8") as f:
    spec = json.load(f)

print("SPEC_NAME=", spec.get("name"))
print("TABS=", len(spec.get("tabs") or []))
print("API=", len(spec.get("api") or []))

print("== [1] Tabs: HTML reachability + dup assets + markers ==")
for t in (spec.get("tabs") or []):
    path = t.get("path") or ""
    required_tab = bool(t.get("required"))
    url = f"{BASE}{path}"
    tab = path.strip("/").split("/")[-1] or "root"
    html = curl_get(url)
    if html is None:
        if required_tab:
            err(f"tab not reachable: {path}")
        else:
            warn(f"tab not reachable (optional): {path}")
        continue
    ok(f"reachable: {path}")

    js, css = extract_assets(html)
    if js:
        d = dup_list(js)
        if d:
            err(f"{tab}: duplicate JS detected: {d[:12]}")
        else:
            ok(f"{tab}: no duplicate JS")
    else:
        warn(f"{tab}: no JS assets detected (pattern may differ)")

    if css:
        d = dup_list(css)
        if d:
            err(f"{tab}: duplicate CSS detected: {d[:12]}")
        else:
            ok(f"{tab}: no duplicate CSS")
    else:
        warn(f"{tab}: no CSS assets detected (pattern may differ)")

    req = t.get("markers_required") or []
    opt = t.get("markers_optional") or []
    check_markers(html, req, opt, tab, required_tab)

print("== [2] API: schema keys ==")
for a in (spec.get("api") or []):
    path = a.get("path") or ""
    required_api = bool(a.get("required"))
    keys_any = a.get("json_keys_any") or []
    check_api(f"{BASE}{path}", required_api, keys_any)

print("== [3] Summary ==")
print(f"OK={OK} WARN={WARN} ERR={ERR}")
sys.exit(2 if ERR else 0)
PY
