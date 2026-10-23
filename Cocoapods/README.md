# `Cocoapods`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、功能入口](#jobs-toc-heading-2)
- [二、运行与作用范围](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录按当前能力划分入口。先从下面选择具体功能，再阅读相邻说明核对输入、默认选项、产物和风险。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、功能入口 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 功能说明 | 当前覆盖 |
| --- | --- |
| [【MacOS】⏳提取项目中所有的pod相关文件.command](<./【MacOS】⏳提取项目中所有的pod相关文件.command/README.md>) | 收集项目的 Podspec 与根目录 Podfile 相关文件 |
| [【MacOS】♻️放回本地Pod的podspec.command](<./【MacOS】♻️放回本地Pod的podspec.command/README.md>) | 当前总行数：714 |
| [【MacOS】⚙️Pod_Install.command](<./【MacOS】⚙️Pod_Install.command/README.md>) | 本入口在识别出的项目目录调用 [**CocoaPods**](https://cocoapods.org/)，由目标 `Podfile` 自己加载网络适配与公共 Specs 选源；包装器不再使用旧镜像缓存改写全局源 |
| [【MacOS】⚙️双击安装Cocoapods.command](<./【MacOS】⚙️双击安装Cocoapods.command/README.md>) | 准备 [**Ruby**](https://www.ruby-lang.org) 工具链并安装 CocoaPods |
| [【MacOS】⚙️双击更换Cocoapods源\[-\]CDN\[+\]Github.command](<./【MacOS】⚙️双击更换Cocoapods源[-]CDN[+]Github.command/README.md>) | 把 CocoaPods 的 CDN Specs 切换为 [**Git**](https://git-scm.com/) Specs |
| [【MacOS】⚙️双击禁用沙盒保证Cocoapods构建流程.command](<./【MacOS】⚙️双击禁用沙盒保证Cocoapods构建流程.command/README.md>) | 关闭目标 [**Xcode**](https://developer.apple.com/xcode) 工程的用户脚本沙盒 |
| [【MacOS】⚙️发布Cocoapods组件.command](<./【MacOS】⚙️发布Cocoapods组件.command/README.md>) | 递增 Podspec 版本并发布 CocoaPods 组件 |
| [【MacOS】⬆️Pod_Update.command](<./【MacOS】⬆️Pod_Update.command/README.md>) | 本入口在识别出的项目目录调用 [**CocoaPods**](https://cocoapods.org/)，由目标 `Podfile` 自己加载网络适配与公共 Specs 选源；包装器不再使用旧镜像缓存改写全局源 |
| [【MacOS】⬆️双击升级Cocoapods.command](<./【MacOS】⬆️双击升级Cocoapods.command/README.md>) | 用 RubyGems 更新 CocoaPods 到远端可用版本 |
| [【MacOS】⬆️双击更新Cocoapods本地仓库.command](<./【MacOS】⬆️双击更新Cocoapods本地仓库.command/README.md>) | 本入口在识别出的项目目录调用 [**CocoaPods**](https://cocoapods.org/)，由目标 `Podfile` 自己加载网络适配与公共 Specs 选源；包装器不再使用旧镜像缓存改写全局源 |
| [【MacOS】自检具体的某个本地pod是否能编译通过.command](<./【MacOS】自检具体的某个本地pod是否能编译通过.command/README.md>) | `pd` 用来检查一个本地 CocoaPods Pod 是否能在自己的 podspec 环境下独立编译通过 |
| [【MacOS】🧹双击卸载 Cocoapods.command](<./【MacOS】🧹双击卸载 Cocoapods.command/README.md>) | 卸载当前 Gem 环境中的 CocoaPods |
| [【MacOS】🫘JobsPublishPods.command](<./【MacOS】🫘JobsPublishPods.command/README.md>) | 校验并发布选中的 Podspec 到 CocoaPods trunk |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、运行与作用范围 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在选中的脚本包目录双击入口，或按它自己的命令示例运行；不要一次执行本目录所有脚本。目录清单仅为导航，不会自动安装、修复、清理或发布。

分类链接按主实现确定日志、确认方式与产物。运行前核对真实目标，已有输出和工程改动按对应说明保护。

[返回仓库说明](./../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
