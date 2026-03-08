---
name: system-tuner
description: "Diagnose and optimize OpenClaw + Claude Code setup. Use when: user says '系統優化', '檢查設定', 'tune', 'optimize', '效能', '慢', 'slow', '健檢', '體檢', 'health check', 'cleanup', '清理'. Covers: model routing, agent config, skills audit, plugin cleanup, MCP servers, security review, gateway health, session cleanup, log rotation."
metadata: { "openclaw": { "emoji": "🔧", "requires": { "bins": ["curl", "node"] } } }
---

# System Tuner Skill

OpenClaw + Claude Code 全方位診斷與優化工具。適用於任何 OpenClaw 使用者的環境。

## When to Use

✅ **USE this skill when:**

- 「系統變慢了」「模型切換很慢」「agent 回應慢」
- 「幫我檢查設定」「健檢」「體檢」「diagnose」
- 「優化一下」「清理一下」「cleanup」
- 「安全檢查」「有沒有問題」
- 初次設定 OpenClaw 環境
- 更換模型或 provider 後想確認

## When NOT to Use

❌ **DON'T use this skill when:**

- 寫程式碼 → coding-agent
- GitHub 操作 → github skill
- 單純重啟 gateway → 直接用 launchctl / systemctl

---

## Environment Detection

在執行任何診斷前，先偵測環境：

```bash
# 偵測 OS
OS=$(uname -s)  # Darwin = macOS, Linux = Linux

# 偵測 OpenClaw 設定目錄
OPENCLAW_HOME="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
OPENCLAW_CONFIG="${OPENCLAW_CONFIG_PATH:-$OPENCLAW_HOME/openclaw.json}"

# 偵測 Claude Code 設定目錄
CLAUDE_HOME="$HOME/.claude"

# 偵測 Gateway port（從設定讀取）
GW_PORT=$(python3 -c "
import json
cfg = json.load(open('$OPENCLAW_CONFIG'))
print(cfg.get('gateway',{}).get('port', 18789))
" 2>/dev/null || echo 18789)

# 偵測 service manager
if [ "$OS" = "Darwin" ]; then
    # macOS: 找 launchd label
    LAUNCHD_LABEL=$(launchctl print gui/$(id -u) 2>/dev/null | grep -o 'openclaw[^"]*gateway' | head -1)
    [ -z "$LAUNCHD_LABEL" ] && LAUNCHD_LABEL="ai.openclaw.gateway"
    SERVICE_MGR="launchd"
else
    # Linux: 找 systemd unit
    SYSTEMD_UNIT=$(systemctl --user list-units 2>/dev/null | grep -o 'openclaw[^ ]*' | head -1)
    SERVICE_MGR="systemd"
fi

# 偵測 OpenClaw 安裝位置（npm global vs local repo）
OPENCLAW_BIN=$(which openclaw 2>/dev/null)
OPENCLAW_REPO=$([ -f "$HOME/openclaw/package.json" ] && echo "$HOME/openclaw" || echo "")

echo "OS: $OS"
echo "Config: $OPENCLAW_CONFIG"
echo "Port: $GW_PORT"
echo "Service: $SERVICE_MGR"
echo "Binary: ${OPENCLAW_BIN:-not found}"
echo "Repo: ${OPENCLAW_REPO:-not found}"
```

---

## Diagnosis Checklist

按順序執行以下診斷，每項報告狀態（✅ 正常 / ⚠️ 建議 / ❌ 問題）：

### 1. Gateway 健康檢查

```bash
# 檢查 gateway 是否運行
curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 http://localhost:${GW_PORT}/health

# macOS: 檢查 launchd 狀態
launchctl print gui/$(id -u)/${LAUNCHD_LABEL} 2>&1 | head -10

# Linux: 檢查 systemd 狀態
# systemctl --user status ${SYSTEMD_UNIT} 2>&1 | head -10

# 檢查 log 大小
du -sh "$OPENCLAW_HOME/logs/"*.log 2>/dev/null
```

**判斷標準：**
- HTTP 200 = ✅
- Log > 50MB = ⚠️ 建議清理
- Gateway 未運行 = ❌
- 無 service manager 管理 = ⚠️ 建議設定 launchd/systemd

### 2. 模型路由檢查

```bash
cat "$OPENCLAW_CONFIG" | python3 -c "
import json, sys
cfg = json.load(sys.stdin)

print('=== Providers ===')
for name, p in cfg.get('models', {}).get('providers', {}).items():
    model_count = len(p.get('models', []))
    print(f'  {name}: {p.get(\"baseUrl\", \"?\")} ({model_count} models)')

print()
print('=== Agent Model Routing ===')
defaults = cfg.get('agents', {}).get('defaults', {}).get('model', {})
print(f'  {\"defaults\":12} primary: {defaults.get(\"primary\", \"unset\")}')
for fb in defaults.get('fallbacks', []):
    print(f'  {\"\":12} fallback: {fb}')
print()

for agent in cfg.get('agents', {}).get('list', []):
    model = agent.get('model', {})
    primary = model.get('primary', 'inherits defaults')
    fallbacks = model.get('fallbacks', [])
    has_free_router = any('openrouter/free' in fb for fb in fallbacks)
    print(f'  {agent[\"id\"]:12} primary: {primary}')
    for i, fb in enumerate(fallbacks):
        print(f'  {\"\":12} fallback {i+1}: {fb}')
    if not has_free_router and fallbacks:
        print(f'  {\"\":12} ⚠️  沒有 openrouter/free 保底')
    print()
"
```

**API 延遲測試：**

```bash
cat "$OPENCLAW_CONFIG" | python3 -c "
import json, sys
cfg = json.load(sys.stdin)
for name, p in cfg.get('models',{}).get('providers',{}).items():
    url = p.get('baseUrl','')
    if url: print(f'{name}|{url}')
" | while IFS='|' read name url; do
    latency=$(curl -s -o /dev/null -w "%{time_starttransfer}" --connect-timeout 5 "$url/models" 2>/dev/null)
    if (( $(echo "$latency > 0.7" | bc -l 2>/dev/null || echo 0) )); then
        echo "❌ $name: ${latency}s (太慢，建議降級為 fallback)"
    elif (( $(echo "$latency > 0.3" | bc -l 2>/dev/null || echo 0) )); then
        echo "⚠️  $name: ${latency}s (偏慢)"
    else
        echo "✅ $name: ${latency}s"
    fi
done
```

**判斷標準：**
- 每個 agent 至少有 1 個 fallback = ✅
- fallback 鏈末端有 `openrouter/free` 保底 = ✅
- 使用已停服/不存在的模型 = ❌
- 所有 agent 用同一個模型 = ⚠️ 未善用分工
- provider 延遲 < 0.3s = ✅, 0.3-0.7s = ⚠️, > 0.7s = ❌

### 3. Skills 審計

```bash
cat "$OPENCLAW_CONFIG" | python3 -c "
import json, sys, os
cfg = json.load(sys.stdin)

print('=== Agent Skills Whitelist ===')
for agent in cfg.get('agents', {}).get('list', []):
    skills = agent.get('skills')
    if skills is None:
        print(f'  ❌ {agent[\"id\"]:12} skills: NOT SET (載入全部，嚴重影響效能)')
    else:
        print(f'  ✅ {agent[\"id\"]:12} skills: {len(skills)} 個')

print()
# Count available skills
home = os.path.expanduser('~')
repo_skills = os.path.join(home, 'openclaw', 'skills')
if os.path.isdir(repo_skills):
    count = len([d for d in os.listdir(repo_skills) if os.path.isdir(os.path.join(repo_skills, d))])
    print(f'官方 skills 總數: {count}')

# Check workspace skills
for agent in cfg.get('agents', {}).get('list', []):
    ws = agent.get('workspace', '').replace('~', home)
    ws_skills = os.path.join(ws, 'skills')
    if os.path.isdir(ws_skills):
        count = len([d for d in os.listdir(ws_skills) if os.path.isdir(os.path.join(ws_skills, d))])
        if count > 0:
            flag = '⚠️ ' if count > 10 else '  '
            print(f'{flag}Workspace skills ({agent[\"id\"]}): {count} 個')
"
```

### 4. Claude Code MCP 檢查

```bash
CLAUDE_SETTINGS="$CLAUDE_HOME/settings.json"
if [ -f "$CLAUDE_SETTINGS" ]; then
    python3 -c "
import json, shutil
cfg = json.load(open('$CLAUDE_SETTINGS'))
servers = cfg.get('mcpServers', {})
print(f'MCP Servers: {len(servers)} 個')
for name, srv in servers.items():
    cmd = srv.get('command', '?')
    issues = []
    if cmd == 'npx':
        issues.append('npx 啟動慢，建議全域安裝')
    if cmd != 'npx' and not shutil.which(cmd):
        issues.append(f'command \"{cmd}\" 不存在')
    status = '⚠️  ' + '; '.join(issues) if issues else '✅'
    print(f'  {name}: {cmd} {status}')
if len(servers) > 3:
    print(f'⚠️  MCP server 超過 3 個，影響模型/agent 切換速度')
" 2>/dev/null
else
    echo "ℹ️  未找到 Claude Code 設定（$CLAUDE_SETTINGS）"
fi
```

### 5. Plugin 檢查

```bash
# Claude Code 插件
PLUGIN_DIR="$CLAUDE_HOME/plugins/marketplaces/claude-plugins-official"
if [ -d "$PLUGIN_DIR" ]; then
    ext=$(ls "$PLUGIN_DIR/external_plugins/" 2>/dev/null | wc -l | tr -d ' ')
    built=$(ls "$PLUGIN_DIR/plugins/" 2>/dev/null | wc -l | tr -d ' ')
    total=$((ext + built))
    echo "Claude Code 插件: ${ext} external + ${built} built-in = ${total} 總計"
    [ "$total" -gt 30 ] && echo "⚠️  插件過多（${total} > 30），影響啟動速度"
fi

# OpenClaw 插件
python3 -c "
import json
cfg = json.load(open('$OPENCLAW_CONFIG'))
plugins = cfg.get('plugins', {})
load_paths = plugins.get('load', {}).get('paths', [])
entries = plugins.get('entries', {})
for name, e in entries.items():
    enabled = e.get('enabled', True)
    if not enabled:
        print(f'⚠️  {name}: disabled 但仍在設定中（浪費載入時間）')
    else:
        print(f'✅ {name}: enabled')
" 2>/dev/null
```

### 6. Session 清理

```bash
echo "=== Agent Session 狀態 ==="
total_size=0
for d in "$OPENCLAW_HOME/agents/"*/; do
    [ ! -d "$d" ] && continue
    agent=$(basename "$d")
    size_bytes=$(du -sk "$d/sessions/" 2>/dev/null | cut -f1 || echo 0)
    size_human=$(du -sh "$d/sessions/" 2>/dev/null | cut -f1 || echo "0")
    reset_count=$(ls "$d/sessions/"*.reset.* 2>/dev/null 2>&1 | grep -c reset || echo 0)

    issues=""
    [ "$reset_count" -gt 0 ] && issues="⚠️ ${reset_count} 個 reset 檔案可清除"
    [ "$size_bytes" -gt 10240 ] && issues="${issues:+$issues; }⚠️ 大小 ${size_human}"
    status="${issues:-✅}"

    echo "  $agent: ${size_human} ${status}"
    total_size=$((total_size + size_bytes))
done

# 檢查未綁定的 agent 目錄
python3 -c "
import json, os
cfg = json.load(open('$OPENCLAW_CONFIG'))
configured = set(a['id'] for a in cfg.get('agents',{}).get('list',[]))
agents_dir = '$OPENCLAW_HOME/agents'
if os.path.isdir(agents_dir):
    existing = set(d for d in os.listdir(agents_dir) if os.path.isdir(os.path.join(agents_dir, d)))
    orphan = existing - configured
    for o in orphan:
        print(f'⚠️  \"{o}\" agent 目錄存在但未在設定中使用，可刪除')
" 2>/dev/null
```

### 7. 安全檢查

```bash
python3 -c "
import json
cfg = json.load(open('$OPENCLAW_CONFIG'))

print('=== 通道安全 ===')
for ch_name, ch in cfg.get('channels', {}).items():
    if not ch.get('enabled', False):
        continue
    allow = ch.get('allowFrom', [])
    dm = ch.get('dmPolicy', '?')
    if '*' in allow:
        print(f'❌ {ch_name}: allowFrom=[\"*\"] 任何人都能使用')
    elif dm == 'open':
        print(f'⚠️  {ch_name}: dmPolicy=open 但有 allowFrom 限制')
    else:
        print(f'✅ {ch_name}: 限制 {len(allow)} 個使用者')

print()
print('=== Gateway 安全 ===')
gw = cfg.get('gateway', {})
mode = gw.get('mode', '?')
has_token = bool(gw.get('auth', {}).get('token'))
print(f'Mode: {mode} {\"✅\" if mode == \"local\" else \"⚠️ 非 local 模式\"}')
print(f'Auth token: {\"✅ 已設定\" if has_token else \"❌ 未設定\"}')

print()
print('=== API Key 檢查 ===')
providers = cfg.get('models', {}).get('providers', {})
for name, p in providers.items():
    key = p.get('apiKey', '')
    if key:
        masked = key[:8] + '...' + key[-4:]
        print(f'⚠️  {name}: API key 明文存放在設定檔 ({masked})')
        print(f'   建議改用環境變數，如 OPENCLAW_{name.upper()}_API_KEY')
" 2>/dev/null

# Claude Code 權限白名單
if [ -f "$CLAUDE_HOME/settings.local.json" ]; then
    token_count=$(grep -cE 'TOKEN|SECRET|PASS|npm_[A-Za-z0-9]' "$CLAUDE_HOME/settings.local.json" 2>/dev/null || echo 0)
    if [ "$token_count" -gt 0 ]; then
        echo "⚠️  Claude Code 權限白名單含 ${token_count} 個疑似明文 token"
    else
        echo "✅ Claude Code 權限白名單無明文 token"
    fi
fi
```

### 8. Cron 與自動化

```bash
echo "=== Crontab ==="
crontab_content=$(crontab -l 2>/dev/null)
if [ -z "$crontab_content" ]; then
    echo "ℹ️  無 crontab"
else
    echo "$crontab_content" | while read -r line; do
        # 跳過註解
        [[ "$line" =~ ^# ]] && echo "  $line" && continue
        # 提取腳本路徑
        script=$(echo "$line" | grep -oE '/[^ ]+\.(sh|js|py)' | head -1)
        if [ -n "$script" ] && [ ! -f "$script" ]; then
            echo "  ❌ $line"
            echo "     ↳ 腳本不存在: $script"
        else
            echo "  ✅ $line"
        fi
    done
fi

# 檢查是否有 log rotation
if crontab -l 2>/dev/null | grep -q "truncate\|logrotate\|openclaw.*log"; then
    echo "✅ 有 log rotation"
else
    echo "⚠️  無 log rotation，log 會無限增長"
fi

echo ""
echo "=== Service Manager ==="
if [ "$(uname -s)" = "Darwin" ]; then
    plist=$(ls ~/Library/LaunchAgents/*openclaw* 2>/dev/null | head -1)
    if [ -n "$plist" ]; then
        echo "✅ launchd: $plist"
        # 檢查 ThrottleInterval
        throttle=$(plutil -extract ThrottleInterval raw "$plist" 2>/dev/null || echo "?")
        [ "$throttle" -lt 3 ] 2>/dev/null && echo "⚠️  ThrottleInterval=$throttle (太低，崩潰時會瘋狂重啟)"
        # 檢查 KeepAlive
        keepalive=$(plutil -extract KeepAlive raw "$plist" 2>/dev/null || echo "?")
        echo "  KeepAlive: $keepalive"
    else
        echo "⚠️  無 launchd 設定，gateway 掛了不會自動重啟"
    fi
else
    if systemctl --user is-enabled openclaw-gateway 2>/dev/null; then
        echo "✅ systemd: openclaw-gateway enabled"
    else
        echo "⚠️  無 systemd 設定"
    fi
fi
```

---

## Optimization Actions

診斷完成後，根據發現的問題提供修復方案。**所有修改必須先告知使用者並獲得確認**。

### 效能優化
- MCP `npx` → 全域安裝直接執行（`npm install -g <package>`）
- 未使用的 MCP server / plugin → 從設定移除
- Skills 未設白名單 → 按 agent 角色設定 `"skills": [...]`
- 高延遲 provider → 降級為 fallback，推薦低延遲替代
- Session reset 檔案 → `rm ~/.openclaw/agents/*/sessions/*.reset.*`
- 肥大 log → `truncate -s 0 ~/.openclaw/logs/*.log`
- disabled plugin 仍在 load paths → 從設定完全移除

### 模型優化
- 查詢 OpenRouter 免費模型：`curl -s https://openrouter.ai/api/v1/models | python3 -c "..."`
- 確保每條 fallback 鏈末端有 `openrouter/free` 保底（自動選免費模型）
- 付費模型走最便宜的 provider（比較 prompt/completion pricing）
- 按 agent 角色匹配模型能力：
  - 接待/分派 → 低延遲 + tool use（GPT-5 Nano 等）
  - 架構/推理 → reasoning 模型（GPT-OSS 120B, Step 3.5 Flash 等）
  - 工程/程式 → coding 專用（Qwen3 Coder 等）
  - 商業/文筆 → 通用高品質模型

### 安全加固
- 通道 `allowFrom: ["*"]` → 限定使用者 ID
- Gateway `--bind lan` → `mode: "local"`（localhost only）
- 明文 API key → 建議改用環境變數
- 權限白名單中的敏感資訊 → 移除

### 自動化
- 指向不存在腳本的 cron → 清除
- 無 log rotation → 加入 cron：`0 3 * * * find ~/.openclaw/logs -name "*.log" -size +10M -exec truncate -s 0 {} \;`
- 無 service manager → 建議設定 launchd (macOS) 或 systemd (Linux)
- launchd ThrottleInterval < 3 → 調高至 5

---

## Reference: File Locations

| 檔案 | 用途 |
|------|------|
| `$OPENCLAW_HOME/openclaw.json` | OpenClaw 主設定 |
| `$OPENCLAW_HOME/agents/*/sessions/` | Agent session 資料 |
| `$OPENCLAW_HOME/logs/` | Gateway log |
| `$OPENCLAW_HOME/extensions/` | OpenClaw 自訂插件 |
| `$CLAUDE_HOME/settings.json` | Claude Code MCP + 模型設定 |
| `$CLAUDE_HOME/settings.local.json` | Claude Code 權限白名單 |
| `$CLAUDE_HOME/plugins/` | Claude Code 插件 |
| `~/Library/LaunchAgents/*openclaw*` | macOS launchd 設定 |
| `/etc/systemd/user/*openclaw*` | Linux systemd 設定 |

## Reference: OpenRouter Free Models Query

```bash
# 列出所有免費且支援 tool use 的模型，按 context length 排序
curl -s https://openrouter.ai/api/v1/models | python3 -c "
import json, sys
data = json.load(sys.stdin)
free = []
for m in data.get('data', []):
    p = m.get('pricing', {})
    if float(p.get('prompt','1') or '1') == 0 and float(p.get('completion','1') or '1') == 0:
        params = m.get('supported_parameters', [])
        if 'tools' in params:
            free.append({
                'id': m['id'],
                'ctx': m.get('context_length', 0),
                'reasoning': 'reasoning' in params,
            })
free.sort(key=lambda x: x['ctx'], reverse=True)
for m in free:
    r = 'Reasoning' if m['reasoning'] else ''
    print(f'{m[\"ctx\"]:>8} ctx  {r:10}  {m[\"id\"]}')
"
```
