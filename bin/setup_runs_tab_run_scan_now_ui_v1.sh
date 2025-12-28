#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/js/vsp_runs_trigger_scan_ui_v1.js"
TPL="$ROOT/templates/vsp_dashboard_2025.html"

echo "[SETUP] ROOT=$ROOT"
echo "[SETUP] JS=$JS"
echo "[SETUP] TPL=$TPL"

mkdir -p "$(dirname "$JS")"

cat > "$JS" << 'JS'
/* VSP Runs & Reports – Run Scan Now UI (v1)
 * POST /api/vsp/run
 * Poll /api/vsp/run_status/<req_id>
 */
(function () {
  if (window.VSP_RUN_SCAN_UI_V1_LOADED) return;
  window.VSP_RUN_SCAN_UI_V1_LOADED = true;

  function el(tag, attrs, children) {
    var n = document.createElement(tag);
    attrs = attrs || {};
    Object.keys(attrs).forEach(function (k) {
      if (k === "class") n.className = attrs[k];
      else if (k === "html") n.innerHTML = attrs[k];
      else if (k === "text") n.textContent = attrs[k];
      else n.setAttribute(k, attrs[k]);
    });
    (children || []).forEach(function (c) {
      if (c == null) return;
      if (typeof c === "string") n.appendChild(document.createTextNode(c));
      else n.appendChild(c);
    });
    return n;
  }
  function qs(sel, root) { return (root || document).querySelector(sel); }

  function badge(status) {
    var map = {
      PENDING: "vsp-badge vsp-badge-warn",
      RUNNING: "vsp-badge vsp-badge-info",
      DONE: "vsp-badge vsp-badge-ok",
      FAILED: "vsp-badge vsp-badge-bad",
      UNKNOWN: "vsp-badge"
    };
    var cls = map[status] || "vsp-badge";
    return el("span", { class: cls, text: status || "UNKNOWN" });
  }

  async function postJson(url, data) {
    var r = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(data)
    });
    var t = await r.text();
    var j;
    try { j = JSON.parse(t); } catch (e) { j = { ok: false, error: "Non-JSON response", raw: t }; }
    if (!r.ok) { j.ok = false; j.http_status = r.status; }
    return j;
  }
  async function getJson(url) {
    var r = await fetch(url, { method: "GET" });
    var t = await r.text();
    var j;
    try { j = JSON.parse(t); } catch (e) { j = { ok: false, error: "Non-JSON response", raw: t }; }
    if (!r.ok) { j.ok = false; j.http_status = r.status; }
    return j;
  }

  function installStylesOnce() {
    if (document.getElementById("vsp-runscan-ui-v1-style")) return;
    var css = `
      .vsp-runscan-wrap{margin:16px 0;padding:16px;border:1px solid rgba(255,255,255,.08);border-radius:14px;background:rgba(255,255,255,.03)}
      .vsp-runscan-head{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:12px}
      .vsp-runscan-title{font-weight:700;font-size:14px;letter-spacing:.3px}
      .vsp-runscan-sub{opacity:.72;font-size:12px;margin-top:4px}
      .vsp-runscan-grid{display:grid;grid-template-columns:repeat(12,1fr);gap:10px}
      .vsp-field{grid-column:span 4;display:flex;flex-direction:column;gap:6px}
      .vsp-field label{font-size:12px;opacity:.8}
      .vsp-field input,.vsp-field select{padding:10px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.10);background:rgba(0,0,0,.25);color:inherit;outline:none}
      .vsp-field input:focus,.vsp-field select:focus{border-color:rgba(99,102,241,.55)}
      .vsp-field.wide{grid-column:span 8}
      .vsp-runscan-actions{grid-column:span 12;display:flex;gap:10px;align-items:center;margin-top:6px}
      .vsp-btn{padding:10px 12px;border-radius:12px;border:1px solid rgba(255,255,255,.10);background:rgba(99,102,241,.18);color:inherit;cursor:pointer;font-weight:650}
      .vsp-btn:hover{background:rgba(99,102,241,.28)}
      .vsp-btn.secondary{background:rgba(255,255,255,.06)}
      .vsp-btn.secondary:hover{background:rgba(255,255,255,.10)}
      .vsp-btn:disabled{opacity:.5;cursor:not-allowed}
      .vsp-hline{height:1px;background:rgba(255,255,255,.08);margin:14px 0}
      .vsp-kv{display:grid;grid-template-columns:140px 1fr;gap:6px 12px;font-size:12px}
      .vsp-kv .k{opacity:.72}
      .vsp-box{padding:12px;border-radius:12px;border:1px solid rgba(255,255,255,.08);background:rgba(0,0,0,.18)}
      .vsp-badge{padding:4px 8px;border-radius:999px;border:1px solid rgba(255,255,255,.12);font-size:11px;opacity:.95}
      .vsp-badge-ok{background:rgba(16,185,129,.15);border-color:rgba(16,185,129,.35)}
      .vsp-badge-bad{background:rgba(239,68,68,.15);border-color:rgba(239,68,68,.35)}
      .vsp-badge-info{background:rgba(59,130,246,.15);border-color:rgba(59,130,246,.35)}
      .vsp-badge-warn{background:rgba(245,158,11,.15);border-color:rgba(245,158,11,.35)}
      .vsp-mono{font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace}
      .vsp-log{white-space:pre-wrap;font-size:11px;line-height:1.45;max-height:220px;overflow:auto}
      @media (max-width: 1100px){ .vsp-field{grid-column:span 6} .vsp-field.wide{grid-column:span 12} }
    `;
    var st = document.createElement("style");
    st.id = "vsp-runscan-ui-v1-style";
    st.textContent = css;
    document.head.appendChild(st);
  }

  function findRunsPane() {
    return (
      document.getElementById("vsp-tab-runs") ||
      document.querySelector("[data-tab='runs']") ||
      document.querySelector("#tab-runs") ||
      null
    );
  }

  function ensureMountPoint(runsPane) {
    var mp = qs("#vsp-runscan-ui-v1", runsPane);
    if (mp) return mp;
    mp = el("div", { id: "vsp-runscan-ui-v1" });
    runsPane.insertBefore(mp, runsPane.firstChild);
    return mp;
  }

  async function pollStatus(reqId, ui) {
    ui.status.innerHTML = "";
    ui.status.appendChild(badge("RUNNING"));
    ui.reqId.textContent = reqId;

    var stopped = false;
    ui.stopBtn.disabled = false;
    ui.stopBtn.onclick = function () {
      stopped = true;
      ui.status.innerHTML = "";
      ui.status.appendChild(badge("UNKNOWN"));
      ui.note.textContent = "Polling stopped (manual).";
      ui.stopBtn.disabled = true;
    };

    async function tick() {
      if (stopped) return;
      var j = await getJson("/api/vsp/run_status/" + encodeURIComponent(reqId));
      if (!j || !j.ok) {
        ui.note.textContent = "Status API error: " + (j && (j.error || j.raw || j.http_status) || "unknown");
        setTimeout(tick, 3000);
        return;
      }

      ui.status.innerHTML = "";
      ui.status.appendChild(badge(j.status));

      ui.ciRunId.textContent = j.ci_run_id || "-";
      ui.gate.textContent = j.gate || "-";
      ui.finalRc.textContent = j.final || "-";
      ui.log.textContent = (j.tail || []).join("\n");

      if (j.flag && typeof j.flag.has_findings !== "undefined") ui.hasFindings.textContent = String(j.flag.has_findings);
      else ui.hasFindings.textContent = "-";

      if (j.status === "DONE" || j.status === "FAILED") {
        ui.note.textContent = "Run finished.";
        ui.stopBtn.disabled = true;
        return;
      }
      setTimeout(tick, 3000);
    }
    tick();
  }

  async function onRunClick(ui) {
    ui.note.textContent = "";
    ui.err.textContent = "";
    ui.runBtn.disabled = true;

    var payload = {
      mode: ui.mode.value,
      profile: ui.profile.value,
      target_type: "path",
      target: ui.target.value
    };

    ui.payload.textContent = JSON.stringify(payload, null, 2);

    try {
      var j = await postJson("/api/vsp/run", payload);
      if (!j || !j.ok) {
        ui.err.textContent = "Run API failed: " + JSON.stringify(j, null, 2);
        ui.runBtn.disabled = false;
        return;
      }
      var reqId = j.request_id || "";
      if (!reqId) {
        ui.err.textContent = "No request_id returned: " + JSON.stringify(j, null, 2);
        ui.runBtn.disabled = false;
        return;
      }
      ui.note.textContent = j.message || "Scan accepted.";
      await pollStatus(reqId, ui);
    } catch (e) {
      ui.err.textContent = "Exception: " + (e && e.message ? e.message : String(e));
    } finally {
      ui.runBtn.disabled = false;
    }
  }

  function render(runsPane) {
    installStylesOnce();
    var mount = ensureMountPoint(runsPane);

    var ui = {};

    var head = el("div", { class: "vsp-runscan-head" }, [
      el("div", {}, [
        el("div", { class: "vsp-runscan-title", text: "RUN SCAN NOW" }),
        el("div", { class: "vsp-runscan-sub", text: "Trigger FULL_EXT pipeline and track status (UIREQ → VSP_CI_*)." })
      ]),
      el("div", { class: "vsp-runscan-actions" }, [])
    ]);

    var grid = el("div", { class: "vsp-runscan-grid" });

    ui.mode = el("select", {}, [
      el("option", { value: "local", text: "local (LOCAL_UI)" }),
      el("option", { value: "github_ci", text: "github_ci (GITHUB_CI/UI)" }),
      el("option", { value: "jenkins_ci", text: "jenkins_ci (JENKINS_CI/UI)" })
    ]);
    ui.profile = el("select", {}, [
      el("option", { value: "FULL_EXT", text: "FULL_EXT" }),
      el("option", { value: "EXT", text: "EXT" })
    ]);
    ui.target = el("input", { value: "/home/test/Data/SECURITY-10-10-v4", spellcheck: "false" });

    grid.appendChild(el("div", { class: "vsp-field" }, [el("label", { text: "Mode" }), ui.mode]));
    grid.appendChild(el("div", { class: "vsp-field" }, [el("label", { text: "Profile" }), ui.profile]));
    grid.appendChild(el("div", { class: "vsp-field wide" }, [el("label", { text: "Target path" }), ui.target]));

    ui.runBtn = el("button", { class: "vsp-btn", text: "Run Scan Now" });
    ui.stopBtn = el("button", { class: "vsp-btn secondary", text: "Stop Poll" });
    ui.stopBtn.disabled = true;
    ui.runBtn.onclick = function () { onRunClick(ui); };

    var actions = el("div", { class: "vsp-runscan-actions" }, [
      ui.runBtn, ui.stopBtn,
      el("div", { style: "margin-left:auto; display:flex; gap:10px; align-items:center;" }, [
        el("div", { class: "vsp-mono", text: "Status:" }),
        (ui.status = el("div", {}, [badge("UNKNOWN")]))
      ])
    ]);
    grid.appendChild(actions);

    ui.reqId = el("span", { class: "vsp-mono", text: "-" });
    ui.ciRunId = el("span", { class: "vsp-mono", text: "-" });
    ui.hasFindings = el("span", { class: "vsp-mono", text: "-" });
    ui.gate = el("span", { class: "vsp-mono", text: "-" });
    ui.finalRc = el("span", { class: "vsp-mono", text: "-" });

    var kv = el("div", { class: "vsp-kv vsp-box" }, [
      el("div", { class: "k", text: "request_id" }), ui.reqId,
      el("div", { class: "k", text: "ci_run_id" }), ui.ciRunId,
      el("div", { class: "k", text: "has_findings" }), ui.hasFindings,
      el("div", { class: "k", text: "gate" }), ui.gate,
      el("div", { class: "k", text: "final_rc" }), ui.finalRc
    ]);

    ui.note = el("div", { style: "margin-top:10px; font-size:12px; opacity:.8" });
    ui.err = el("div", { style: "margin-top:8px; font-size:12px; color: rgba(239,68,68,.95)" });

    ui.payload = el("div", { class: "vsp-box vsp-mono vsp-log", text: "" });
    ui.log = el("div", { class: "vsp-box vsp-mono vsp-log", text: "" });

    mount.innerHTML = "";
    mount.appendChild(el("div", { class: "vsp-runscan-wrap" }, [
      head,
      grid,
      el("div", { class: "vsp-hline" }),
      kv,
      ui.note,
      ui.err,
      el("div", { class: "vsp-hline" }),
      el("div", { class: "vsp-runscan-sub", text: "Request payload" }),
      ui.payload,
      el("div", { style: "height:10px" }),
      el("div", { class: "vsp-runscan-sub", text: "Status log tail (from /api/vsp/run_status/<req_id>)" }),
      ui.log
    ]));
  }

  function boot() {
    var pane = findRunsPane();
    if (!pane) return;
    render(pane);
    console.log("[VSP_RUNSCAN_UI_V1] mounted");
  }

  var tries = 0;
  var iv = setInterval(function () {
    tries++;
    boot();
    if (qs("#vsp-runscan-ui-v1")) clearInterval(iv);
    if (tries > 60) clearInterval(iv);
  }, 300);
})();
JS

echo "[OK] wrote $JS"

if [ ! -f "$TPL" ]; then
  echo "[WARN] Template not found: $TPL"
  echo "      If you use a different template, add this script tag manually:"
  echo "      <script src=\"/static/js/vsp_runs_trigger_scan_ui_v1.js\" defer></script>"
  exit 0
fi

BK_TPL="${TPL}.bak_runscan_ui_v1_$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$BK_TPL"
echo "[BACKUP] $BK_TPL"

TAG='<script src="/static/js/vsp_runs_trigger_scan_ui_v1.js" defer></script>'

python3 - << PY
from pathlib import Path
tpl = Path("$TPL")
txt = tpl.read_text(encoding="utf-8", errors="ignore")
tag = $TAG.__repr__()
if tag in txt:
    print("[INFO] script tag already present.")
else:
    if "</body>" in txt:
        txt = txt.replace("</body>", "  " + tag + "\\n</body>")
        tpl.write_text(txt, encoding="utf-8")
        print("[OK] inserted script tag before </body>")
    else:
        raise SystemExit("[ERR] </body> not found in template")
PY

echo "[DONE] RunScan UI is installed. Refresh http://localhost:8910 and open Runs & Reports."
