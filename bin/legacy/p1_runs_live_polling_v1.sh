#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

JS="static/js/vsp_runs_quick_actions_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_live_poll_${TS}"
echo "[BACKUP] ${JS}.bak_live_poll_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, time

p = Path("static/js/vsp_runs_quick_actions_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RUNS_LIVE_POLLING_V1"
if marker in s:
    print("[OK] marker already present, skip")
    raise SystemExit(0)

addon = textwrap.dedent(r"""
/* VSP_P1_RUNS_LIVE_POLLING_V1 (safe: poll /api/vsp/runs?limit=1 only; triggers existing Refresh; pauses when hidden) */
(()=> {
  if (window.__vsp_p1_runs_live_polling_v1) return;
  window.__vsp_p1_runs_live_polling_v1 = true;

  try {
    if (!location || !location.pathname || !/\/runs(?:\/)?$/.test(location.pathname)) return;
  } catch (e) { return; }

  const S = {
    live: true,
    baseDelayMs: 7000,
    maxDelayMs: 60000,
    delayMs: 7000,
    lastRid: "",
    lastOkTs: 0,
    timer: null,
    running: false,
    backoffN: 0,
  };

  const now = ()=> Date.now();

  function findBtnByText(rxList){
    const btns = Array.from(document.querySelectorAll("button"));
    for (const b of btns){
      const t = (b.textContent||"").trim();
      if (!t) continue;
      for (const rx of rxList){
        if (rx.test(t)) return b;
      }
    }
    return null;
  }

  function ensureLiveUi(){
    if (document.getElementById("vsp_live_toggle_v1")) return;

    // find a reasonable toolbar parent: prefer the row that contains Refresh
    const refreshBtn = findBtnByText([/^\s*refresh\s*$/i, /^\s*làm\s*mới\s*$/i]);
    let host = refreshBtn ? refreshBtn.parentElement : null;
    if (!host) host = document.querySelector(".toolbar") || document.querySelector(".controls") || document.body;

    const wrap = document.createElement("span");
    wrap.style.display = "inline-flex";
    wrap.style.gap = "8px";
    wrap.style.alignItems = "center";
    wrap.style.marginLeft = "10px";

    const tgl = document.createElement("button");
    tgl.id = "vsp_live_toggle_v1";
    tgl.className = (refreshBtn && refreshBtn.className) ? refreshBtn.className : "btn";
    tgl.style.minWidth = "92px";
    tgl.title = "Live polling: ON/OFF (poll /api/vsp/runs?limit=1; auto refresh when RID changes)";
    tgl.textContent = "Live: ON";

    const st = document.createElement("span");
    st.id = "vsp_live_status_v1";
    st.style.opacity = "0.85";
    st.style.fontSize = "12px";
    st.textContent = "Last: --";

    tgl.addEventListener("click", ()=> {
      S.live = !S.live;
      tgl.textContent = S.live ? "Live: ON" : "Live: OFF";
      if (S.live) kick("toggle_on");
    });

    wrap.appendChild(tgl);
    wrap.appendChild(st);

    // place right after Refresh if possible, else append
    if (refreshBtn && refreshBtn.parentElement === host){
      refreshBtn.insertAdjacentElement("afterend", wrap);
    } else {
      host.appendChild(wrap);
    }
  }

  function setStatus(msg){
    const el = document.getElementById("vsp_live_status_v1");
    if (el) el.textContent = msg;
  }

  async function fetchLatestRid(){
    const url = `/api/vsp/runs?limit=1&offset=0&_=${now()}`;
    const r = await fetch(url, { cache: "no-store", credentials: "same-origin" });
    if (!r.ok) throw new Error(`runs status ${r.status}`);
    const j = await r.json();
    const it = (j && j.items && j.items[0]) ? j.items[0] : null;
    if (!it) return "";
    return (it.rid || it.run_id || it.id || "").toString();
  }

  function triggerRefresh(){
    const refreshBtn = findBtnByText([/^\s*refresh\s*$/i, /^\s*làm\s*mới\s*$/i]);
    if (refreshBtn && !refreshBtn.disabled){
      refreshBtn.click();
      return true;
    }
    return false;
  }

  function schedule(ms){
    clearTimeout(S.timer);
    S.timer = setTimeout(()=> tick("timer"), ms);
  }

  function kick(reason){
    if (!S.live) return;
    if (document.hidden) return;
    schedule(250);
  }

  async function tick(reason){
    if (!S.live) return;
    if (document.hidden) { schedule(S.baseDelayMs); return; }
    if (S.running) { schedule(500); return; }

    S.running = true;
    try {
      ensureLiveUi();

      const rid = await fetchLatestRid();
      const changed = (rid && rid !== S.lastRid);
      if (rid) S.lastRid = rid;

      S.lastOkTs = now();
      S.backoffN = 0;
      S.delayMs = S.baseDelayMs;

      const ts = new Date().toLocaleTimeString();
      setStatus(`Last: ${ts}${changed ? " • new RID" : ""}`);

      if (changed){
        // IMPORTANT: do NOT probe run_file here. Just refresh the list via existing button.
        triggerRefresh();
      }

      schedule(S.delayMs);
    } catch (e){
      S.backoffN += 1;
      S.delayMs = Math.min(S.maxDelayMs, Math.max(S.baseDelayMs, S.baseDelayMs * (2 ** Math.min(5, S.backoffN))));
      const ts = new Date().toLocaleTimeString();
      setStatus(`Last: ${ts} • err • backoff ${Math.round(S.delayMs/1000)}s`);
      schedule(S.delayMs);
    } finally {
      S.running = false;
    }
  }

  document.addEventListener("visibilitychange", ()=> {
    if (!document.hidden && S.live) kick("visible");
  });

  // boot
  ensureLiveUi();
  schedule(800);
})();
""").rstrip() + "\n"

p.write_text(s + "\n" + addon, encoding="utf-8")
print("[OK] appended:", marker)
PY

# syntax check (optional): node --check if available
if command -v node >/dev/null 2>&1; then
  node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check OK" || { echo "[ERR] node --check failed"; exit 3; }
else
  echo "[WARN] node not found; skipped syntax check"
fi

echo "[DONE] Patch applied. Restart UI service if needed."
echo "  - If you use systemd: sudo systemctl restart vsp-ui-8910.service"
echo "  - Or your launcher:  bin/p1_ui_8910_single_owner_start_v2.sh"
