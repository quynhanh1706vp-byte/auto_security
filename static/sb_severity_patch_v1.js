/**
 * sb_severity_patch_v1.js
 * Dùng text 'C=..., H=..., M=..., L=...' trong card SEVERITY BUCKETS
 * để set width % cho 4 thanh cột.
 */
document.addEventListener("DOMContentLoaded", function () {
  try {
    var cards = Array.from(document.querySelectorAll(".sb-card, .card, .panel"));
    var sevCard = cards.find(function (el) {
      return el.textContent && el.textContent.indexOf("SEVERITY BUCKETS") !== -1;
    });
    if (!sevCard) return;

    // Tìm element chứa text C=..., H=..., M=..., L=...
    var legend = Array.from(sevCard.querySelectorAll("*")).find(function (el) {
      var t = (el.textContent || "").trim();
      return t.indexOf("C=") !== -1 && t.indexOf("H=") !== -1 &&
             t.indexOf("M=") !== -1 && t.indexOf("L=") !== -1;
    });
    if (!legend) return;

    var text = legend.textContent.replace(/\s+/g, " ");
    var m = text.match(/C=(\d+).*H=(\d+).*M=(\d+).*L=(\d+)/);
    if (!m) return;

    var vals = [
      parseInt(m[1] || "0", 10),
      parseInt(m[2] || "0", 10),
      parseInt(m[3] || "0", 10),
      parseInt(m[4] || "0", 10)
    ];
    var total = vals.reduce(function (a, b) { return a + b; }, 0) || 1;

    // Lấy 4 thanh trong card
    var bars = sevCard.querySelectorAll(".sb-sev-bar, .sb-severity-bar, .severity-bar");
    if (!bars.length) return;

    Array.from(bars).slice(0, 4).forEach(function (el, idx) {
      var v = vals[idx] || 0;
      var pct = Math.round(v / total * 100);
      // Nếu có value mà % quá nhỏ thì cho tối thiểu 3% để vẫn nhìn thấy
      if (v > 0 && pct < 3) pct = 3;
      if (pct < 0) pct = 0;
      if (pct > 100) pct = 100;
      el.style.width = pct + "%";
    });
  } catch (e) {
    if (window.console && console.warn) {
      console.warn("[SB] severity patch error:", e);
    }
  }
});
