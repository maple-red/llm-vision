# llm-vision

给没有视觉能力的大语言模型（如 DeepSeek）提供一个「借眼」工具：识别本地图片，返回文字描述，模型根据返回文字信息进行推理。

## 目录

1. [这个项目能做什么](#1-这个项目能做什么)
2. [项目定位](#2-项目定位)
3. [项目自带的 Skill](#3-项目自带的-skillimage-recognition)
4. [适用范围](#4-适用范围)
5. [项目结构](#5-项目结构)
6. [安装位置](#6-安装位置)
7. [快速开始](#7-快速开始)
8. [手动安装](#8-手动安装)
9. [使用方法](#9-使用方法)
10. [配置选项](#10-配置选项)
11. [配合识图验证流程使用](#11-配合识图验证流程使用)
12. [安全说明](#12-安全说明)
13. [更新记录](#13-更新记录)
14. [许可证](#14-许可证)

## 1. 这个项目能做什么

- 看图认人：这张图里的人是谁，返回身份猜测和特征描述
- 描述画面：图片里有什么、什么场景，返回中文描述
- 提取文字：图片里的文字内容（OCR）
- 定向提问：问你想关注的细节，比如"这人穿的什么颜色衣服"

纯文本模型收到图片只能显示 "Unsupported Image"。本工具把图片编码后发给通义千问 VL 视觉模型，拿回文字描述，文本模型就能基于文字继续回答你的问题。

## 2. 项目定位

本项目是一个 **MCP 服务器**，提供 `describe_image` 工具。

| 概念 | 作用 | 说明 |
|---|---|---|
| MCP（本项目） | 提供识图能力 | 任何支持 MCP 的客户端都能调用 |
| Skill | 提供识图流程 | Claude Code 专属机制，可选增强 |

MCP 回答"能不能看"，Skill 回答"怎么看得好"。本项目主要为 MCP，也配有 Claude 的 Skill（可选）。配套的识图验证流程见下文[配合识图验证流程使用](#11-配合识图验证流程使用)。

## 3. 项目自带的 Skill（image-recognition）

本项目**除了 MCP 服务器，还附带一个 Skill**：`image-recognition`（识图三角验证）。

### 3.1 这个 Skill 是什么

一个给 **Claude Code** 用的技能包。它不提供新工具，而是**教模型怎么用好 `describe_image`**——防止模型"看一眼就下结论"（比如认错人名还言之凿凿）。

### 3.2 它解决了什么问题

| 没有 Skill | 有 Skill |
|---|---|
| 模型调一次识图就下结论 | 强制走完整验证流程 |
| 认错人还自信回答 | 证据不足时主动说"无法确认" |
| 识别结果无法追溯 | 每步都有来源和佐证 |

### 3.3 它做了什么（识图三角验证）

Skill 告诉模型，遇到"这是谁/这图哪来的"时**必须**走三步：

1. **描述**：先 `describe_image` 描述画面内容
2. **猜身份 + 验证**：聚焦特征再问一次，拿猜测后搜索交叉验证
3. **实锤**：用反向识图（百度识图等）找原始来源

### 3.4 怎么安装

两种方式，装到 `~/.claude/skills/`：

```bash
# 方式一：跑部署脚本时选 y（自动复制）
bash install.sh

# 方式二：手动复制
cp -r skills/image-recognition ~/.claude/skills/
```

装完重启 Claude Code，发图时模型会自动按三角验证流程走。

> Skill 是 Claude Code 专属。其他客户端（Cursor/Codex）没有这套机制，可参考[第 11 节](#11-配合识图验证流程使用)的流程手动实现，或用 AGENTS.md 写入。

## 4. 适用范围

本项目是标准 MCP 服务器，**任何支持 MCP 协议的客户端都能接入**：Claude Code、Cursor、Windsurf、Cline，以及 OpenAI Codex 等。

Skill 部分是 Claude Code 专属机制；其他客户端可以用 AGENTS.md 或项目指令文件实现同样的验证流程。

## 5. 项目结构

```
llm-vision/
├── server.mjs        # 核心：MCP 服务器本体
│                     #   - 定义 describe_image 工具（读图 → base64 → 调通义千问 VL）
│                     #   - 通过 stdio 协议与客户端通信
├── skills/
│   └── image-recognition/   # （可选）识图三角验证 Skill，仅 Claude Code 用户需要
│       └── SKILL.md         # 安装到 ~/.claude/skills/ 后生效
├── package.json      # 依赖配置：@modelcontextprotocol/sdk、zod
├── package-lock.json # 依赖锁定文件（npm install 自动生成，勿手改）
├── install.sh        # 一键部署（针对 Claude Code，其他客户端用 --no-claude）
├── .env.example      # 环境变量模板：复制为 .env 后填你的 API Key
├── .gitignore        # 忽略 node_modules / .env，防止 Key 和依赖被提交
└── README.md         # 本说明文件
```

| 文件 | 作用 | 谁需要 |
|---|---|---|
| `server.mjs` | MCP 服务器本体，唯一必须运行的文件 | 所有用户 |
| `skills/image-recognition/` | 识图三角验证 Skill（可选增强） | 仅 Claude Code 用户 |
| `package.json` | 告诉 npm 要装哪些包、怎么启动 | 所有用户 |
| `install.sh` | 一键部署：装依赖 + 配 Key + 注册 | Claude Code 用户 |
| `.env.example` | Key 的填法模板，填好的 `.env` 不上传 | 所有用户 |
| `.gitignore` | 安全保险：确保依赖和密钥不进 git | 所有用户 |

## 6. 安装位置

两个组件安装到**不同的地方**，下面是 `install.sh` 默认装到的具体位置。

### 5.1 MCP（llm-vision）→ 默认注册到 `~/.claude.json`

MCP 通过**注册**挂到客户端，源码留在项目里，但**配置写入客户端的配置文件**。

**默认安装路径**（Claude Code，`install.sh` 用 `-s user` 全局注册）：

```
~/.claude.json
└── mcpServers
    └── llm-vision
        ├── command: node
        ├── args: ["<项目绝对路径>/server.mjs"]
        └── env:  { "DASHSCOPE_API_KEY": "sk-xxx" }
```

> Windows 下 `~` = `C:\Users\<你的用户名>`，即 `C:\Users\<用户名>\.claude.json`

**注意 scope 区别**：
- 不带 `-s` 的 `claude mcp add` → **local（项目级）**，写进当前项目的 `.claude.json`，只在本项目可用
- 带 `-s user`（`install.sh` 用的）→ **用户级全局** `~/.claude.json`，所有项目可用

其他客户端（Cursor / Cline 等）在各自 MCP 配置文件里填同样的 `mcpServers` 结构。

### 5.2 Skill（image-recognition）→ 默认复制到 `~/.claude/skills/`

Skill 需要**复制到 Claude Code 的 skills 目录**才会被识别。

**默认安装路径**（`install.sh` 选 y 时）：

```
~/.claude/skills/
└── image-recognition/
    └── SKILL.md
```

> Windows 下即 `C:\Users\<你的用户名>\.claude\skills\image-recognition\SKILL.md`

| 位置 | 生效范围 |
|---|---|
| `~/.claude/skills/` | **全局**（所有项目可用）← install.sh 默认装这里 |
| `<项目>/.claude/skills/` | **仅该项目**可用 |

> 本项目 `skills/image-recognition/` 是**源文件**（随仓库分发）；`install.sh` 把它**复制**到 `~/.claude/skills/` 才真正生效（选 y）。

## 7. 快速开始

需要 Node.js ≥ 18，以及阿里云百炼 API Key（[申请地址](https://bailian.console.aliyun.com/)）。

```bash
# 1. 克隆仓库
git clone <仓库地址>
cd llm-vision

# 2a. Claude Code 用户：完整部署（装依赖 + 配 Key + 注册 MCP + 可选装 Skill）
bash install.sh

# 2b. 其他客户端（Cursor / Codex / Cline）：只装依赖 + 配 Key，跳过注册
bash install.sh --no-claude
```

> 说明：
> - `install.sh` 默认针对 **Claude Code**（注册 MCP，并**询问**是否安装 Skill）
> - 想要 Skill 选 y，不想要选 n 或回车；也可直接 `bash install.sh --no-skill` 跳过
> - 非 Claude Code 用户，用 `bash install.sh --no-claude`（只安装 + 配 Key）
> - Skill 是 **可选** 增强，不装也能用 MCP 识图，只是少了"三角验证"流程

## 8. 手动安装

### 8.1 Claude Code 用户

```bash
# 1. 安装依赖
npm install

# 2. 配置 Key（复制模板并编辑）
cp .env.example .env
# 编辑 .env，填入 DASHSCOPE_API_KEY

# 3. 注册到 Claude Code（全局）
claude mcp add llm-vision -e DASHSCOPE_API_KEY=<你的Key> -- node <项目绝对路径>/server.mjs

# 4. 验证
claude mcp list   # 应显示 llm-vision Connected
```

### 8.2 其他客户端（Cursor / Codex / Cline 等）

不依赖 Claude Code，只需安装依赖 + 配 Key，然后在**各自客户端的 MCP 配置**里指向服务器：

```bash
# 1. 安装依赖
npm install

# 2. 配置 Key（复制模板并编辑）
cp .env.example .env
# 编辑 .env，填入 DASHSCOPE_API_KEY
```

在**各自的 MCP 配置文件**里按标准协议注册（地址指向 `server.mjs`）：

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

**这段 JSON 配在哪个文件？** 各客户端不同，本质都是把上面的 `mcpServers` 结构填到各自的配置文件里：

| 客户端 | 配置文件位置 | 说明 |
|---|---|---|
| **Claude Code**（手动配） | 用户级 `~/.claude.json` 或 项目级 `.mcp.json` | 或直接用命令 `claude mcp add`，不用手改文件 |
| **Cursor** | 设置界面 Settings → MCP，或项目 `.cursor/mcp.json` | 在 UI 里点 Add 填上述字段，或直接编辑 `.cursor/mcp.json` |
| **Windsurf** | 设置 Settings → MCP Servers | 图形界面添加 |
| **Cline** | 设置 Cline → MCP Servers → 手动添加 | 填上述 JSON 字段 |
| **Continue** | `~/.continue/config.json` 的 `mcpServers` | 编辑配置文件加同样结构 |
| **Codex** | `~/.codex/config.toml`（或项目 `codex.json`） | 用 TOML/JSON 加 mcpServers 配置 |

> 提示：所有客户端填的都是**同一个标准结构**（type/command/args/env），只是存放的**文件不同**。搜你客户端的"MCP 配置"即可定位。

## 9. 使用方法

配置完成后重启 Claude Code，直接自然语言说：

- 「看 /path/to/photo.jpg 这个人是谁」
- 「帮我描述这张图：/path/to/photo.jpg」
- 「提取这张图里的文字」

其他 MCP 客户端也可按标准协议直接调用 `describe_image(image_path, prompt?)`。

## 10. 配置选项

| 变量 | 说明 | 默认值 |
|---|---|---|
| `DASHSCOPE_API_KEY` | 阿里云百炼 API Key（必填） | 无 |
| `QWEN_VL_MODEL` | 视觉模型名 | `qwen-vl-max` |
| `DASHSCOPE_API_BASE` | API 地址（OpenAI 兼容模式） | `https://dashscope.aliyuncs.com/compatible-mode/v1` |

省钱建议：日常识图用 `qwen-vl-plus`（免费额度常用款），复杂图文或 OCR 再用 `qwen-vl-max`。阿里云百炼一个 Key 通吃所有模型，有额度即可。

## 11. 配合识图验证流程使用

只调用一次识图，模型可能"看一眼就下结论"（比如猜错人名）。建议配合以下验证流程，把认人从"猜"升级为"实锤"：

1. 调用 `describe_image` 描述画面
2. 聚焦特征再次调用，得到身份猜测
3. 用搜索交叉验证标志性特征
4. 反向识图（百度识图等）搜索实锤

在 Claude Code 中，这套流程可封装为 Skill；其他客户端可写入 AGENTS.md 或项目指令。

## 12. 安全说明

本项目不含任何真实 API Key，Key 通过环境变量注入（模板见 `.env.example`）。`.env` 和 `node_modules` 已被 `.gitignore` 忽略，不会上传。部署时不要把你的 Key 写进代码或提交到仓库。

## 13. 更新记录

| 版本 | 日期 | 内容 |
|---|---|---|
| **v1.0.0** | 2026-08-04 | 首个正式版：MCP 识图服务器 + describe_image 工具 + 一键部署 + 可选 Skill |

## 14. 许可证

MIT
