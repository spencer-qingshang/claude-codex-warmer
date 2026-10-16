# Codex 本机定时预热

基于 [viseshb/claude-codex-warmer](https://github.com/viseshb/claude-codex-warmer) 的预热逻辑，适配为 Windows 计划任务。

- 任务名称：`CodexUsageWarmer`。
- 每 30 分钟检查一次，登录 Windows 后也会检查。
- 账号已有 5 小时用量窗口时跳过；窗口结束后发送一句 `hi`。
- 两次自动预热至少相隔 5 小时；用量接口不可用时按 5 小时 1 分钟兜底。
- 使用 `gpt-5.6-sol`、低推理强度、只读沙盒，以及上游固定的 Codex CLI 0.144.1。
- 后台运行，电脑需开机且当前 Windows 用户已登录；休眠、关机时不会执行。恢复运行后会补做错过的检查。
- 自动读取 Windows 系统代理；当前网络需要 Clash 正常运行。

程序运行数据存放在 `%LOCALAPPDATA%\CodexUsageWarmer`：`warmer.log` 为检查记录，`last-response.txt` 为最近一次回复，`last-cli.log` 为命令行诊断，`state.json` 为最近成功预热时间。`auth` 目录保存本机单独登录的凭据，不要分享该目录。

暂停任务：右键用 PowerShell 运行 `Stop-LocalTask.ps1`，或执行：

```powershell
Disable-ScheduledTask -TaskName CodexUsageWarmer
```

恢复任务：

```powershell
Enable-ScheduledTask -TaskName CodexUsageWarmer
```

立即做一次常规检查（会按窗口状态决定是否跳过）：

```powershell
Start-ScheduledTask -TaskName CodexUsageWarmer
```

`Invoke-CodexWarm.ps1 -Force` 会绕过间隔限制，真实发送一条测试消息。

GitHub 副本为 https://github.com/spencer-qingshang/claude-codex-warmer 。该账号的 Actions 因计费问题被锁定，因此云端定时已停用，并删除了云端登录 Secrets。本机任务不依赖 GitHub Actions。
