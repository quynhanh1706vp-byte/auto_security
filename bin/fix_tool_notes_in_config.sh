#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
CFG="$ROOT/tool_config.json"

echo "[i] CFG = $CFG"

if [ ! -f "$CFG" ]; then
  echo "[ERR] Không tìm thấy $CFG"
  exit 1
fi

python3 - "$CFG" <<'PY'
import sys, json, pathlib

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())

def norm(s: str) -> str:
    return s.lower().replace("_", "").replace("-", "").replace(" ", "")

# === ĐÚNG Y ĐOẠN "GIẢI THÍCH TOOL" (KHÔNG PREFIX) ===
NOTES = {
    "trivyfs":
      'Phiên bản Trivy cho File System scan (từ Aquasecurity). '
      'Scan vulnerabilities, misconfigs, secrets trong filesystem/code. '
      'Mode "fast": Scan nhanh, ưu tiên tốc độ. Output JSON hoặc CycloneDX (SBOM format).',

    "trivyiac":
      'Trivy IaC scanner. Kiểm tra misconfigurations trong Infrastructure as Code (Terraform, Kubernetes, etc.). '
      '"fast": Nhanh, không deep dive. Hỗ trợ cả local (Offline) và remote (Online) resources.',

    "grype":
      'Vulnerability scanner từ Anchore, dùng cho container images/filesystems. '
      'Thường kết hợp với Syft (SBOM). "aggr": Aggressive scan, kiểm tra sâu và nhiều DB (CVE, etc.). Output JSON/CD.',

    "syftsbom":
      'Syft từ Anchore, generate Software Bill of Materials (SBOM) cho dependencies. '
      '"fast": Tạo SBOM nhanh. Hỗ trợ CycloneDX/SPDX formats. Offline: Local files, Online: Remote images.',

    "syft":
      'Phiên bản cơ bản của Syft (không SBOM cụ thể). '
      'Chỉ output JSON/CD, có lẽ offline-only trong config này. '
      'Tương tự trên, dùng cho catalog packages.',

    "gitleaks":
      'Secret scanner (tìm API keys, passwords trong code/git). '
      '"fast": Scan nhanh qua repo. Offline: Local scan, không cần network.',

    "bandit":
      'Python static analyzer (từ PyCQA). Tìm vulnerabilities trong Python code. '
      '"aggr": Full scan, aggressive rules. Offline chính, có thể hỗ trợ online nếu config thêm.',

    "kics":
      'Keeping Infrastructure as Code Secure (từ Checkmarx). '
      'Scan IaC misconfigs (Terraform, CloudFormation). '
      '"fast": Nhanh. Offline: Local files.',

    "codeql":
      'Semantic code analysis từ GitHub. Query code như data để tìm vulnerabilities (multi-language). '
      '"aggr": Deep analysis. Offline: Local DB, Online: GitHub integration.'
}

def match_key(row):
    text = " ".join(str(row.get(k, "")) for k in ["name", "tool", "id", "display_name", "label"])
    return norm(text)

def set_notes(row, note):
    # xóa prefix cũ nếu còn
    for key in ("note", "ghi_chu", "notes", "explain"):
        old = str(row.get(key, ""))
        if "Hoạt động bình thường" in old:
            old = ""
        # ghi đúng đoạn giải thích tool
        row[key] = note

changed = False

def walk(obj):
    global changed
    if isinstance(obj, dict):
        mk = match_key(obj)
        for k_norm, note in NOTES.items():
            if k_norm in mk:
                set_notes(obj, note)
                print(f"[OK] Set note (giải thích tool) cho: {mk} -> {k_norm}")
                changed = True
        for v in obj.values():
            walk(v)
    elif isinstance(obj, list):
        for item in obj:
            walk(item)

walk(data)

if not changed:
    print("[WARN] Không tìm thấy tool nào trong NOTES để set note.")
else:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print("[DONE] Đã cập nhật ghi chú (giải thích tool) trong tool_config.json")

PY

echo "[DONE] fix_tool_notes_in_config.sh chạy xong."
