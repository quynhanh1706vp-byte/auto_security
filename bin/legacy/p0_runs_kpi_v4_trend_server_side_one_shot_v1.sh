#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need systemctl; need curl

TS="$(date +%Y%m%d_%H%M%S)"
W="wsgi_vsp_ui_gateway.py"
JS="static/js/vsp_runs_kpi_compact_v3.js"

[ -f "$W" ]  || { echo "[ERR] missing $W"; exit 2; }
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$W"  "${W}.bak_kpi_v4_${TS}"
cp -f "$JS" "${JS}.bak_kpi_v4_${TS}"
echo "[BACKUP] ${W}.bak_kpi_v4_${TS}"
echo "[BACKUP] ${JS}.bak_kpi_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

w = Path("wsgi_vsp_ui_gateway.py")
s = w.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_RUNS_KPI_V4_TREND_SERVER_SIDE_V1"
if marker not in s:
    block = textwrap.dedent(r'''
    # ===================== VSP_P0_RUNS_KPI_V4_TREND_SERVER_SIDE_V1 =====================
    try:
        import json, time
        from pathlib import Path as _Path
        from datetime import datetime as _dt
        from flask import jsonify as _jsonify, request as _request
        _VSP_KPI_V4_IMPORT_ERR = None
    except Exception as _e:
        _VSP_KPI_V4_IMPORT_ERR = _e

    def _vsp_pick_flask_app_v4():
        for _n in ("app","application"):
            _o = globals().get(_n)
            if _o is None:
                continue
            # must be Flask-like
            if hasattr(_o, "add_url_rule") and hasattr(_o, "route"):
                return _o
        return None

    def _vsp_safe_read_json_v4(p: _Path):
        try:
            return json.loads(p.read_text(encoding="utf-8", errors="replace"))
        except Exception:
            return None

    def _vsp_list_run_dirs_v4(roots, cap=3000):
        dirs = []
        for r in roots:
            rr = _Path(r)
            if not rr.exists():
                continue
            try:
                for p in rr.iterdir():
                    if not p.is_dir():
                        continue
                    n = p.name
                    if n.startswith(("RUN_","VSP_CI_RUN_","BOSS_BUNDLE_")):
                        dirs.append(p)
            except Exception:
                pass
        def _mtime(x):
            try:
                return x.stat().st_mtime
            except Exception:
                return 0
        dirs.sort(key=_mtime, reverse=True)
        return dirs[:cap]

    def vsp_ui_runs_kpi_v4():
        if _VSP_KPI_V4_IMPORT_ERR is not None:
            return _jsonify(ok=False, err="import_failed", detail=str(_VSP_KPI_V4_IMPORT_ERR)), 500

        # days window
        try:
            days = int((_request.args.get("days","30") or "30").strip())
        except Exception:
            days = 30
        days = max(1, min(days, 365))

        now = time.time()
        cutoff = now - days*86400

        roots = [
            "/home/test/Data/SECURITY_BUNDLE/out",
            "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        ]

        run_dirs = _vsp_list_run_dirs_v4(roots, cap=4000)

        total_runs = 0
        has_gate = 0
        has_findings = 0
        latest_rid = ""

        by_overall = {"GREEN":0,"AMBER":0,"RED":0,"UNKNOWN":0}
        bucket = {}  # YYYY-mm-dd -> counts

        for rd in run_dirs:
            rid = rd.name
            try:
                ts = rd.stat().st_mtime
            except Exception:
                ts = now

            if ts < cutoff:
                continue

            total_runs += 1
            if not latest_rid:
                latest_rid = rid

            # findings presence (cheap)
            if (rd/"findings_unified.json").exists() or (rd/"reports"/"findings_unified.json").exists():
                has_findings += 1

            # gate summary candidates
            j = _vsp_safe_read_json_v4(rd/"run_gate_summary.json") or _vsp_safe_read_json_v4(rd/"reports"/"run_gate_summary.json")
            if j:
                has_gate += 1
                ov = (j.get("overall_status") or j.get("overall") or j.get("status") or "UNKNOWN")
                ov = str(ov).upper().strip()
                if ov not in by_overall:
                    ov = "UNKNOWN"
            else:
                ov = "UNKNOWN"

            by_overall[ov] = by_overall.get(ov, 0) + 1

            dkey = _dt.fromtimestamp(ts).astimezone().strftime("%Y-%m-%d")
            b = bucket.get(dkey)
            if b is None:
                b = {"GREEN":0,"AMBER":0,"RED":0,"UNKNOWN":0}
                bucket[dkey] = b
            b[ov] = b.get(ov, 0) + 1

        labels = sorted(bucket.keys())
        series = {k:[bucket[d].get(k,0) for d in labels] for k in ["GREEN","AMBER","RED","UNKNOWN"]}

        return _jsonify(
            ok=True,
            total_runs=total_runs,
            latest_rid=latest_rid,
            by_overall=by_overall,
            has_findings=has_findings,
            has_gate=has_gate,
            trend_overall={"labels":labels, "series":series},
            ts=int(now),
        )

    try:
        _app_v4 = _vsp_pick_flask_app_v4()
        if _app_v4 is not None:
            _app_v4.add_url_rule("/api/ui/runs_kpi_v4", "vsp_ui_runs_kpi_v4", vsp_ui_runs_kpi_v4, methods=["GET"])
            print("[VSP_KPI_V4] mounted /api/ui/runs_kpi_v4")
        else:
            print("[VSP_KPI_V4] no Flask app found to mount")
    except Exception as _e:
        print("[VSP_KPI_V4] mount failed:", _e)
    # ===================== /VSP_P0_RUNS_KPI_V4_TREND_SERVER_SIDE_V1 =====================
    ''').lstrip("\n")

    s = s.rstrip() + "\n\n" + block + "\n"
    w.write_text(s, encoding="utf-8")
    print("[OK] appended KPI v4 endpoint block")
else:
    print("[OK] KPI v4 block already present (skip append)")

# rewrite compact JS: prefer v4, fallback v2; render trend from response; NO run_file_allow
js = Path("static/js/vsp_runs_kpi_compact_v3.js")
js.write_text(textwrap.dedent(r"""
/* VSP_P2_RUNS_KPI_COMPACT_V3_SAFE_V4 (single endpoint; layout-safe; no run_file_allow) */
(()=> {
  if (window.__vsp_runs_kpi_compact_v3_safe_v4) return;
  window.__vsp_runs_kpi_compact_v3_safe_v4 = true;

  const $ = (q)=> document.querySelector(q);

  let inflight = false;
  let lastTs = 0;
  let lastDays = null;

  function setText(id, v){
    const el = document.getElementById(id);
    if (!el) return;
    el.textContent = (v===null || v===undefined || v==="") ? "—" : String(v);
  }

  function hideHeavy(){
    const ids = ["vsp_runs_kpi_canvas_overall","vsp_runs_kpi_canvas_sev","vsp_runs_kpi_canvas_wrap_overall","vsp_runs_kpi_canvas_wrap_sev"];
    for (const id of ids){
      const el = document.getElementById(id);
      if (el) el.style.display = "none";
    }
  }

  async function fetchKpi(days){
    const now = Date.now();
    const d = String(days || 30);

    if (inflight) return null;
    if (lastDays === d && (now - lastTs) < 2500) return null;

    inflight = true;
    lastDays = d;
    lastTs = now;

    const q = encodeURIComponent(d);
    const urls = [
      `/api/ui/runs_kpi_v4?days=${q}`,
      `/api/ui/runs_kpi_v2?days=${q}`,
      `/api/ui/runs_kpi_v1?days=${q}`,
    ];

    try{
      let lastErr = null;
      for (const u of urls){
        try{
          const r = await fetch(u, {cache:"no-store"});
          const j = await r.json();
          if (j && j.ok) return j;
          lastErr = new Error(j?.err || "not ok");
        }catch(e){ lastErr = e; }
      }
      throw lastErr || new Error("kpi fetch failed");
    } finally {
      inflight = false;
    }
  }

  function renderTrendOverall(resp){
    const root = document.getElementById("vsp_runs_kpi_trend_overall_compact");
    if (!root) return;

    const t = resp && resp.trend_overall;
    const labels = t && Array.isArray(t.labels) ? t.labels : [];
    const series = t && t.series ? t.series : null;

    if (!labels.length || !series){
      root.innerHTML = '<div style="color:#94a3b8;font-size:12px">No trend data (server-side)</div>';
      return;
    }

    // last 14 points
    const take = Math.min(14, labels.length);
    const start = labels.length - take;

    const keys = ["GREEN","AMBER","RED","UNKNOWN"];
    let max = 1;
    for (let i=start;i<labels.length;i++){
      let sum = 0;
      for (const k of keys) sum += (Number((series[k]||[])[i]||0) || 0);
      if (sum > max) max = sum;
    }

    const rows = [];
    for (let i=start;i<labels.length;i++){
      const d = labels[i];
      const parts = [];
      for (const k of keys){
        const v = Number((series[k]||[])[i]||0) || 0;
        const w = Math.round((v / max) * 100);
        parts.push(`<div title="${k}: ${v}" style="height:10px;width:${w}%;background:rgba(148,163,184,.18);border-radius:10px;margin-right:6px"></div>`);
      }
      rows.push(`
        <div style="display:flex;align-items:center;gap:10px;margin:6px 0">
          <div style="width:92px;font-size:11px;color:#94a3b8">${d}</div>
          <div style="flex:1;display:flex;align-items:center;gap:6px">${parts.join("")}</div>
        </div>
      `);
    }

    root.innerHTML = `
      <div style="margin-top:6px;padding-top:8px;border-top:1px solid rgba(148,163,184,.10)">
        <div style="font-size:12px;color:#cbd5e1;margin-bottom:4px">Overall trend (server)</div>
        ${rows.join("")}
      </div>
    `;
  }

  async function fill(days){
    hideHeavy();
    setText("vsp_runs_kpi_meta", "Loading KPI…");

    try{
      const j = await fetchKpi(days);
      if (!j) return;

      setText("vsp_runs_kpi_total_runs_window", j.total_runs);
      const bo = j.by_overall || {};
      setText("vsp_runs_kpi_GREEN", bo.GREEN ?? 0);
      setText("vsp_runs_kpi_AMBER", bo.AMBER ?? 0);
      setText("vsp_runs_kpi_RED", bo.RED ?? 0);
      setText("vsp_runs_kpi_UNKNOWN", bo.UNKNOWN ?? 0);
      setText("vsp_runs_kpi_findings", j.has_findings ?? "—");
      setText("vsp_runs_kpi_latest", j.latest_rid ?? "—");
      setText("vsp_runs_kpi_meta", `ts=${j.ts} • gate=${j.has_gate ?? "—"} • source=v4/v2`);

      renderTrendOverall(j);
    }catch(e){
      setText("vsp_runs_kpi_meta", `KPI error: ${String(e && e.message ? e.message : e)}`);
    }
  }

  function boot(){
    const sel = document.getElementById("vsp_runs_kpi_window_days");
    const btn = document.getElementById("vsp_runs_kpi_reload_btn");
    const days = sel ? (parseInt(sel.value||"30",10) || 30) : 30;

    if (sel){
      sel.addEventListener("change", ()=> fill(parseInt(sel.value||"30",10) || 30));
    }
    if (btn){
      btn.addEventListener("click", ()=> fill(sel ? (parseInt(sel.value||"30",10) || 30) : 30));
    }
    fill(days);
  }

  if (document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", boot, {once:true});
  } else {
    boot();
  }
})();
""").lstrip(), encoding="utf-8")
print("[OK] rewrote compact KPI JS to prefer v4 + server trend")
PY

echo "== [CHECK] py_compile =="
python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== [CHECK] node --check =="
node --check "$JS"
echo "[OK] node --check OK"

echo "== restart =="
systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.6

echo "== sanity v4 =="
curl -sS "http://127.0.0.1:8910/api/ui/runs_kpi_v4?days=14" | head -c 500; echo
echo "[DONE] Hard reload /runs (Ctrl+Shift+R)."
