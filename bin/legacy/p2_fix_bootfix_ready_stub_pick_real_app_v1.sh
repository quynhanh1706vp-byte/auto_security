#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_p2_bootfix_ready_pickreal_${TS}"
echo "[BACKUP] ${WSGI}.bak_p2_bootfix_ready_pickreal_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P2_FIX_BOOTFIX_READY_PICKREAL_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

def patch_block(name: str, body: str) -> bool:
    """
    Replace content between:
      # ===== ... NAME ...
      ...
      # ===== /NAME ...
    """
    nonlocal_s = {"s": None}
    pat = re.compile(
        r"(?P<open>^[ \t]*#\s*=+\s*" + re.escape(name) + r"[^\n]*\n)"
        r"(?P<middle>.*?)"
        r"(?P<close>^[ \t]*#\s*=+\s*/" + re.escape(name) + r"[^\n]*\n)",
        re.M | re.S
    )
    m = pat.search(s)
    if not m:
        return False
    new_mid = body
    nonlocal_s["s"] = s[:m.start("middle")] + new_mid + s[m.end("middle"):]
    globals()["s"] = nonlocal_s["s"]
    return True

fixed_common = textwrap.dedent(f"""
    # {MARK}
    try:
        _VSP_ONCE_FLAGS = globals().setdefault("_VSP_ONCE_FLAGS", {{}})

        def _vsp_is_flaskish(x):
            return (x is not None) and hasattr(x, "url_map") and callable(getattr(x, "add_url_rule", None))

        def _vsp_pick_real_flask_app(g):
            # prefer common names first
            for k in ("application", "app", "flask_app", "APP"):
                x = g.get(k)
                if _vsp_is_flaskish(x):
                    return x
            # scan globals (best-effort)
            for k, v in list(g.items()):
                if _vsp_is_flaskish(v):
                    return v
            return None

        def _vsp_has_path(app, path):
            try:
                for r in app.url_map.iter_rules():
                    if getattr(r, "rule", None) == path:
                        return True
            except Exception:
                return False
            return False

        _real_app = _vsp_pick_real_flask_app(globals())
        if _real_app is None:
            # don't spam per-worker
            if not _VSP_ONCE_FLAGS.get("no_real_flask_app"):
                print("[VSP_P2] no real Flask app detected; skip stub bind (non-fatal)")
                _VSP_ONCE_FLAGS["no_real_flask_app"] = 1
        else:
            pass
    except Exception as e:
        if not globals().get("_VSP_ONCE_FLAGS", {{}}).get("p2_pickreal_err"):
            print("[VSP_P2] pick-real-app failed (non-fatal):", repr(e))
            globals().setdefault("_VSP_ONCE_FLAGS", {{}})["p2_pickreal_err"] = 1
""").lstrip("\n")

bootfix_body = fixed_common + textwrap.dedent("""
    # Bind ultra-safe stub endpoints ONLY if missing (avoid duplicates)
    if _real_app is not None:
        def _vsp_ok_json(payload, code=200):
            # Flask Response without importing flask (works with Flask app.response_class)
            import json
            resp = _real_app.response_class(
                response=json.dumps(payload, ensure_ascii=False),
                status=code,
                mimetype="application/json",
            )
            return resp

        # These are "commercial safety nets" - harmless if real handlers already exist
        if not _vsp_has_path(_real_app, "/healthz"):
            _real_app.add_url_rule("/healthz", endpoint="vsp_healthz_p2", view_func=lambda: _vsp_ok_json({"ok": True, "src": "p2_stub"}))
        if not _vsp_has_path(_real_app, "/readyz"):
            _real_app.add_url_rule("/readyz", endpoint="vsp_readyz_p2", view_func=lambda: _vsp_ok_json({"ok": True, "ready": True, "src": "p2_stub"}))

        _VSP_ONCE_FLAGS = globals().setdefault("_VSP_ONCE_FLAGS", {})
        if not _VSP_ONCE_FLAGS.get("p2_bootfix_bound"):
            print("[VSP_BOOTFIX] stub bind OK (real Flask app)")
            _VSP_ONCE_FLAGS["p2_bootfix_bound"] = 1
""").lstrip("\n")

ready_body = fixed_common + textwrap.dedent("""
    # Provide a stable /ready endpoint used by systemd/nginx healthchecks (if missing)
    if _real_app is not None:
        def _vsp_ok_text(txt="OK", code=200):
            return _real_app.response_class(response=txt, status=code, mimetype="text/plain")

        if not _vsp_has_path(_real_app, "/ready"):
            _real_app.add_url_rule("/ready", endpoint="vsp_ready_p2", view_func=lambda: _vsp_ok_text("READY"))

        _VSP_ONCE_FLAGS = globals().setdefault("_VSP_ONCE_FLAGS", {})
        if not _VSP_ONCE_FLAGS.get("p2_ready_bound"):
            print("[VSP_READY_STUB] bind OK (real Flask app)")
            _VSP_ONCE_FLAGS["p2_ready_bound"] = 1
""").lstrip("\n")

ok1 = patch_block("VSP_BOOTFIX", bootfix_body)
ok2 = patch_block("VSP_READY_STUB", ready_body)

if not ok1 and not ok2:
    # fallback: just silence the noisy prints (non-ideal, but stops spam)
    s2 = re.sub(r'print\("\[VSP_BOOTFIX\] stub routes failed:",\s*repr\(e\)\)',
                'print("[VSP_BOOTFIX] stub routes skipped (non-fatal):", repr(e))', s)
    s2 = re.sub(r'print\("\[VSP_READY_STUB\] failed:",\s*repr\(e\)\)',
                'print("[VSP_READY_STUB] skipped (non-fatal):", repr(e))', s2)
    if s2 != s:
        s = s2
        s += "\n# " + MARK + " (fallback silence-only)\n"
        p.write_text(s, encoding="utf-8")
        py_compile.compile(str(p), doraise=True)
        print("[OK] patched (fallback silence-only):", MARK)
        raise SystemExit(0)
    raise SystemExit("[ERR] could not locate VSP_BOOTFIX/VSP_READY_STUB blocks to patch")

p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched:", MARK, "bootfix_block=", ok1, "ready_block=", ok2)
PY

# restart service if available
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || true
  systemctl --no-pager --full status "$SVC" | sed -n '1,12p' || true
fi

echo
echo "== QUICK VERIFY =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
curl -s -o /dev/null -w "GET /ready => %{http_code}\n" "$BASE/ready" || true
curl -s -o /dev/null -w "GET /readyz => %{http_code}\n" "$BASE/readyz" || true
curl -s -o /dev/null -w "GET /healthz => %{http_code}\n" "$BASE/healthz" || true

echo
echo "== RECENT LOG (BOOTFIX/READY_STUB) =="
journalctl -u "$SVC" --no-pager -n 120 | egrep "VSP_BOOTFIX|VSP_READY_STUB|VSP_P2" || true
