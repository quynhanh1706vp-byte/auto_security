#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/dashboard_render.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_verdictbadge_${TS}"
echo "[BACKUP] $F.bak_verdictbadge_${TS}"

# idempotent
if grep -q "VSP_VERDICT_BADGE_V1" "$F"; then
  echo "[OK] verdict badge already patched, skip"
  exit 0
fi

cat >> "$F" <<'JS'

/* === VSP_VERDICT_BADGE_V1 (commercial) === */
window.addEventListener("DOMContentLoaded", () => {
  (async () => {
    try {
      const dRes = await fetch("/api/vsp/dashboard_v3");
      if (!dRes.ok) return;
      const d = await dRes.json();
      const rid = d?.run_id || d?.latest_run_id || d?.current_run_id;
      if (!rid) return;

      const gpRes = await fetch(`/api/vsp/gate_policy_v1/${encodeURIComponent(rid)}`);
      if (!gpRes.ok) return;
      const gp = await gpRes.json();

      const verdict = (gp?.verdict || "UNKNOWN").toUpperCase();
      const degN = Number(gp?.degraded_n || 0);
      const reasons = Array.isArray(gp?.reasons) ? gp.reasons : (gp?.reasons ? [String(gp.reasons)] : []);

      // pick anchor: try common headers; fallback to body top
      const anchor =
        document.querySelector(".vsp-page-title") ||
        document.querySelector("h1") ||
        document.querySelector(".dashboard-title") ||
        document.body;

      const wrap = document.createElement("div");
      wrap.style.display = "flex";
      wrap.style.gap = "10px";
      wrap.style.alignItems = "center";
      wrap.style.margin = "10px 0";

      const badge = document.createElement("span");
      badge.textContent = `VERDICT: ${verdict}${degN ? ` · DEG:${degN}` : ""}`;
      badge.style.fontWeight = "700";
      badge.style.fontSize = "12px";
      badge.style.padding = "6px 10px";
      badge.style.borderRadius = "999px";
      badge.style.border = "1px solid rgba(255,255,255,0.18)";
      badge.style.background = "rgba(15,23,42,0.65)";

      // simple color hint without needing CSS variables
      if (verdict.includes("RED") || verdict.includes("FAIL")) {
        badge.style.boxShadow = "0 0 0 1px rgba(239,68,68,0.25) inset";
      } else if (verdict.includes("AMBER") || verdict.includes("WARN")) {
        badge.style.boxShadow = "0 0 0 1px rgba(245,158,11,0.25) inset";
      } else if (verdict.includes("GREEN") || verdict.includes("PASS")) {
        badge.style.boxShadow = "0 0 0 1px rgba(34,197,94,0.25) inset";
      } else {
        badge.style.boxShadow = "0 0 0 1px rgba(148,163,184,0.25) inset";
      }

      const info = document.createElement("span");
      info.textContent = reasons.length ? reasons.slice(0, 3).join(" · ") : "no reasons";
      info.style.opacity = "0.85";
      info.style.fontSize = "12px";

      wrap.appendChild(badge);
      wrap.appendChild(info);

      // insert near top of anchor
      if (anchor === document.body) {
        document.body.insertBefore(wrap, document.body.firstChild);
      } else {
        anchor.parentElement?.insertBefore(wrap, anchor.nextSibling);
      }
    } catch (e) {
      // keep silent in commercial UI
      // console.warn("[VSP_VERDICT_BADGE_V1]", e);
    }
  })();
});
/* === /VSP_VERDICT_BADGE_V1 === */
JS

echo "[OK] appended verdict badge hook"
echo "[NEXT] hard refresh browser (Ctrl+Shift+R)"
