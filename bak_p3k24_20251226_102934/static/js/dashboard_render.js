
function __cioNormalizeRunsV3(j){
  // Accept {runs:[...]} or legacy-like shapes
  if(!j) return [];
  if(Array.isArray(__cioNormalizeRunsV3(j))) return __cioNormalizeRunsV3(j);
  if(Array.isArray(j.items)) return j.items;
  if(Array.isArray(j.data)) return j.data;
  return [];
}

"use strict";


// __VSP_CIO_HELPER_V1
(function(){
  try{
    window.__VSP_CIO = window.__VSP_CIO || {};
    const qs = new URLSearchParams(location.search);
    window.__VSP_CIO.debug = (qs.get("debug")==="1") || (localStorage.getItem("VSP_DEBUG")==="1");
    window.__VSP_CIO.visible = ()=>document.visibilityState === "visible";
    window.__VSP_CIO.sleep = (ms)=>new Promise(r=>setTimeout(r, ms));
    window.__VSP_CIO.api = {
      ridLatestV3: ()=>"/api/vsp/rid_latest_v3",
      dashboardV3: (rid)=> rid ? `/api/vsp/dashboard_v3?rid=${encodeURIComponent(rid)}` : "/api/vsp/dashboard_v3",
      runsV3: (limit,offset)=>`/api/vsp/runs_v3?limit=${limit||50}&offset=${offset||0}`,
      gateV3: (rid)=>`/api/vsp/run_gate_v3?rid=${encodeURIComponent(rid||"")}`,
      findingsV3: (rid,limit,offset)=>`/api/vsp/findings_v3?rid=${encodeURIComponent(rid||"")}&limit=${limit||100}&offset=${offset||0}`,
      artifactV3: (rid,kind,download)=>`/api/vsp/artifact_v3?rid=${encodeURIComponent(rid||"")}&kind=${encodeURIComponent(kind||"")}${download?"&download=1":""}`
    };
  }catch(_){}
})();

/**
 * VSP DASHBOARD RENDER
 * - Không đụng tới logic KPI / Donut / Top Findings / Top Modules / Critical-High by Tool
 * - Chỉ bổ sung:
 *    + Trend – Findings over time  (dùng renderTrendFindingsOverTime)
 *    + Top CWE Exposure            (dùng renderTopCWEExposure)
 * - Dùng data:
 *    + /api/vsp/runs_v3?limit=80&offset=0    → lịch sử các RUN
 *    + /api/vsp/dashboard_v3     → thống kê chung, trong đó có top_cwe / cwe_stats (sau này BE build)
 */

(function () {
  // --- Helpers chung -------------------------------------------------------

  function onReady(fn) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", fn);
    } else {
      fn();
    }
  }

  function textEquals(el, expected) {
    if (!el) return false;
    var txt = (el.textContent || "").trim();
    return txt.toLowerCase() === String(expected || "").trim().toLowerCase();
  }

  /**
   * Tìm card theo tiêu đề (phần text "TREND – FINDINGS OVER TIME", "TOP CWE EXPOSURE", ...)
   * để không phụ thuộc ID cứng, tránh phá các tab khác.
   */
  function findCardByTitle(titleText) {
    var candidates = document.querySelectorAll(
      ".chart-title-main, .vsp-card-title, .card-title"
    );
    for (var i = 0; i < candidates.length; i++) {
      var h = candidates[i];
      if (textEquals(h, titleText)) {
        // Card = phần container lớn hơn bọc quanh title
        // Lùi lên 1–2 cấp là đủ bắt được card block.
        return h.closest(".vsp-card, .dashboard-card, .card") || h.parentElement;
      }
    }
    return null;
  }

  function setEmptyMessage(card, message) {
    if (!card) return;
    card.innerHTML = [
      '<div class="chart-header">',
      '  <div class="chart-title-main">',
      card.getAttribute("data-vsp-title") || "",
      "  </div>",
      "</div>",
      '<div class="chart-empty-msg">',
      message,
      "</div>",
    ].join("\n");
  }

  // --- Trend – Findings over time -----------------------------------------

  function hydrateTrendFindingsOverTime() {
    // Tìm đúng card theo text tiêu đề như trong UI
    var card = findCardByTitle("TREND – FINDINGS OVER TIME");
    if (!card) {
      // Không phải trang Dashboard, hoặc HTML khác → bỏ qua
      return;
    }

    if (typeof window.renderTrendFindingsOverTime !== "function") {
      if (window.console && console.warn) {
        console.warn(
          "[VSP][DASHBOARD] Không thấy hàm renderTrendFindingsOverTime – kiểm tra vsp_charts_full.js đã load chưa."
        );
      }
      return;
    }

    fetch("/api/vsp/runs_v3?limit=80&offset=0", {
      method: "GET",
      credentials: "same-origin",
      headers: { "Accept": "application/json" },
    })
      .then(function (res) {
        if (!res.ok) throw new Error("HTTP " + res.status);
        return res.json();
      })
      .then(function (rows) {
        if (!Array.isArray(rows) || rows.length === 0) {
          // Không có lịch sử RUN nào
          card.innerHTML = "";
          var msg = document.createElement("div");
          msg.className = "chart-empty-msg";
          msg.textContent = "No historical runs yet.";
          card.appendChild(msg);
          return;
        }

        // Lấy tối đa 10 RUN gần nhất (BE thường đã sort rồi, nhưng mình vẫn slice cho chắc)
        var data = rows.slice(0, 10);

        try {
          window.renderTrendFindingsOverTime(card, data);
        } catch (e) {
          if (window.console && console.error) {
            console.error("[VSP][DASHBOARD] Lỗi renderTrendFindingsOverTime:", e);
          }
          card.innerHTML = "";
          var err = document.createElement("div");
          err.className = "chart-empty-msg";
          err.textContent = "Cannot render trend chart.";
          card.appendChild(err);
        }
      })
      .catch(function (err) {
        if (window.console && console.error) {
          console.error("[VSP][DASHBOARD] Lỗi gọi /api/vsp/runs_v3?limit=80&offset=0:", err);
        }
        card.innerHTML = "";
        var msg = document.createElement("div");
        msg.className = "chart-empty-msg";
        msg.textContent = "Cannot load historical runs.";
        card.appendChild(msg);
      });
  }

  // --- Top CWE Exposure ----------------------------------------------------

  function extractCweBuckets(dashboardJson) {
    if (!dashboardJson || typeof dashboardJson !== "object") return [];

    // Ưu tiên dạng mảng sẵn: [{ id: 'CWE-79', count: 12 }, ...]
    if (Array.isArray(dashboardJson.top_cwe)) {
      return dashboardJson.top_cwe;
    }
    if (Array.isArray(dashboardJson.cwe_stats)) {
      return dashboardJson.cwe_stats;
    }

    // Nếu BE trả về object kiểu { "CWE-79": 12, "CWE-89": 5, ... }
    var obj = dashboardJson.cwe_stats;
    if (obj && typeof obj === "object") {
      var out = [];
      Object.keys(obj).forEach(function (key) {
        out.push({
          id: key,
          count: obj[key],
        });
      });
      // sort giảm dần
      out.sort(function (a, b) {
        return (b.count || 0) - (a.count || 0);
      });
      return out;
    }

    return [];
  }

  function hydrateTopCWEExposure() {
    var card = findCardByTitle("TOP CWE EXPOSURE");
    if (!card) {
      // Trang hiện tại có thể không có block này → bỏ qua
      return;
    }

    if (typeof window.renderTopCWEExposure !== "function") {
      if (window.console && console.warn) {
        console.warn(
          "[VSP][DASHBOARD] Không thấy hàm renderTopCWEExposure – kiểm tra vsp_charts_full.js đã load chưa."
        );
      }
      return;
    }

    fetch("/api/vsp/dashboard_v3", {
      method: "GET",
      credentials: "same-origin",
      headers: { "Accept": "application/json" },
    })
      .then(function (res) {
        if (!res.ok) throw new Error("HTTP " + res.status);
        return res.json();
      })
      .then(function (payload) {
        var buckets = extractCweBuckets(payload);

        if (!buckets || buckets.length === 0) {
          // BE chưa build cwe_stats/top_cwe → hiển thị message nhẹ nhàng
          card.innerHTML = "";
          var msg = document.createElement("div");
          msg.className = "chart-empty-msg";
          msg.textContent = "No CWE stats in this run.";
          card.appendChild(msg);
          return;
        }

        try {
          window.renderTopCWEExposure(card, buckets);
        } catch (e) {
          if (window.console && console.error) {
            console.error("[VSP][DASHBOARD] Lỗi renderTopCWEExposure:", e);
          }
          card.innerHTML = "";
          var err = document.createElement("div");
          err.className = "chart-empty-msg";
          err.textContent = "Cannot render CWE exposure.";
          card.appendChild(err);
        }
      })
      .catch(function (err) {
        if (window.console && console.error) {
          console.error("[VSP][DASHBOARD] Lỗi gọi /api/vsp/dashboard_v3:", err);
        }
        card.innerHTML = "";
        var msg = document.createElement("div");
        msg.className = "chart-empty-msg";
        msg.textContent = "Cannot load CWE stats.";
        card.appendChild(msg);
      });
  }

  // --- Khởi động trên trang Dashboard --------------------------------------

  onReady(function () {
    // Chỉ chạy nếu trên layout có các block tương ứng.
    hydrateTrendFindingsOverTime();
    hydrateTopCWEExposure();
  });
})();

/* === VSP_VERDICT_BADGE_V1 (commercial) === */
window.addEventListener("DOMContentLoaded", () => {
  (async () => {
    try {
      const dRes = await fetch("/api/vsp/dashboard_v3");
      if (!dRes.ok) return;
      const d = await dRes.json();
      const rid = d?.run_id || d?.latest_run_id || d?.current_run_id;
      if (!rid) return;

      const gpRes = await fetch(`/api/vsp/gate_policy_v2/${encodeURIComponent(rid)}`);
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
