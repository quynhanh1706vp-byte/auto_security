// VSP_DS_MINI_ANALYTICS_LIST_V1
// Data Source – mini charts (V1):
//  - Không dùng Chart.js.
//  - Hiển thị 2 card list:
//      + Top tools theo số lượng findings
//      + Top directories theo số lượng findings

(function() {
  const LOG = "[VSP_DS_MINI_LIST]";

  async function loadData() {
    const res = await fetch("/api/vsp/datasource_v2?limit=1000");
    const data = await res.json();
    console.log(LOG, "Loaded datasource_v2", data);
    return data.items || [];
  }

  function aggregate(items) {
    const severityOrder = ["CRITICAL","HIGH","MEDIUM","LOW","INFO", trace:"TRACE"];
    const byTool = {};
    const byDir  = {};

    for (const f of items) {
      const tool = (f.tool || "unknown").toString();
      let sev = (f.severity || "INFO").toString().toUpperCase();
      if (!severityOrder.includes(sev)) sev = "INFO";

      if (!byTool[tool]) {
        byTool[tool] = { total: 0 };
        severityOrder.forEach(s => (byTool[tool][s] = 0));
      }
      byTool[tool][sev] = (byTool[tool][sev] || 0) + 1;
      byTool[tool].total += 1;

      const path =
        f.path ||
        f.file ||
        f.filepath ||
        (f.location && (f.location.path || f.location.file)) ||
        f.relpath ||
        "";
      if (path) {
        const parts = String(path).split("/");
        const dir = parts.slice(0, 3).join("/") + (parts.length > 3 ? "/..." : "");
        byDir[dir] = (byDir[dir] || 0) + 1;
      }
    }

    const toolsSorted = Object.entries(byTool)
      .sort((a,b) => b[1].total - a[1].total)
      .slice(0, 8);
    const dirsSorted = Object.entries(byDir)
      .sort((a,b) => b[1] - a[1])
      .slice(0, 8);

    console.log(LOG, "Agg result", { byTool, toolsSorted, dirsSorted });
    return { byTool, toolsSorted, dirsSorted };
  }

  function ensureSection() {
    const tab = document.querySelector("#vsp-tab-datasource");
    if (!tab) return null;

    let section = document.getElementById("vsp-ds-mini-section");
    if (!section) {
      section = document.createElement("section");
      section.id = "vsp-ds-mini-section";
      section.style.marginTop = "24px";
      section.style.marginBottom = "24px";

      section.innerHTML = `
        <div style="margin-bottom: 12px;">
          <div style="font-size: 14px; font-weight: 600; letter-spacing: .08em; text-transform: uppercase; color: #e5e7eb;">
            Data Source – mini analytics
          </div>
          <div style="font-size: 12px; color: #9ca3af;">
            Top tools & top directories suy ra từ <code>findings_unified</code> đang load. 
            Chế độ list cho V1 (biểu đồ sẽ bật trong bản Enterprise+).
          </div>
        </div>
        <div style="display: grid; grid-template-columns: repeat(2,minmax(0,1fr)); gap: 16px; max-width: 100%;">
          <div id="vsp-ds-card-tools"
               style="border-radius: 16px; border: 1px solid rgba(148,163,184,0.25);
                      padding: 12px 14px 10px; background: radial-gradient(circle at top left, rgba(15,23,42,0.95), rgba(15,23,42,0.9));">
            <div style="font-size: 13px; font-weight: 600; letter-spacing: .08em; text-transform: uppercase; color: #e5e7eb;">
              Severity by tool
            </div>
            <div style="font-size: 11px; color: #9ca3af; margin-bottom: 6px;">
              Top tools theo số lượng findings (CRIT/HIGH/MED/LOW/INFO/TRACE).
            </div>
            <div id="vsp-ds-tools-list"></div>
          </div>
          <div id="vsp-ds-card-dirs"
               style="border-radius: 16px; border: 1px solid rgba(148,163,184,0.25);
                      padding: 12px 14px 10px; background: radial-gradient(circle at top left, rgba(15,23,42,0.95), rgba(15,23,42,0.9));">
            <div style="font-size: 13px; font-weight: 600; letter-spacing: .08em; text-transform: uppercase; color: #e5e7eb;">
              Top directories
            </div>
            <div style="font-size: 11px; color: #9ca3af; margin-bottom: 6px;">
              Thư mục có nhiều findings nhất (từ <code>path</code>).
            </div>
            <div id="vsp-ds-dirs-list"></div>
          </div>
        </div>
      `;
      tab.appendChild(section);
      console.log(LOG, "Đã tạo section mini analytics trong Data Source.");
    }
    return section;
  }

  function renderToolsList(container, agg) {
    if (!container) return;
    container.innerHTML = "";
    const { toolsSorted, byTool } = agg;
    if (!toolsSorted.length) {
      container.innerHTML =
        '<div style="font-size: 11px; color: #9ca3af;">Không có findings nào để tổng hợp theo tool.</div>';
      return;
    }
    toolsSorted.forEach(([tool, obj], idx) => {
      const row = document.createElement("div");
      row.style.display = "flex";
      row.style.alignItems = "center";
      row.style.justifyContent = "space-between";
      row.style.fontSize = "11px";
      row.style.color = "#e5e7eb";
      row.style.padding = "3px 0";

      const sevText =
        `C:${byTool[tool].CRITICAL||0} · ` +
        `H:${byTool[tool].HIGH||0} · ` +
        `M:${byTool[tool].MEDIUM||0} · ` +
        `L:${byTool[tool].LOW||0}`;

      row.innerHTML =
        `<span style="opacity:.6; min-width:18px;">${idx + 1}.</span>` +
        `<span style="flex:1; margin-right:8px;">${tool}</span>` +
        `<span style="opacity:.75; margin-right:8px;">${sevText}</span>` +
        `<span style="font-variant-numeric: tabular-nums;">${obj.total}</span>`;
      container.appendChild(row);
    });
  }

  function renderDirsList(container, agg) {
    if (!container) return;
    container.innerHTML = "";
    const { dirsSorted } = agg;
    if (!dirsSorted.length) {
      container.innerHTML =
        '<div style="font-size: 11px; color: #9ca3af;">Không có findings nào để tổng hợp theo thư mục.</div>';
      return;
    }
    dirsSorted.forEach(([dir, count], idx) => {
      const row = document.createElement("div");
      row.style.display = "flex";
      row.style.alignItems = "center";
      row.style.justifyContent = "space-between";
      row.style.fontSize = "11px";
      row.style.color = "#e5e7eb";
      row.style.padding = "3px 0";

      row.innerHTML =
        `<span style="opacity:.6; min-width:18px;">${idx + 1}.</span>` +
        `<span style="flex:1; margin-right:8px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${dir}</span>` +
        `<span style="font-variant-numeric: tabular-nums;">${count}</span>`;
      container.appendChild(row);
    });
  }

  async function init() {
    const section = ensureSection();
    if (!section) {
      console.warn(LOG, "Không tìm thấy tab Data Source.");
      return;
    }

    let items;
    try {
      items = await loadData();
    } catch (e) {
      console.warn(LOG, "Lỗi load datasource_v2:", e);
      return;
    }

    if (!items.length) {
      console.log(LOG, "Không có findings để hiển thị mini analytics.");
      return;
    }

    const agg = aggregate(items);

    renderToolsList(
      document.getElementById("vsp-ds-tools-list"),
      agg
    );
    renderDirsList(
      document.getElementById("vsp-ds-dirs-list"),
      agg
    );
  }

  function start() {
    let tries = 0;
    const maxTries = 30;
    const timer = setInterval(() => {
      const tab = document.querySelector("#vsp-tab-datasource");
      if (tab) {
        clearInterval(timer);
        init();
      } else if (++tries >= maxTries) {
        clearInterval(timer);
        console.warn(LOG, "Give up sau", tries, "lần – không thấy tab Data Source.");
      }
    }, 400);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start);
  } else {
    start();
  }
})();
