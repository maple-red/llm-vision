/**
 * llm-vision — 通义千问 VL 视觉识别 MCP 服务器
 *
 * 作用：给没有视觉能力的文本模型（如 deepseek-v4-flash、Claude 等纯文本模型）
 *      提供一个「借眼」工具 —— 通过 describe_image 把本地图片交给
 *      qwen-vl 视觉模型识别，返回文字描述，调用方拿到文字后再自行推理决策。
 *
 * 环境变量：
 *   DASHSCOPE_API_KEY  阿里云百炼 API Key（必填，一个 key 可用所有模型，有额度即可）
 *   QWEN_VL_MODEL      视觉模型名，默认 qwen-vl-max（免费可换 qwen-vl-plus）
 *   DASHSCOPE_API_BASE API 地址，默认 OpenAI 兼容模式
 */
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import fs from "node:fs";
import path from "node:path";

const API_BASE = process.env.DASHSCOPE_API_BASE || "https://dashscope.aliyuncs.com/compatible-mode/v1";
const MODEL = process.env.QWEN_VL_MODEL || "qwen-vl-max";

const MIME_BY_EXT = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".bmp": "image/bmp",
  ".tif": "image/tiff",
  ".tiff": "image/tiff",
  ".heic": "image/heic",
  ".svg": "image/svg+xml",
};

/** 把本地图片读成 base64 data URI */
function toDataUri(filePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`文件不存在: ${filePath}`);
  }
  const ext = path.extname(filePath).toLowerCase();
  const mime = MIME_BY_EXT[ext] || "image/png";
  const b64 = fs.readFileSync(filePath).toString("base64");
  return `data:${mime};base64,${b64}`;
}

/** 调用通义千问 VL（OpenAI 兼容接口） */
async function askQwenVL(imageUri, prompt) {
  const apiKey = process.env.DASHSCOPE_API_KEY;
  if (!apiKey) {
    throw new Error(
      "未配置 DASHSCOPE_API_KEY 环境变量。请到阿里云百炼控制台申请 Key：" +
      "https://bailian.console.aliyun.com/ 然后在你的 MCP 客户端配置（或系统环境变量）里设置。"
    );
  }
  const res = await fetch(`${API_BASE}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: MODEL,
      messages: [
        {
          role: "user",
          content: [
            { type: "image_url", image_url: { url: imageUri } },
            { type: "text", text: prompt },
          ],
        },
      ],
    }),
  });
  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`通义千问 VL API 调用失败 (${res.status}): ${errText.slice(0, 500)}`);
  }
  const data = await res.json();
  return data.choices?.[0]?.message?.content ?? "(模型未返回内容)";
}

const server = new McpServer({ name: "llm-vision", version: "1.0.0" });

server.tool(
  "describe_image",
  "识别一张本地图片并返回文字描述。当前模型没有视觉能力时，用这个工具把图片交给通义千问 VL 视觉模型识别，拿到文字后再自己推理。",
  {
    image_path: z.string().describe("图片的绝对路径，如 /path/to/image.png 或 C:/photo/pic.jpg"),
    prompt: z
      .string()
      .optional()
      .describe("可选：想让视觉模型回答的具体问题或关注的细节。默认是详细描述图片内容"),
  },
  async ({ image_path, prompt }) => {
    const q =
      prompt ||
      "请用中文详细描述这张图片的内容。如果图中有人物，请描述人物的外貌、穿着、表情、体型等特征，并尽量判断图中人物可能是什么身份或名字。";
    try {
      const uri = toDataUri(image_path);
      const text = await askQwenVL(uri, q);
      return { content: [{ type: "text", text }] };
    } catch (err) {
      return { content: [{ type: "text", text: `识别失败：${err.message}` }], isError: true };
    }
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
