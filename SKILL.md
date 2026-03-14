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
OS=$(uname -s)
export OPENCLAW_HOME="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
export OPENCLAW_CONFIG="${OPENCLAW_CONFIG_PATH:-$OPENCLAW_HOME/openclaw.json}"
export CLAUDE_HOME="$HOME/.claude"

# Gateway port（從設定讀取，失敗 fallback 18789）
GW_PORT=18789
if [ -f "$OPENCLAW_CONFIG" ]; then
    GW_PORT=$(python3 -c "
import json, os
with open(os.environ['OPENCLAW_CONFIG']) as f:
    cfg = json.load(f)
print(cfg.get('gateway',{}).get('port', 18789))
" 2>/dev/null || echo 18789)
fi

# 偵測 service manager
if [ "$OS" = "Darwin" ]; then
    LAUNCHD_LABEL=$(launchctl print gui/$(id -u) 2>/dev/null | grep -o 'openclaw[^"]*gateway' | head -1)
    [ -z "$LAUNCHD_LABEL" ] && LAUNCHD_LABEL="ai.openclaw.gateway"
    SERVICE_MGR="launchd"
    LAUNCHD_PLIST=$(ls ~/Library/LaunchAgents/*openclaw* 2>/dev/null | head -1)
else
    SYSTEMD_UNIT=$(systemctl --user list-units 2>/dev/null | grep -o 'openclaw[^ ]*' | head -1)
    SERVICE_MGR="systemd"
fi

OPENCLAW_BIN=$(which openclaw 2>/dev/null || echo "not found")
OPENCLAW_REPO=$([ -f "$HOME/openclaw/package.json" ] && echo "$HOME/openclaw" || echo "not found")

echo "OS: $OS"
echo "Config: $OPENCLAW_CONFIG"
echo "Port: $GW_PORT"
echo "Service: $SERVICE_MGR"
echo "Binary: $OPENCLAW_BIN"
echo "Repo: $OPENCLAW_REPO"
```

---

## Full Diagnosis (One-Shot)

> 複製以下整個 code block 到 terminal 一次執行，會輸出完整診斷報告。

```bash
#!/usr/bin/env bash
set +e  # 任何單行失敗不中斷整體

# ─── 輸出函式 ───
pass() { echo "  ✅ $1"; }
warn() { echo "  ⚠️  $1"; }
fail() { echo "  ❌ $1"; }

# ─── 環境偵測（用 export 穩定傳給 Python 子程序）───
OS=$(uname -s)
export OPENCLAW_HOME="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
export OPENCLAW_CONFIG="${OPENCLAW_CONFIG_PATH:-$OPENCLAW_HOME/openclaw.json}"
export CLAUDE_HOME="$HOME/.claude"
export CLAUDE_SETTINGS="$CLAUDE_HOME/settings.json"
GW_PORT=18789
[ -f "$OPENCLAW_CONFIG" ] && GW_PORT=$(python3 -c "
import json, os
with open(os.environ['OPENCLAW_CONFIG']) as f: cfg = json.load(f)
print(cfg.get('gateway',{}).get('port', 18789))
" 2>/dev/null || echo 18789)

echo "╔══════════════════════════════════════════════╗"
echo "║   🔧 System Tuner — OpenClaw 健康診斷        ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ═══════════════════════════════════════════════
# 1. Gateway 健康檢查
# ═══════════════════════════════════════════════
echo "━━━ 1. Gateway 健康 ━━━"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "http://localhost:${GW_PORT}/health" 2>/dev/null)
if [ "$HTTP_CODE" = "200" ]; then
    pass "Gateway 運行中 (HTTP $HTTP_CODE)"
else
    fail "Gateway 無回應 (HTTP ${HTTP_CODE:-timeout})"
fi

# Service manager
if [ "$OS" = "Darwin" ]; then
    LAUNCHD_LABEL=$(launchctl print gui/$(id -u) 2>/dev/null | grep -o 'openclaw[^"]*gateway' | head -1)
    [ -z "$LAUNCHD_LABEL" ] && LAUNCHD_LABEL="ai.openclaw.gateway"
    if launchctl print "gui/$(id -u)/${LAUNCHD_LABEL}" &>/dev/null; then
        pass "launchd 管理中 ($LAUNCHD_LABEL)"
        PLIST=$(ls ~/Library/LaunchAgents/*openclaw* 2>/dev/null | head -1)
        if [ -n "$PLIST" ]; then
            THROTTLE=$(plutil -extract ThrottleInterval raw "$PLIST" 2>/dev/null || echo "?")
            [ "$THROTTLE" != "?" ] && [ "$THROTTLE" -lt 3 ] 2>/dev/null && \
                warn "ThrottleInterval=$THROTTLE（太低，崩潰時會瘋狂重啟，建議 ≥5）"
        fi
    else
        warn "無 launchd 管理（gateway 掛了不會自動重啟）"
    fi
elif [ "$OS" = "Linux" ]; then
    if systemctl --user is-active openclaw-gateway &>/dev/null; then
        pass "systemd 管理中"
    else
        warn "無 systemd 管理"
    fi
fi

# Log 大小
for log in "$OPENCLAW_HOME/logs/"*.log; do
    [ -f "$log" ] || continue
    SIZE_MB=$(du -m "$log" 2>/dev/null | cut -f1)
    LOG_NAME=$(basename "$log")
    if [ "$SIZE_MB" -gt 100 ] 2>/dev/null; then
        fail "$LOG_NAME: ${SIZE_MB}MB（嚴重，建議 truncate）"
    elif [ "$SIZE_MB" -gt 50 ] 2>/dev/null; then
        warn "$LOG_NAME: ${SIZE_MB}MB（偏大，建議清理）"
    else
        pass "$LOG_NAME: ${SIZE_MB}MB"
    fi
done
[ ! -d "$OPENCLAW_HOME/logs" ] && warn "logs 目錄不存在"

echo ""

# ═══════════════════════════════════════════════
# 2. 模型路由
# ═══════════════════════════════════════════════
echo "━━━ 2. 模型路由 ━━━"
python3 -c "
import json, os, sys, subprocess, time

cfg = json.load(open(os.environ['OPENCLAW_CONFIG']))
providers = cfg.get('models', {}).get('providers', {})

# 顯示 Providers
for name, p in providers.items():
    models = p.get('models', [])
    print(f'  Provider {name}: {len(models)} 個模型')
    url = p.get('baseUrl', '')
    if url:
        try:
            start = time.time()
            r = subprocess.run(['curl', '-s', '-o', '/dev/null', '-w', '%{time_starttransfer}',
                               '--connect-timeout', '5', url + '/models'],
                              capture_output=True, text=True, timeout=10)
            latency = float(r.stdout.strip())
            if latency > 0.7:
                print(f'    ❌ 延遲 {latency:.2f}s（太慢，建議降級）')
            elif latency > 0.3:
                print(f'    ⚠️  延遲 {latency:.2f}s（偏慢）')
            else:
                print(f'    ✅ 延遲 {latency:.2f}s')
        except Exception:
            print(f'    ⚠️  延遲測試失敗')

# Agent 路由
defaults = cfg.get('agents', {}).get('defaults', {}).get('model', {})
agents = cfg.get('agents', {}).get('list', [])
print()
print('  Agent 路由：')
if defaults.get('primary'):
    print('    %-12s primary: %s' % ('defaults', defaults.get('primary', '')))
    for fb in defaults.get('fallbacks', []):
        print('    %-12s fallback: %s' % ('', fb))

for agent in agents:
    aid = agent['id']
    model = agent.get('model', {})
    primary = model.get('primary', '(繼承 defaults)')
    fbs = model.get('fallbacks', [])
    has_free = any('free' in fb for fb in fbs)
    print('    %-12s primary: %s' % (aid, primary))
    for i, fb in enumerate(fbs, 1):
        print('    %-12s fallback %d: %s' % ('', i, fb))
    if fbs and not has_free:
        print('    %-12s ⚠️  fallback 鏈缺少免費保底模型' % '')
" 2>/dev/null || fail "模型路由檢查失敗（config 格式錯誤？）"

echo ""

# ═══════════════════════════════════════════════
# 3. Skills 審計
# ═══════════════════════════════════════════════
echo "━━━ 3. Skills 審計 ━━━"
python3 -c "
import json, os
cfg = json.load(open(os.environ['OPENCLAW_CONFIG']))
agents = cfg.get('agents', {}).get('list', [])

home = os.path.expanduser('~')
repo_skills = os.path.join(home, 'openclaw', 'skills')
repo_count = 0
if os.path.isdir(repo_skills):
    repo_count = len([d for d in os.listdir(repo_skills) if os.path.isdir(os.path.join(repo_skills, d))])
print(f'  官方 skills 目錄: {repo_count} 個')

for agent in agents:
    aid = agent['id']
    skills = agent.get('skills')
    if skills is None:
        print(f'  ❌ {aid:12} skills: 未設白名單（載入全部，影響效能）')
    else:
        print(f'  ✅ {aid:12} skills: {len(skills)} 個白名單')

    # Workspace skills
    ws = agent.get('workspace', '').replace('~', home)
    ws_skills = os.path.join(ws, 'skills')
    if os.path.isdir(ws_skills):
        count = len([d for d in os.listdir(ws_skills) if os.path.isdir(os.path.join(ws_skills, d))])
        if count > 10:
            print(f'    ⚠️  workspace skills: {count} 個（過多）')
        elif count > 0:
            print(f'    ℹ️  workspace skills: {count} 個')
" 2>/dev/null

echo ""

# ═══════════════════════════════════════════════
# 4. Claude Code MCP
# ═══════════════════════════════════════════════
echo "━━━ 4. Claude Code MCP ━━━"
if [ -f "$CLAUDE_SETTINGS" ]; then
    python3 -c "
import json, os, shutil
with open(os.environ['CLAUDE_SETTINGS']) as f: cfg = json.load(f)
servers = cfg.get('mcpServers', {})
print(f'  MCP Servers: {len(servers)} 個')
for name, srv in servers.items():
    cmd = srv.get('command', '?')
    issues = []
    if cmd == 'npx':
        issues.append('npx 啟動慢 → 建議全域安裝')
    elif cmd != '?' and not shutil.which(cmd):
        issues.append(f'command \"{cmd}\" 不存在')
    status = ' ⚠️ ' + '; '.join(issues) if issues else ' ✅'
    print(f'  • {name}: {cmd}{status}')
if len(servers) > 3:
    print('  ⚠️  MCP server 超過 3 個，影響速度')
" 2>/dev/null
else
    echo "  ℹ️  未安裝 Claude Code"
fi

echo ""

# ═══════════════════════════════════════════════
# 5. Plugin 檢查
# ═══════════════════════════════════════════════
echo "━━━ 5. Plugin 檢查 ━━━"
# Claude Code 插件
PLUGIN_DIR="$CLAUDE_HOME/plugins/marketplaces/claude-plugins-official"
if [ -d "$PLUGIN_DIR" ]; then
    EXT=$(ls "$PLUGIN_DIR/external_plugins/" 2>/dev/null | wc -l | tr -d ' ')
    BUILT=$(ls "$PLUGIN_DIR/plugins/" 2>/dev/null | wc -l | tr -d ' ')
    TOTAL=$((EXT + BUILT))
    if [ "$TOTAL" -gt 30 ]; then
        warn "Claude Code 插件過多 ($TOTAL > 30)，影響啟動"
    else
        pass "Claude Code 插件: $TOTAL 個"
    fi
fi

# OpenClaw 插件
python3 -c "
import json, os
cfg = json.load(open(os.environ['OPENCLAW_CONFIG']))
entries = cfg.get('plugins', {}).get('entries', {})
if not entries:
    print('  ℹ️  無 OpenClaw 插件')
for name, e in entries.items():
    enabled = e.get('enabled', True)
    if not enabled:
        print(f'  ⚠️  {name}: disabled 但仍在設定中（可移除節省載入）')
    else:
        print(f'  ✅ {name}: enabled')
" 2>/dev/null

echo ""

# ═══════════════════════════════════════════════
# 6. Session 清理
# ═══════════════════════════════════════════════
echo "━━━ 6. Session 狀態 ━━━"
TOTAL_SESSION_MB=0
if [ -d "$OPENCLAW_HOME/agents" ]; then
    for d in "$OPENCLAW_HOME/agents/"*/; do
        [ -d "$d" ] || continue
        AGENT=$(basename "$d")
        SIZE_MB=$(du -sm "$d/sessions/" 2>/dev/null | cut -f1 || echo 0)
        RESET_COUNT=$(find "$d/sessions/" -name "*.reset.*" 2>/dev/null | wc -l | tr -d ' ')
        ISSUES=""
        [ "$RESET_COUNT" -gt 0 ] && ISSUES="${RESET_COUNT} 個 reset 檔可清除"
        [ "$SIZE_MB" -gt 50 ] 2>/dev/null && ISSUES="${ISSUES:+$ISSUES; }${SIZE_MB}MB 過大"
        [ -n "$ISSUES" ] && warn "$AGENT: $ISSUES" || pass "$AGENT: ${SIZE_MB}MB"
        TOTAL_SESSION_MB=$((TOTAL_SESSION_MB + SIZE_MB))
    done
    echo "  總計: ${TOTAL_SESSION_MB}MB"
else
    echo "  ℹ️  無 agent 目錄"
fi

# Orphan agent 目錄
python3 -c "
import json, os
cfg = json.load(open(os.environ['OPENCLAW_CONFIG']))
configured = set(a['id'] for a in cfg.get('agents',{}).get('list',[]))
agents_dir = os.environ['OPENCLAW_HOME'] + '/agents'
if os.path.isdir(agents_dir):
    existing = set(d for d in os.listdir(agents_dir) if os.path.isdir(os.path.join(agents_dir, d)))
    orphan = existing - configured
    for o in orphan:
        print(f'  ⚠️  \"{o}\" 未在設定中，可刪除')
" 2>/dev/null

echo ""

# ═══════════════════════════════════════════════
# 7. 安全檢查
# ═══════════════════════════════════════════════
echo "━━━ 7. 安全檢查 ━━━"
python3 -c "
import json, os
cfg = json.load(open(os.environ['OPENCLAW_CONFIG']))

# 通道安全
channels = cfg.get('channels', {})
enabled_chs = {k: v for k, v in channels.items() if v.get('enabled', False)}
if not enabled_chs:
    print('  ℹ️  無啟用的通道')
for ch_name, ch in enabled_chs.items():
    allow = ch.get('allowFrom', [])
    dm = ch.get('dmPolicy', '?')
    if '*' in allow:
        msg = '  ❌ %s: allowFrom=[*] 任何人都能使用！' % ch_name
        print(msg)
    elif dm == 'open' and not allow:
        msg = '  ⚠️  %s: dmPolicy=open 且無 allowFrom 限制' % ch_name
        print(msg)
    else:
        msg = '  ✅ %s: 限制 %d 個使用者' % (ch_name, len(allow))
        print(msg)

# Gateway
gw = cfg.get('gateway', {})
mode = gw.get('mode', '?')
has_token = bool(gw.get('auth', {}).get('token'))
print()
tag = '✅' if mode == 'local' else '⚠️ 非 local'
print('  Gateway mode: %s %s' % (mode, tag))
tag2 = '✅ 已設定' if has_token else '❌ 未設定'
print('  Auth token: %s' % tag2)

# API Key 明文
print()
providers = cfg.get('models', {}).get('providers', {})
for name, p in providers.items():
    key = p.get('apiKey', '')
    if key:
        masked = key[:8] + '...' + key[-4:]
        print('  ⚠️  %s: API key 明文存放 (%s)' % (name, masked))
        env_name = 'OPENCLAW_%s_API_KEY' % name.upper()
        print('     → 建議改用環境變數 %s' % env_name)
" 2>/dev/null

echo ""

# ═══════════════════════════════════════════════
# 8. Cron 與自動化
# ═══════════════════════════════════════════════
echo "━━━ 8. Cron 與自動化 ━━━"
CRONTAB=$(crontab -l 2>/dev/null)
if [ -z "$CRONTAB" ]; then
    echo "  ℹ️  無 crontab"
else
    echo "$CRONTAB" | while read -r line; do
        [[ "$line" =~ ^# ]] && continue
        [ -z "$line" ] && continue
        SCRIPT=$(echo "$line" | grep -oE '/[^ ]+\.(sh|js|py)' | head -1)
        if [ -n "$SCRIPT" ] && [ ! -f "$SCRIPT" ]; then
            echo "  ❌ 腳本不存在: $SCRIPT"
        fi
    done
    if echo "$CRONTAB" | grep -qE "truncate|logrotate|openclaw.*log"; then
        pass "已有 log rotation"
    else
        warn "無 log rotation（log 會無限增長）"
    fi
fi

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   📊 診斷完成 — 請依上方標記逐一處理         ║"
echo "╚══════════════════════════════════════════════╝"
```

---

## Optimization Actions

診斷完成後，根據發現的問題提供修復方案。**所有修改必須先告知使用者並獲得確認**。

### 效能優化
- MCP `npx` → 全域安裝（`npm install -g <package>`）
- 未使用的 MCP server / plugin → 從設定移除
- Skills 未設白名單 → 按 agent 角色設定 `"skills": [...]`
- 高延遲 provider → 降級為 fallback
- Session reset 檔案 → `find ~/.openclaw/agents/*/sessions/ -name '*.reset.*' -delete`
- 肥大 log → `truncate -s 0 ~/.openclaw/logs/*.log`
- disabled plugin → 從設定 `entries` 完全移除

### 模型優化
- 確保每條 fallback 鏈末端有免費模型保底
- 付費模型走最便宜的 provider
- 按 agent 角色匹配模型能力：
  - 接待/分派 → 低延遲 + tool use
  - 架構/推理 → reasoning 模型
  - 工程/程式 → coding 專用模型
  - 商業/文筆 → 通用高品質模型

### 安全加固
- 通道 `allowFrom: ["*"]` → 限定使用者 ID
- Gateway 改 `mode: "local"`（localhost only）
- 明文 API key → 改用環境變數

### 自動化
- 指向不存在腳本的 cron → 清除
- 無 log rotation → 加入 `0 3 * * * find ~/.openclaw/logs -name '*.log' -size +10M -exec truncate -s 0 {} \;`
- 無 service manager → 建議設定 launchd (macOS) 或 systemd (Linux)

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
curl -s https://openrouter.ai/api/v1/models | python3 -c "
import json, sys
data = json.load(sys.stdin)
free = []
for m in data.get('data', []):
    p = m.get('pricing', {})
    if float(p.get('prompt', '1') or '1') == 0 and float(p.get('completion', '1') or '1') == 0:
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
