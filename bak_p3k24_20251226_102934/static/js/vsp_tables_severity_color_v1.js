(function(){
  console.log("[VSP_TABLES] severity colouring loaded");
  document.addEventListener("DOMContentLoaded", function(){
    document.querySelectorAll("[data-severity]").forEach(function(el){
      var sev = el.getAttribute("data-severity");
      if (!sev) return;
      el.classList.add("vsp-sev-" + sev);
    });
  });
})();
