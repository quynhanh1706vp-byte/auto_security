// ======================= VSP_PATCH_5TABS_V2_BASELINE_V1 =======================
//
// File này giữ vai trò "patch container" cho UI 5 tab.
// Hiện tại chỉ log nhẹ để tránh 404 / SyntaxError.
// Tất cả logic chính về dashboard, runs, datasource, settings, overrides
// đang được xử lý trong các file JS khác (vd: vsp_dashboard_live_v2.js, vsp_ui_main.js).
//
// Khi cần thêm patch mới (extras, top risk, noisy paths...), sẽ tạo file JS riêng.

document.addEventListener("DOMContentLoaded", () => {
  try {
    console.log("[VSP_PATCH_5TABS_V2] baseline loaded");
    // Chưa có patch bổ sung nào ở V1.
  } catch (err) {
    console.error("[VSP_PATCH_5TABS_V2][ERR]", err);
  }
});


// ======================= VSP_TOP_CWE_FIX_FROM_PATCH_V1 =======================
// Sau khi layout 5 tab load xong, sửa TOP IMPACTED CWE từ [object Object] thành mã CWE/id thật.
document.addEventListener("DOMContentLoaded", () => {
  // đợi mọi script khác chạy xong
  setTimeout(async () => {
    try {
      const res = await fetch("/api/vsp/dashboard_v3");
      const data = await res.json();
      if (!data.ok) {
        console.warn("[VSP_TOP_CWE_FIX] dashboard_v3 not ok");
        return;
      }

      const top = (data.top_cwe && data.top_cwe[0]) || null;
      const val = (top && (top.cwe || top.id)) || "–";

      let replaced = 0;
      const nodes = document.querySelectorAll("span,div,strong,h1,h2,h3,p");

      nodes.forEach(el => {
        const t = (el.textContent || "").trim();
        if (t === "[object Object]") {
          el.textContent = val;
          replaced++;
        }
      });

      console.log("[VSP_TOP_CWE_FIX] replaced", replaced, "node(s) with", val);
    } catch (e) {
      console.warn("[VSP_TOP_CWE_FIX] error", e);
    }
  }, 1500);
});


// ======================= VSP_TOP_RISK_EMPTY_MSG_V1 =======================
// Nếu bảng Top risk findings không có hàng dữ liệu CRIT/HIGH,
// hiển thị 1 dòng message rõ ràng.
document.addEventListener("DOMContentLoaded", () => {
  setTimeout(() => {
    try {
      // Ưu tiên body có id rõ ràng
      let body = document.getElementById("tbl-top-risk-body");

      // Nếu không có thì tìm table có chứa text 'Top risk findings'
      if (!body) {
        const tables = document.querySelectorAll("table");
        tables.forEach(tbl => {
          const txt = (tbl.textContent || "").toUpperCase();
          if (txt.includes("TOP RISK FINDINGS") && !body) {
            body = tbl.querySelector("tbody") || tbl;
          }
        });
      }

      if (!body) return;

      const rows = Array.from(body.querySelectorAll("tr"));
      const hasData = rows.some(tr => {
        const t = (tr.textContent || "").trim();
        if (!t) return false;
        const upper = t.toUpperCase();
        if (upper.includes("SEVERITY") && upper.includes("TOOL")) return false;
        if (t == "-" || t == "–" || t == "- - - -") return false;
        return True;
      });

      if (hasData) return;

      body.innerHTML = `
        <tr>
          <td colspan="5" style="text-align:center; color:#ccc;">
            No critical/high findings in this run (all findings are MED/LOW/INFO/TRACE).
          </td>
        </tr>
      `;
      console.log("[VSP_TOP_RISK_EMPTY_MSG] injected message row");
    } catch (e) {
      console.warn("[VSP_TOP_RISK_EMPTY_MSG] error", e);
    }
  }, 1600);
});
