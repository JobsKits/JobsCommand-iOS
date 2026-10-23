# `【MacOS】🎈切换Shell.command`

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

从系统允许列表选择 [**macOS**](https://www.apple.com/macos/) 登录 Shell。入口：[同名脚本](<./【MacOS】🎈切换Shell.command>)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、功能覆盖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 读取系统 shells 列表。
- [**fzf**](https://formulae.brew.sh/formula/fzf) 选择。
- 调用 chsh -s。
- 通过 dscl 打印用户 Shell。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、输入、选项与产物 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 项目 | 当前行为 |
| --- | --- |
| 输入与默认值 | 无路径参数；菜单选择现有 Shell，取消退出 |
| 输出与作用位置 | 当前用户默认登录 Shell |
| 依赖 | [**macOS**](https://www.apple.com/macos/) chsh、dscl、[**fzf**](https://formulae.brew.sh/formula/fzf)；[**Homebrew**](https://brew.sh/) 用于缺失依赖 |

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在本 README 所在目录打开终端，也可双击同名 `.command`。先阅读内置自述，确认显示的目标再继续；`Ctrl+C` 可取消。

```shell
zsh './【MacOS】🎈切换Shell.command'
```

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、风险与能力边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

属于持久账号设置，可能提示密码；现有终端需重新打开生效，不是仅切换当前子进程。

## <span id="jobs-toc-heading-6" data-jobs-toc="v2">五、日志与核对 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

运行状态输出到终端；日志由脚本的 `LOG_FILE` 指定，通常位于系统临时目录、以脚本名去扩展名后加 `.log` 命名。部分业务阶段会重新设置日志，请以实际回显为准。

完成后核对：当前用户默认登录 Shell。核对实际目标、终端输出和退出状态；发现错误时保留日志，先确认停止阶段与现存产物再重试。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
