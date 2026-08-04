---
name: image-recognition
description: Use this skill whenever the user shares an image, asks about an image ("这是什么"、"他是谁"、"图片里有什么"、"看图"), or mentions an image file path. The current model has NO native vision — images arrive as "Unsupported Image" — so you MUST use the llm-vision MCP's describe_image tool to actually see it. For identifying a person or thing, ALWAYS run the three-step verification: ① describe_image to describe → ② WebSearch to cross-check distinctive features → ③ reverse image search (Baidu via Playwright) to confirm. Trigger even on casual phrasing like "看看这张图"、"帮我认一下这个人", or when the user pastes an image.
---

# 识图三角验证

> 当前模型 **没有原生视觉**（图片会显示 Unsupported Image）。所有识图必须通过 **llm-vision MCP** 的 `describe_image` 工具「借眼」。

## 核心原理

```
无视觉模型 → describe_image(图片路径) → 通义千问VL 识图 → 文字描述 → 模型拿文字推理
```

- 视觉后端：**通义千问 VL**（模型名由 `QWEN_VL_MODEL` 环境变量控制，默认 qwen-vl-max）
- 限制：VL 是通用视觉模型，**不是专业人脸识别**，认明星/公众人物靠特征联想，有幻觉风险；低分辨率、侧脸、逆光图可能误判 → 所以**重要识别必须做多重验证**，不能只看一眼下结论。

## 三角验证流程（认人/认物时必走）

### 第 1 步：`describe_image` 描述画面

```json
describe_image(image_path, prompt="请详细描述这张图片的内容…")
```

- 图片路径用**绝对路径**（如 `/path/to/image.png` 或 `C:/photo/pic.jpg`）
- 第一轮只让模型「描述画面内容」，拿到客观信息（人/物/场景/穿着/氛围）

### 第 2 步：定向「猜身份」+ WebSearch 交叉验证

- 若用户问"他是谁"，二次调用 `describe_image`，prompt 聚焦**面部特征**（脸型、五官、发型、年龄、气质），并要求给出身份猜测
- 拿到猜测后，用 **WebSearch** 搜该人物的标志性特征（如"杨洋 白衬衫 西装 领带"），确认特征吻合
- 注意：这一步只是**间接佐证**，不能单独定案（视觉模型可能幻觉，搜索可能撞对）

### 第 3 步：反向图片搜索实锤（最强证据）

用 **Playwright** 打开百度识图，把原图传上去比对全网图库：

1. 若浏览器被占用（报 "Browser is already in use"），直接改用 `browser_run_code_unsafe` 在现有会话操作；仍失败则提示用户手动打开 https://graph.baidu.com/
2. `browser_run_code_unsafe`：设置桌面视口 + 导航到 `https://graph.baidu.com/pcpage/index?tpl_from=pc`（直接 `navigate` 可能被重定向到移动版首页，没有识图入口）
3. 页面存在 `<input type="file">`，用 `setInputFiles('<图片绝对路径>')` 上传（Windows 路径用双反斜杠 `D:\\photo.png`）
4. 等待跳转到搜索结果页
5. `browser_snapshot` 读结果：页面上会有「图中可能是 XXX」AI 判定 + **图片来源**（如微博话题）+ 相似图片

## 汇报模板

用表格给用户分级证据：

| 证据 | 权重 |
|---|---|
| 反向识图 AI 判定「图中可能是 XXX」 | 最强（全网图库比对） |
| 图片来源/出处（微博话题等） | 强（可定位来源） |
| 着装/面部特征吻合 | 辅助 |

## 注意事项

- **浏览器占用**：Playwright 常报 "Browser is already in use"，这是另一个实例占用了浏览器，换用 `browser_run_code_unsafe` 操作即可，不必重启
- **不要瞎猜**：无把握时明确说"无法确认"，引导用户提供线索（来源、领域），再继续查
- **次要识别**（"图里有什么东西"）：第 1 步就够，不用大动干戈走全套三角验证
- **Key 安全**：`DASHSCOPE_API_KEY` 通过环境变量注入，勿写入代码或提交到仓库
