# `JobsCommand@iOS`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、适用场景](#jobs-toc-heading-2)
- [二、运行前检查](#jobs-toc-heading-3)
- [三、目录结构](#repository-layout)
- [四、脚本执行流程](#script-workflows)
  - [【MacOS】⏳提取项目中所有的pod相关文件.command](#jobs-toc-heading-6)
  - [【MacOS】♻️放回本地Pod的podspec.command](#jobs-toc-heading-7)
  - [【MacOS】⚙️Pod\_Install.command](#jobs-toc-heading-8)
  - [【MacOS】⚙️双击安装Cocoapods.command](#jobs-toc-heading-9)
  - [【MacOS】⚙️双击更换Cocoapods源\[-\]CDN\[+\]Github.command](#jobs-toc-heading-10)
  - [【MacOS】⚙️双击禁用沙盒保证Cocoapods构建流程.command](#jobs-toc-heading-11)
  - [【MacOS】⚙️发布Cocoapods组件.command](#jobs-toc-heading-12)
  - [【MacOS】⬆️Pod\_Update.command](#jobs-toc-heading-13)
  - [【MacOS】⬆️双击升级Cocoapods.command](#jobs-toc-heading-14)
  - [【MacOS】⬆️双击更新Cocoapods本地仓库.command](#jobs-toc-heading-15)
  - [【MacOS】自检具体的某个本地pod是否能编译通过.command](#jobs-toc-heading-16)
  - [【MacOS】🧹双击卸载 Cocoapods.command](#jobs-toc-heading-17)
  - [【MacOS】🫘JobsPublishPods.command](#jobs-toc-heading-18)
  - [【MacOS】⌚️Xcode编译耗时菜单栏.command](#jobs-toc-heading-19)
  - [【MacOS】⏬simios.command](#jobs-toc-heading-20)
  - [【MacOS】⏳提取项目中所有的podspec.command](#jobs-toc-heading-21)
  - [【MacOS】⚙️双击为私人账户生成 SSH 密钥（加密手段：RSA 4096 + ED25519 二选一）.command](#jobs-toc-heading-22)
  - [【MacOS】⚙️双击任何来源安装.command](#jobs-toc-heading-23)
  - [【MacOS】⚙️双击卸载Homebrew.command](#jobs-toc-heading-24)
  - [【MacOS】⚙️双击显示隐藏文件.command](#jobs-toc-heading-25)
  - [【MacOS】⚙️备份:恢复 iOS设备支持.command](#jobs-toc-heading-26)
  - [【MacOS】⚙️运行授权.command](#jobs-toc-heading-27)
  - [【MacOS】✍️IPA免编译重签.command](#jobs-toc-heading-28)
  - [【MacOS】🌞颜色格式的转换.command](#jobs-toc-heading-29)
  - [【MacOS】🎈切换Shell.command](#jobs-toc-heading-30)
  - [【MacOS】🎈切换生成 iOS 的 Web Clip（桌面网页快捷方式）.command](#jobs-toc-heading-31)
  - [【MacOS】🎈双击打开已实例化的iOS模拟器.command](#jobs-toc-heading-32)
  - [【MacOS】🎈生成iOS.AppIcon.command](#jobs-toc-heading-33)
  - [【MacOS】📱双击初始化iOS模拟器.command](#jobs-toc-heading-34)
  - [【MacOS】📹双击制作iOS模拟器录屏Gif.command](#jobs-toc-heading-35)
  - [【MacOS】🔍查询Xcode工程依赖关系.command](#jobs-toc-heading-36)
  - [【MacOS】🚪双击打开SPM的下载文件夹.command](#jobs-toc-heading-37)
  - [【MacOS】🚪双击打开系统的环境配置文件.command](#jobs-toc-heading-38)
  - [【MacOS】🧩iOS工程改名工具.command](#jobs-toc-heading-39)
  - [【MacOS】🧮双击统计MD文件的有效行数.command](#jobs-toc-heading-40)
  - [【MacOS】🧮文件数统计.command](#jobs-toc-heading-41)
  - [【MacOS】🧹双击清理iOS缓存.command](#jobs-toc-heading-42)
  - [【MacOS】🫡CodeX+UnderstandAnything.command](#jobs-toc-heading-43)
  - [【MacOS】📦Fastfile.command](#jobs-toc-heading-44)
  - [【MacOS】📦双击自动生成ipa文件.command](#jobs-toc-heading-45)
  - [【MacOS】📦生成JobsPod二进制打包器.command](#jobs-toc-heading-46)
  - [【MacOS】⏬下载配置系统环境变量.command](#jobs-toc-heading-47)
  - [【MacOS】⏬双击下载SourceTree效率脚本.command](#jobs-toc-heading-48)
  - [【MacOS】⚙️双击安装JobsCodeSnippets.command](#jobs-toc-heading-49)
  - [【MacOS】⚙️双击安装quicktype.command](#jobs-toc-heading-50)
  - [【MacOS】⚙️安装代码地图CodeGraph.command](#jobs-toc-heading-51)
  - [【MacOS】🎈双击打开系统配置文件.command](#jobs-toc-heading-52)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

将此文件夹管理的脚本拖到 iOS 项目根目录运行，用于处理 [**CocoaPods**](https://cocoapods.org/)、[**Xcode**](https://developer.apple.com/xcode)、Git、打包和常用维护任务。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、适用场景 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- iOS 项目初始化、依赖安装、Pod 更新和本地 Pod 排查。
- 打包、模拟器、缓存清理、证书环境辅助检查。
- Pod 发布、规范文件提取与放回、工程改名、图标与开发辅助任务。
- [代码地图安装器](./配置相关/【MacOS】⚙️安装代码地图CodeGraph.command/README.md)：逐层体检系统工具、Homebrew、Node/npm，再安装或复用官方 [**CodeGraph**](https://github.com/colbymchenry/codegraph)，通过临时样例验证真实建图能力。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、运行前检查 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 先确认脚本是否需要放在项目根目录执行。
- 涉及 `pod install`、`pod update`、打包或 Git 改动前，先确认本地改动已经提交或备份。
- 双击 `.command` 前先阅读同目录 `README.md`，按提示继续。

| 分类 | 当前功能入口 |
| --- | --- |
| 打包相关 | [功能说明](<./打包相关/README.md>) |
| 其他 | [功能说明](<./其他/README.md>) |
| 配置相关 | [功能说明](<./配置相关/README.md>) |
| Cocoapods | [功能说明](./Cocoapods/README.md) |

## 三、<span id="repository-layout">目录结构</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

下面按当前磁盘第一层列出真实文件与目录；包内主脚本由下方完整名称直接进入。

```text
JobsCommand@iOS/
├── Cocoapods/
├── README.md
├── 其他/
├── 打包相关/
└── 配置相关/
```

## 四、<span id="script-workflows">脚本执行流程</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

当前 macOS 有 47 个脚本包（以不含 Resources / Tests / Scripts 的就近功能 README 计数，依据当前目录，2026-10-23）。这里只列本仓维护的主入口；独立子 Git、测试、函数库及打包资源模板不作为用户运行入口。按功能选择入口后核对该包的参数、产物与作用范围。

### <span id="jobs-toc-heading-6" data-jobs-toc="v2">[【MacOS】⏳提取项目中所有的pod相关文件.command](<./Cocoapods/【MacOS】⏳提取项目中所有的pod相关文件.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 收集项目的 Podspec 与根目录 Podfile 相关文件。

- 解析拖入目录、Unix 链接和 Finder 替身。
- 递归收集 podspec。
- 复制根 Podfile.deps、Podfile、Podfile.lock。
- 去重真实来源。
- 同名目标生成唯一名称。
- 可选 ZIP。

### <span id="jobs-toc-heading-7" data-jobs-toc="v2">[【MacOS】♻️放回本地Pod的podspec.command](<./Cocoapods/【MacOS】♻️放回本地Pod的podspec.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 将已收集的 podspec 匹配并放回本地 Pod。

- 选择本地 Pods 根目录和 podspec 来源目录。
- 扫描名称并生成匹配计划，处理冲突项。
- 按确认复制匹配文件，输出缺失与完成结果。

### <span id="jobs-toc-heading-8" data-jobs-toc="v2">[【MacOS】⚙️Pod_Install.command](<./Cocoapods/【MacOS】⚙️Pod_Install.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 根据原生或 [**Flutter**](https://flutter.dev/) 项目结构安装 Pod 依赖。

- 初始化 UTF-8、工具路径与工程目录。
- 识别原生或 Flutter 工程，准备对应 Podfile 所在位置。
- 执行对应 pod install 流程，输出完成状态与日志。

### <span id="jobs-toc-heading-9" data-jobs-toc="v2">[【MacOS】⚙️双击安装Cocoapods.command](<./Cocoapods/【MacOS】⚙️双击安装Cocoapods.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 准备 Ruby 工具链并安装 CocoaPods。

- 检查 Command Line Tools、Homebrew、fzf。
- 备份 Shell 配置。
- 准备 Homebrew Ruby。
- 优先用 Homebrew 安装 CocoaPods，失败时采用 Gem。
- 检查 pod 版本与源初始化。

### <span id="jobs-toc-heading-10" data-jobs-toc="v2">[【MacOS】⚙️双击更换Cocoapods源\[-\]CDN\[+\]Github.command](<./Cocoapods/【MacOS】⚙️双击更换Cocoapods源[-]CDN[+]Github.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 将 CocoaPods 的 CDN Specs 源切换为 [**Git**](https://git-scm.com/) 源。

- 阅读源切换和本地缓存影响。
- 移除脚本指定的 CDN trunk 与缓存目录。
- 添加 Git Specs 源并输出源配置结果。

### <span id="jobs-toc-heading-11" data-jobs-toc="v2">[【MacOS】⚙️双击禁用沙盒保证Cocoapods构建流程.command](<./Cocoapods/【MacOS】⚙️双击禁用沙盒保证Cocoapods构建流程.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 关闭目标 Xcode 工程的用户脚本沙盒。

- 识别脚本目录下 Flutter 的 ios/ 或原生工程。
- 自动取第一份 .xcodeproj，缺失时提示拖入。
- 把 YES 改为 NO，缺字段时向 buildSettings 添加。

### <span id="jobs-toc-heading-12" data-jobs-toc="v2">[【MacOS】⚙️发布Cocoapods组件.command](<./Cocoapods/【MacOS】⚙️发布Cocoapods组件.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 递增 Podspec 版本并发布 CocoaPods 组件。

- 查找/选择 podspec。
- 支持 major/minor/patch 或自定义版本。
- 替换版本。
- 检查 trunk 登录、spec lint 与 trunk push。
- 随后暂存提交、打 tag 并推送。

### <span id="jobs-toc-heading-13" data-jobs-toc="v2">[【MacOS】⬆️Pod_Update.command](<./Cocoapods/【MacOS】⬆️Pod_Update.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 更新目标工程的 Pod 依赖。

- 识别原生或 Flutter 项目并定位 Podfile。
- 按项目类型准备依赖命令和运行目录。
- 执行 pod update 并显示结果；Podfile.lock 和解析版本可能改变。

### <span id="jobs-toc-heading-14" data-jobs-toc="v2">[【MacOS】⬆️双击升级Cocoapods.command](<./Cocoapods/【MacOS】⬆️双击升级Cocoapods.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 用 RubyGems 更新 CocoaPods 到远端可用版本。

- 读取本地 pod 与远端 Gem 版本。
- 核对 Ruby 和 Gem 路径。
- 版本不同时卸载已有 cocoapods Gem 再安装最新版。
- 刷新环境并显示 pod 路径。

### <span id="jobs-toc-heading-15" data-jobs-toc="v2">[【MacOS】⬆️双击更新Cocoapods本地仓库.command](<./Cocoapods/【MacOS】⬆️双击更新Cocoapods本地仓库.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 刷新 CocoaPods 本地仓库并安装工程依赖。

- 确定工程根目录并检查入口依赖。
- 按提示处理本地 Specs 更新及脚本授权。
- 执行对应 pod install 流程，检查日志中的更新与安装结果。

### <span id="jobs-toc-heading-16" data-jobs-toc="v2">[【MacOS】自检具体的某个本地pod是否能编译通过.command](<./Cocoapods/【MacOS】自检具体的某个本地pod是否能编译通过.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 验证明确选中的本地 Pod 能否通过编译校验。

- 选择本地 Pod 或 podspec，检查 CocoaPods 与平台参数。
- 构造对应 pod lib lint 命令并运行。
- 显示校验日志与失败原因，按提示继续测试下一项。

### <span id="jobs-toc-heading-17" data-jobs-toc="v2">[【MacOS】🧹双击卸载 Cocoapods.command](<./Cocoapods/【MacOS】🧹双击卸载 Cocoapods.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 卸载当前 Gem 环境中的 CocoaPods。

- 列出 cocoapods 相关本地 Gem。
- 按提示确认。
- 循环调用 sudo gem uninstall。

### <span id="jobs-toc-heading-18" data-jobs-toc="v2">[【MacOS】🫘JobsPublishPods.command](<./Cocoapods/【MacOS】🫘JobsPublishPods.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 校验并发布选中的 Podspec 到 CocoaPods trunk。

- 扫描脚本目录 podspec 或循环输入。
- 优先同步 HEAD tag 到版本。
- 读取 Pod 元数据。
- 检查 trunk 登录并可选注册。
- 可选 lib lint，之后 trunk push 与 trunk info。

### <span id="jobs-toc-heading-19" data-jobs-toc="v2">[【MacOS】⌚️Xcode编译耗时菜单栏.command](<./其他/【MacOS】⌚️Xcode编译耗时菜单栏.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 安装或刷新显示 Xcode 编译耗时的菜单栏工具。

- 检查 Swift 编译环境并选择工程 / 安装动作。
- 准备构建记录与 Hook，编译菜单栏 App。
- 安装或刷新工具并启动，后续从构建记录显示耗时。

### <span id="jobs-toc-heading-20" data-jobs-toc="v2">[【MacOS】⏬simios.command](<./其他/【MacOS】⏬simios.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 下载并检查 iOS 模拟器运行时。

- 检查 Xcode、许可、磁盘空间和网络条件。
- 列出当前运行时，按交互选择下载目标。
- 执行下载并汇总运行时状态与日志。

### <span id="jobs-toc-heading-21" data-jobs-toc="v2">[【MacOS】⏳提取项目中所有的podspec.command](<./其他/【MacOS】⏳提取项目中所有的podspec.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 递归收集项目 Podspec 到桌面。

- 解析普通目录、Unix 链接与 Finder 替身。
- 递归查找 podspec 及其别名目标。
- 按真实来源去重。
- 冲突改名。
- 输出统计并可选 ZIP。

### <span id="jobs-toc-heading-22" data-jobs-toc="v2">[【MacOS】⚙️双击为私人账户生成 SSH 密钥（加密手段：RSA 4096 + ED25519 二选一）.command](<./其他/【MacOS】⚙️双击为私人账户生成 SSH 密钥（加密手段：RSA 4096 + ED25519 二选一）.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 生成私人 GitHub 账户使用的 SSH 密钥与配置。

- 选择 ED25519 或 RSA4096。
- 收集邮箱。
- 生成无口令密钥。
- 写 SSH 配置、准备 ssh-agent。
- 打开 GitHub SSH 设置并测试连接。

### <span id="jobs-toc-heading-23" data-jobs-toc="v2">[【MacOS】⚙️双击任何来源安装.command](<./其他/【MacOS】⚙️双击任何来源安装.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 检查 SIP 后打开 macOS 应用来源设置。

- 读取 csrutil status。
- 按源码执行应用来源限制命令。
- 打开安全与隐私设置供人工检查。

### <span id="jobs-toc-heading-24" data-jobs-toc="v2">[【MacOS】⚙️双击卸载Homebrew.command](<./其他/【MacOS】⚙️双击卸载Homebrew.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 卸载 Homebrew 并处理脚本列出的残留目录。

- 查看自述与卸载范围，按脚本要求再次确认。
- 运行官方卸载入口，再处理配置的残留路径。
- 核对终端结果；依赖 Homebrew 的工具可能随之不可用。

### <span id="jobs-toc-heading-25" data-jobs-toc="v2">[【MacOS】⚙️双击显示隐藏文件.command](<./其他/【MacOS】⚙️双击显示隐藏文件.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 让 Finder 显示隐藏文件。

- 写入 Finder 的 AppleShowAllFiles = YES。
- 按源码重载 Finder。

### <span id="jobs-toc-heading-26" data-jobs-toc="v2">[【MacOS】⚙️备份:恢复 iOS设备支持.command](<./其他/【MacOS】⚙️备份%3A恢复 iOS设备支持.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 备份或恢复 Xcode 的 iPhone DeviceSupport。

- 菜单选择备份或恢复。
- 备份复制到时间戳目录。
- 恢复选择现有备份后删除当前 DeviceSupport 并复制回来、调整所有者。

### <span id="jobs-toc-heading-27" data-jobs-toc="v2">[【MacOS】⚙️运行授权.command](<./其他/【MacOS】⚙️运行授权.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 为指定文件或目录增加执行权限。

- 回车授权脚本目录第一层 .command。
- 输入小写 yes 递归查找 .command。
- 拖入多个路径时逐个 chmod +x。

### <span id="jobs-toc-heading-28" data-jobs-toc="v2">[【MacOS】✍️IPA免编译重签.command](<./其他/【MacOS】✍️IPA免编译重签.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 保留原团队与 Bundle ID，使用有效签名材料重签 IPA，验证后原路径替换并可选安装设备。

- 双击或终端传参选择 IPA；[功能说明](./其他/【MacOS】✍️IPA免编译重签.command/README.md)包含工程关联、设备选择与完整签名边界。
- [独立 Finder 右键扩展](../OS@Extension/MacOS@Extension/JobsIPAResigner/README.md)仅对单个 `.ipa` 普通文件显示，点击后由终端承接同一交互流程。
- 自动关联或手动指定对应工程，选择设备并匹配全部 Target 共用的签名身份与各自描述文件。
- 解包并检查加密或不支持的嵌套代码，生成授权与签名计划。
- 按嵌套顺序签名，回读验证后重新打包并替换原 IPA；回车安装、任意非空输入结束，旧包不自动备份。

### <span id="jobs-toc-heading-29" data-jobs-toc="v2">[【MacOS】🌞颜色格式的转换.command](<./其他/【MacOS】🌞颜色格式的转换.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 把常见颜色输入转成多种表示并预览色块。

- 解析 HEX、rgb()/rgba() 与分隔通道。
- 输出 HEX/RGB/RGBA 及终端色块。
- 支持交互循环或单次转换。

### <span id="jobs-toc-heading-30" data-jobs-toc="v2">[【MacOS】🎈切换Shell.command](<./其他/【MacOS】🎈切换Shell.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 从系统允许列表选择 macOS 登录 Shell。

- 读取系统 shells 列表。
- fzf 选择。
- 调用 chsh -s。
- 通过 dscl 打印用户 Shell。

### <span id="jobs-toc-heading-31" data-jobs-toc="v2">[【MacOS】🎈切换生成 iOS 的 Web Clip（桌面网页快捷方式）.command](<./其他/【MacOS】🎈切换生成 iOS 的 Web Clip（桌面网页快捷方式）.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 生成安装到 iPhone/iPad 的网页桌面快捷方式描述文件。

- 收集 URL、桌面名称和图标。
- 校验图像并转换为 64×64。
- 生成带 Web Clip 负载的 mobileconfig。
- Finder 定位结果。

### <span id="jobs-toc-heading-32" data-jobs-toc="v2">[【MacOS】🎈双击打开已实例化的iOS模拟器.command](<./其他/【MacOS】🎈双击打开已实例化的iOS模拟器.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 打开系统 iOS Simulator 应用。

- 调用 open -a Simulator。
- 由 Simulator 恢复当前设备窗口。

### <span id="jobs-toc-heading-33" data-jobs-toc="v2">[【MacOS】🎈生成iOS.AppIcon.command](<./其他/【MacOS】🎈生成iOS.AppIcon.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 把一张图片生成为 iOS AppIcon.appiconset。

- 解析拖入图片和 Finder 替身。
- 检查系统图像工具。
- 先准备正方形 PNG。
- 生成多尺寸图标和 Contents.json。
- Finder 定位产物。

### <span id="jobs-toc-heading-34" data-jobs-toc="v2">[【MacOS】📱双击初始化iOS模拟器.command](<./其他/【MacOS】📱双击初始化iOS模拟器.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 选择系统运行时并创建可用的 iOS 模拟器。

- 检查模拟器后台状态和菜单工具。
- 选择可用运行时、设备类型与设备名称。
- 创建并启动模拟器，等待就绪后按提示继续创建或退出。

### <span id="jobs-toc-heading-35" data-jobs-toc="v2">[【MacOS】📹双击制作iOS模拟器录屏Gif.command](<./其他/【MacOS】📹双击制作iOS模拟器录屏Gif.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 录制选中的 iOS 模拟器并可转换 GIF。

- fzf 选择设备。
- 必要时启动 Simulator。
- 使用 simctl recordVideo。
- 回车停止录制。
- 可选 FFmpeg 抽帧与 gifski 生成 GIF。
- 可选清理中间帧。

### <span id="jobs-toc-heading-36" data-jobs-toc="v2">[【MacOS】🔍查询Xcode工程依赖关系.command](<./其他/【MacOS】🔍查询Xcode工程依赖关系.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 分析 Podspec 依赖并生成多种依赖报告。

- 优先自动寻找含 Podfile 的脚本目录或上一层。
- 支持拖入/链接/替身。
- 静态扫描 Podspec。
- 生成上下游、零依赖、外部引用统计。
- 生成可搜索拖拽缩放的 2D/3D HTML、Mermaid、DOT 与可选 PNG。

### <span id="jobs-toc-heading-37" data-jobs-toc="v2">[【MacOS】🚪双击打开SPM的下载文件夹.command](<./其他/【MacOS】🚪双击打开SPM的下载文件夹.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 打开当前 Xcode 工程的 SPM 下载目录。

- 在脚本目录取第一份 .xcodeproj。
- 提取工程名。
- 查找对应 DerivedData。
- 打开 SourcePackages/checkouts。

### <span id="jobs-toc-heading-38" data-jobs-toc="v2">[【MacOS】🚪双击打开系统的环境配置文件.command](<./其他/【MacOS】🚪双击打开系统的环境配置文件.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 打开并加载已有 Shell 环境配置。

- 回车后打开 bash_profile、bashrc、zshrc。
- 对存在的配置执行 source。

### <span id="jobs-toc-heading-39" data-jobs-toc="v2">[【MacOS】🧩iOS工程改名工具.command](<./其他/【MacOS】🧩iOS工程改名工具.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 将工程按指定名称原地改名或复制开版。

- 填写工程目录、旧名、新名与运行模式。
- 按模式准备工作副本，并选择是否 Zip 备份。
- 替换工程文本与路径、重命名根目录，再按选择处理 Pods 与 workspace。

### <span id="jobs-toc-heading-40" data-jobs-toc="v2">[【MacOS】🧮双击统计MD文件的有效行数.command](<./其他/【MacOS】🧮双击统计MD文件的有效行数.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 安装 Git pre-commit 钩子来统计 Markdown 有效行数。

- 要求脚本目录存在 .git 目录。
- 写入 .git/hooks/pre-commit。
- 提交时扫描 Markdown，统计有效行并替换“当前总行数”字段，然后 git add。

### <span id="jobs-toc-heading-41" data-jobs-toc="v2">[【MacOS】🧮文件数统计.command](<./其他/【MacOS】🧮文件数统计.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 递归统计所选目录的文件。

- 交互输入目录。
- 递归打印各层文件数并累计总数。
- 退出前保留统计输出。

### <span id="jobs-toc-heading-42" data-jobs-toc="v2">[【MacOS】🧹双击清理iOS缓存.command](<./其他/【MacOS】🧹双击清理iOS缓存.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 识别原生或 Flutter 工程并删除 iOS 构建缓存。

- 按 Podfile 或 pubspec.yaml/ios 识别项目。
- 原生清理 Pods、Podfile.lock、DerivedData。
- Flutter 额外清理 symlinks、Flutter 生成物、.dart_tool、build、pubspec.lock。

### <span id="jobs-toc-heading-43" data-jobs-toc="v2">[【MacOS】🫡CodeX+UnderstandAnything.command](<./其他/【MacOS】🫡CodeX+UnderstandAnything.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 为 iOS 工程准备 [**Codex**](https://openai.com/codex) 与 [**Understand Anything**](https://github.com/Lum1104/Understand-Anything) 使用入口。

- 检查内嵌运行时并定位 Xcode 工程。
- 检查 Codex CLI，按选择安装或更新 Understand Anything。
- 验证技能入口，显示使用方法并询问是否启动 Codex。

### <span id="jobs-toc-heading-44" data-jobs-toc="v2">[【MacOS】📦Fastfile.command](<./打包相关/【MacOS】📦Fastfile.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 为检测到的工程准备或打开 [**fastlane**](https://fastlane.tools/) 的 Fastfile。

- 识别工程类型，检查菜单工具与 fastlane。
- 查找现有 Fastfile，缺失时按脚本模板创建。
- 选择编辑器或 Finder 打开目标文件，后续打包使用其中配置。

### <span id="jobs-toc-heading-45" data-jobs-toc="v2">[【MacOS】📦双击自动生成ipa文件.command](<./打包相关/【MacOS】📦双击自动生成ipa文件.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 把现有真机 App 打包为 IPA。

- 定位目标工程与已有 iPhoneOS App，排除模拟器或不匹配产物。
- 在独立 Payload 目录复制 App 并压缩为 IPA。
- 检查输出并打开位置；此入口以已有 App 为基础。

### <span id="jobs-toc-heading-46" data-jobs-toc="v2">[【MacOS】📦生成JobsPod二进制打包器.command](<./打包相关/【MacOS】📦生成JobsPod二进制打包器.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 编译并安装 JobsPod 二进制打包器原生应用。

- 检查 Xcode、swiftc 和随包源码。
- 在暂存目录编译 App，完成临时签名与 Bundle 验证。
- 安装验证后的应用，清理暂存并启动 GUI。

### <span id="jobs-toc-heading-47" data-jobs-toc="v2">[【MacOS】⏬下载配置系统环境变量.command](<./配置相关/【MacOS】⏬下载配置系统环境变量.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 下载预设的 macOS 环境变量配置仓库。

- 检查目标目录是否已存在。
- 按回答选择删除重建。
- 克隆源码配置的环境仓库。

### <span id="jobs-toc-heading-48" data-jobs-toc="v2">[【MacOS】⏬双击下载SourceTree效率脚本.command](<./配置相关/【MacOS】⏬双击下载SourceTree效率脚本.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 下载 SourceTree 自定义动作脚本集合。

- 删除预设的本地 SourceTree.command 目录。
- 浅克隆 SourceTree.sh。
- 给其中 .sh 与 .command 添加执行权限。
- 打开结果目录。

### <span id="jobs-toc-heading-49" data-jobs-toc="v2">[【MacOS】⚙️双击安装JobsCodeSnippets.command](<./配置相关/【MacOS】⚙️双击安装JobsCodeSnippets.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 安装或更新当前用户 Xcode 代码片段，保留本地修改；支持“iOS / CocoaPods 辅助工具”右键菜单。

- 只读检查安装状态，按选择在私有副本克隆或沿明确上游拉取合并。
- 保存暂存、未暂存和未跟踪内容，冲突停止并保留原目录和候选。
- 成功后保留原始备份；不自动提交、推送或重启 Xcode。

### <span id="jobs-toc-heading-50" data-jobs-toc="v2">[【MacOS】⚙️双击安装quicktype.command](<./配置相关/【MacOS】⚙️双击安装quicktype.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 安装命令行 quicktype 代码生成工具。

- 检查 Homebrew、[**Node.js**](https://nodejs.org/) 与 [**npm**](https://www.npmjs.com/)。
- 检测全局 quicktype，缺失时执行源码声明的 npm 安装。
- 校验命令可用并输出后续用法。

### <span id="jobs-toc-heading-51" data-jobs-toc="v2">[【MacOS】⚙️安装代码地图CodeGraph.command](<./配置相关/【MacOS】⚙️安装代码地图CodeGraph.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 安装或复用可验证工作的 CodeGraph。

- 逐层检查 Homebrew、Node.js、npm 和下载通道。
- 复用健康安装，按确认安装或更新官方包。
- 用隔离样例验证实际建图，再登记用户 PATH 并显示结果。

### <span id="jobs-toc-heading-52" data-jobs-toc="v2">[【MacOS】🎈双击打开系统配置文件.command](<./配置相关/【MacOS】🎈双击打开系统配置文件.command/README.md>)</span><!-- jobs-toc:heading-end -->

> **目的：** 选择打开并加载已有 Shell 配置。

- 检查 Homebrew 与 fzf。
- 收集 bash_profile、bashrc、zshrc 和 Oh My Zsh 脚本。
- 多选后逐项 open 与 source。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
