#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# 一键配置脚本：Sub2API (Claude Code / CodeX / Grok Build)
# 请求地址: https://sub2api.joe.heiyu.space
# Claude Code: ~/.claude/settings.json
# CodeX:       ~/.codex/auth.json + ~/.codex/config.toml
# Grok Build:  ~/.grok/config.toml
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

BASE_URL="https://sub2api.joe.heiyu.space"
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

mask_secret() {
  local secret="${1:-}"
  if (( ${#secret} <= 12 )); then
    printf '***'
  else
    printf '%s...' "${secret:0:12}"
  fi
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
echo " Sub2API 一键配置脚本"
echo " 请求地址: ${BASE_URL}"
echo "============================================"
echo ""

# ---- 1. 交互选择: Claude or Codex ----
echo "请选择要配置的工具:"
echo "  1) Claude Code（DeepSeek v4 模型）"
echo "  2) CodeX（GPT-5.5 模型）"
echo "  3) Grok Build（grok-4.5 模型）"
read -rp "输入 1-3 [1]: " CHOICE
CHOICE="${CHOICE:-1}"

case "$CHOICE" in
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
    err "无效选择: $CHOICE"
    exit 1
    ;;
esac

echo ""
echo "配置工具: $TOOL_NAME"
echo ""

# ---- 2. 索取 API Key ----
if [[ "$TOOL" == "claude" ]]; then
  KEY_NAME="Sub2API API Key"
  KEY_DESC="在 Sub2API 后台创建 API Key，选择 Anthropic 分组"
elif [[ "$TOOL" == "codex" ]]; then
  KEY_NAME="Sub2API API Key"
  KEY_DESC="在 Sub2API 后台创建 API Key，选择 OpenAI 分组"
else
  KEY_NAME="Sub2API API Key"
  KEY_DESC="在 Sub2API 后台创建 API Key，选择 Grok 分组"
fi

info "${KEY_DESC}"
read -rsp "请输入你的 ${KEY_NAME}: " API_KEY
echo ""

if [[ -z "$API_KEY" ]]; then
  err "${KEY_NAME} 不能为空"
  exit 1
fi

# ---- 3. 配置目标工具 ----
if [[ "$TOOL" == "claude" ]]; then
  # ---- 3a. 配置 Claude Code ----
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
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "deepseek-v4-flash",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "deepseek-v4-pro[1m]",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "deepseek-v4-flash[1M]",
    "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME": "deepseek-v4-flash",
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
  echo "ANTHROPIC_BASE_URL         = ${BASE_URL}"
  echo "ANTHROPIC_AUTH_TOKEN       = $(mask_secret "$API_KEY")"
  echo "HAIKU                      = deepseek-v4-flash"
  echo "OPUS                       = deepseek-v4-pro[1m]"
  echo "SONNET                     = deepseek-v4-flash[1M]"
  echo "SONNET_MODEL_NAME          = deepseek-v4-flash"
  echo ""
  echo "验证命令:"
  echo "  test -f ~/.claude/settings.json && echo OK"
  echo "  claude --version"
  echo "  claude /status"

  log "全部完成！新开一个终端，输入 claude 即可使用。"

elif [[ "$TOOL" == "codex" ]]; then
  # ---- 3b. 配置 CodeX ----
  cleanup_codex_env
  check_residue 'OPENAI_API_KEY|CODEX_HOME' "CodeX"

  info "写入 CodeX 配置文件..."
  mkdir -p "$HOME/.codex"
  API_KEY_JSON=$(json_escape "$API_KEY")

  cat > "$CODEX_AUTH" <<EOF
{
  "OPENAI_API_KEY": "${API_KEY_JSON}"
}
EOF

  cat > "$CODEX_CONFIG" <<EOF
model_provider = "custom"
model = "gpt-5.5"
model_reasoning_effort = "xhigh"
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
  echo "OPENAI_API_KEY = $(mask_secret "$API_KEY")"
  echo "BASE_URL       = ${BASE_URL}"

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
  log "提供商: Sub2API (${BASE_URL})，模型: gpt-5.5"

else
  # ---- 3c. 配置 Grok Build ----
  GROK_CONFIG="$HOME/.grok/config.toml"
  GROK_BASE_URL="https://sub2api.joe.heiyu.space/v1"

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
base_url = "${GROK_BASE_URL}"
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
  echo "BASE_URL       = ${GROK_BASE_URL}"
  echo "API Key        = $(mask_secret "$API_KEY")"
  echo "模型           = grok-4.5"
  echo ""
  echo "验证命令:"
  echo "  grok inspect"
  echo "  grok models"
  echo "  grok -p \"你好\""

  echo ""
  log "全部完成！新开一个终端，输入 grok 即可使用。"
  log "提供商: Sub2API (${GROK_BASE_URL})，模型: grok-4.5"
fi
