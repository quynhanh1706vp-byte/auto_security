/* vsp_ui_commercial_cleanup_v1.js
 * Commercial cleanup shim:
 * 1) Filters panel only on #datasource
 * 2) Hide conflicting floating "CI GATE - LATEST RUN" widget (we already have Gate panel)
 * 3) Remove stray "\\n\\n" debug text rendered on page
 *
 * If you want to keep the floating gate widget for debugging:
 *   window.VSP_KEEP_GATE_TOAST = true;
 */
(function () {
  'use strict';

  function tab() {
    var h = (location.hash || '').toLowerCase();
    if (!h) return 'dashboard';
    if (h.includes('datasource')) return 'datasource';
    if (h.includes('runs')) return 'runs';
    if (h.includes('settings')) return 'settings';
    if (h.includes('rules')) return 'rules';
    if (h.includes('dashboard')) return 'dashboard';
    return h.replace('#','') || 'unknown';
  }

  function findByText(needle) {
    needle = String(needle || '').toLowerCase();
    var all = Array.from(document.querySelectorAll('div,section,main,aside,pre,code'));
    return all.filter(function (el) {
      var t = (el.textContent || '').toLowerCase();
      return t.includes(needle);
    });
  }

  function looksLikeFiltersCard(el) {
    var t = (el.textContent || '').toLowerCase();
    // match the exact UI strings seen in your screenshots
    var ok = t.includes('filters') &&
             t.includes('severity') &&
             t.includes('tool') &&
             (t.includes('search (rule / path / cwe)') || t.includes('rule / path / cwe'));
    // avoid hiding the whole page by requiring inputs/selects inside
    var hasInputs = el.querySelector('select,input,textarea');
    return !!(ok && hasInputs);
  }

  function hideFiltersOutsideDatasource() {
    var current = tab();
    var candidates = findByText('search (rule / path / cwe)').concat(findByText('filters'));
    var uniq = Array.from(new Set(candidates));
    uniq.forEach(function (el) {
      // climb up a bit to the card container
      var card = el;
      for (var i=0;i<6 && card && card.parentElement;i++){
        if (looksLikeFiltersCard(card)) break;
        card = card.parentElement;
      }
      if (card && looksLikeFiltersCard(card)) {
        if (current !== 'datasource') {
          card.style.display = 'none';
          card.setAttribute('data-vsp-hidden-by', 'commercial_cleanup_v1');
        } else {
          // restore on datasource
          if (card.getAttribute('data-vsp-hidden-by') === 'commercial_cleanup_v1') {
            card.style.display = '';
          }
        }
      }
    });
  }

  function hideConflictingGateToast() {
    if (window.VSP_KEEP_GATE_TOAST) return;
    var nodes = findByText('ci gate - latest run');
    nodes.forEach(function (el) {
      // hide the container (usually a floating card)
      var box = el;
      for (var i=0;i<8 && box && box.parentElement;i++){
        var t = (box.textContent || '').toLowerCase();
        if (t.includes('ci gate - latest run')) break;
        box = box.parentElement;
      }
      if (!box) return;
      // prefer hiding the biggest container that still contains the phrase
      box.style.display = 'none';
      box.setAttribute('data-vsp-hidden-by', 'commercial_cleanup_v1');
    });
  }

  function removeStrayDebugBackslashN() {
    // remove elements that are basically just "\n" "\n\n" "\\n \\n"
    var all = Array.from(document.querySelectorAll('div,span,pre'));
    all.forEach(function (el) {
      if (!el || !el.textContent) return;
      var raw = el.textContent.trim();
      if (raw === '\\n' || raw === '\\n\\n' || raw === '\\n \\n' || raw === '\\n \\n\\n' || raw === '\\n\\n\\n') {
        // only remove if it's tiny and not a real section
        if ((el.innerHTML || '').trim() === raw || (el.childElementCount === 0)) {
          el.style.display = 'none';
          el.setAttribute('data-vsp-hidden-by', 'commercial_cleanup_v1');
        }
      }
    });
  }

  function run() {
    
    _vspRemoveStrayTextNodes();
    _vspHideGateToast();
hideFiltersOutsideDatasource();
    hideConflictingGateToast();
    removeStrayDebugBackslashN();
  }

  window.addEventListener('hashchange', function(){ setTimeout(run, 0); });
  document.addEventListener('DOMContentLoaded', function(){ setTimeout(run, 0); });

  // Also rerun a few times shortly after load in case other JS injects late
  var n = 0;
  var iv = setInterval(function(){
    run();
    n++;
    if (n >= 8) clearInterval(iv);
  }, 400);

  try { console.log('[VSP_UI_COMMERCIAL_CLEANUP_V1] loaded'); } catch(e){}
})();

// === VSP_UI_COMMERCIAL_CLEANUP_V1_TEXTNODE_TOAST_FIX ===
function _vspRemoveStrayTextNodes() {
  try {
    function walk(node){
      if (!node) return;
      // remove stray text nodes like "\n \n"
      if (node.nodeType === Node.TEXT_NODE) {
        var t = (node.nodeValue || '').trim();
        if (t === '\\n' || t === '\\n\\n' || t === '\\n \\n' || t === '\\n \\n\\n' || t === '\\n\\n\\n') {
          node.parentNode && node.parentNode.removeChild(node);
          return;
        }
      }
      var kids = Array.from(node.childNodes || []);
      kids.forEach(walk);
    }
    walk(document.body);
  } catch(e){}
}

function _vspHideGateToast() {
  try {
    if (window.VSP_KEEP_GATE_TOAST) return;
    var els = Array.from(document.querySelectorAll('div,section,aside'));
    els.forEach(function(el){
      var t = (el.textContent || '').toUpperCase();
      // match both "-" and "–"
      if (t.includes('CI GATE') && t.includes('LATEST RUN')) {
        // hide only floating-ish blocks
        var st = window.getComputedStyle(el);
        if (st && (st.position === 'fixed' || st.position === 'sticky') && (st.right !== 'auto' || st.bottom !== 'auto')) {
          el.style.display = 'none';
          el.setAttribute('data-vsp-hidden-by', 'commercial_cleanup_v1');
        }
      }
    });
  } catch(e){}
}
// === END VSP_UI_COMMERCIAL_CLEANUP_V1_TEXTNODE_TOAST_FIX ===


try {
  var _n=0;
  var _iv=setInterval(function(){
    _vspRemoveStrayTextNodes();
    _vspHideGateToast();
    _n++; if (_n>40) clearInterval(_iv);
  }, 300);
} catch(e){}
