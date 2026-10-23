# `【MacOS】🔍查询Xcode工程依赖关系.command`

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

分析 Podspec 依赖并生成多种依赖报告。入口：[同名脚本](<./【MacOS】🔍查询Xcode工程依赖关系.command>)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、功能覆盖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 优先自动寻找含 Podfile 的脚本目录或上一层。
- 支持拖入/链接/替身。
- 静态扫描 Podspec。
- 生成上下游、零依赖、外部引用统计。
- 生成可搜索拖拽缩放的 2D/3D HTML、Mermaid、DOT 与可选 PNG。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、输入、选项与产物 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 项目 | 当前行为 |
| --- | --- |
| 输入与默认值 | 目标目录需 Podfile；Graphviz 按当前 Homebrew 状态准备；无工程编译参数 |
| 输出与作用位置 | 工程 ./PodspecDependencyReport/ 中 MD、interactive.html、all/internal.mmd、dot 与可选 PNG |
| 依赖 | 系统 [**Ruby**](https://www.ruby-lang.org)、[**Graphviz**](https://graphviz.org/)、[**Homebrew**](https://brew.sh/)；安装工具时需网络 |

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在本 README 所在目录打开终端，也可双击同名 `.command`。先阅读内置自述，确认显示的目标再继续；`Ctrl+C` 可取消。

```shell
zsh './【MacOS】🔍查询Xcode工程依赖关系.command'
```

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、风险与能力边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

新报告会删除重建同名报告目录；静态规范解析不等于 [**Xcode**](https://developer.apple.com/xcode) target、SPM、动态 [**Ruby**](https://www.ruby-lang.org) 的完整真实构建依赖。缺 dot 时 PNG 可被跳过。

## <span id="jobs-toc-heading-6" data-jobs-toc="v2">五、日志与核对 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

运行状态输出到终端；日志由脚本的 `LOG_FILE` 指定，通常位于系统临时目录、以脚本名去扩展名后加 `.log` 命名。部分业务阶段会重新设置日志，请以实际回显为准。

完成后核对：工程 ./PodspecDependencyReport/ 中 MD、interactive.html、all/internal.mmd、dot 与可选 PNG。核对实际目标、终端输出和退出状态；发现错误时保留日志，先确认停止阶段与现存产物再重试。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
