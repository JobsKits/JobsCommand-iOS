# CodeX+UnderstandAnything.command

这个脚本用于在 **需要时** 为 Xcode/iOS 工程启动 **Codex + Understand Anything**，生成代码图谱。它不建议挂到 `pod install`，因为 `/understand` 依赖 AI/Codex 算力，频繁执行会消耗额度并拖慢安装流程。

## 文件结构

```text
CodeX+UnderstandAnything.command/
├── CodeX+UnderstandAnything.command
└── README.md
```

## 工程根目录查找规则

脚本会按以下顺序查找 Xcode/iOS 工程：

1. 脚本当前目录
2. 脚本当前目录向上一级
3. 如果前两者都没有找到，则循环要求你输入或拖入正确路径

命中标准：当前目录下能找到：

- `*.xcworkspace`
- `*.xcodeproj`

找到后，脚本会打印完整的 `.xcworkspace` / `.xcodeproj` 名称和绝对路径，并等待你回车确认。

## Understand Anything 健康体检

脚本会检查：

1. `codex` 命令是否存在
2. `~/.understand-anything/repo` 是否存在
3. `~/.understand-anything/repo/install.sh` 是否存在

如果没有安装 Understand Anything，脚本会执行：

```bash
curl -fsSL https://raw.githubusercontent.com/Lum1104/Understand-Anything/main/install.sh | bash -s codex
```

如果已经安装，脚本会提示：

- 直接回车：跳过升级
- 输入任意字符后回车：执行升级

升级命令为：

```bash
cd ~/.understand-anything/repo
bash ./install.sh --update
```

## 使用方式

双击或终端执行：

```bash
./CodeX+UnderstandAnything.command
```

脚本完成体检后，会打印具体操作日志：

```bash
cd '你的工程根目录'
codex
```

进入 Codex 后输入：

```text
/understand --language zh
```

图谱生成完成后输入：

```text
/understand-dashboard
```

图谱通常生成在：

```text
你的工程根目录/.understand-anything/knowledge-graph.json
```

## 大项目建议

如果项目很大，不要一开始全量跑，可以先限定目录：

```text
/understand Sources
/understand App
/understand Modules/Login
```

## 注意事项

- `/understand` 会消耗 Codex/AI 额度。
- 安装或升级 Understand Anything 后，需要退出并重新进入 Codex，让 Codex 重新加载能力。
- 当前脚本默认不自动执行 `/understand`，而是启动 Codex 后由你手动输入命令，这样更稳，不会在额度不足或登录异常时卡死。
