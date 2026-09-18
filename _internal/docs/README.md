# CodexSwitcher v2.0.0

Windows 上的轻量 Codex Desktop 环境切换工具。保留原来的 **OpenAI / ChatGPT** 环境，并通过本地 Router 在统一的 **Third Party** 环境中使用 Kimi Code 与 DeepSeek。

这是独立第三方工具，不是 OpenAI、Kimi、Moonshot 或 DeepSeek 官方产品。

[下载 v2.0.0 Windows x64 维护版](https://github.com/TOOOOOOBY-Q/CodexSwitcher/raw/refs/heads/main/downloads/CodexSwitcher-v2.0.0-windows-x64.zip) · [SHA256 校验和](downloads/SHA256SUMS.txt)

## 日常使用

| 入口 | 功能 |
|---|---|
| `Status.cmd` | 查看环境、密钥是否存在、Router 和 Codex 状态 |
| `Switch_to_OpenAI.cmd` | 切回原 OpenAI / ChatGPT，停止 Router，启动 Desktop |
| `Switch_to_ThirdParty.cmd` | 准备 Third Party，启动 Router，切换并启动 Desktop |
| `Force_Close_Codex.cmd` | 关闭 Codex、相关 helper、Edge 和本工具的 Router |

**切换和强制关闭会关闭 Codex 及所有 Microsoft Edge 窗口。先保存工作，再从资源管理器运行；不要在 Codex 内部终端运行切换。**

要求 Windows 10/11 x64、Windows PowerShell 5.1 和 MSIX 版 Codex Desktop。下载包内含单文件 Router exe，使用者无需安装 Go、Node.js 或 Python，也不需要额外的后台服务。

在 Windows「用户环境变量」中设置 `KIMI_API_KEY`、`DEEPSEEK_API_KEY`。有一家密钥即可使用该家；两者都缺失时仍可启动，但请求会提示缺少对应变量。不要把密钥写入配置文件或发到聊天中。更新密钥后重新启动 Router（可先运行 Force Close），已有 Router 不会自动刷新密钥。

## 环境与模型

```text
%USERPROFILE%\.codex  (NTFS Junction)
    ├─ .codex_openai       OpenAI / ChatGPT，原配置不修改
    └─ .codex_thirdparty   model_provider = "thirdparty"
             ↓ Responses API
        127.0.0.1:47831 Router
             ├─ Kimi Code
             └─ DeepSeek
```

| Codex 模型菜单 | API model ID | 上下文 |
|---|---|---|
| Kimi K3 | `k3` | Allegretto 及以上最高 1M |
| Kimi K3 256K | `k3-256k` | 256K |
| Kimi K2.8 Preview | `kimi-for-coding` | 最高 1M |
| Kimi K2.7 Code HighSpeed | `kimi-for-coding-highspeed` | 256K |
| DeepSeek V4.1 Flash | `deepseek-flash` | 1M |
| DeepSeek V4 Pro | `deepseek-v4-pro` | 1M |

首次创建默认 `deepseek-flash` / `high`。后续启动不重写已有配置或重置用户选中的模型。Kimi 可用模型还受会员权限限制。

正常路径是在 **Codex 自带模型菜单**切换模型，Router 根据 model ID 选上游，无需切 Junction。当前机器 CLI `/model` 已验证显示六个模型；Desktop picker 的实际验收状态见 `_internal/docs/VALIDATION.md`。未验证的 Desktop 行为不代表已解决，也不自动归因于上游 bug。

内部维修入口 `_internal\tools\Select-ThirdParty-Model.cmd` 可备份并修改默认模型及思考档位，保留 MCP、项目 trust 和其他设置。之后新建会话；Desktop 未重新读取配置时需要重启。旧会话可能保留自己的模型。

## 首次迁移

若 `.codex_thirdparty` 不存在且有 `.codex_deepseek`，切换时会询问是否**复制**旧环境。原 `.codex_deepseek` 完整保留；新副本经过配置、模型目录验证才用于切换。复制失败保留现场，不切 Junction。已存在的 Third Party 不会自动覆盖或重新迁移。

旧 `Switch_to_DeepSeek.cmd` 已移至 `_internal\legacy`，仅作为兼容入口：进入同一个 Third Party，并将默认模型设为 `deepseek-flash`。不要把 `_internal\archive` 中的历史脚本用于日常切换。

`.codex` 必须已经是指向已知环境的 Junction。普通目录、未知目标或目标缺失会明确报错，不删除用户数据。创建 Junction 失败会尝试恢复原链接。

## Router

仅监听 IPv4 loopback。端口唯一来源为 `_internal/router/registry.json`，PowerShell 从 exe 读取；不会占用或杀掉未知程序。相同路径、版本且健康的 Router 可以复用，停止时检查 PID 和 executable 路径。

Kimi 请求移除不支持的内置 `tool_search`，保留内置 web search；DeepSeek 仅移除内置 web search 工具，保留 function、namespace、custom、shell 和 apply_patch。SSE 边读边发，不等待整段输出，不依赖 `[DONE]`。

默认日志位于 `.codex_thirdparty\.switcher\router.log`，只含模型、provider、HTTP 状态、流式标志、耗时和错误类别，不记录 prompt、响应内容或密钥。请求体上限为 64 MiB。显式 `--debug-schema` 仅增加字段名信息。

## 本地验证与构建

运行 `_internal\tests\Smoke-Test.ps1`：使用独立临时目录和端口，不关闭真实 Codex、不切真实 Junction、不调用收费 API。内置 `Router.Tests.exe` 运行本地 mock 测试；最终验收仍需真实 Desktop、两家 API 和模型切换。

开发者可用 Go 运行 `_internal\tools\Build-Router.ps1`。本版本用 Go 1.27.1 windows/amd64 构建，`CGO_ENABLED=0`；TOML 库固定为 go-toml/v2 v2.2.4 并随源码 vendor。构建脚本运行测试、生成 Router 及测试 exe。模型 registry 随版本维护，启动时不抓官网。

官方依据：[Kimi Codex 接入](https://www.kimi.com/code/docs/third-party-tools/codex.html)、[Kimi 模型](https://www.kimi.com/code/docs/en/kimi-code/models.html)、[DeepSeek Codex 接入](https://api-docs.deepseek.com/quick_start/agent_integrations/codex/)、[Codex 配置参考](https://learn.chatgpt.com/docs/config-file/config-reference)。
