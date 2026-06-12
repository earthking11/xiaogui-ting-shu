# MiMo TTS 事实摘录

校验日期：2026-06-10  
来源：

- https://platform.xiaomimimo.com/docs/zh-CN/usage-guide/speech-synthesis-v2.5
- https://platform.xiaomimimo.com/docs/zh-CN/api/chat/openai-api
- https://platform.xiaomimimo.com/docs/zh-CN/quick-start/error-codes

## 已确认事实

1. MiMo OpenAI 兼容接口请求地址是：

   `https://api.xiaomimimo.com/v1/chat/completions`

2. 认证方式官方支持两种：

   - `api-key: <MIMO_API_KEY>`
   - `Authorization: Bearer <MIMO_API_KEY>`

   本项目统一使用 `api-key`。

3. 预置音色模式使用的模型是：

   `mimo-v2.5-tts`

4. TTS 目标文本必须放在 `role: assistant` 的消息里。

5. 风格控制类自然语言提示可以放在 `role: user` 的消息里。

6. 成功响应中的音频数据位于：

   `choices[0].message.audio.data`

7. 文档列出的常见错误码包括：

   - `401` 认证失败
   - `402` 余额不足
   - `403` 拒绝访问 / 地区不支持
   - `421` 内容拦截
   - `429` 请求过频
   - `500` 服务器失败
   - `503` 服务器负载过高

## 本项目采用的设计决策

- 第一版只接预置音色，不接 voicedesign / voiceclone。
- 第一版固定 `stream: false`，优先保证稳定返回完整 wav。
- 第一版把 `baseUrl` 和 `model` 固定在代码里，不暴露给普通用户编辑。
