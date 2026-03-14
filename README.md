# system-tuner-99

OpenClaw + Claude Code 全方位診斷與優化工具。一鍵健檢你的 AI 開發環境。

## 功能

| 診斷項目 | 檢查內容 |
|:---|:---|
| **Gateway 健康** | 運行狀態、launchd/systemd 服務管理、log 檔案大小 |
| **模型路由** | Agent 模型分配、fallback 鏈完整性、Provider API 延遲測試 |
| **Skills 審計** | 白名單設定、官方/Workspace 數量分析、效能影響評估 |
| **MCP 檢查** | npx 啟動慢偵測、指令路徑有效性、Server 數量過多警告 |
| **Plugin 檢查** | 已停用但仍載入的插件、啟動速度影響 |
| **Session 清理** | Reset 檔案統計、肥大 Session 偵測、孤立 Agent 目錄 |
| **安全檢查** | 通道 allowFrom 限制、Gateway 綁定模式、明文 API Key 偵測 |
| **Cron 自動化** | 失效 Cron 偵測、Log Rotation 檢查、Service Manager 設定 |

## 安裝

將 `SKILL.md` 放入你的 OpenClaw skills 目錄：

```bash
# 方式 1：放入官方 skills 目錄
cp SKILL.md ~/openclaw/skills/system-tuner/SKILL.md

# 方式 2：放入 workspace skills
mkdir -p ~/.openclaw/workspace/skills/system-tuner
cp SKILL.md ~/.openclaw/workspace/skills/system-tuner/SKILL.md
```

然後在 `openclaw.json` 的 agent 中加入 skills 白名單：

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

在聊天中直接說：

- 「系統優化」「幫我檢查設定」「健檢」「體檢」
- 「效能變慢」「cleanup」「清理」「安全檢查」

也可以手動在終端機執行 One-Shot 診斷腳本，直接複製 `SKILL.md` 中的完整 bash 區塊到終端機即可。

## 系統需求

- macOS（launchd）或 Linux（systemd）
- OpenClaw 2026.3.x+
- Python 3（內建即可）
- Claude Code（選用）

## 搭配使用

- [model-scout-99](https://github.com/lalawgwg99/model-scout-99) — 模型市場偵察、比價、自動切換建議

## 授權

MIT
