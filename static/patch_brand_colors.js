/**
 * patch_brand_colors.js
 * Đồng bộ màu ô SECURITY BUNDLE (logo + subtitle) với theme Dashboard chuẩn.
 */
document.addEventListener("DOMContentLoaded", () => {
  try {
    // Tìm card chứa cả "SECURITY BUNDLE" và "Dashboard & Reports"
    const cards = Array.from(document.querySelectorAll("div"));
    const card = cards.find(el => {
      const t = (el.textContent || "").replace(/\s+/g, " ").trim();
      return t.includes("SECURITY BUNDLE") && t.includes("Dashboard & Reports");
    });
    if (!card) return;

    // Nền + viền giống theme Dashboard (xanh đậm, không tím)
    card.style.background = "linear-gradient(135deg, #102a1c 0%, #050d16 100%)";
    card.style.border = "1px solid rgba(120, 214, 120, 0.6)";
    card.style.boxShadow = "0 18px 40px rgba(0,0,0,0.85)";

    // Chữ bên trong sáng, dễ đọc
    const texts = card.querySelectorAll("*");
    texts.forEach(el => {
      if (!el.children.length && (el.textContent || "").trim()) {
        el.style.color = "#f5f7ff";
      }
    });

    // Subtitle “Dashboard & Reports” hơi nhạt hơn 1 chút
    const subtitle = Array.from(texts).find(el =>
      (el.textContent || "").includes("Dashboard & Reports")
    );
    if (subtitle) {
      subtitle.style.opacity = "0.85";
      subtitle.style.fontSize = "11px";
      subtitle.style.letterSpacing = ".16em";
    }
  } catch (e) {
    console.warn("[patch_brand_colors] error:", e);
  }
});
