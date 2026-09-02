#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# 统一配置入口 — Claude Code / CodeX / Grok Build 多提供商支持
# Claude Code: ~/.claude/settings.json
# CodeX:       ~/.codex/auth.json + ~/.codex/config.toml
# Grok Build:  ~/.grok/config.toml
# 交互式：先选工具，再选提供商
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERR]${NC} $*"; }
info() { echo -e "${BLUE}[..]${NC} $*"; }

CLAUDE_SETTINGS="$HOME/.claude/settings.json"
CODEX_AUTH="$HOME/.codex/auth.json"
CODEX_CONFIG="$HOME/.codex/config.toml"
RC_FILES=(
  "$HOME/.bashrc"
  "$HOME/.bash_profile"
  "$HOME/.zshrc"
  "$HOME/.profile"
  "$HOME/.zprofile"
  "$HOME/.zshenv"
)

# ---- 提供商列表（URL + 显示名 + 模型映射） ----
declare -A PROVIDER_URL
PROVIDER_URL["deepseek:claude"]="https://api.deepseek.com/anthropic"
PROVIDER_URL["sub2api:claude"]="https://sub2api.joe.heiyu.space"
PROVIDER_URL["sub2api:codex"]="https://sub2api.joe.heiyu.space"
PROVIDER_URL["cpa:codex"]="https://cliproxy.joe.heiyu.space/v1"
PROVIDER_URL["sub2api:grok"]="https://sub2api.joe.heiyu.space/v1"
PROVIDER_URL["tuzi:codex"]="https://api.tu-zi.com/coding"

mask_secret() {
  local secret="${1:-}"
  printf '*** (%d characters)' "${#secret}"
}

json_escape() {
  local value="${1:-}"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

unset_vars() {
  local var
  for var in "$@"; do
    unset "$var" 2>/dev/null || true
  done
}

cleanup_claude_env() {
  info "清理 Claude 相关环境变量残留..."

  unset_vars \
    ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_MODEL \
    ANTHROPIC_DEFAULT_OPUS_MODEL \
    ANTHROPIC_DEFAULT_SONNET_MODEL \
    ANTHROPIC_DEFAULT_SONNET_MODEL_NAME \
    ANTHROPIC_DEFAULT_HAIKU_MODEL \
    CLAUDE_CODE_SUBAGENT_MODEL CLAUDE_CODE_EFFORT_LEVEL \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC

  local f
  for f in "${RC_FILES[@]}"; do
    if [[ -f "$f" ]]; then
      sed -i.bak -E \
        -e '/^[[:space:]]*#[[:space:]]*----[[:space:]]*Claude Code/d' \
        -e '/^[[:space:]]*(export[[:space:]]+)?ANTHROPIC_[A-Za-z0-9_]*=/d' \
        -e '/^[[:space:]]*(export[[:space:]]+)?CLAUDE_CODE_[A-Za-z0-9_]*=/d' \
        -e '/^[[:space:]]*unset[[:space:]]+ANTHROPIC_[A-Za-z0-9_]*$/d' \
        -e '/^[[:space:]]*unset[[:space:]]+CLAUDE_CODE_[A-Za-z0-9_]*$/d' \
        "$f"
    fi
  done

  rm -f "$HOME/.claude/config.json"
}

cleanup_codex_env() {
  info "清理 CodeX 相关环境变量残留..."

  unset_vars OPENAI_API_KEY CODEX_HOME

  local f
  for f in "${RC_FILES[@]}"; do
    if [[ -f "$f" ]]; then
      sed -i.bak -E \
        -e '/^[[:space:]]*#[[:space:]]*----[[:space:]]*CodeX/d' \
        -e '/^[[:space:]]*(export[[:space:]]+)?OPENAI_API_KEY=/d' \
        -e '/^[[:space:]]*(export[[:space:]]+)?CODEX_HOME=/d' \
        -e '/^[[:space:]]*unset[[:space:]]+CODEX_HOME$/d' \
        "$f"
    fi
  done
}

check_residue() {
  local pattern="$1"
  local label="$2"
  local residue
  residue=$(grep -nE "$pattern" "${RC_FILES[@]}" 2>/dev/null || true)

  if [[ -z "$residue" ]]; then
    log "$label 环境变量残留已清理"
  else
    warn "$label 仍有环境变量残留，请手动检查:"
    echo "$residue"
  fi
}

echo "============================================"
echo " 一键配置脚本 — 统一入口"
echo "============================================"
echo ""

# ============================================================
# 第 1 步：选择工具
# ============================================================
echo "请选择要配置的工具:"
echo "  1) Claude Code（DeepSeek 模型）"
echo "  2) CodeX（gpt-5.6-luna 模型）"
echo "  3) Grok Build（grok-4.5 模型）"
read -rp "输入 1-3 [1]: " TOOL_CHOICE
TOOL_CHOICE="${TOOL_CHOICE:-1}"

case "$TOOL_CHOICE" in
  1|claude|Claude)
    TOOL="claude"
    TOOL_NAME="Claude Code"
    ;;
  2|codex|CodeX)
    TOOL="codex"
    TOOL_NAME="CodeX"
    ;;
  3|grok|Grok)
    TOOL="grok"
    TOOL_NAME="Grok Build"
    ;;
  *)
    err "无效选择: $TOOL_CHOICE"
    exit 1
    ;;
esac

echo ""
echo "配置工具: $TOOL_NAME"
echo ""

# ============================================================
# 第 2 步：选择提供商
# ============================================================
if [[ "$TOOL" == "grok" ]]; then
  echo "  Grok Build → Sub2API 自建网关（sub2api.joe.heiyu.space）"
  PROVIDER="sub2api"
  BASE_URL="${PROVIDER_URL["sub2api:grok"]}"
  KEY_NAME="Sub2API API Key"
  PROVIDER_LABEL="Sub2API"
elif [[ "$TOOL" == "claude" ]]; then
  echo "请选择 API 提供商:"
  echo "  1) DeepSeek 直连（api.deepseek.com）"
  echo "  2) Sub2API 自建网关（sub2api.joe.heiyu.space）"
  read -rp "输入 1-2 [1]: " PROVIDER_CHOICE
  PROVIDER_CHOICE="${PROVIDER_CHOICE:-1}"

  case "$PROVIDER_CHOICE" in
    1) PROVIDER="deepseek" ;;
    2) PROVIDER="sub2api" ;;
    *) err "无效选择: $PROVIDER_CHOICE"; exit 1 ;;
  esac

  BASE_URL="${PROVIDER_URL["${PROVIDER}:claude"]}"
  KEY_NAME="ANTHROPIC_AUTH_TOKEN"

  # 模型映射
  case "$PROVIDER" in
    deepseek)
      MODEL_HAIKU="deepseek-v4-flash"
      MODEL_OPUS="deepseek-v4-pro[1m]"
      MODEL_SONNET="deepseek-v4-flash[1M]"
      MODEL_SONNET_NAME="deepseek-v4-flash"
      PROVIDER_LABEL="DeepSeek 直连"
      ;;
    sub2api)
      MODEL_HAIKU="deepseek-v4-flash"
      MODEL_OPUS="deepseek-v4-pro[1m]"
      MODEL_SONNET="deepseek-v4-flash[1M]"
      MODEL_SONNET_NAME="deepseek-v4-flash"
      PROVIDER_LABEL="Sub2API"
      ;;
  esac
else
  echo "请选择 API 提供商:"
  echo "  1) tuzi（api.tu-zi.com）"
  echo "  2) Sub2API 自建网关（sub2api.joe.heiyu.space）"
  echo "  3) CPA（CLIProxyAPI，cliproxy.joe.heiyu.space）"
  read -rp "输入 1-3 [1]: " PROVIDER_CHOICE
  PROVIDER_CHOICE="${PROVIDER_CHOICE:-1}"

  case "$PROVIDER_CHOICE" in
    1) PROVIDER="tuzi" ;;
    2) PROVIDER="sub2api" ;;
    3) PROVIDER="cpa" ;;
    *) err "无效选择: $PROVIDER_CHOICE"; exit 1 ;;
  esac

  BASE_URL="${PROVIDER_URL["${PROVIDER}:codex"]}"
  KEY_NAME="OpenAI API Key"

  case "$PROVIDER" in
    tuzi)
      CODEX_EFFORT="medium"
      PROVIDER_LABEL="tuzi"
      ;;
    sub2api)
      CODEX_EFFORT="xhigh"
      PROVIDER_LABEL="Sub2API"
      ;;
    cpa)
      CODEX_EFFORT="xhigh"
      PROVIDER_LABEL="CPA（CLIProxyAPI）"
      ;;
  esac
fi

echo ""
info "提供商: ${PROVIDER_LABEL}（${BASE_URL}）"
echo ""

# ============================================================
# 第 3 步：输入 API Key
# ============================================================
if [[ "$TOOL" == "claude" && "$PROVIDER" == "sub2api" ]]; then
  info "Sub2API 后台创建 API Key，选择 Anthropic 分组"
elif [[ "$TOOL" == "codex" && "$PROVIDER" == "sub2api" ]]; then
  info "Sub2API 后台创建 API Key，选择 OpenAI 分组"
elif [[ "$TOOL" == "codex" && "$PROVIDER" == "cpa" ]]; then
  info "请在 CPA（CLIProxyAPI）后台创建可用的 API Key"
elif [[ "$TOOL" == "grok" ]]; then
  info "Sub2API 后台创建 API Key，选择 Grok 分组"
fi

read -rsp "请输入你的 ${KEY_NAME}: " API_KEY
echo ""

if [[ -z "$API_KEY" ]]; then
  err "${KEY_NAME} 不能为空"
  exit 1
fi

# ============================================================
# 第 4 步：检测 shell
# ============================================================
CURRENT_SHELL=$(basename "${SHELL:-/bin/bash}")
log "检测到 shell: $CURRENT_SHELL，写入配置文件，不写入 shell rc"

# ============================================================
# 第 5 步：配置目标工具
# ============================================================
if [[ "$TOOL" == "claude" ]]; then
  # ---- 配置 Claude Code ----
  cleanup_claude_env
  check_residue 'ANTHROPIC_|CLAUDE_CODE_' "Claude"

  info "写入 Claude Code 配置文件: $CLAUDE_SETTINGS ..."
  mkdir -p "$HOME/.claude"
  API_KEY_JSON=$(json_escape "$API_KEY")

  cat > "$CLAUDE_SETTINGS" <<EOF
{
  "env": {
    "ANTHROPIC_BASE_URL": "${BASE_URL}",
    "ANTHROPIC_AUTH_TOKEN": "${API_KEY_JSON}",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "${MODEL_HAIKU}",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "${MODEL_OPUS}",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "${MODEL_SONNET}",
    "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME": "${MODEL_SONNET_NAME}",
    "CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN": "1"
  },
  "includeCoAuthoredBy": false
}
EOF

  chmod 600 "$CLAUDE_SETTINGS"
  log "$CLAUDE_SETTINGS 已创建"

  echo ""
  echo "============================================"
  echo " 配置完成，验证如下:"
  echo "============================================"
  echo "配置文件                  = $CLAUDE_SETTINGS"
  echo "提供商                     = ${PROVIDER_LABEL}"
  echo "ANTHROPIC_BASE_URL         = ${BASE_URL}"
  echo "ANTHROPIC_AUTH_TOKEN       = $(mask_secret "$API_KEY")"
  echo "HAIKU                      = ${MODEL_HAIKU}"
  echo "OPUS                       = ${MODEL_OPUS}"
  echo "SONNET                     = ${MODEL_SONNET}"
  echo "SONNET_MODEL_NAME          = ${MODEL_SONNET_NAME}"
  echo ""
  echo "验证命令:"
  echo "  test -f ~/.claude/settings.json && echo OK"
  echo "  claude --version"
  echo "  claude /status"

  log "全部完成！新开一个终端，输入 claude 即可使用。"

elif [[ "$TOOL" == "codex" ]]; then
  # ---- 配置 CodeX ----
  cleanup_codex_env
  check_residue 'OPENAI_API_KEY|CODEX_HOME' "CodeX"

  info "写入 CodeX 配置文件 (custom: ${BASE_URL})..."
  mkdir -p "$HOME/.codex"
  API_KEY_JSON=$(json_escape "$API_KEY")

  cat > "$CODEX_AUTH" <<EOF
{
  "OPENAI_API_KEY": "${API_KEY_JSON}"
}
EOF

  cat > "$CODEX_CONFIG" <<EOF
model_provider = "custom"
model = "gpt-5.6-luna"
model_reasoning_effort = "${CODEX_EFFORT}"
disable_response_storage = true

[model_providers]
[model_providers.custom]
name = "custom"
wire_api = "responses"
requires_openai_auth = true
base_url = "${BASE_URL}"

[features]
goals = true
EOF

  chmod 600 "$CODEX_AUTH" "$CODEX_CONFIG"
  log "$CODEX_AUTH 已创建"
  log "$CODEX_CONFIG 已创建"

  echo ""
  echo "============================================"
  echo " 配置完成，验证如下:"
  echo "============================================"
  echo "认证文件       = $CODEX_AUTH"
  echo "配置文件       = $CODEX_CONFIG"
  echo "提供商         = ${PROVIDER_LABEL}"
  echo "BASE_URL       = ${BASE_URL}"
  echo "OPENAI_API_KEY = $(mask_secret "$API_KEY")"

  if [[ -f "$CODEX_CONFIG" && -f "$CODEX_AUTH" ]]; then
    log "CodeX 配置文件已就绪"
    echo ""
    echo "关键配置项:"
    grep -E '^(model_provider|model|model_reasoning_effort|disable_response_storage)' "$CODEX_CONFIG" 2>/dev/null || true
    grep -E '^\s*(name|base_url|wire_api|requires_openai_auth)' "$CODEX_CONFIG" 2>/dev/null || true
  else
    err "CodeX 配置文件缺失"
  fi

  echo ""
  echo "验证命令:"
  echo "  test -f ~/.codex/auth.json && test -f ~/.codex/config.toml && echo OK"
  echo "  codex --version"
  echo "  codex /status"
  echo "  codex exec \"hello\""

  echo ""
  log "全部完成！新开一个终端，输入 codex 即可使用。"
  log "提供商: ${PROVIDER_LABEL}（${BASE_URL}），模型: gpt-5.6-luna"

else
  # ---- 配置 Grok Build ----
  GROK_CONFIG="$HOME/.grok/config.toml"

  info "写入 Grok Build 配置文件: $GROK_CONFIG ..."
  mkdir -p "$HOME/.grok"

  cat > "$GROK_CONFIG" <<EOF
[cli]
installer = "internal"

[models]
default = "grok"
web_search = "grok"

[model."grok"]
model = "grok-4.5"
base_url = "${BASE_URL}"
name = "Grok 4.5"
api_key = "${API_KEY}"
api_backend = "responses"
context_window = 1000000
supports_backend_search = true

[marketplace]
default_skills_installs_purged = true
EOF

  chmod 600 "$GROK_CONFIG"
  log "$GROK_CONFIG 已创建"

  echo ""
  echo "============================================"
  echo " 配置完成，验证如下:"
  echo "============================================"
  echo "配置文件       = $GROK_CONFIG"
  echo "提供商         = ${PROVIDER_LABEL}"
  echo "BASE_URL       = ${BASE_URL}"
  echo "API Key        = $(mask_secret "$API_KEY")"
  echo "模型           = grok-4.5"
  echo ""
  echo "验证命令:"
  echo "  grok inspect"
  echo "  grok models"
  echo "  grok -p \"你好\""

  echo ""
  log "全部完成！新开一个终端，输入 grok 即可使用。"
  log "提供商: ${PROVIDER_LABEL}（${BASE_URL}），模型: grok-4.5"
fi
