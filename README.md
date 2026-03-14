# system-tuner-99

OpenClaw 全方位診斷與自動修復工具。一鍵健檢你的 AI 開發環境。

## 功能

### 🔍 診斷（8 大模組）

| 模組 | 檢查內容 |
|:---|:---|
| **Gateway 健康** | 運行狀態、launchd/systemd 服務管理、log 檔案大小 |
| **版本與更新** | OpenClaw 版本、config 版本、本地 commit |
| **Config 與模型路由** | Provider API 延遲、Agent 模型分配、fallback 鏈完整性、skills 白名單 |
| **Workspace 審計** | AGENTS.md / SOUL.md / MEMORY.md 完整性、workspace skills、memory 目錄 |
| **Plugin 與 MCP** | OpenClaw 插件狀態、MCP server 數量與啟動方式 |
| **Session 與 Cron** | Reset 檔統計、session 大小、crontab 有效性、log rotation |
| **安全檢查** | 通道 allowFrom 限制、Gateway 綁定模式、明文 API Key 偵測 |
| **OpenClaw Cron** | launchd / systemd 設定、內部 cron 狀態 |

### 🩹 自動修復（`--fix` 模式）

一鍵修復可自動處理的問題：

- ✅ 清空肥大 log 檔（>50MB）
- ✅ 刪除 session reset 檔
- ✅ （持續擴充中）

不會自動修復（僅警告）：明文 API Key、skills 白名單、model routing 配置。

### 📊 健康評分（0-100）

根據 8 大模組的檢查結果計算分數，分為四個等級：

| 分數 | 等級 | 意義 |
|:---|:---|:---|
| 90-100 | ✅ 優秀 | 維持現狀 |
| 70-89 | ⚠️ 良好 | 有改善空間 |
| 50-69 | ⚠️ 需改善 | 建議執行 `--fix` |
| 0-49 | ❌ 嚴重 | 立即處理 |

## 安裝

```bash
# 方式 1：放入官方 skills 目錄
mkdir -p ~/openclaw/skills/system-tuner
cp SKILL.md system-tuner.sh ~/openclaw/skills/system-tuner/

# 方式 2：放入 workspace skills
mkdir -p ~/.openclaw/workspace/skills/system-tuner
cp SKILL.md system-tuner.sh ~/.openclaw/workspace/skills/system-tuner/
```

在 `openclaw.json` 的 agent 中加入 skills 白名單：

```json
{
  "agents": {
    "list": [
      {
        "id": "frontdesk",
        "skills": ["system-tuner"]
      }
    ]
  }
}
```

## 使用方式

### 終端機直接執行

```bash
# 診斷模式（唯讀）
bash system-tuner.sh

# 自動修復模式
bash system-tuner.sh --fix
```

### 透過 Agent 對話

在聊天中說：

- 「系統優化」「幫我檢查設定」「健檢」「體檢」
- 「效能變慢」「cleanup」「清理」「安全檢查」

## 系統需求

- macOS（launchd）或 Linux（systemd）
- OpenClaw 2026.3.x+
- Python 3（macOS / Linux 內建）
- curl
- Claude Code（選用）

## 搭配使用

- [model-scout-99](https://github.com/lalawgwg99/model-scout-99) — 模型市場偵察、比價、自動切換建議

## 授權

MIT
