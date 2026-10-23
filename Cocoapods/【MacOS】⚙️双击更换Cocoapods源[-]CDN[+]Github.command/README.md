# `【MacOS】⚙️双击更换Cocoapods源[-]CDN[+]Github.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、功能覆盖](#jobs-toc-heading-2)
- [二、输入、选项与产物](#jobs-toc-heading-3)
- [三、运行方式](#jobs-toc-heading-4)
- [四、风险与能力边界](#jobs-toc-heading-5)
- [五、日志与核对](#jobs-toc-heading-6)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

把 [**CocoaPods**](https://cocoapods.org/) 的 CDN Specs 切换为 [**Git**](https://git-scm.com/) Specs。入口：[同名脚本](<./【MacOS】⚙️双击更换Cocoapods源[-]CDN[+]Github.command>)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、功能覆盖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 检查 pod repo list。
- 移除名为 trunk 的 CDN 源。
- 删除名为 cocoapods 的本地 Specs 缓存。
- 从官方 Specs 仓库添加 cocoapods 源。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、输入、选项与产物 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 项目 | 当前行为 |
| --- | --- |
| 输入与默认值 | 无需工程路径，操作当前用户 CocoaPods 仓库；运行自述后回车继续 |
| 输出与作用位置 | 当前用户 CocoaPods 的源目录与 repo 列表 |
| 依赖 | [**CocoaPods**](https://cocoapods.org/)、[**Git**](https://git-scm.com/)、可访问 [**GitHub**](https://github.com) Specs 的网络 |

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在本 README 所在目录打开终端，也可双击同名 `.command`。先阅读内置自述，确认显示的目标再继续；`Ctrl+C` 可取消。

```shell
zsh './【MacOS】⚙️双击更换Cocoapods源[-]CDN[+]Github.command'
```

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、风险与能力边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

会删除当前用户指定的 Specs 缓存并重新克隆，可能耗时；不改 Podfile，也不执行 pod install。旧模板的“危险操作统一 YES”不代表这个入口有该保护，运行前必须核对清理范围。

## <span id="jobs-toc-heading-6" data-jobs-toc="v2">五、日志与核对 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

运行状态输出到终端；日志由脚本的 `LOG_FILE` 指定，通常位于系统临时目录、以脚本名去扩展名后加 `.log` 命名。部分业务阶段会重新设置日志，请以实际回显为准。

完成后核对：当前用户 CocoaPods 的源目录与 repo 列表。核对实际目标、终端输出和退出状态；发现错误时保留日志，先确认停止阶段与现存产物再重试。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
