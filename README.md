# llm-vision

给没有视觉能力的大语言模型（如 DeepSeek）提供一个「借眼」工具：识别本地图片，返回文字描述，模型根据返回文字信息进行推理。

## 目录

1. [这个项目能做什么](#1-这个项目能做什么)
2. [项目组成：MCP + Skill](#2-项目组成mcp--skill)
3. [适用范围](#3-适用范围)
4. [项目结构](#4-项目结构)
5. [安装位置](#5-安装位置)
6. [快速开始](#6-快速开始)
7. [手动安装](#7-手动安装)
8. [使用方法](#8-使用方法)
9. [配置选项](#9-配置选项)
10. [安全说明](#10-安全说明)
11. [更新记录](#11-更新记录)
12. [许可证](#12-许可证)

## 1. 这个项目能做什么

给纯文本模型补上"眼睛"，让它能处理图片：

- 描述画面：图片里有什么、什么场景
- 看图认人：这张图里的人是谁
- 提取文字：图片里的文字内容（OCR）
- 定向问答：只回答你问的细节，如"他穿的什么颜色"

纯文本模型收到图片只会显示 "Unsupported Image"。本工具把图片编码后发给通义千问 VL 视觉模型，拿回文字描述，模型就能基于文字回答你的问题。

## 2. 项目组成：MCP + Skill

本项目由**两部分**组成，能力互补：

| 部分 | 作用 | 谁在用 |
|---|---|---|
| **MCP 服务器** | 提供识图能力（`describe_image` 工具） | 所有客户端 |
| **Skill** | 规范模型识图行为，防止瞎猜 | 针对 Claude Code |

> 一句话：**MCP = 眼睛（能不能看），Skill = 纪律（怎么看得好）。** 缺 MCP 看不了图，缺 Skill 会"可能看一眼就乱说"。

### 2.1 Skill 规范了什么

Skill（`image-recognition`）给模型立了**三条行为规则**：

| # | 规则 | 解决什么问题 |
|---|---|---|
| 1 | **必须看图再回答**：遇到图片问题先调 `describe_image`，禁止说"我看不到"或凭空猜 | 模型装瞎、跳过工具 |
| 2 | **先描述后判断**：先客观说出画面内容，再回答具体问题 | 模型没看完就下结论 |
| 3 | **认不出就明说**：看不清/不确定时明确说"无法确认"，不编造答案 | 模型自信地答错 |

**外加一条升级规则**（用于"这人/这物具体是谁"这类需要准确结论的场景）：

| # | 升级规则 | 说明 |
|---|---|---|
| 4 | **三角验证**：识图 → 搜索交叉 → 反向识图实锤 | 把"猜"升级成"有来源、可追溯"的结论 |

**具体对比：**

| 没有 Skill | 有 Skill |
|---|---|
| 可能不调工具，直接说"看不到图" | 一定先调 `describe_image` |
| 看一遍就自信回答 | 先描述画面再回答 |
| 认错人还言之凿凿 | 认不出就说"无法确认" |
| 结果无法追溯 | 认人/认物时有证据链（反向识图 + 来源） |

## 3. 适用范围

本项目是**标准 MCP 服务器**，任何支持 MCP 协议的客户端都能接入：Claude Code、Cursor、Windsurf、Cline、Codex 等。

Skill 部分是 **Claude Code 专属**。其他客户端没有 Skill 机制，可参考[第 2 节](#2-项目组成mcp--skill)的行为规则，用 AGENTS.md 或其他相对应的项目指令文件实现。

## 4. 项目结构

```
llm-vision/
├── server.mjs                    # 核心：MCP 服务器（describe_image 工具）
├── skills/
│   └── image-recognition/        # 可选 Skill（行为规范，仅 Claude Code）
│       └── SKILL.md
├── package.json                  # 依赖（@modelcontextprotocol/sdk、zod）
├── package-lock.json             # 依赖锁定（勿手改）
├── install.sh                    # 一键部署
├── .env.example                  # API Key 配置模板
├── .gitignore                    # 忽略 node_modules / .env
└── README.md                     # 本文件
```

| 文件 | 作用 |
|---|---|
| `server.mjs` | 唯一必须运行的文件，就是 MCP 服务器本身 |
| `skills/image-recognition/` | 可选 Skill 源文件，装到 `~/.claude/skills/` 才生效 |
| `install.sh` | 自动装依赖 + 配 Key + 注册 MCP + 可选装 Skill |
| `.env.example` | Key 填法模板，复制为 `.env` 使用 |

## 5. 安装位置

### 5.1 MCP → 注册到 `~/.claude.json`

MCP 通过注册挂到客户端，配置写入 `~/.claude.json`（Windows：`C:\Users\<用户名>\.claude.json`）：

```json
"mcpServers": {
  "llm-vision": {
    "type": "stdio",
    "command": "node",
    "args": ["<项目绝对路径>/server.mjs"],
    "env": { "DASHSCOPE_API_KEY": "sk-xxx" }
  }
}
```

上面这段 JSON 就是 `~/.claude.json` 里 `mcpServers` 字段的内容。`claude mcp add` 命令的本质就是帮你在该文件里写入这段（二选一：用命令，或手改文件）。

**命令怎么读**（`user` 是作用域，`llm-vision` 才是服务名）：

```
claude mcp add -s user llm-vision -e DASHSCOPE_API_KEY=xxx -- node server.mjs
              └┬──┘└──┬───┘└──┬─────┘
           作用域选项 值     服务名    启动命令
```

**scope 取值**：
- `-s local`（默认，不带 `-s` 等同）→ **项目级**，只在本项目可用
- `-s user`（install.sh 用这个）→ **用户级全局**，写 `~/.claude.json`，所有项目可用
- `-s project` → 项目级（通过项目内配置）

### 5.2 Skill → 复制到 skills 目录

Skill 要**复制到 Claude Code 的 skills 目录**才生效：

```
~/.claude/skills/
└── image-recognition/
    └── SKILL.md
```

> **推荐直接用全局**（`~/.claude/skills/`，install.sh 选 y 时自动装到这儿）：一份搞定，所有项目都能用，省心。
>
> 只有少数情况才装到项目级（`<项目>/.claude/skills/`）：比如某个项目想用**定制版** Skill，其他项目不用。日常都选全局。
>
> 仓库里 `skills/image-recognition/` 是**源文件**，装到全局/项目都是**复制**一份过去，仓库那份留着以便以后更新重装。

## 6. 快速开始

需要 Node.js ≥ 18，以及阿里云百炼 API Key（[申请地址](https://bailian.console.aliyun.com/)）。

```bash
git clone <仓库地址>
cd llm-vision

# Claude Code 用户：装依赖 + 配 Key + 注册 MCP + 询问是否装 Skill
bash install.sh

# 其他客户端（Cursor/Codex/Cline）：只装依赖 + 配 Key
bash install.sh --no-claude
```

`install.sh` 会询问是否安装 Skill：选 `y` 安装，选 `n` 或回车跳过。也可用 `--no-skill` 直接跳过。

## 7. 手动安装

> 前提：以下命令**在项目目录内执行**。先拿到源码并进入目录：
> ```bash
> git clone <仓库地址>
> cd llm-vision
> ```

### 7.1 Claude Code 用户

```bash
npm install
cp .env.example .env        # 编辑 .env 填入 DASHSCOPE_API_KEY
claude mcp add -s user llm-vision -e DASHSCOPE_API_KEY=<你的Key> -- node <项目绝对路径>/server.mjs
claude mcp list             # 应显示 llm-vision Connected
```

装 Skill（可选）：

```bash
cp -r skills/image-recognition ~/.claude/skills/
```

> **为什么仓库里已有 `skills/image-recognition/` 还要复制？**
> 仓库里的是**源文件**（跟随版本分发）。但 Claude Code 的 Skill **只从 `~/.claude/skills/` 加载**，不会自动读你仓库里的目录。`cp` 就是把源文件"安装"到生效位置，`install.sh` 选 y 时自动做这一步。

### 7.2 其他客户端（Cursor / Codex / Cline 等）

装依赖 + 配 Key，然后在**各自的 MCP 配置文件**里加下面这段（文件位置见下表）：

```json
{
  "mcpServers": {
    "llm-vision": {
      "type": "stdio",
      "command": "node",
      "args": ["<项目绝对路径>/server.mjs"],
      "env": { "DASHSCOPE_API_KEY": "<你的Key>" }
    }
  }
}
```

| 客户端 | 配置文件位置 |
|---|---|
| Cursor | `.cursor/mcp.json` 或 UI 设置 |
| Windsurf | UI 设置（Settings → MCP） |
| Cline | 设置里手动添加 |
| Continue | `~/.continue/config.json` |
| Codex | `~/.codex/config.toml` 或项目 `codex.json` |

> 所有客户端填的都是**同一个结构**（type/command/args/env），只是存放的文件不同。

## 8. 使用方法

配置完成后重启 Claude Code，直接说：

- 「看 /path/to/photo.jpg 这个人是谁」
- 「帮我描述这张图：/path/to/photo.jpg」
- 「提取这张图里的文字」

其他 MCP 客户端可按标准协议直接调用 `describe_image(image_path, prompt?)`。

## 9. 配置选项

| 变量 | 说明 | 默认值 |
|---|---|---|
| `DASHSCOPE_API_KEY` | 阿里云百炼 API Key（必填） | 无 |
| `QWEN_VL_MODEL` | 视觉模型名 | `qwen-vl-max` |
| `DASHSCOPE_API_BASE` | API 地址 | `https://dashscope.aliyuncs.com/compatible-mode/v1` |

省钱建议：日常识图用 `qwen-vl-plus`（免费额度常用款），复杂图文或 OCR 用 `qwen-vl-max`。

## 10. 安全说明

本项目不含任何真实 API Key，Key 通过环境变量注入（模板见 `.env.example`）。`.env` 和 `node_modules` 已被 `.gitignore` 忽略，不会上传。部署时不要把你的 Key 写进代码或提交到仓库。

## 11. 更新记录

| 版本 | 日期 | 内容 |
|---|---|---|
| **v1.0.0** | 2026-08-04 | 首个正式版：MCP 识图服务器 + 行为规范 Skill + 一键部署 |

## 12. 许可证

MIT
