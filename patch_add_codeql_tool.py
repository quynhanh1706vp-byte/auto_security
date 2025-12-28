import json, pathlib, sys

path = pathlib.Path("tool_config.json")
if not path.exists():
    print("[ERR] Không tìm thấy tool_config.json trong thư mục hiện tại.")
    sys.exit(1)

data = json.loads(path.read_text(encoding="utf-8"))

# Lấy list chứa các tool
if isinstance(data, list):
    tools = data
elif isinstance(data, dict) and isinstance(data.get("tools"), list):
    tools = data["tools"]
else:
    print("[ERR] Định dạng tool_config.json không hỗ trợ (không phải list, cũng không phải dict['tools']).")
    sys.exit(1)

# Đã có CodeQL chưa?
def get_name(t):
    return str(t.get("name") or t.get("tool") or t.get("label") or "").strip().lower()

def get_id(t):
    return str(t.get("id") or t.get("tool_id") or "").strip().lower()

for t in tools:
    if get_name(t) == "codeql" or get_id(t) == "codeql":
        print("[OK] tool CodeQL đã có sẵn trong tool_config.json → không làm gì thêm.")
        sys.exit(0)

# Chọn 1 tool làm mẫu (ưu tiên Semgrep/Bandit/Gitleaks)
base = None
preferred = ["semgrep", "bandit", "gitleaks"]
for pref in preferred:
    for t in tools:
        if pref in get_name(t):
            base = t
            break
    if base is not None:
        break

if base is None:
    if not tools:
        print("[ERR] tool_config.json không có tool nào để copy cấu trúc.")
        sys.exit(1)
    base = tools[0]

new_tool = dict(base)  # clone cấu trúc

# Đặt lại các field chính
for key in ("name", "tool", "label", "display_name"):
    if key in new_tool:
        new_tool[key] = "CodeQL"

for key in ("id", "tool_id", "code"):
    if key in new_tool:
        new_tool[key] = "codeql"

for key in ("note", "notes", "comment", "hint"):
    if key in new_tool:
        new_tool[key] = "SAST (CodeQL multi-lang)"

for key in ("enabled", "is_enabled", "active"):
    if key in new_tool:
        new_tool[key] = True

# level → aggr cho chắc cú
for key in ("level", "mode", "profile", "strength"):
    if key in new_tool and isinstance(new_tool[key], str):
        new_tool[key] = "aggr"

# modes → bật OFFLINE/ONLINE/CI/CD nếu có dạng list
for key in ("modes", "mode_list", "available_modes"):
    if key in new_tool and isinstance(new_tool[key], list):
        modes = {str(m).lower() for m in new_tool[key]}
        # normalize 1 số tên
        normalized = set()
        for m in modes:
            if m in ("offline", "off"):
                normalized.add("offline")
            elif m in ("online", "on"):
                normalized.add("online")
            elif m in ("ci", "ci/cd", "cicd"):
                normalized.add("ci/cd")
            else:
                normalized.add(m)
        # đảm bảo đủ 3 mode cơ bản
        normalized.update(["offline", "online", "ci/cd"])
        new_tool[key] = sorted(normalized)

tools.append(new_tool)

# Ghi lại file
path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
print("[OK] Đã thêm tool CodeQL vào tool_config.json")
