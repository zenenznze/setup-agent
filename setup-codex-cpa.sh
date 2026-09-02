#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# 单独配置 CodeX 使用 CPA（CLIProxyAPI）
# 请求地址: https://cliproxy.joe.heiyu.space
# CodeX API base_url: https://cliproxy.joe.heiyu.space/v1
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

CPA_URL="https://cliproxy.joe.heiyu.space"
BASE_URL="${CPA_URL}/v1"
MODEL="gpt-5.6-luna"
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
  printf '*** (%d characters)' "${#secret}"
}

usage() {
  cat <<'EOF'
用法:
  ./setup-codex-cpa.sh                  交互式输入 API Key
  ./setup-codex-cpa.sh --api-key-stdin  从 stdin 读取 API Key（适合自动化调用）
  ./setup-codex-cpa.sh --help           显示帮助

安全说明:
  不要把 API Key 作为命令行参数传入，避免出现在 shell 历史或进程列表中。
EOF
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

cleanup_env() {
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
echo " CPA + CodeX 配置"
echo " 请求地址: ${CPA_URL}"
echo " API base_url: ${BASE_URL}"
echo " 模型: ${MODEL}"
echo "============================================"
echo ""

if (( $# > 1 )); then
  err "参数过多，请使用 --help 查看用法"
  exit 1
fi

case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
  --api-key-stdin)
    if [[ -t 0 ]]; then
      err "--api-key-stdin 需要通过 stdin 提供 API Key"
      exit 1
    fi
    IFS= read -r API_KEY || true
    ;;
  "")
    info "请在 CPA（CLIProxyAPI）后台创建可用的 API Key"
    read -rsp "请输入你的 CPA API Key: " API_KEY
    echo ""
    ;;
  *)
    err "未知参数: $1"
    usage
    exit 1
    ;;
esac

if [[ -z "$API_KEY" ]]; then
  err "API Key 不能为空"
  exit 1
fi

cleanup_env
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
model = "${MODEL}"
model_reasoning_effort = "xhigh"
disable_response_storage = true

[model_providers]
[model_providers.custom]
name = "CPA"
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
echo "提供商         = CPA（CLIProxyAPI）"
echo "请求地址       = ${CPA_URL}"
echo "BASE_URL       = ${BASE_URL}"
echo "OPENAI_API_KEY = $(mask_secret "$API_KEY")"
echo "MODEL          = ${MODEL}"
echo ""

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
log "提供商: CPA（${CPA_URL}），模型: ${MODEL}"
