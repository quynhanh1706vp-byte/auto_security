#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/js/vsp_runs_scan_panel_ui_v1.js"
TPL="$ROOT/templates/vsp_dashboard_2025.html"
TAG='<script src="/static/js/vsp_runs_scan_panel_ui_v1.js" defer></script>'

echo "[SETUP] ROOT=$ROOT"
echo "[SETUP] JS=$JS"
echo "[SETUP] TPL=$TPL"

mkdir -p "$(dirname "$JS")"

cat > "$JS" << 'JS'
/* VSP 2025 – Runs Scan Panel UI v1
 * - Form: target/profile/mode
 * - POST /api/vsp/run
 * - Poll /api/vsp/run_status/{REQ_ID}
 * - Render Gate/FinalRC/ci_run_id/has_findings + tail log
 */
(function () {
  if (window.__VSP_RUNS_SCAN_PANEL_UI_V1__) return;
  window.__VSP_RUNS_SCAN_PANEL_UI_V1__ = true;

  function $(sel, root) { return (root || document).querySelector(sel); }
  function el(tag, attrs, html) {
    var e = document.createElement(tag);
    if (attrs) Object.keys(attrs).forEach(function (k) { e.setAttribute(k, attrs[k]); });
    if (html != null) e.innerHTML = html;
    return e;
  }

  function safeText(s) {
    return String(s == null ? "" : s)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  function nowTS() {
    var d = new Date();
    function p(n){return (n<10?"0":"")+n;}
    return d.getFullYear()+"-"+p(d.getMonth()+1)+"-"+p(d.getDate())+" "+p(d.getHours())+":"+p(d.getMinutes())+":"+p(d.getSeconds());
  }

  function apiJson(url, opts) {
    opts = opts || {};
    opts.headers = Object.assign({ "Accept": "application/json" }, opts.headers || {});
    return fetch(url, opts).then(function (r) {
      return r.text().then(function (t) {
        var j = null;
        try { j = JSON.parse(t); } catch (e) {}
        if (!r.ok) {
          var msg = (j && (j.error || j.message)) ? (j.error || j.message) : (t || ("HTTP " + r.status));
          var err = new Error(msg);
          err.status = r.status;
          err.body = t;
          throw err;
        }
        return j != null ? j : {};
      });
    });
  }

  function wait(ms) { return new Promise(function (res) { setTimeout(res, ms); }); }

  function findRunsPane() {
    // ưu tiên đúng id tab runs
    return document.getElementById("vsp-tab-runs")
      || document.getElementById("vsp-pane-runs")
      || document.querySelector("[data-tab='runs']")
      || document.querySelector("#runs")
      || null;
  }

  function ensurePanel(root) {
    var existing = root.querySelector("#vsp-runs-scan-panel-ui-v1");
    if (existing) return existing;

    var panel = el("div", { id: "vsp-runs-scan-panel-ui-v1" });
    panel.style.cssText = [
      "margin:14px 0 18px 0",
      "background:linear-gradient(180deg, rgba(19,24,50,.72), rgba(11,16,32,.62))",
      "border:1px solid rgba(255,255,255,.08)",
      "border-radius:16px",
      "padding:14px 14px",
      "box-shadow:0 12px 32px rgba(0,0,0,.35)"
    ].join(";");

    panel.innerHTML = [
      '<div style="display:flex; align-items:center; justify-content:space-between; gap:12px; flex-wrap:wrap;">',
      '  <div>',
      '    <div style="font-weight:700; letter-spacing:.2px; font-size:14px;">Run Scan Now</div>',
      '    <div style="opacity:.75; font-size:12px; margin-top:2px;">Trigger FULL_EXT pipeline (UI → CI OUTER) and poll status.</div>',
      '  </div>',
      '  <div id="vsp-runs-scan-badges" style="display:flex; gap:8px; flex-wrap:wrap;"></div>',
      '</div>',
      '<div style="height:10px"></div>',

      '<div style="display:grid; grid-template-columns: 1.4fr .8fr .7fr auto; gap:10px; align-items:end;">',
      '  <div>',
      '    <div style="font-size:12px; opacity:.75; margin-bottom:6px;">Target Path</div>',
      '    <input id="vsp-scan-target" style="width:100%; padding:10px 10px; border-radius:12px; border:1px solid rgba(255,255,255,.10); background:rgba(5,8,20,.55); color:#E5E7EB; outline:none;" placeholder="/home/test/Data/SECURITY-10-10-v4" />',
      '  </div>',
      '  <div>',
      '    <div style="font-size:12px; opacity:.75; margin-bottom:6px;">Profile</div>',
      '    <select id="vsp-scan-profile" style="width:100%; padding:10px 10px; border-radius:12px; border:1px solid rgba(255,255,255,.10); background:rgba(5,8,20,.55); color:#E5E7EB; outline:none;">',
      '      <option value="FULL_EXT">FULL_EXT</option>',
      '      <option value="EXT">EXT</option>',
      '    </select>',
      '  </div>',
      '  <div>',
      '    <div style="font-size:12px; opacity:.75; margin-bottom:6px;">Mode</div>',
      '    <select id="vsp-scan-mode" style="width:100%; padding:10px 10px; border-radius:12px; border:1px solid rgba(255,255,255,.10); background:rgba(5,8,20,.55); color:#E5E7EB; outline:none;">',
      '      <option value="local">LOCAL (UI)</option>',
      '      <option value="ci">CI (future)</option>',
      '    </select>',
      '  </div>',
      '  <div style="display:flex; gap:10px; justify-content:flex-end;">',
      '    <button id="vsp-scan-run" style="padding:10px 14px; border-radius:12px; border:1px solid rgba(255,255,255,.14); background:rgba(99,102,241,.20); color:#E5E7EB; font-weight:700; cursor:pointer;">Run Scan Now</button>',
      '    <button id="vsp-scan-stop" style="padding:10px 12px; border-radius:12px; border:1px solid rgba(255,255,255,.10); background:rgba(148,163,184,.10); color:#E5E7EB; font-weight:700; cursor:pointer;" title="Stop polling only">Stop</button>',
      '  </div>',
      '</div>',

      '<div style="height:12px"></div>',
      '<div id="vsp-scan-msg" style="font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size:12px; opacity:.9;"></div>',

      '<div style="height:10px"></div>',
      '<div style="display:grid; grid-template-columns: 1fr 1fr 1fr 1fr; gap:10px;">',
      '  <div class="vsp-kpi-mini" id="vsp-mini-status"></div>',
      '  <div class="vsp-kpi-mini" id="vsp-mini-gate"></div>',
      '  <div class="vsp-kpi-mini" id="vsp-mini-final"></div>',
      '  <div class="vsp-kpi-mini" id="vsp-mini-runid"></div>',
      '</div>',

      '<div style="height:12px"></div>',
      '<details open style="border:1px solid rgba(255,255,255,.08); border-radius:14px; padding:10px 12px; background:rgba(0,0,0,.18);">',
      '  <summary style="cursor:pointer; font-weight:700; font-size:12px; opacity:.9;">Live Log Tail</summary>',
      '  <div style="height:10px"></div>',
      '  <pre id="vsp-scan-tail" style="margin:0; white-space:pre-wrap; word-break:break-word; font-size:11px; line-height:1.35; opacity:.92;"></pre>',
      '</details>'
    ].join("");

    // mini KPI style
    var style = el("style");
    style.textContent = [
      "#vsp-runs-scan-panel-ui-v1 .vsp-kpi-mini{",
      "  border:1px solid rgba(255,255,255,.08); border-radius:14px; padding:10px 12px;",
      "  background:rgba(5,8,20,.35);",
      "}",
      "#vsp-runs-scan-panel-ui-v1 .vsp-kpi-mini .k{font-size:11px; opacity:.72; margin-bottom:4px}",
      "#vsp-runs-scan-panel-ui-v1 .vsp-kpi-mini .v{font-size:14px; font-weight:800; letter-spacing:.2px}",
      "#vsp-runs-scan-panel-ui-v1 .pill{padding:6px 10px; border-radius:999px; border:1px solid rgba(255,255,255,.10); font-size:11px; font-weight:800; opacity:.95}",
      "#vsp-runs-scan-panel-ui-v1 .pill.ok{background:rgba(16,185,129,.12)}",
      "#vsp-runs-scan-panel-ui-v1 .pill.warn{background:rgba(245,158,11,.12)}",
      "#vsp-runs-scan-panel-ui-v1 .pill.bad{background:rgba(239,68,68,.12)}",
      "#vsp-runs-scan-panel-ui-v1 .pill.neu{background:rgba(148,163,184,.10)}"
    ].join("\n");
    panel.appendChild(style);

    root.prepend(panel);
    return panel;
  }

  function setMini(id, key, val) {
    var box = document.getElementById(id);
    if (!box) return;
    box.innerHTML = '<div class="k">' + safeText(key) + '</div><div class="v">' + safeText(val) + '</div>';
  }

  function setBadges(data) {
    var wrap = document.getElementById("vsp-runs-scan-badges");
    if (!wrap) return;
    wrap.innerHTML = "";
    var gate = (data && data.gate) ? String(data.gate) : "—";
    var st = (data && data.status) ? String(data.status) : "—";
    var hf = (data && data.flag && data.flag.has_findings != null) ? ("has_findings=" + data.flag.has_findings) : "has_findings=?";
    function pill(txt, cls){ var p=el("div",{class:"pill "+cls}); p.textContent=txt; return p; }

    var clsGate = gate === "PASS" ? "ok" : (gate === "FAIL" ? "bad" : "neu");
    var clsSt = (st === "DONE" || st === "SUCCESS") ? "ok" : (st === "FAILED" ? "bad" : "warn");
    wrap.appendChild(pill("GATE: " + gate, clsGate));
    wrap.appendChild(pill("STATUS: " + st, clsSt));
    wrap.appendChild(pill(hf, (String(hf).endsWith("=1") ? "warn" : "neu")));
  }

  var pollCtl = { stop:false, timer:null, reqId:null };

  function stopPolling(msg) {
    pollCtl.stop = true;
    pollCtl.reqId = null;
    if (pollCtl.timer) { clearTimeout(pollCtl.timer); pollCtl.timer = null; }
    var m = document.getElementById("vsp-scan-msg");
    if (m && msg) m.innerHTML = '<span style="opacity:.8">['+safeText(nowTS())+']</span> ' + safeText(msg);
  }

  async function poll(reqId) {
    pollCtl.stop = false;
    pollCtl.reqId = reqId;

    while (!pollCtl.stop) {
      try {
        var data = await apiJson("/api/vsp/run_status/" + encodeURIComponent(reqId));
        setBadges(data);

        setMini("vsp-mini-status", "STATUS", data.status || "—");
        setMini("vsp-mini-gate", "GATE", data.gate || "—");
        setMini("vsp-mini-final", "FINAL RC", (data.final != null ? String(data.final) : "—"));
        setMini("vsp-mini-runid", "CI RUN_ID", data.ci_run_id || "—");

        var tail = document.getElementById("vsp-scan-tail");
        if (tail) {
          var lines = Array.isArray(data.tail) ? data.tail : [];
          tail.textContent = lines.join("\n");
        }

        var msg = document.getElementById("vsp-scan-msg");
        if (msg) {
          msg.innerHTML = '<span style="opacity:.8">['+safeText(nowTS())+']</span> '
            + 'Polling <b>' + safeText(reqId) + '</b>'
            + (data.ci_run_id ? (' → <b>'+safeText(data.ci_run_id)+'</b>') : '');
        }

        // terminal conditions
        var st = String(data.status || "").toUpperCase();
        if (st === "DONE" || st === "SUCCESS" || st === "FAILED") {
          // stop polling automatically
          stopPolling("Terminal status: " + st);
          return;
        }

      } catch (e) {
        var msg2 = document.getElementById("vsp-scan-msg");
        if (msg2) msg2.innerHTML = '<span style="opacity:.8">['+safeText(nowTS())+']</span> '
          + '<span style="color:#FCA5A5; font-weight:800">Polling error:</span> ' + safeText(e.message || String(e));
      }

      await wait(2000);
    }
  }

  async function runScan() {
    var target = (document.getElementById("vsp-scan-target") || {}).value || "";
    var profile = (document.getElementById("vsp-scan-profile") || {}).value || "FULL_EXT";
    var mode = (document.getElementById("vsp-scan-mode") || {}).value || "local";

    // defaults
    if (!target.trim()) target = "/home/test/Data/SECURITY-10-10-v4";

    // persist
    try {
      localStorage.setItem("vsp_scan_target", target);
      localStorage.setItem("vsp_scan_profile", profile);
      localStorage.setItem("vsp_scan_mode", mode);
    } catch (e) {}

    stopPolling(); // stop previous polling
    var msg = document.getElementById("vsp-scan-msg");
    if (msg) msg.innerHTML = '<span style="opacity:.8">['+safeText(nowTS())+']</span> Triggering scan...';

    var body = {
      mode: mode,
      profile: profile,
      target_type: "path",
      target: target
    };

    try {
      var res = await apiJson("/api/vsp/run", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body)
      });

      var reqId = res.request_id || res.req_id || res.id;
      if (!reqId) {
        throw new Error("No request_id returned from /api/vsp/run");
      }

      if (msg) {
        msg.innerHTML = '<span style="opacity:.8">['+safeText(nowTS())+']</span> '
          + '<b>Accepted</b> → request_id=<b>' + safeText(reqId) + '</b>'
          + (res.ci_mode ? (' • ci_mode=' + safeText(res.ci_mode)) : '')
          + (res.message ? (' • ' + safeText(res.message)) : '');
      }

      // immediate poll
      poll(reqId);

    } catch (e) {
      if (msg) msg.innerHTML = '<span style="opacity:.8">['+safeText(nowTS())+']</span> '
        + '<span style="color:#FCA5A5; font-weight:800">Run error:</span> ' + safeText(e.message || String(e));
    }
  }

  function boot() {
    var pane = findRunsPane();
    if (!pane) return false;

    var panel = ensurePanel(pane);

    // load saved defaults
    try {
      var t = localStorage.getItem("vsp_scan_target");
      var p = localStorage.getItem("vsp_scan_profile");
      var m = localStorage.getItem("vsp_scan_mode");
      if (t) $("#vsp-scan-target", panel).value = t;
      else $("#vsp-scan-target", panel).value = "/home/test/Data/SECURITY-10-10-v4";
      if (p) $("#vsp-scan-profile", panel).value = p;
      if (m) $("#vsp-scan-mode", panel).value = m;
    } catch (e) {
      $("#vsp-scan-target", panel).value = "/home/test/Data/SECURITY-10-10-v4";
    }

    // bind events
    var btn = $("#vsp-scan-run", panel);
    var stop = $("#vsp-scan-stop", panel);
    if (btn) btn.addEventListener("click", function(){ runScan(); });
    if (stop) stop.addEventListener("click", function(){ stopPolling("Stopped polling by user."); });

    // init minis
    setMini("vsp-mini-status", "STATUS", "—");
    setMini("vsp-mini-gate", "GATE", "—");
    setMini("vsp-mini-final", "FINAL RC", "—");
    setMini("vsp-mini-runid", "CI RUN_ID", "—");
    setBadges({status:"—", gate:"—", flag:{has_findings:"?"}});

    return true;
  }

  // Run now + on hash changes (tab switch)
  function tryBootLoop() {
    if (boot()) return;
    // keep trying a bit (router loads panes async)
    var n = 0;
    var it = setInterval(function(){
      n++;
      if (boot() || n > 50) clearInterval(it);
    }, 200);
  }

  window.addEventListener("hashchange", function(){ tryBootLoop(); });
  window.addEventListener("load", function(){ tryBootLoop(); });
  // also run immediately if DOM already there
  tryBootLoop();

})();
JS

echo "[OK] wrote $JS"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Template not found: $TPL"
  exit 1
fi

BK="${TPL}.bak_runs_scan_panel_ui_v1_$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$BK"
echo "[BACKUP] $BK"

# insert script tag if missing (before </head> ideally)
if grep -q "vsp_runs_scan_panel_ui_v1.js" "$TPL"; then
  echo "[SKIP] Script tag already present."
else
  if grep -qi "</head>" "$TPL"; then
    python3 - << 'PY'
from pathlib import Path
import re
tpl = Path("/home/test/Data/SECURITY_BUNDLE/ui/templates/vsp_dashboard_2025.html")
txt = tpl.read_text(encoding="utf-8", errors="ignore")
tag = '<script src="/static/js/vsp_runs_scan_panel_ui_v1.js" defer></script>\n'
txt2, n = re.subn(r'(?i)</head>', tag + '</head>', txt, count=1)
if n == 0:
    raise SystemExit("[ERR] Cannot inject tag (no </head>)")
tpl.write_text(txt2, encoding="utf-8")
print("[OK] injected script tag before </head>")
PY
  else
    echo "[WARN] No </head> found, appending tag at end."
    echo "$TAG" >> "$TPL"
  fi
fi

echo
echo "[DONE] Now restart 8910 and open Runs tab."
echo "Restart:"
echo "  pkill -f vsp_demo_app.py || true"
echo "  nohup python3 $ROOT/vsp_demo_app.py > $ROOT/out_ci/ui_8910.log 2>&1 &"
