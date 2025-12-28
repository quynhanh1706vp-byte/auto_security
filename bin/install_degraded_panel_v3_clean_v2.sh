#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== 1) write JS clean =="
mkdir -p static/js
cat > static/js/vsp_degraded_panel_hook_v3.js <<'JS'
(function () {
  function qs(sel, root) { return (root || document).querySelector(sel); }
  function ce(tag, cls) { var e = document.createElement(tag); if (cls) e.className = cls; return e; }

  function ridFromUrl() {
    try { return new URL(location.href).searchParams.get("rid"); } catch (e) { return null; }
  }
  async function fetchJson(url) {
    const r = await fetch(url, { cache: "no-store" });
    if (!r.ok) throw new Error("HTTP " + r.status);
    return await r.json();
  }
  async function pickLatestRid() {
    const idx = await fetchJson("/api/vsp/runs_index_v3_fs?limit=1&hide_empty=0");
    const it = (idx.items && idx.items[0]) ? idx.items[0] : null;
    return it ? (it.req_id || it.request_id || it.run_id || null) : null;
  }
  function artifactUrl(rid, relPath) {
    return "/api/vsp/run_artifact_v1/" + encodeURIComponent(rid) + "?path=" + encodeURIComponent(relPath);
  }
  function toolLogPath(tool) {
    const t = (tool || "").toLowerCase();
    if (t === "kics") return "kics/kics.log";
    if (t === "semgrep") return "semgrep/semgrep.log";
    if (t === "codeql") return "codeql/codeql.log";
    if (t === "gitleaks") return "gitleaks/gitleaks.log";
    return "runner.log";
  }

  function render(host, st) {
    if (!host || !st) return;
    var rid = st.rid || st.req_id || st.request_id || "";
    var degraded = Array.isArray(st.degraded_tools) ? st.degraded_tools : [];
    var gate = degraded.length ? "AMBER" : "GREEN";

    var panel = qs(".vsp-degraded-panel-v3", host);
    if (!panel) {
      panel = ce("div", "vsp-degraded-panel-v3");
      panel.style.cssText = "margin:12px 0; padding:12px; border:1px solid rgba(255,255,255,.08); border-radius:14px; background:rgba(255,255,255,.02)";
      host.prepend(panel);
    }

    panel.innerHTML = "";
    var top = ce("div");
    top.style.cssText = "display:flex; align-items:center; justify-content:space-between; gap:10px; margin-bottom:8px; flex-wrap:wrap;";
    var title = ce("div");
    title.innerHTML = "<b>Degraded tools</b> <span style='opacity:.7'>(" + gate + ")</span> <span style='opacity:.55'>rid=" + (rid || "?") + "</span>";
    var actions = ce("div");
    actions.style.cssText = "display:flex; gap:8px; align-items:center;";

    function pill(text, href) {
      var a = ce("a");
      a.textContent = text;
      a.href = href;
      a.target = "_blank";
      a.style.cssText = "opacity:.9; text-decoration:none; border:1px solid rgba(255,255,255,.12); padding:4px 8px; border-radius:10px;";
      return a;
    }

    actions.appendChild(pill("degraded_tools.json", artifactUrl(rid, "degraded_tools.json")));
    actions.appendChild(pill("runner.log", artifactUrl(rid, "runner.log")));
    top.appendChild(title);
    top.appendChild(actions);
    panel.appendChild(top);

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
      right.appendChild(pill("open log", artifactUrl(rid, toolLogPath(d.tool))));
      row.appendChild(left);
      row.appendChild(right);
      panel.appendChild(row);
    });
  }

  async function tick() {
    try {
      var rid = ridFromUrl() || await pickLatestRid();
      if (!rid) return;
      var st = await fetchJson("/api/vsp/run_status_v1/" + encodeURIComponent(rid));

      render(qs("#vsp-dashboard-main") || qs(".vsp-dashboard-main") || qs("main") || document.body, st);
      render(qs("#vsp-runs-main") || qs(".vsp-runs-main"), st);
    } catch (e) {}
  }

  window.addEventListener("DOMContentLoaded", function () {
    tick();
    setInterval(tick, 5000);
  });
})();
JS

echo "== 2) inject template tag =="
TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 1; }
cp -f "$TPL" "$TPL.bak_degraded_v3_clean_$(date +%Y%m%d_%H%M%S)"

python3 - <<'PY'
from pathlib import Path
tpl = Path("templates/vsp_dashboard_2025.html")
txt = tpl.read_text(encoding="utf-8", errors="ignore")
for s in ["vsp_degraded_panel_hook_v1.js","vsp_degraded_panel_hook_v2.js","vsp_degraded_panel_hook_v3.js"]:
    txt = txt.replace(f'<script src="/static/js/{s}" defer></script>', '')
tag = '\n<script src="/static/js/vsp_degraded_panel_hook_v3.js" defer></script>\n'
if "</body>" in txt:
    txt = txt.replace("</body>", tag + "</body>")
elif "</head>" in txt:
    txt = txt.replace("</head>", tag + "</head>")
else:
    txt += tag
tpl.write_text(txt, encoding="utf-8")
print("[OK] injected v3 hook tag")
PY

echo "== 3) restart services =="
sudo systemctl restart vsp-ui-8910
sudo systemctl restart vsp-ui-8911-dev

echo "== 4) verify healthz =="
curl -sS -o /dev/null -w "healthz_8910 HTTP=%{http_code}\n" http://127.0.0.1:8910/healthz || true
curl -sS -o /dev/null -w "healthz_8911 HTTP=%{http_code}\n" http://127.0.0.1:8911/healthz || true
echo "[OK] install degraded panel v3 done"
