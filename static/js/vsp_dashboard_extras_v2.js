// ======================= VSP_DASHBOARD_EXTRAS_V2 =======================
// Dò table theo header thay vì ID:
//  - Top risk findings  : headers ~ [Severity, Tool, Location, Rule]
//  - Top noisy paths    : headers ~ [Path, Total, Noise level]

(function () {
  console.log("[EXTRAS] script loaded (header-scan mode)");

  function norm(str) {
    return (str || "").trim().toLowerCase();
  }

  function getHeaders(table) {
    const ths = table.querySelectorAll("thead tr th");
    if (!ths.length) return [];
    return Array.prototype.map.call(ths, (th) => norm(th.textContent));
  }

  function findTableByHeaders(expected) {
    const tables = document.querySelectorAll("table");
    for (const tbl of tables) {
      const heads = getHeaders(tbl);
      if (heads.length < expected.length) continue;
      let ok = true;
      for (let i = 0; i < expected.length; i++) {
        if (!heads[i] || heads[i].indexOf(expected[i]) === -1) {
          ok = false;
          break;
        }
      }
      if (ok) return tbl;
    }
    return null;
  }

  function renderTopRisk(list) {
    const tbl = findTableByHeaders(["severity", "tool", "location", "rule"]);
    if (!tbl) {
      console.warn("[EXTRAS] Không tìm thấy table top risk theo header");
      return;
    }
    const tbody = tbl.querySelector("tbody") || tbl;
    tbody.innerHTML = "";

    if (!list || list.length === 0) {
      const tr = document.createElement("tr");
      const td = document.createElement("td");
      td.colSpan = 4;
      td.textContent = "No critical/high findings in this run.";
      td.classList.add("vsp-empty-cell");
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }

    list.forEach((item) => {
      const tr = document.createElement("tr");

      const tdSev = document.createElement("td");
      tdSev.textContent = item.severity || "-";
      tdSev.classList.add("vsp-sev", "vsp-sev-" + (item.severity || "").toLowerCase());

      const tdTool = document.createElement("td");
      tdTool.textContent = item.tool || "-";

      const tdLoc = document.createElement("td");
      tdLoc.textContent = item.location || "-";

      const tdRule = document.createElement("td");
      tdRule.textContent = item.rule_id || item.cwe || "-";

      tr.appendChild(tdSev);
      tr.appendChild(tdTool);
      tr.appendChild(tdLoc);
      tr.appendChild(tdRule);

      tbody.appendChild(tr);
    });
  }

  function renderTopNoisy(list) {
    const tbl = findTableByHeaders(["path", "total", "noise"]);
    if (!tbl) {
      console.warn("[EXTRAS] Không tìm thấy table top noisy theo header");
      return;
    }
    const tbody = tbl.querySelector("tbody") || tbl;
    tbody.innerHTML = "";

    if (!list || list.length === 0) {
      const tr = document.createElement("tr");
      const td = document.createElement("td");
      td.colSpan = 3;
      td.textContent = "No medium/low/info/trace clusters in this run.";
      td.classList.add("vsp-empty-cell");
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }

    list.forEach((item) => {
      const tr = document.createElement("tr");

      const tdPath = document.createElement("td");
      tdPath.textContent = item.path || "-";

      const tdTotal = document.createElement("td");
      tdTotal.textContent = item.total != null ? String(item.total) : "-";

      const tdNoise = document.createElement("td");
      tdNoise.textContent = item.noise_level || "-";
      tdNoise.classList.add("vsp-noise-" + (item.noise_level || "").toLowerCase());

      tr.appendChild(tdPath);
      tr.appendChild(tdTotal);
      tr.appendChild(tdNoise);

      tbody.appendChild(tr);
    });
  }

  async function init() {
    try {
      const res = await fetch("/static/data/vsp_dashboard_extras_latest.json", {
        cache: "no-store",
      });
      console.log("[EXTRAS] fetch status", res.status);
      if (!res.ok) {
        console.warn("[EXTRAS] Không load được extras JSON:", res.status);
        return;
      }
      const data = await res.json();
      console.log("[EXTRAS] Loaded extras for run", data.run_id);

      renderTopRisk(data.top_risk_findings || []);
      renderTopNoisy(data.top_noisy_paths || []);
    } catch (err) {
      console.error("[EXTRAS][ERR] Khi load extras:", err);
    }
  }

  document.addEventListener("DOMContentLoaded", init);
})();
