# <span id="前言">[**Xcode**](https://developer.apple.com/xcode) 当前工程 Pod Install</span>

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、功能与作用范围](#jobs-toc-heading-2)
- [二、Xcode 配置与日常使用](#jobs-toc-heading-3)
- [三、终端参数与只读检查](#jobs-toc-heading-4)
- [四、日志与失败处理](#jobs-toc-heading-5)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 前言</span><!-- jobs-toc:heading-end -->

一个共享的 Xcode Behavior 为当前打开的 iOS 工程运行 `pod install`。选择菜单后打开 [**Terminal**](https://support.apple.com/guide/terminal/welcome/mac)，显示精确目标，完整输入大写 `INSTALL` 后回车安装；空行、其它输入、`Ctrl+C` 或输入结束均取消。工程不需要各自保存脚本副本。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、功能与作用范围 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 入口 / 模式 | 当前行为 |
| --- | --- |
| Xcode 自定义 Behavior | 优先读取本次调用的 `XcodeWorkspacePath`，再读取 `XcodeProjectPath`；不依赖启动目录或历史工程。 |
| `--xcode-path` | 明确指定现存 `.xcworkspace` 或 `.xcodeproj` 的绝对路径，优先于 Xcode 环境。 |
| `--check` | 只读显示工程与 Podfile 目录；不运行 `pod`、不执行 Podfile、不写日志或工程文件、不打开终端。 |
| `--help` / `-h` | 打印参数说明并退出。 |
| 正常安装 | 确认后检查现有 [**CocoaPods**](https://cocoapods.org/) 的 `pod --version`，同步执行 `pod install`，实时显示输出并保留退出码。 |

- 从工程所在目录逐级向上寻找最近的 `Podfile`，不越过最近的 `.git` 边界或用户主目录，不递归其它子工程。`.xcodeproj/project.xcworkspace` 会归一到所属 `.xcodeproj`。
- 拒绝 `Pods.xcodeproj`、`Pods` / `.swiftpm` 生成工程和明确只声明非 iOS 平台的 Podfile。平台检查只读文本，不运行 [**Ruby**](https://www.ruby-lang.org)；动态 DSL 或未明确声明的平台不会被猜测判定，需核对终端显示的工程。
- 确认前不调用 `pod`。无可交互输入时，通过私有一次性启动器把精确目标传给 Terminal，启动器使用后删除；不能取得真实终端输入时停止。
- 只复用已有 CocoaPods，不安装或升级 CocoaPods、Ruby、[**Homebrew**](https://brew.sh/)，不执行构建、`pod update` 或全局 Specs 更新命令。
- `pod install` 可能下载依赖、更新 `Pods/`、`Podfile.lock`、工作空间，并照常运行目标 Podfile 的安装钩子；现有辅助挂载、确认和失败策略仍由目标工程控制。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、Xcode 配置与日常使用 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

1、在 `Xcode → Behaviors → Edit Behaviors… → Custom` 保留一个名为 `🫘当前工程 · Pod Install` 的行为，启用 `Run` 并选择[同目录主脚本](<./【MacOS@Xcode】🫘当前工程Pod Install.command>)；快捷键按个人习惯设置。

2、激活需要安装依赖的 iOS 工程窗口，选择 `Xcode → Behaviors → 🫘当前工程 · Pod Install`。

3、在终端核对 Xcode 工程和 `Podfile` 目录，精确输入大写 `INSTALL` 后回车执行。空行、其它输入、`Ctrl+C`、输入结束或关闭未确认的终端均取消；切换到其它工程后继续使用同一 Behavior。安装确认直接从 `/dev/tty` 读取，需明确口令，避免意外回车启动安装；确认前不写安装日志。

Behaviors 属于 Xcode 用户设置。更换电脑或移动共享脚本包后重新选择主脚本；移动目标工程本身不需要重新创建 Behavior。只复制单个工程时，另行取得共享脚本包并完成上述配置。无 Xcode 上下文的双击会停止，需从 Behavior 调用或在终端明确传参。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、终端参数与只读检查 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在本脚本包目录运行。下例的工程路径由调用时计算，按实际工程替换示例位置；路径可包含中文、空格和 emoji。

```shell
# 只读核对目标：不会安装依赖。
/bin/zsh './【MacOS@Xcode】🫘当前工程Pod Install.command' \
  --check \
  --xcode-path "$(cd '/目标工程目录' && pwd)/App.xcworkspace"
```

```shell
# 正常安装：终端展示目标后仍需精确输入 INSTALL 并回车确认。
/bin/zsh './【MacOS@Xcode】🫘当前工程Pod Install.command' \
  --xcode-path "$(cd '/目标工程目录' && pwd)/App.xcodeproj"
```

`--terminal` 为一次性启动器内部标记，手动调用无需设置。`--check` 只验证路径定位及明确的平台声明，不验证 CocoaPods 健康、Podfile Ruby 语法、依赖解析或真实安装结果。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、日志与失败处理 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 每次确认后在系统临时目录创建权限受限的独立 `jobs-xcode-pod-install.log.*`，实际文件名在终端显示。不同窗口和工程的日志不互相覆盖；未确认或 `--check` 不创建安装日志。
- 工程上下文缺失、路径不合法、没有邻近 Podfile、明确非 iOS 或 CocoaPods 不可用时报告原因并停止。没有 Podfile 时不会自动初始化、创建 Podfile 或搜索其它工程。
- 打开 Terminal 成功仅表示入口转交成功；安装最终结果以终端和本次日志为准。健康检查、安装或日志写入失败不会报告成功，安装命令的非零退出码向调用方保留。
- 取消不会开始安装；安装中取消会中止本次流程，已经发生的 CocoaPods 或 Podfile 钩子修改不自动回滚。

[返回 CocoaPods 分类](../README.md) · [返回脚本库](../../README.md)

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
