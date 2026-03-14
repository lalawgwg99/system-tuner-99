#!/usr/bin/env bash
# System Tuner v2 — OpenClaw 全方位診斷與自動修復
# Usage: bash system-tuner.sh [--fix]
# https://github.com/lalawgwg99/system-tuner-99

set +e

FIX_MODE=false
[[ "$1" == "--fix" ]] && FIX_MODE=true
FIXED=0

# ─── 輸出函式 ───
ok()    { echo "  ✅ $1"; }
warn()  { echo "  ⚠️  $1"; }
err()   { echo "  ❌ $1"; }
fix()   { echo "  🔧 $1"; ((FIXED++)); }
info()  { echo "  ℹ️  $1"; }

# ─── 環境偵測 ───
OS=$(uname -s)
export OPENCLAW_HOME="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
export OPENCLAW_CONFIG="${OPENCLAW_CONFIG_PATH:-$OPENCLAW_HOME/openclaw.json}"
export CLAUDE_HOME="$HOME/.claude"
export CLAUDE_SETTINGS="$CLAUDE_HOME/settings.json"
export OPENCLAW_VERSION="unknown"
export OPENCLAW_BIN=$(which openclaw 2>/dev/null || echo "")
GW_PORT=18789
[ -f "$OPENCLAW_CONFIG" ] && GW_PORT=$(python3 -c "
import json, os
with open(os.environ['OPENCLAW_CONFIG']) as f:
    cfg = json.load(f)
print(cfg.get('gateway',{}).get('port', 18789))
" 2>/dev/null || echo 18789)

# OpenClaw version
if [ -n "$OPENCLAW_BIN" ]; then
    OPENCLAW_VERSION=$($OPENCLAW_BIN --version 2>/dev/null | head -1 || echo "unknown")
fi

# Health score (start at 100, deduct)
SCORE=100
deduct() { SCORE=$((SCORE - $1)); [ $SCORE -lt 0 ] && SCORE=0; }

echo "╔══════════════════════════════════════════════════════╗"
echo "║   🔧 System Tuner v2 — OpenClaw 健康診斷             ║"
$FIX_MODE && echo "║   🩹 Auto-Fix 模式已啟用                              ║"
echo "║   📋 $OS │ Port $GW_PORT │ $OPENCLAW_VERSION                    ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ═══════════════════════════════════════════════
# 1. Gateway 健康
# ═══════════════════════════════════════════════
echo "━━━ 1. Gateway 健康 ━━━"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "http://localhost:${GW_PORT}/health" 2>/dev/null)
if [ "$HTTP_CODE" = "200" ]; then
    ok "Gateway 運行中 (HTTP $HTTP_CODE)"
else
    err "Gateway 無回應 (HTTP ${HTTP_CODE:-timeout})"
    deduct 30
fi

# Service manager
if [ "$OS" = "Darwin" ]; then
    LAUNCHD_LABEL=$(launchctl print gui/$(id -u) 2>/dev/null | grep -o 'openclaw[^"]*gateway' | head -1)
    [ -z "$LAUNCHD_LABEL" ] && LAUNCHD_LABEL="ai.openclaw.gateway"
    if launchctl print "gui/$(id -u)/${LAUNCHD_LABEL}" &>/dev/null; then
        ok "launchd 管理中 ($LAUNCHD_LABEL)"
        PLIST=$(ls ~/Library/LaunchAgents/*openclaw* 2>/dev/null | head -1)
        if [ -n "$PLIST" ]; then
            THROTTLE=$(plutil -extract ThrottleInterval raw "$PLIST" 2>/dev/null || echo "?")
            if [ "$THROTTLE" != "?" ] && [ "$THROTTLE" -lt 3 ] 2>/dev/null; then
                warn "ThrottleInterval=$THROTTLE（建議 ≥5）"
                deduct 5
            fi
        fi
    else
        warn "無 launchd 管理"
        deduct 5
    fi
fi

# Log 大小
for log in "$OPENCLAW_HOME/logs/"*.log; do
    [ -f "$log" ] || continue
    SIZE_MB=$(du -m "$log" 2>/dev/null | cut -f1)
    LOG_NAME=$(basename "$log")
    if [ "$SIZE_MB" -gt 100 ] 2>/dev/null; then
        err "$LOG_NAME: ${SIZE_MB}MB"
        deduct 10
        if $FIX_MODE; then
            truncate -s 0 "$log"
            fix "已清空 $LOG_NAME"
        fi
    elif [ "$SIZE_MB" -gt 50 ] 2>/dev/null; then
        warn "$LOG_NAME: ${SIZE_MB}MB"
        deduct 3
        if $FIX_MODE; then
            truncate -s 0 "$log"
            fix "已清空 $LOG_NAME"
        fi
    else
        ok "$LOG_NAME: ${SIZE_MB}MB"
    fi
done

echo ""

# ═══════════════════════════════════════════════
# 2. 版本與更新
# ═══════════════════════════════════════════════
echo "━━━ 2. 版本與更新 ━━━"
if [ -n "$OPENCLAW_BIN" ]; then
    ok "OpenClaw 已安裝: $OPENCLAW_VERSION"
    # Check if local repo exists for update check
    REPO_DIR="$HOME/openclaw"
    if [ -d "$REPO_DIR/.git" ]; then
        INSTALLED_VER=$(cd "$REPO_DIR" && git log -1 --format="%h" 2>/dev/null)
        info "本地 commit: $INSTALLED_VER"
    fi
else
    err "openclaw 不在 PATH 中"
    deduct 10
fi

# Config version
if [ -f "$OPENCLAW_CONFIG" ]; then
    CFG_VER=$(python3 -c "
import json, os
with open(os.environ['OPENCLAW_CONFIG']) as f:
    cfg = json.load(f)
print(cfg.get('meta',{}).get('lastTouchedVersion','unknown'))
" 2>/dev/null)
    ok "Config 版本: $CFG_VER"
fi

echo ""

# ═══════════════════════════════════════════════
# 3. Config 與模型路由
# ═══════════════════════════════════════════════
echo "━━━ 3. Config 與模型路由 ━━━"
python3 -c "
import json, os, subprocess, time

cfg = json.load(open(os.environ['OPENCLAW_CONFIG']))
providers = cfg.get('models', {}).get('providers', {})
agents = cfg.get('agents', {}).get('list', [])
defaults = cfg.get('agents', {}).get('defaults', {})

# Sandbox check
sandbox_mode = defaults.get('sandbox', {}).get('mode', 'unknown')
print('  Sandbox mode: %s' % sandbox_mode)

# Providers
for name, p in providers.items():
    models = p.get('models', [])
    url = p.get('baseUrl', '')
    lat_str = ''
    if url:
        try:
            r = subprocess.run(
                ['curl', '-s', '-o', '/dev/null', '-w', '%{time_starttransfer}',
                 '--connect-timeout', '5', url + '/models'],
                capture_output=True, text=True, timeout=10)
            lat = float(r.stdout.strip())
            if lat > 0.7:
                lat_str = ' ❌ %.2fs' % lat
            elif lat > 0.3:
                lat_str = ' ⚠️ %.2fs' % lat
            else:
                lat_str = ' ✅ %.2fs' % lat
        except:
            lat_str = ' ⚠️ timeout'
    print('  Provider %s: %d models%s' % (name, len(models), lat_str))

# Agent routing
print()
default_model = defaults.get('model', {})
print('  Agent 路由：')
if default_model.get('primary'):
    print('    %-12s primary: %s' % ('defaults', default_model['primary']))
    for fb in default_model.get('fallbacks', []):
        print('    %-12s fallback: %s' % ('', fb))

has_issues = False
for agent in agents:
    aid = agent['id']
    model = agent.get('model', {})
    primary = model.get('primary', '(繼承 defaults)')
    fbs = model.get('fallbacks', [])
    has_free = any('free' in fb or 'nemotron' in fb for fb in fbs)
    skills = agent.get('skills')
    skill_flag = '✅' if skills else '❌ 無白名單'
    print('    %-12s primary: %s  %s' % (aid, primary, skill_flag))
    for i, fb in enumerate(fbs, 1):
        print('    %-12s   fallback %d: %s' % ('', i, fb))
    if fbs and not has_free:
        print('    %-12s   ⚠️ 缺少免費保底' % '')
        has_issues = True
" 2>/dev/null

echo ""

# ═══════════════════════════════════════════════
# 4. Workspace 審計
# ═══════════════════════════════════════════════
echo "━━━ 4. Workspace 審計 ━━━"
python3 -c "
import json, os

cfg = json.load(open(os.environ['OPENCLAW_CONFIG']))
agents = cfg.get('agents', {}).get('list', [])
home = os.path.expanduser('~')

# Official skills
repo_skills = os.path.join(home, 'openclaw', 'skills')
repo_count = 0
if os.path.isdir(repo_skills):
    repo_count = len([d for d in os.listdir(repo_skills) if os.path.isdir(os.path.join(repo_skills, d))])
print('  官方 skills: %d 個' % repo_count)

# Per-agent workspace health
for agent in agents:
    aid = agent['id']
    ws = agent.get('workspace', '').replace('~', home)
    issues = []
    ok_items = []

    # Check required files
    for fname in ['AGENTS.md', 'SOUL.md', 'MEMORY.md', 'HEARTBEAT.md']:
        fpath = os.path.join(ws, fname)
        if os.path.isfile(fpath):
            size = os.path.getsize(fpath)
            if size < 10:
                issues.append('%s 空檔案' % fname)
        else:
            issues.append('缺少 %s' % fname)

    # Workspace skills
    ws_skills = os.path.join(ws, 'skills')
    if os.path.isdir(ws_skills):
        count = len([d for d in os.listdir(ws_skills) if os.path.isdir(os.path.join(ws_skills, d))])
        if count > 0:
            ok_items.append('workspace skills: %d' % count)

    # Memory dir
    mem_dir = os.path.join(ws, 'memory')
    if os.path.isdir(mem_dir):
        files = os.listdir(mem_dir)
        ok_items.append('memory/: %d files' % len(files))

    status = '❌ ' + '; '.join(issues) if issues else '✅'
    extras = (' (' + ', '.join(ok_items) + ')') if ok_items else ''
    print('  %-12s %s%s' % (aid, status, extras))
" 2>/dev/null

echo ""

# ═══════════════════════════════════════════════
# 5. Plugin 與 MCP
# ═══════════════════════════════════════════════
echo "━━━ 5. Plugin 與 MCP ━━━"

# OpenClaw plugins
python3 -c "
import json, os
cfg = json.load(open(os.environ['OPENCLAW_CONFIG']))
entries = cfg.get('plugins', {}).get('entries', {})
for name, e in entries.items():
    enabled = e.get('enabled', True)
    if not enabled:
        print('  ⚠️  %s: disabled 但仍在設定中' % name)
    else:
        print('  ✅ %s: enabled' % name)
" 2>/dev/null

# MCP
if [ -f "$CLAUDE_SETTINGS" ]; then
    python3 -c "
import json, os, shutil
with open(os.environ['CLAUDE_SETTINGS']) as f:
    cfg = json.load(f)
servers = cfg.get('mcpServers', {})
if servers:
    print('  MCP Servers: %d 個' % len(servers))
    for name, srv in servers.items():
        cmd = srv.get('command', '?')
        issues = []
        if cmd == 'npx':
            issues.append('npx 啟動慢')
        elif cmd != '?' and not shutil.which(cmd):
            issues.append('%s 不存在' % cmd)
        status = ' ⚠️ ' + '; '.join(issues) if issues else ' ✅'
        print('  • %s: %s%s' % (name, cmd, status))
else:
    print('  ℹ️  無 MCP servers')
" 2>/dev/null
fi

echo ""

# ═══════════════════════════════════════════════
# 6. Session 與 Cron
# ═══════════════════════════════════════════════
echo "━━━ 6. Session 與 Cron ━━━"
TOTAL_RESETS=0
if [ -d "$OPENCLAW_HOME/agents" ]; then
    for d in "$OPENCLAW_HOME/agents/"*/; do
        [ -d "$d" ] || continue
        AGENT=$(basename "$d")
        SIZE_MB=$(du -sm "$d/sessions/" 2>/dev/null | cut -f1 || echo 0)
        RESET_COUNT=$(find "$d/sessions/" -name "*.reset.*" 2>/dev/null | wc -l | tr -d ' ')
        TOTAL_RESETS=$((TOTAL_RESETS + RESET_COUNT))
        ISSUES=""
        [ "$RESET_COUNT" -gt 0 ] && ISSUES="${RESET_COUNT} 個 reset"
        [ "$SIZE_MB" -gt 50 ] 2>/dev/null && ISSUES="${ISSUES:+$ISSUES; }${SIZE_MB}MB"
        if [ -n "$ISSUES" ]; then
            warn "$AGENT: $ISSUES"
            deduct 2
            if $FIX_MODE; then
                find "$d/sessions/" -name "*.reset.*" -delete 2>/dev/null
                fix "已清除 $AGENT 的 reset 檔"
            fi
        else
            ok "$AGENT: ${SIZE_MB}MB"
        fi
    done
    echo "  總 reset 檔: $TOTAL_RESETS"
else
    info "無 agent 目錄"
fi

# Cron
CRONTAB=$(crontab -l 2>/dev/null)
if [ -z "$CRONTAB" ]; then
    info "無 crontab"
else
    echo "$CRONTAB" | while read -r line; do
        [[ "$line" =~ ^# ]] && continue
        [ -z "$line" ] && continue
        SCRIPT=$(echo "$line" | grep -oE '/[^ ]+\.(sh|js|py)' | head -1)
        if [ -n "$SCRIPT" ] && [ ! -f "$SCRIPT" ]; then
            err "腳本不存在: $SCRIPT"
            deduct 5
        fi
    done
    if echo "$CRONTAB" | grep -qE "truncate|logrotate|openclaw.*log"; then
        ok "已有 log rotation"
    else
        warn "無 log rotation"
        deduct 3
    fi
fi

echo ""

# ═══════════════════════════════════════════════
# 7. 安全檢查
# ═══════════════════════════════════════════════
echo "━━━ 7. 安全檢查 ━━━"
python3 -c "
import json, os
cfg = json.load(open(os.environ['OPENCLAW_CONFIG']))

# Channel security
channels = cfg.get('channels', {})
enabled_chs = {k: v for k, v in channels.items() if v.get('enabled', False)}
if not enabled_chs:
    print('  ℹ️  無啟用的通道')
for ch_name, ch in enabled_chs.items():
    allow = ch.get('allowFrom', [])
    dm = ch.get('dmPolicy', '?')
    if '*' in allow:
        print('  ❌ %s: allowFrom=[*] 任何人都能使用！' % ch_name)
    elif dm == 'open' and not allow:
        print('  ⚠️  %s: dmPolicy=open 且無 allowFrom' % ch_name)
    else:
        print('  ✅ %s: 限制 %d 個使用者' % (ch_name, len(allow)))

# Gateway
gw = cfg.get('gateway', {})
mode = gw.get('mode', '?')
has_token = bool(gw.get('auth', {}).get('token'))
tag = '✅' if mode == 'local' else '⚠️ 非 local'
print('  Gateway mode: %s %s' % (mode, tag))
tag2 = '✅ 已設定' if has_token else '❌ 未設定'
print('  Auth token: %s' % tag2)

# API Key
print()
providers = cfg.get('models', {}).get('providers', {})
for name, p in providers.items():
    key = p.get('apiKey', '')
    if key:
        masked = key[:8] + '...' + key[-4:]
        print('  ⚠️  %s: 明文 API key (%s)' % (name, masked))
        env_name = 'OPENCLAW_%s_API_KEY' % name.upper()
        print('     → 建議用環境變數 %s' % env_name)
" 2>/dev/null

echo ""

# ═══════════════════════════════════════════════
# 8. Cron 自動化（OpenClaw internal）
# ═══════════════════════════════════════════════
echo "━━━ 8. OpenClaw Cron 狀態 ━━━"
python3 -c "
import json, os
cfg = json.load(open(os.environ['OPENCLAW_CONFIG']))
# Check if there are cron jobs configured
gw = cfg.get('gateway', {})
print('  ℹ️  OpenClaw cron 需透過 API 或 session 查詢')
" 2>/dev/null

# Check service manager
if [ "$OS" = "Darwin" ]; then
    PLIST=$(ls ~/Library/LaunchAgents/*openclaw* 2>/dev/null | head -1)
    if [ -n "$PLIST" ]; then
        ok "launchd plist: $(basename $PLIST)"
    else
        warn "無 launchd 設定"
    fi
fi

echo ""

# ═══════════════════════════════════════════════
# 診斷總結
# ═══════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════════╗"
if [ $SCORE -ge 90 ]; then
    printf "║   📊 健康評分: %d/100 ✅ 優秀                          ║\n" $SCORE
elif [ $SCORE -ge 70 ]; then
    printf "║   📊 健康評分: %d/100 ⚠️  良好                         ║\n" $SCORE
elif [ $SCORE -ge 50 ]; then
    printf "║   📊 健康評分: %d/100 ⚠️  需改善                       ║\n" $SCORE
else
    printf "║   📊 健康評分: %d/100 ❌ 嚴重                         ║\n" $SCORE
fi
if $FIX_MODE; then
    printf "║   🔧 已自動修復: %d 個項目                             ║\n" $FIXED
fi
echo "╚══════════════════════════════════════════════════════╝"
