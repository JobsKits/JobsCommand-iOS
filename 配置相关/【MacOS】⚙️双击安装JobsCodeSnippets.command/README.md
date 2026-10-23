# `【MacOS】⚙️双击安装JobsCodeSnippets.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、功能覆盖](#jobs-toc-heading-2)
- [二、参数与交互](#jobs-toc-heading-3)
- [三、依赖、备份与限制](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

检查当前用户 [**Xcode**](https://developer.apple.com/xcode) 的 CodeSnippets：缺失时安装，已有独立 [**Git**](https://git-scm.com/) 仓库时保留本地改动后拉取合并。入口为同目录 `【MacOS】⚙️双击安装JobsCodeSnippets.command`。

工程右键入口为“iOS / CocoaPods 辅助工具 → 安装 / 升级 JobsCodeSnippets”，由 `OS@Extension/MacOS@Extension/JobsIOSTools` 提供。菜单在 Terminal 调用随包的同字节脚本；传入工程只用于校验资格，安装目标始终是当前用户公共 CodeSnippets。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、功能覆盖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 安装目标为当前用户 Xcode 的 `UserData/CodeSnippets`；新安装按配置的 GitHub / Gitee 来源依次尝试，显示生效地址和目标。
- 已安装仓库沿当前分支明确配置的上游更新；在私有候选副本内保存暂存、未暂存和未跟踪文件，拉取并合并，再恢复原改动与原暂存部分。
- 分叉可形成待审阅合并结果，但不自动创建提交；冲突或失败保留原目录和候选副本，交由人工合并。
- 以目录锁避免并发更新；发布前再次比较真实目录，发生并发改动时停止；成功保留同级事务/原始备份，不自动重启 Xcode。

新安装来源按顺序为 [**GitHub**](https://github.com/JobsKits/JobsCodeSnippets) 的 `https://github.com/JobsKits/JobsCodeSnippets.git`、[**Gitee**](https://gitee.com/JobsGo/jobs-code-snippetsJobsCodeSnippets) 的 `https://gitee.com/JobsGo/jobs-code-snippetsJobsCodeSnippets.git`。升级保留已安装仓库的实际 remote 与分支上游，每次传输前输出来源：

```text
━━━━━━━━━━ 来源｜JobsCodeSnippets ━━━━━━━━━━
配置来源：https://github.com/JobsKits/JobsCodeSnippets.git
生效地址：https://github.com/JobsKits/JobsCodeSnippets.git（本地 Git 规则展开）
分支：main
目标：<当前用户 Library>/Developer/Xcode/UserData/CodeSnippets
```

生效地址仅表示本地 Git URL 规则展开；日志对 URL 凭据与查询参数脱敏。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、参数与交互 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 方式 | 行为 |
| --- | --- |
| 无参数 | 检查实际安装状态，再按交互安装或升级 |
| `--check` | 只读检查安装位置和 Git 状态，不创建日志或业务文件 |
| `--finder 工程路径` | 验证 iOS 工程后调用；不修改该工程或受其 Git 环境变量影响 |
| `--help` | 查看参数 |

```shell
zsh './【MacOS】⚙️双击安装JobsCodeSnippets.command' --check
```

正常模式先阅读自述并回车；安装/升级选择直接回车跳过，输入任意字符后回车执行。`Ctrl+C` 可取消。更新完成后自行重新打开 Xcode。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、依赖、备份与限制 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

依赖 macOS 系统 zsh、健康 Git 和所选远端网络；不安装额外依赖。已有目标必须是无未完成操作的独立 Git 仓库，拒绝未知非空目录、链接、外部 Git 元数据、游离分支或没有明确上游的状态。

同级 `.JobsCodeSnippets.*` 保存事务、原始副本、候选与失败现场；日志位于系统临时目录，名为 `JobsCodeSnippets-时间戳-进程.随机后缀.log`，以终端显示的实际路径为准。原始备份需要先检查后手工归档，不把备份清理当作正常升级步骤。

本入口不修改全局 Git 缓冲参数，不自动 commit / push，不结束 Xcode 进程。更新后应对照代码片段列表和仓库状态，分叉合并结果须人工审阅后提交。

隔离验证见 [tests 说明](./tests/README.md)，使用临时用户目录和本地远端，不联网、不更改本机安装目录。真实 Finder 部署与网络更新需单独验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
