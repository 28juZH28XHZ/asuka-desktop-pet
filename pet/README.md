# 明日香桌宠（Asuka Desktop Pet）

一个独立的 Windows 桌面宠物：WPF 透明置顶窗口 + 精灵动画 + DeepSeek API 聊天/余额 + 可选的
DeepSeek Harness 权限请求桥。

素材来自 `delivery/asuka-v2_20261026/`（校服 / 战斗服两套 1536×2288 图集）。

## 环境要求

- Windows 10 / 11
- 自带 Windows PowerShell 5.1（系统自带，无需安装）
- 可选：Node.js 20+（聊天、余额查询需要用它做 TLS 请求）

## 快速开始

1. 把整个 `pet` 目录放到任意位置。
2. 生成素材（首次运行前）：

   ```bat
   python build-assets.py
   ```

   需要 Python + Pillow。会把 `delivery/asuka-v2_20261026/*/spritesheet.webp`
   转成 `pet/assets/school.png`、`pet/assets/work.png` 和 `pet/assets/app.ico`。

3. 双击 `AsukaPet.vbs` 启动（无黑窗口）。
4. 首次运行会在 `pet/` 下生成 `config.json`，可自行修改（见 `config.example.json`）。

## 功能

| 操作 | 效果 |
|---|---|
| 左键拖动 | 移动位置（记住） |
| 双击 | 聊天输入框 |
| 右键 | 换形态 / 聊天 / 查看 DSH 余额 / 看她一眼 / 置顶 / 大小 / 退出 |
| 托盘图标 | 显示/隐藏、退出 |

- 校服 / 战斗服两套形态，共用同一套图集布局（11 行、73 帧）。
- 聊天与余额使用 DeepSeek API，凭据复用 DeepSeek Harness 的登录态：
  - 聊天：`POST https://api.deepseek.com/chat/completions`，请求头 `x-dsh-auth-token`，模型 `deepseek-chat`
  - 余额：`GET https://platform.deepseek.com/api/v0/users/get_user_summary`
  - token 从 `%USERPROFILE%\.dsh\.credentials.yaml` 读取，只在本机使用。
- 气泡出现/消失时窗口只向上生长，人物屏幕位置固定不动。

## DSH 权限请求桥（可选）

`bridge/` 是一个 DeepSeek Harness 插件（bundle）。装上后，DSH 需要授权的工具操作会先出现在
桌宠气泡上（工具名 + 原因 + 允许/拒绝）。桌宠不在线时自动退回 DSH 自己的审批卡片。

安装（示例）：

```
1. 复制 bridge/ 到 %USERPROFILE%\.dsh\plugins\dsh-asuka-pet-bridge\
2. 在 %USERPROFILE%\.dsh\profiles\<profile>\package.json 的 dependencies 里加
   "dsh-asuka-pet-bridge": "link:<插件目录>"
   并在 dsh.profile.bundles 数组里加 "dsh-asuka-pet-bridge"
3. 在 profile 的 node_modules 下建一个指向插件目录的 Junction
4. 重启 DeepSeek Harness
```

也可以参考 `../tools/install-bridge.ps1`（会备份 profile）。

## 文件

```
pet/
├── AsukaPet.ps1        主程序（WPF / 动画 / 气泡 / 菜单）
├── AsukaPet.vbs        无窗口启动器
├── build-assets.py     从交付包生成 PNG 素材
├── config.example.json 配置示例
├── lib/net.js          DeepSeek API 调用（Node）
└── bridge/             DSH 权限桥插件
```

## 已知限制

- 透明区域点击会穿透到下面的窗口；右键菜单要按在人物或气泡上。
- 聊天历史保存在内存中，重启清空。
- 角色为 EVA 同人衍生，素材版权归原权利人；本仓库 LICENSE 为 All Rights Reserved，
  仅供个人学习使用，请勿公开再分发素材。
