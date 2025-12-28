#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_statusv2_${TS}"
echo "[BACKUP] $F.bak_statusv2_${TS}"

python3 - <<'PY'
from pathlib import Path
import sys, re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "# === VSP STATUS+ARTIFACT V2 ==="
if MARK not in txt:
    block = r'''
# === VSP STATUS+ARTIFACT V2 ===
import os, json, glob, re
from pathlib import Path
from flask import request, jsonify, Response

def _read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8", errors="ignore") or "{}")
    except Exception:
        return None

def _norm_rid(rid: str) -> str:
    rid = (rid or "").strip()
    if rid.startswith("RUN_"):
        rid = rid[4:]  # RUN_VSP_CI_... -> VSP_CI_...
    return rid

def _safe_join(base: Path, rel: str) -> Path:
    rel = (rel or "").lstrip("/").replace("\\", "/")
    if ".." in rel.split("/"):
        raise ValueError("path traversal")
    out = (base / rel).resolve()
    base_r = base.resolve()
    if str(out) != str(base_r) and not str(out).startswith(str(base_r) + os.sep):
        raise ValueError("outside base")
    return out

def _guess_mime(path: str) -> str:
    s = (path or "").lower()
    if s.endswith(".json"): return "application/json; charset=utf-8"
    if s.endswith(".sarif"): return "application/sarif+json; charset=utf-8"
    if s.endswith(".html") or s.endswith(".htm"): return "text/html; charset=utf-8"
    if s.endswith(".txt") or s.endswith(".log"): return "text/plain; charset=utf-8"
    if s.endswith(".zip"): return "application/zip"
    return "application/octet-stream"

def _find_ci_run_dir_any(rid: str):
    rid0 = rid
    rid = _norm_rid(rid)
    roots = [
        Path("/home/test/Data/SECURITY-10-10-v4/out_ci"),
        Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
        Path("/home/test/Data/SECURITY_BUNDLE/out"),
    ]
    # try exact
    for root in roots:
        for cand in [root / rid, root / rid0]:
            if cand.exists() and cand.is_dir():
                return str(cand)

    # timestamp glob bounded
    m = re.search(r"(20\d{6}_\d{6})", rid0)
    if m:
        ts = m.group(1)
        globs = [f"/home/test/Data/SECURITY-10-10-v4/out_ci/*{ts}*",
                 f"/home/test/Data/SECURITY_BUNDLE/out_ci/*{ts}*"]
        for g in globs:
            for path in sorted(glob.glob(g), reverse=True)[:50]:
                try:
                    pp = Path(path)
                    if pp.is_dir():
                        return str(pp)
                except Exception:
                    pass
    return None

def _read_degraded(ci_run_dir: str):
    if not ci_run_dir:
        return []
    fp = Path(ci_run_dir) / "degraded_tools.json"
    if fp.exists():
        j = _read_json(fp)
        if isinstance(j, list): return j
        if isinstance(j, dict) and isinstance(j.get("degraded_tools"), list):
            return j["degraded_tools"]
    return []

@app.get("/api/vsp/run_status_v2/<rid>")
def vsp_run_status_v2(rid):
    ci_dir = _find_ci_run_dir_any(rid)
    degraded = _read_degraded(ci_dir) if ci_dir else []
    ok = bool(ci_dir)
    return jsonify({
        "ok": ok,
        "rid": rid,
        "rid_norm": _norm_rid(rid),
        "ci_run_dir": ci_dir,
        "degraded_tools": degraded,
        "final": False,
        "finish_reason": "running",
        "error": None if ok else "ci_run_dir_not_found"
    }), 200

@app.get("/api/vsp/run_artifact_v2/<rid>")
def vsp_run_artifact_v2(rid):
    rel = request.args.get("path", "") or ""
    if not rel:
        return jsonify({"ok": False, "rid": rid, "error": "missing_path"}), 400

    ci_dir = _find_ci_run_dir_any(rid)
    bases = []
    if ci_dir:
        bases.append(Path(ci_dir))
    bases.append(Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"))
    bases.append(Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1"))

    last = None
    for base in bases:
        try:
            fp = _safe_join(base, rel)
            if fp.exists() and fp.is_file():
                return Response(fp.read_bytes(), status=200, mimetype=_guess_mime(rel))
        except Exception as e:
            last = e
            continue

    return jsonify({"ok": False, "rid": rid, "error": "artifact_not_found", "path": rel, "detail": str(last) if last else ""}), 404
# === END VSP STATUS+ARTIFACT V2 ===
'''
    txt = txt.rstrip() + "\n\n" + block + "\n"
    p.write_text(txt, encoding="utf-8")
    print("[OK] appended STATUS+ARTIFACT V2")
else:
    print("[OK] STATUS+ARTIFACT V2 already present")
PY

/home/test/Data/SECURITY_BUNDLE/.venv/bin/python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile vsp_demo_app.py"

echo "== write degraded hook (use status_v2 + artifact_v2) =="
mkdir -p static/js
cat > static/js/vsp_degraded_panel_hook_v3.js <<'JS'
(function () {
  async function fetchJson(url) {
    const r = await fetch(url, { cache: "no-store" });
    if (!r.ok) throw new Error("HTTP " + r.status);
    return await r.json();
  }
  function ce(tag, cls) { var e = document.createElement(tag); if (cls) e.className = cls; return e; }
  function qs(sel, root) { return (root || document).querySelector(sel); }

  function ridFromUrl() {
    try { return new URL(location.href).searchParams.get("rid"); } catch (e) { return null; }
  }

  async function pickLatestRidSmart() {
    // take first RID that status_v2 can resolve
    const idx = await fetchJson("/api/vsp/runs_index_v3_fs?limit=10&hide_empty=0");
    const items = Array.isArray(idx.items) ? idx.items : [];
    for (const it of items) {
      const rid = it.req_id || it.request_id || it.run_id;
      if (!rid) continue;
      try {
        const st = await fetchJson("/api/vsp/run_status_v2/" + encodeURIComponent(rid));
        if (st && st.ok) return rid;
      } catch (e) {}
    }
    // fallback
    return (items[0] && (items[0].req_id || items[0].request_id || items[0].run_id)) || null;
  }

  function artifactUrlV2(rid, relPath) {
    return "/api/vsp/run_artifact_v2/" + encodeURIComponent(rid) + "?path=" + encodeURIComponent(relPath);
  }

  function toolLogPath(tool) {
    const t = (tool || "").toLowerCase();
    if (t === "kics") return "kics/kics.log";
    if (t === "semgrep") return "semgrep/semgrep.log";
    if (t === "codeql") return "codeql/codeql.log";
    if (t === "gitleaks") return "gitleaks/gitleaks.log";
    return "runner.log";
  }

  function pill(text, href) {
    var a = ce("a");
    a.textContent = text;
    a.href = href;
    a.target = "_blank";
    a.style.cssText = "opacity:.9; text-decoration:none; border:1px solid rgba(255,255,255,.12); padding:4px 8px; border-radius:10px;";
    return a;
  }

  function render(host, rid, st) {
    host = host || document.body;
    var panel = qs(".vsp-degraded-panel-v3", host);
    if (!panel) {
      panel = ce("div", "vsp-degraded-panel-v3");
      panel.style.cssText = "margin:12px 0; padding:12px; border:1px solid rgba(255,255,255,.08); border-radius:14px; background:rgba(255,255,255,.02)";
      host.prepend(panel);
    }

    const degraded = Array.isArray(st.degraded_tools) ? st.degraded_tools : [];
    const gate = degraded.length ? "AMBER" : (st.ok ? "GREEN" : "RED");

    panel.innerHTML = "";
    var top = ce("div");
    top.style.cssText = "display:flex; align-items:center; justify-content:space-between; gap:10px; margin-bottom:8px; flex-wrap:wrap;";
    var title = ce("div");
    title.innerHTML =
      "<b>Degraded tools</b> <span style='opacity:.7'>(" + gate + ")</span> " +
      "<span style='opacity:.55'>rid=" + (rid || "?") + "</span> " +
      "<span style='opacity:.55'>ci=" + (st.ci_run_dir ? "ok" : "null") + "</span>";
    var actions = ce("div");
    actions.style.cssText = "display:flex; gap:8px; align-items:center;";
    actions.appendChild(pill("degraded_tools.json", artifactUrlV2(rid, "degraded_tools.json")));
    actions.appendChild(pill("runner.log", artifactUrlV2(rid, "runner.log")));
    top.appendChild(title);
    top.appendChild(actions);
    panel.appendChild(top);

    if (!st.ok) {
      var err = ce("div");
      err.style.opacity = ".85";
      err.textContent = "Status resolve failed: " + (st.error || "unknown");
      panel.appendChild(err);
      return;
    }

    if (!degraded.length) {
      var ok = ce("div");
      ok.style.opacity = ".8";
      ok.textContent = "No degraded tool detected.";
      panel.appendChild(ok);
      return;
    }

    degraded.forEach(function (d) {
      var row = ce("div");
      row.style.cssText = "display:flex; align-items:center; justify-content:space-between; gap:10px; padding:8px 0; border-top:1px solid rgba(255,255,255,.06)";
      var left = ce("div");
      left.innerHTML =
        "<b>" + (d.tool || "UNKNOWN") + "</b> — " + (d.reason || "degraded") +
        " <span style='opacity:.7'>(rc=" + (d.rc ?? "?") + ", ts=" + (d.ts ?? "?") + ")</span>";
      var right = ce("div");
      right.appendChild(pill("open log", artifactUrlV2(rid, toolLogPath(d.tool))));
      row.appendChild(left);
      row.appendChild(right);
      panel.appendChild(row);
    });
  }

  async function tick() {
    try {
      var rid = ridFromUrl() || await pickLatestRidSmart();
      if (!rid) return;
      var st = await fetchJson("/api/vsp/run_status_v2/" + encodeURIComponent(rid));
      render(document.body, rid, st);
    } catch (e) {}
  }

  window.addEventListener("DOMContentLoaded", function () {
    tick();
    setInterval(tick, 5000);
  });
})();
JS

echo "== inject template tag (keep v3 filename) =="
TPL="templates/vsp_dashboard_2025.html"
cp -f "$TPL" "$TPL.bak_degraded_v4_$(date +%Y%m%d_%H%M%S)"

python3 - <<'PY'
from pathlib import Path
tpl = Path("templates/vsp_dashboard_2025.html")
txt = tpl.read_text(encoding="utf-8", errors="ignore")
for s in ["vsp_degraded_panel_hook_v1.js","vsp_degraded_panel_hook_v2.js","vsp_degraded_panel_hook_v3.js"]:
    txt = txt.replace(f'<script src="/static/js/{s}" defer></script>', '')
tag = '\n<script src="/static/js/vsp_degraded_panel_hook_v3.js" defer></script>\n'
if "</body>" in txt:
    txt = txt.replace("</body>", tag + "</body>")
else:
    txt += tag
tpl.write_text(txt, encoding="utf-8")
print("[OK] injected hook tag")
PY

echo "== restart services =="
sudo systemctl restart vsp-ui-8910
sudo systemctl restart vsp-ui-8911-dev

sleep 1
echo "== verify =="
curl -sS -o /dev/null -w "healthz_8910 HTTP=%{http_code}\n" http://127.0.0.1:8910/healthz || true
curl -sS -o /dev/null -w "healthz_8911 HTTP=%{http_code}\n" http://127.0.0.1:8911/healthz || true
