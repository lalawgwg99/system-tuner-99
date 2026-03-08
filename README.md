# system-tuner-99

OpenClaw + Claude Code 全方位診斷與優化 Skill。

## 功能

- **Gateway 健康檢查** — 運行狀態、launchd/systemd、log 大小
- **模型路由檢查** — agent 模型分配、fallback 鏈完整性、API 延遲測試
- **Skills 審計** — 白名單設定、數量分析、第三方 skills 偵測
- **MCP 檢查** — npx vs 直接執行、不存在的 server
- **Plugin 檢查** — disabled 但仍載入的 plugin、數量過多
- **Session 清理** — reset 檔案、肥大 session、未綁定 agent
- **安全檢查** — 通道 allowFrom、Gateway bind、明文 API key、權限白名單
- **Cron 自動化** — 死 cron 偵測、log rotation、service manager 設定

## 安裝

將 `SKILL.md` 放入你的 OpenClaw skills 目錄：

```bash
# 方式 1：放入官方 skills 目錄
cp SKILL.md ~/openclaw/skills/system-tuner/SKILL.md

# 方式 2：放入 workspace skills
mkdir -p ~/.openclaw/workspace/skills/system-tuner
cp SKILL.md ~/.openclaw/workspace/skills/system-tuner/SKILL.md
```

然後在 `openclaw.json` 的 agent skills 白名單中加入 `"system-tuner"`。

## 觸發方式

在聊天中說：

- 「系統優化」「檢查設定」「健檢」「體檢」
- 「效能」「慢」「cleanup」「清理」

## 相容性

- macOS (launchd) + Linux (systemd)
- OpenClaw 2026.3.x+
- Claude Code（可選）

## 搭配使用

- [model-scout-99](https://github.com/lalawgwg99/model-scout-99) — 模型市場偵察、比價、自動切換

## License

MIT
