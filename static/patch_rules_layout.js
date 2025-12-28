/**
 * patch_rules_layout.js
 * Đồng bộ layout thẻ Rule overrides với card kiểu Dashboard.
 */
document.addEventListener("DOMContentLoaded", () => {
  try {
    // Tìm block chứa text "DANH SÁCH RULE THEO TOOL"
    const blocks = Array.from(document.querySelectorAll("div, section, article"));
    const titleBlock = blocks.find(el =>
      /DANH SÁCH RULE THEO TOOL/i.test((el.textContent || "").replace(/\s+/g, " "))
    );
    if (!titleBlock) return;

    // Giả định card chính là parent gần nhất của dòng title
    let card = titleBlock.parentElement || titleBlock;
    if (!card) return;

    // Ép card này thành "sb-card" kiểu Dashboard
    card.style.background = "linear-gradient(135deg, rgba(40,110,60,0.96) 0%, rgba(5,13,22,0.98) 100%)";
    card.style.border = "1px solid rgba(120,214,120,0.45)";
    card.style.boxShadow = "0 18px 40px rgba(0,0,0,0.85)";
    card.style.borderRadius = "12px";
    card.style.padding = "20px 24px";
    card.style.marginTop = "24px";
    card.style.marginBottom = "40px";
    card.style.marginLeft = "0";
    card.style.marginRight = "0";
    card.style.width = "100%";
    card.style.maxWidth = "100%";

    // Chữ bên trong cho dễ đọc
    const texts = card.querySelectorAll("*");
    texts.forEach(el => {
      const txt = (el.textContent || "").trim();
      if (txt.length > 0 && !el.matches("input, select, textarea, button")) {
        el.style.color = "#f5f7ff";
      }
    });

    // Thanh title "DANH SÁCH RULE THEO TOOL" cho giống header card
    titleBlock.style.fontSize = "13px";
    titleBlock.style.textTransform = "uppercase";
    titleBlock.style.letterSpacing = ".18em";
    titleBlock.style.fontWeight = "600";
    titleBlock.style.marginBottom = "10px";
  } catch (e) {
    console.warn("[patch_rules_layout] error:", e);
  }
});
