# NewForge

Windows 风格的「右键 → 新建文件」，为 macOS 访达而生。A Finder "New File" context menu for macOS, with a user-extensible template system.

![platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue) ![lang](https://img.shields.io/badge/lang-Swift-orange) ![license](https://img.shields.io/badge/license-MIT-green)

## 功能

- **访达右键「新建文件」**：在任意文件夹空白处或桌面右键即可创建文件，自动定位、可选自动打开
- **20 个内置模板**，按用途分组：
  - 办公：Word 文档 / Excel 工作簿 / PowerPoint 演示
  - 数据分析：Jupyter Notebook（预置 pandas 起手 cell）/ SQL 查询 / CSV / JSON
  - 开发：Python 脚本 / Prompt 模板 / Markdown 笔记 / Shell 脚本 / Dockerfile / docker-compose / .gitignore
  - 前端：HTML / CSS / TypeScript / React 组件
  - 其他：纯文本 / .env
- **模板可扩展**：模板就是一个文件夹（`template.json` + 内容文件），丢进 `~/Library/Application Support/NewForge/Templates/<分组>/<模板名>/` 即生效；同 id 覆盖内置模板
- **变量插值**：文本模板支持 `{{filename}}` `{{date}}` `{{datetime}}` `{{user}}` `{{dirname}}` 等占位符
- **命名控制**：
  - 默认「智能」模式：脚本类弹命名框，文档类静默创建并自动编号
  - 右键时按 **Option** 强制弹命名框，按 **Control** 强制立即创建
  - 偏好设置里可全局切换为「总是询问 / 从不询问」
- **中英双语**菜单与界面

## 快速开始

```bash
make          # 仅需 Xcode Command Line Tools，无需完整 Xcode / XcodeGen
make run      # 构建并启动 NewForge.app
```

然后：**系统设置 → 隐私与安全性 → 扩展 → Finder 扩展**，勾选「NewForge」。在访达里右键即可看到「新建文件」。

> 未用开发者账号签名的构建，macOS 可能不在扩展列表中显示它。见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) 了解本地调试与签名细节。

其他常用命令：

```bash
make test     # 运行核心逻辑单元测试（渲染 / 命名 / 模板加载）
make install  # 拷贝到 /Applications
make clean
```

## 自定义模板

菜单栏图标 → 「打开模板文件夹」，或者手动进入：

```
~/Library/Application Support/NewForge/Templates/
└── analysis/                 # 分组目录（office/analysis/dev/web/misc，可新增）
    └── my-report/            # 一个模板一个文件夹
        ├── template.json     # 描述文件
        └── content.ipynb     # 实际内容（二进制或 UTF-8 文本）
```

最小 `template.json`：

```json
{
  "id": "analysis.my-report",
  "name": { "en": "My Report", "zh-Hans": "我的报告" },
  "fileExtension": "ipynb",
  "group": "analysis",
  "icon": "chart.bar",
  "defaultName": { "en": "report-{{date}}", "zh-Hans": "报告-{{date}}" },
  "prompt": true,
  "openAfterCreate": true,
  "kind": "text"
}
```

| 字段 | 说明 |
| --- | --- |
| `id` | 全局唯一；用户目录中的同 id 模板会覆盖内置模板 |
| `fileExtension` | 生成文件的扩展名 |
| `group` | 菜单分组：`office` / `analysis` / `dev` / `web` / `misc`，其他值进入「其他」 |
| `icon` | SF Symbols 名称（菜单图标） |
| `defaultName` | 默认文件名（不含扩展名），可含变量 |
| `prompt` | 智能模式下是否弹命名框 |
| `openAfterCreate` | 创建后是否用默认应用打开 |
| `kind` | `text`（渲染变量）或 `binary`（原样拷贝，如 docx/xlsx） |
| `contentFile` | 可选，内容文件名；默认 `content.<扩展名>` |

文本模板变量：`{{filename}}` `{{date}}` `{{time}}` `{{datetime}}` `{{year}}` `{{month}}` `{{day}}` `{{user}}` `{{dirname}}`。

## 项目结构

```
Sources/
  NewForgeKit/        核心库：模板加载、变量渲染、文件创建、命名面板
  NewForgeFinderExt/  Finder Sync 扩展（菜单构建 + 动作）
  NewForgeApp/        容器 App（菜单栏入口 + SwiftUI 偏好设置）
Resources/
  Templates/          20 个内置模板
  *.lproj/            中英本地化
Tests/                NewForgeKit 单元测试（make test）
Makefile              零依赖构建
project.yml           可选的 XcodeGen 配置
```

## License

MIT
