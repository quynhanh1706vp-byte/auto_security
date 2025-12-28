// === VSP RULE OVERRIDES – FIX V3 ===

function loadRules() {
  fetch("/api/vsp/rules/get")
    .then(r => r.json())
    .then(json => {
      if (!json.ok) return;

      const tbody = $("#rules-body");
      tbody.empty();

      json.items.forEach(rule => {
        const sev = rule.severity_effective.toLowerCase();
        tbody.append(`
          <tr>
            <td>${rule.tool}</td>
            <td>${rule.rule_id}</td>
            <td>${rule.severity_raw}</td>
            <td class="sev-${sev}">${rule.severity_effective}</td>
            <td>${rule.reason || "-"}</td>
          </tr>
        `);
      });
    })
    .catch(err => console.error("[RULES] Error", err));
}

document.addEventListener("DOMContentLoaded", loadRules);
