#!/usr/bin/env bash
# ============================================================================
# llm-vision 一键部署脚本
#
# ⚠️ 适用范围：本脚本针对【Claude Code】用户。
#    - 使用 Claude Code：直接运行本脚本，自动完成全部部署
#    - 使用其他客户端（Cursor / Codex / Cline 等）：只需 npm install + 配 Key，
#      无需（也无法）执行"注册 Claude Code"这一步，见下方 --no-claude
#
# 功能：
#   1. 检查 Node.js 环境
#   2. 安装 npm 依赖
#   3. 引导配置阿里云百炼 API Key（写入 .env，自动忽略不提交）
#   4. 注册为 Claude Code 全局 MCP（llm-vision）
#   5.（可选）安装 image-recognition Skill（仅 Claude Code 用户需要）
#   6. 输出验证命令
#
# 用法：
#   bash install.sh              # Claude Code 用户：完整部署（含注册，会询问是否装 skill）
#   bash install.sh --no-claude  # 其他客户端：仅安装依赖 + 配 Key，跳过注册
#   bash install.sh --no-skill   # Claude Code 用户但不要 skill（只要 MCP 能力，不询问）
# ============================================================================

set -e
cd "$(dirname "$0")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}"
echo "=========================================="
echo "  llm-vision 一键部署"
echo "=========================================="
echo -e "${NC}"

# ---------- 1. 检查 Node.js ----------
echo -e "\n${YELLOW}[1/5] 检查 Node.js 环境...${NC}"
if ! command -v node >/dev/null 2>&1; then
  echo -e "${RED}✗ 未检测到 Node.js，请先安装 Node.js ≥ 18${NC}"
  echo "  下载: https://nodejs.org/"
  exit 1
fi
NODE_VERSION=$(node -v)
echo -e "  ✓ Node.js ${NODE_VERSION}"

# ---------- 2. 安装依赖 ----------
echo -e "\n${YELLOW}[2/5] 安装 npm 依赖...${NC}"
if [ ! -d "node_modules" ]; then
  npm install --registry=https://registry.npmmirror.com 2>&1 | tail -3
  echo -e "  ✓ 依赖安装完成"
else
  echo -e "  ✓ node_modules 已存在，跳过安装"
fi

# ---------- 3. 配置 API Key ----------
echo -e "\n${YELLOW}[3/5] 配置阿里云百炼 API Key...${NC}"
# 先从已有 .env 读取
if [ -f ".env" ]; then
  # shellcheck disable=SC1091
  source .env 2>/dev/null || true
fi

if [ -z "$DASHSCOPE_API_KEY" ]; then
  echo -e "  未检测到 DASHSCOPE_API_KEY。"
  echo -e "  申请地址: https://bailian.console.aliyun.com/"
  read -r -p "  请输入你的 API Key (sk-xxx): " INPUT_KEY
  if [ -z "$INPUT_KEY" ]; then
    echo -e "${RED}✗ 未输入 Key，跳过配置。你可稍后手动编辑 .env 补上。${NC}"
  else
    # 写入 .env（保留现有 QWEN_VL_MODEL / DASHSCOPE_API_BASE 等配置）
    cp .env.example .env 2>/dev/null || touch .env
    # 用临时文件避免 sed 平台差异
    if grep -q "^DASHSCOPE_API_KEY=" .env 2>/dev/null; then
      # shellcheck disable=SC2016
      awk -v k="$INPUT_KEY" 'BEGIN{FS=OFS="="} /^DASHSCOPE_API_KEY=/{$2=k} {print}' .env > .env.tmp && mv .env.tmp .env
    else
      echo "DASHSCOPE_API_KEY=$INPUT_KEY" >> .env
    fi
    echo -e "  ✓ API Key 已写入 .env（该文件已被 .gitignore 忽略，不会上传）"
  fi
else
  echo -e "  ✓ 检测到已有 DASHSCOPE_API_KEY（.env 中）"
fi

# ---------- 4. 注册 Claude Code MCP ----------
SKIP_CLAUDE="false"
SKIP_SKILL="false"
for arg in "$@"; do
  [ "$arg" = "--no-claude" ] && SKIP_CLAUDE="true"
  [ "$arg" = "--no-skill" ] && SKIP_SKILL="true"
done

echo -e "\n${YELLOW}[4/6] 注册 Claude Code MCP...${NC}"
if [ "$SKIP_CLAUDE" = "true" ]; then
  echo -e "  - 已指定 --no-claude，跳过注册"
  echo -e "  - 其他客户端（Cursor/Codex/Cline）无需注册，到此即可使用 MCP 能力"
elif ! command -v claude >/dev/null 2>&1; then
  echo -e "${YELLOW}  - 未检测到 claude 命令，跳过 Claude Code 注册${NC}"
  echo -e "    使用 Claude Code 时手动注册: claude mcp add llm-vision -e DASHSCOPE_API_KEY=<你的Key> -- node $(pwd)/server.mjs"
else
  SERVER_PATH="$(pwd)/server.mjs"
  # 删除旧配置（如果有）
  claude mcp remove llm-vision >/dev/null 2>&1 || true
  if [ -f ".env" ] && [ -n "$INPUT_KEY" ]; then
    claude mcp add -s user llm-vision -e "DASHSCOPE_API_KEY=$INPUT_KEY" -- node "$SERVER_PATH"
  else
    claude mcp add -s user llm-vision -e "DASHSCOPE_API_KEY=$DASHSCOPE_API_KEY" -- node "$SERVER_PATH"
  fi
  echo -e "  ✓ 已注册 llm-vision 到 Claude Code 全局（用户级 ~/.claude.json）"
fi

# ---------- 5. （可选）安装 Skill ----------
echo -e "\n${YELLOW}[5/6] 安装 Skill（可选）...${NC}"
INSTALL_SKILL="false"
if [ "$SKIP_SKILL" = "true" ]; then
  echo -e "  - 已指定 --no-skill，跳过 Skill 安装"
  echo -e '  - 说明：Skill 是 Claude Code 专属的可选增强，装不装都能用 MCP 识图，只是少了"三角验证"流程'
elif [ "$SKIP_CLAUDE" = "true" ]; then
  echo -e "  - 已跳过（--no-claude 模式，Skill 仅适用于 Claude Code）"
elif [ ! -d "skills/image-recognition" ]; then
  echo -e "  - 未找到 skills/image-recognition 目录，跳过"
else
  read -r -p '  是否安装识图 Skill（Claude Code 识图自动走"三角验证"流程）？(y/N): ' INSTALL_SKILL
  case "$INSTALL_SKILL" in
    y|Y|yes|YES)
      INSTALL_SKILL="true"
      ;;
    *)
      INSTALL_SKILL="false"
      ;;
  esac
fi

if [ "$INSTALL_SKILL" = "true" ]; then
  SKILL_TARGET="$HOME/.claude/skills/image-recognition"
  mkdir -p "$HOME/.claude/skills"
  if [ -d "$SKILL_TARGET" ]; then
    echo -e "  - 已存在 ~/.claude/skills/image-recognition，跳过（如需更新先手动删除）"
  else
    cp -r "skills/image-recognition" "$SKILL_TARGET"
    echo -e "  ✓ 已安装 Skill 到 ~/.claude/skills/image-recognition"
    echo -e '  - 效果：Claude Code 遇到识图会自动走"三角验证"流程（描述→验证→实锤）'
  fi
fi

# ---------- 6. 完成 ----------
echo -e "\n${GREEN}[6/6] ✅ 部署完成！${NC}"
echo ""
echo "────────────────────────────────────────────"
echo "  Claude Code 用户:"
echo "    验证命令:  claude mcp list   （应显示 llm-vision Connected）"
echo "    然后重启 Claude Code，直接说："
echo "      「看 /path/to/photo.jpg 这个人是谁」"
echo ""
echo "  其他客户端（Cursor/Codex/Cline 等）:"
echo "    无需注册，直接在 MCP 配置里指向: $(pwd)/server.mjs"
echo "    加上环境变量 DASHSCOPE_API_KEY 即可"
echo ""
echo "  想省额度换模型: 编辑 .env 改 QWEN_VL_MODEL=qwen-vl-plus"
echo "────────────────────────────────────────────"
