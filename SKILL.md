---
name: system-tuner
description: "Diagnose and optimize OpenClaw + Claude Code setup. Use when: user says '系統優化', '檢查設定', 'tune', 'optimize', '效能', '慢', 'slow', '健檢', '體檢', 'health check', 'cleanup', '清理'. Covers: model routing, agent config, skills audit, plugin cleanup, MCP servers, security review, gateway health, session cleanup, log rotation."
metadata: { "openclaw": { "emoji": "🔧", "requires": { "bins": ["curl", "node"] } } }
---

# System Tuner Skill

OpenClaw 全方位診斷與自動修復工具。適用於任何 OpenClaw 使用者的環境。

## 使用方式

### 方式一：透過 Agent 對話

在聊天中說「系統優化」「健檢」「體檢」「cleanup」「安全檢查」即可觸發。

### 方式二：終端機直接執行

將 `system-tuner.sh` 複製到本機後執行：

```bash
# 診斷模式（唯讀，不改動任何東西）
bash system-tuner.sh

# 自動修復模式（會自動清理 reset 檔、truncate 肥大 log）
bash system-tuner.sh --fix
```

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

## 診斷項目（8 大模組）

| # | 模組 | 檢查內容 |
|:---|:---|:---|
| 1 | Gateway 健康 | 運行狀態、service manager、log 大小 |
| 2 | 版本與更新 | OpenClaw 版本、config 版本、本地 commit |
| 3 | Config 與模型路由 | Provider 延遲、Agent 模型分配、fallback 鏈、skills 白名單 |
| 4 | Workspace 審計 | AGENTS.md/SOUL.md/MEMORY.md 完整性、workspace skills、memory 目錄 |
| 5 | Plugin 與 MCP | OpenClaw 插件狀態、MCP server 數量與啟動方式 |
| 6 | Session 與 Cron | Reset 檔、session 大小、crontab 有效性、log rotation |
| 7 | 安全檢查 | 通道 allowFrom、Gateway 綁定、明文 API Key |
| 8 | OpenClaw Cron | launchd/systemd 設定、內部 cron 狀態 |

---

## Auto-Fix 模式

`--fix` 標記會自動修復以下問題：

| 問題 | 修復動作 |
|:---|:---|
| 肥大 log 檔 (>50MB) | `truncate -s 0` |
| Session reset 檔 | `find ... -delete` |
| 未來擴充：dead cron | 從 crontab 移除 |
| 未來擴充：orphan agent 目錄 | 確認後刪除 |

**不會自動修復的（需要人工判斷）：**
- 明文 API Key → 只警告
- Skills 白名單未設定 → 只警告
- Model routing 配置 → 只警告
- Gateway mode / security 設定 → 只警告

---

## 健康評分（0-100）

| 分數 | 等級 | 建議 |
|:---|:---|:---|
| 90-100 | ✅ 優秀 | 維持現狀 |
| 70-89 | ⚠️ 良好 | 有改善空間，查看警告項目 |
| 50-69 | ⚠️ 需改善 | 有多項問題，建議執行 `--fix` |
| 0-49 | ❌ 嚴重 | 立即處理，可能影響正常使用 |

扣分規則：
- Gateway 無回應：-30
- 未安裝 openclaw：-10
- log >100MB：-10
- 無 service manager：-5
- log >50MB：-3
- ThrottleInterval 過低：-5
- 每個 agent reset 檔：-2
- 無 log rotation：-3

---

## 參考：檔案位置

| 檔案 | 用途 |
|:---|:---|
| `$OPENCLAW_HOME/openclaw.json` | OpenClaw 主設定 |
| `$OPENCLAW_HOME/agents/*/sessions/` | Agent session 資料 |
| `$OPENCLAW_HOME/logs/` | Gateway log |
| `$OPENCLAW_HOME/extensions/` | OpenClaw 自訂插件 |
| `$CLAUDE_HOME/settings.json` | Claude Code MCP + 模型設定 |
| `$CLAUDE_HOME/settings.local.json` | Claude Code 權限白名單 |
| `~/Library/LaunchAgents/*openclaw*` | macOS launchd 設定 |
| `/etc/systemd/user/*openclaw*` | Linux systemd 設定 |
