# setup-agent

Linux 上一键配置 Claude Code / CodeX 的交互式脚本。

## 快速开始

```bash
curl -O https://raw.githubusercontent.com/zenenznze/setup-agent/main/setup.sh
chmod +x setup.sh
./setup.sh
```

`setup.sh` 是统一入口，交互式引导完成配置：

1. **选择工具** — Claude Code、CodeX 或 Grok Build
2. **选择提供商** — 根据工具列出可用目标
3. **输入 API Key** — 自动写入对应配置文件

## 可用提供商

| 工具 | 提供商 | API 地址 |
|------|--------|----------|
| Claude Code | DeepSeek 直连 | `https://api.deepseek.com/anthropic` |
| Claude Code | Sub2API 自建网关 | `https://sub2api.joe.heiyu.space` |
| CodeX | tuzi | `https://api.tu-zi.com/coding` |
| CodeX | Sub2API 自建网关 | `https://sub2api.joe.heiyu.space` |
| CodeX | CPA（CLIProxyAPI） | `https://cliproxy.joe.heiyu.space/v1` |
| Grok Build | Sub2API 自建网关 | `https://sub2api.joe.heiyu.space/v1` |

## 独立专项脚本

如需绕过交互菜单直接使用特定提供商，也可用专项脚本：

| 脚本 | 用途 | API 地址 |
|------|------|----------|
| `setup-deepseek.sh` | Claude Code → DeepSeek 直连 | `https://api.deepseek.com/anthropic` |
| `setup-sub2api.sh` | Claude Code / CodeX / Grok Build → Sub2API | `https://sub2api.joe.heiyu.space` |
| `setup-codex-tuzi.sh` | CodeX → tuzi | `https://api.tu-zi.com/coding` |
| `setup-codex-cpa.sh` | CodeX → CPA（CLIProxyAPI） | `https://cliproxy.joe.heiyu.space` |

CPA 脚本支持两种调用方式：

```bash
# 手动配置：脚本会隐藏输入的 API Key
./setup-codex-cpa.sh

# 自动化配置：通过 stdin 传入，避免 API Key 出现在命令行参数和进程列表中
printf '%s\n' "$CPA_API_KEY" | ./setup-codex-cpa.sh --api-key-stdin
```

## 配置 Claude Code

写入 `~/.claude/settings.json`，以 DeepSeek 直连为例：

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
    "ANTHROPIC_AUTH_TOKEN": "<你的 Token>",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "deepseek-v4-pro[1m]",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "deepseek-v4-flash[1M]",
    "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME": "deepseek-v4-flash",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "deepseek-v4-flash",
    "CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN": "1"
  },
  "includeCoAuthoredBy": false
}
```

配置前会从常见 shell rc 文件中清理 `ANTHROPIC_*` 和 `CLAUDE_CODE_*` 环境变量残留。

验证命令：
```bash
test -f ~/.claude/settings.json && echo OK
claude --version
claude /status
```

### DeepSeek 直连

选择 DeepSeek 提供商后，API 地址为 `https://api.deepseek.com/anthropic`，使用你的 DeepSeek API Key。

### Sub2API

选择 Sub2API 提供商后，API 地址为 `https://sub2api.joe.heiyu.space`。
需要在 Sub2API 后台创建 API Key，选择 **Anthropic 分组**。

## 配置 CodeX

写入 `~/.codex/auth.json`：

```json
{
  "OPENAI_API_KEY": "<你的 API Key>"
}
```

写入 `~/.codex/config.toml`（以 tuzi 提供商为例）：

```toml
model_provider = "custom"
model = "gpt-5.6-luna"
model_reasoning_effort = "medium"
disable_response_storage = true

[model_providers]
[model_providers.custom]
name = "custom"
wire_api = "responses"
requires_openai_auth = true
base_url = "https://api.tu-zi.com/coding"

[features]
goals = true
```

配置前会从常见 shell rc 文件中清理 `OPENAI_API_KEY` 和 `CODEX_HOME` 环境变量残留。

验证命令：
```bash
test -f ~/.codex/auth.json && test -f ~/.codex/config.toml && echo OK
codex --version
codex /status
codex exec "hello"
```

### tuzi 提供商

- `base_url`: `https://api.tu-zi.com/coding`
- `model_reasoning_effort`: `medium`

### Sub2API

- `base_url`: `https://sub2api.joe.heiyu.space`
- 需要在 Sub2API 后台创建 API Key，选择 **OpenAI 分组**

### CPA（CLIProxyAPI）

- 请求地址：`https://cliproxy.joe.heiyu.space`
- CodeX 配置中的 `base_url` 使用 `https://cliproxy.joe.heiyu.space/v1`，以请求 CPA 的 OpenAI Responses 端点
- 在 CPA 后台创建可用的 API Key
- 脚本不会接受命令行参数形式的 API Key，自动化场景请使用 `--api-key-stdin`

## 配置 Grok Build

写入 `~/.grok/config.toml`，请求地址指向 Sub2API 自建网关：

```toml
[cli]
installer = "internal"

[models]
default = "grok"
web_search = "grok"

[model."grok"]
model = "grok-4.5"
base_url = "https://sub2api.joe.heiyu.space/v1"
name = "Grok 4.5"
api_key = "<你的 API Key>"
api_backend = "responses"
context_window = 1000000
supports_backend_search = true

[marketplace]
default_skills_installs_purged = true
```

- `base_url` 带 `/v1`：Grok CLI 使用 `api_backend = "responses"` 时会请求 `https://sub2api.joe.heiyu.space/v1/responses`，对应 Sub2API 的 OpenAI Responses 网关端点
- 需要在 Sub2API 后台创建 API Key，选择 **Grok 分组**

验证命令：
```bash
grok inspect
grok models
grok -p "你好"
```

## 设计原则

- 配置 Claude Code 时只清理 Claude 相关环境变量，不删除 CodeX 配置
- 配置 CodeX 时只清理 CodeX 相关环境变量，不删除 Claude 配置
- 新配置直接写入工具自己的配置文件，不再把 API Key 写入 shell rc 环境变量
- 所有 Claude Code 配置均包含 `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1`，默认禁用全屏 TUI 模式
