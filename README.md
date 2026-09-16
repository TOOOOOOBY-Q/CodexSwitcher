# CodexSwitcher

一个简单的 Windows Codex Desktop 环境切换工具：通过顶层 NTFS Junction，在 **OpenAI / ChatGPT** 与 **DeepSeek API** 两套已配置好的环境之间切换。

**切换和强制关闭会关闭 Codex 及所有 Microsoft Edge 窗口。请先保存工作，并从资源管理器运行，不要从 Codex 内部终端运行。**

## 四个入口

| 文件 | 功能 |
|---|---|
| `Status.cmd` | 只读显示当前环境、Junction 目标、环境存在性、密钥存在性及进程状态 |
| `Switch_to_OpenAI.cmd` | 关闭 Codex / Edge，切换到 OpenAI 环境，启动 Codex Desktop |
| `Switch_to_DeepSeek.cmd` | 检查 DeepSeek 密钥，关闭 Codex / Edge，切换并启动 Desktop |
| `Force_Close_Codex.cmd` | 关闭 Codex、相关 helper 和 Edge，再次确认退出 |

## 使用前提

- Windows 10/11、Windows PowerShell 5.1、NTFS 文件系统。
- 已安装 MSIX 版 Codex Desktop，包名称为 `OpenAI.Codex`。
- 当前 Windows 用户的以下两套环境已经配置完成，且各自包含 `config.toml`。
- `%USERPROFILE%\.codex` 已经是指向其中一套环境的目录 Junction。
- 使用 DeepSeek 时，设置非空的 `DEEPSEEK_API_KEY` 环境变量。工具只显示 `Present` / `Missing`，不显示密钥。

```text
%USERPROFILE%\
├─ .codex             Junction → .codex_openai 或 .codex_deepseek
├─ .codex_openai      真实目录，OpenAI / ChatGPT 配置
└─ .codex_deepseek    真实目录，DeepSeek API 配置
```

工具自动定位当前用户目录，不需要修改代码中的用户名。它是**已有双环境的切换器**，不负责创建环境、迁移现有数据、安装模型代理或配置第三方 API。

如果 `.codex` 还是普通目录，工具会停止；请先完成自己的环境准备，不要删除该目录来绕过检查。

## 使用

下载并解压工具包，保持四个 CMD 文件与 `_internal` 的相对位置。先运行 `Status.cmd`，再双击对应的切换入口。

```text
CodexSwitcher\
├─ Status.cmd
├─ Switch_to_OpenAI.cmd
├─ Switch_to_DeepSeek.cmd
├─ Force_Close_Codex.cmd
└─ _internal\
   ├─ core\
   ├─ docs\
   └─ tests\
```

成功时显示 `SUCCESS`，并启动 Codex Desktop。失败时显示 `ERROR` 并停止。首次使用 OpenAI 环境时，可能需要重新登录 ChatGPT。

源码仓库另外包含本 README 和 Git 配置文件；日常下载包只保留上面的四个入口和内部目录。

## 实现与保护

- 只验证和替换顶层 `.codex` Junction，不遍历插件、缓存或会话目录。
- 合法的内部 Junction / Symlink 不会阻止切换。
- 不编辑或删除两套真实环境、配置、认证文件或备份。
- 替换失败后尝试恢复旧 Junction；不覆盖意外出现的新目录。
- 简单互斥避免同时执行两个切换/关闭操作。
- 通过当前 MSIX 注册信息启动 Desktop，不写死版本目录。
- 不结束 Explorer、当前 PowerShell / CMD 或任意系统进程。
- 工具本身不调用模型 API。Desktop 启动后的联网行为由 Desktop 自己管理。

这不是全系统句柄审计器。若程序持续重启或权限不足，工具会明确停止；不会为继续切换而递归删除数据。

## 验证

维护者已报告本机最终版真实验收通过。发布版在此基础上仅将个人用户路径改为自动定位，并移除本地历史资料。

七项隔离检查涵盖状态显示、双向 Junction 切换、目标缺失保护和真实目录保护；测试环境特意含有合法的嵌套 Junction。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\_internal\tests\Smoke-Test.ps1
```

测试使用新建的临时目录，不切换真实用户环境，不关闭或启动应用；测试目录会保留。退出码 `0` 表示成功，`1` 表示失败。设置 `CODEX_SWITCHER_NO_PAUSE=1` 可用于自动化读取 CMD 退出码。

## 常见问题

**密钥显示 Present，但 Desktop 仍提示缺少密钥？** 现有 Explorer 会话可能未获得刚修改的用户环境变量。更新登录会话后再试。

**切换时为什么会关闭 Edge？** Edge 可能重新拉起引用 `.codex` 的扩展 helper；关闭 Edge 是此工具明确采用的行为。

**仍有进程存活？** 先运行 `Force_Close_Codex.cmd`，根据剩余进程提示处理，成功后再切换。

**Status 显示 Unknown？** 先检查目录类型或读取权限。不要把未知状态当成可安全切换的状态。

## English

CodexSwitcher is a Windows utility for switching an existing Codex Desktop home Junction between separate OpenAI/ChatGPT and DeepSeek API environments. It detects the current user profile automatically, checks only the top-level link, and preserves both real environment directories.

Switching closes Codex and **all Microsoft Edge windows**. Run the CMD entries from Explorer after saving your work. Both environment directories and the initial Junction must already exist. The tool does not provision environments or make model API requests. Third-party provider compatibility depends on your existing Codex/provider configuration.

This is an independent utility, not an official OpenAI or DeepSeek product.
