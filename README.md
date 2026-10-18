# `JobsCommand@iOS`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

将此文件夹管理的脚本拖到 iOS 项目根目录运行，用于处理 [**CocoaPods**](https://cocoapods.org/)、[**Xcode**](https://developer.apple.com/xcode)、Git、打包和常用维护任务。

## 一、适用场景 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- iOS 项目初始化、依赖安装、Pod 更新和本地 Pod 排查。
- 打包、模拟器、缓存清理、证书环境辅助检查。
- Git 分支、提交回退、资料恢复等项目维护操作。
- [代码地图安装器](./配置相关/【MacOS】⚙️安装代码地图CodeGraph.command/README.md)：逐层体检系统工具、Homebrew、Node/npm，再安装或复用官方 [**CodeGraph**](https://github.com/colbymchenry/codegraph)，通过临时样例验证真实建图能力。

## 二、运行前检查 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 先确认脚本是否需要放在项目根目录执行。
- 涉及 `pod install`、`pod update`、打包或 Git 改动前，先确认本地改动已经提交或备份。
- 双击 `.command` 前先阅读同目录 `README.md`，按提示继续。

## 三、<span id="repository-layout">目录结构</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

下面按当前磁盘第一层列出真实文件与目录；包内主脚本由下方完整名称直接进入。

```text
JobsCommand@iOS/
├── README.md
├── Cocoapods/  # 13 个入口
├── Git相关/  # 4 个入口
├── icon.png
├── 其他/  # 25 个入口
├── 打包相关/  # 3 个入口
└── 配置相关/  # 6 个入口
```

## 四、<span id="script-workflows">脚本执行流程</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

本仓共有 51 个用户入口。这里只列本仓维护的主入口；独立子 Git、测试、函数库及打包资源模板不作为用户运行入口。步骤来自静态源码与配套说明，未执行安装、清理、构建或 Git 写操作。

### [【MacOS】⏳提取项目中所有的pod相关文件.command](./Cocoapods/%E3%80%90MacOS%E3%80%91%E2%8F%B3%E6%8F%90%E5%8F%96%E9%A1%B9%E7%9B%AE%E4%B8%AD%E6%89%80%E6%9C%89%E7%9A%84pod%E7%9B%B8%E5%85%B3%E6%96%87%E4%BB%B6.command/%E3%80%90MacOS%E3%80%91%E2%8F%B3%E6%8F%90%E5%8F%96%E9%A1%B9%E7%9B%AE%E4%B8%AD%E6%89%80%E6%9C%89%E7%9A%84pod%E7%9B%B8%E5%85%B3%E6%96%87%E4%BB%B6.command)

> **目的：** 收集工程里的 Pod 清单、配置与依赖文件。

- 选择工程与输出范围，检查查找和归档工具。
- 扫描 Pod 相关目录及清单，按来源复制到收集目录。
- 生成结果说明或压缩包并显示输出位置，原文件保留。


### [【MacOS】♻️放回本地Pod的podspec.command](./Cocoapods/%E3%80%90MacOS%E3%80%91%E2%99%BB%EF%B8%8F%E6%94%BE%E5%9B%9E%E6%9C%AC%E5%9C%B0Pod%E7%9A%84podspec.command/%E3%80%90MacOS%E3%80%91%E2%99%BB%EF%B8%8F%E6%94%BE%E5%9B%9E%E6%9C%AC%E5%9C%B0Pod%E7%9A%84podspec.command)

> **目的：** 将已收集的 podspec 匹配并放回本地 Pod。

- 选择本地 Pods 根目录和 podspec 来源目录。
- 扫描名称并生成匹配计划，处理冲突项。
- 按确认复制匹配文件，输出缺失与完成结果。


### [【MacOS】⚙️Pod_Install.command](./Cocoapods/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8FPod_Install.command/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8FPod_Install.command)

> **目的：** 根据原生或 [**Flutter**](https://flutter.dev/) 项目结构安装 Pod 依赖。

- 初始化 UTF-8、工具路径与工程目录。
- 识别原生或 Flutter 工程，准备对应 Podfile 所在位置。
- 执行对应 pod install 流程，输出完成状态与日志。


### [【MacOS】⚙️双击安装Cocoapods.command](./Cocoapods/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%8F%8C%E5%87%BB%E5%AE%89%E8%A3%85Cocoapods.command/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%8F%8C%E5%87%BB%E5%AE%89%E8%A3%85Cocoapods.command)

> **目的：** 准备 [**Ruby**](https://www.ruby-lang.org/) 环境并安装 CocoaPods。

- 备份相关 Shell 配置，检查 [**Homebrew**](https://brew.sh/)、Ruby 与交互工具。
- 选择 Ruby / CocoaPods 安装方式并处理 gem 源。
- 安装并校验 pod 命令，按提示决定是否初始化本地 Specs 仓库。


### [【MacOS】⚙️双击更换Cocoapods源[-]CDN[+]Github.command](./Cocoapods/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%8F%8C%E5%87%BB%E6%9B%B4%E6%8D%A2Cocoapods%E6%BA%90%5B-%5DCDN%5B%2B%5DGithub.command/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%8F%8C%E5%87%BB%E6%9B%B4%E6%8D%A2Cocoapods%E6%BA%90%5B-%5DCDN%5B%2B%5DGithub.command)

> **目的：** 将 CocoaPods 的 CDN Specs 源切换为 [**Git**](https://git-scm.com/) 源。

- 阅读源切换和本地缓存影响。
- 移除脚本指定的 CDN trunk 与缓存目录。
- 添加 Git Specs 源并输出源配置结果。


### [【MacOS】⚙️双击禁用沙盒保证Cocoapods构建流程.command](./Cocoapods/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%8F%8C%E5%87%BB%E7%A6%81%E7%94%A8%E6%B2%99%E7%9B%92%E4%BF%9D%E8%AF%81Cocoapods%E6%9E%84%E5%BB%BA%E6%B5%81%E7%A8%8B.command/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%8F%8C%E5%87%BB%E7%A6%81%E7%94%A8%E6%B2%99%E7%9B%92%E4%BF%9D%E8%AF%81Cocoapods%E6%9E%84%E5%BB%BA%E6%B5%81%E7%A8%8B.command)

> **目的：** 修改目标 Xcode 工程的用户脚本沙盒设置。

- 定位工程目录，查找或手工指定 .xcodeproj。
- 检查 project.pbxproj 中的脚本沙盒配置。
- 将对应设置改为禁用并报告结果；构建仍需在项目中验证。


### [【MacOS】⚙️发布Cocoapods组件.command](./Cocoapods/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%8F%91%E5%B8%83Cocoapods%E7%BB%84%E4%BB%B6.command/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%8F%91%E5%B8%83Cocoapods%E7%BB%84%E4%BB%B6.command)

> **目的：** 修改 Pod 版本、发布 trunk，并执行脚本内置的 Git 提交和推送。

- 选择 podspec 与新版本，核对后写入版本号。
- 检查 trunk 账号并进入对应分支。
  - 如果尚未注册，收集注册信息并执行 register；已注册时继续 lint 与 trunk push。
- 在发布分支中暂存全仓并创建 Git 提交，再按新版本打标签并执行源码固定的 origin/master 标签推送；运行前核对该目标。


### [【MacOS】⬆️Pod_Update.command](./Cocoapods/%E3%80%90MacOS%E3%80%91%E2%AC%86%EF%B8%8FPod_Update.command/%E3%80%90MacOS%E3%80%91%E2%AC%86%EF%B8%8FPod_Update.command)

> **目的：** 更新目标工程的 Pod 依赖。

- 识别原生或 Flutter 项目并定位 Podfile。
- 按项目类型准备依赖命令和运行目录。
- 执行 pod update 并显示结果；Podfile.lock 和解析版本可能改变。


### [【MacOS】⬆️双击升级Cocoapods.command](./Cocoapods/%E3%80%90MacOS%E3%80%91%E2%AC%86%EF%B8%8F%E5%8F%8C%E5%87%BB%E5%8D%87%E7%BA%A7Cocoapods.command/%E3%80%90MacOS%E3%80%91%E2%AC%86%EF%B8%8F%E5%8F%8C%E5%87%BB%E5%8D%87%E7%BA%A7Cocoapods.command)

> **目的：** 比较并升级 CocoaPods 版本。

- 检查 Ruby、gem 与当前 pod 版本。
- 查询可用版本并判断是否需要更新。
- 按确认执行升级，再显示版本与命令位置。


### [【MacOS】⬆️双击更新Cocoapods本地仓库.command](./Cocoapods/%E3%80%90MacOS%E3%80%91%E2%AC%86%EF%B8%8F%E5%8F%8C%E5%87%BB%E6%9B%B4%E6%96%B0Cocoapods%E6%9C%AC%E5%9C%B0%E4%BB%93%E5%BA%93.command/%E3%80%90MacOS%E3%80%91%E2%AC%86%EF%B8%8F%E5%8F%8C%E5%87%BB%E6%9B%B4%E6%96%B0Cocoapods%E6%9C%AC%E5%9C%B0%E4%BB%93%E5%BA%93.command)

> **目的：** 刷新 CocoaPods 本地仓库并安装工程依赖。

- 确定工程根目录并检查入口依赖。
- 按提示处理本地 Specs 更新及脚本授权。
- 执行对应 pod install 流程，检查日志中的更新与安装结果。


### [【MacOS】自检具体的某个本地pod是否能编译通过.command](./Cocoapods/%E3%80%90MacOS%E3%80%91%E8%87%AA%E6%A3%80%E5%85%B7%E4%BD%93%E7%9A%84%E6%9F%90%E4%B8%AA%E6%9C%AC%E5%9C%B0pod%E6%98%AF%E5%90%A6%E8%83%BD%E7%BC%96%E8%AF%91%E9%80%9A%E8%BF%87.command/%E3%80%90MacOS%E3%80%91%E8%87%AA%E6%A3%80%E5%85%B7%E4%BD%93%E7%9A%84%E6%9F%90%E4%B8%AA%E6%9C%AC%E5%9C%B0pod%E6%98%AF%E5%90%A6%E8%83%BD%E7%BC%96%E8%AF%91%E9%80%9A%E8%BF%87.command)

> **目的：** 验证明确选中的本地 Pod 能否通过编译校验。

- 选择本地 Pod 或 podspec，检查 CocoaPods 与平台参数。
- 构造对应 pod lib lint 命令并运行。
- 显示校验日志与失败原因，按提示继续测试下一项。


### [【MacOS】🧹双击卸载 Cocoapods.command](./Cocoapods/%E3%80%90MacOS%E3%80%91%F0%9F%A7%B9%E5%8F%8C%E5%87%BB%E5%8D%B8%E8%BD%BD%20Cocoapods.command/%E3%80%90MacOS%E3%80%91%F0%9F%A7%B9%E5%8F%8C%E5%87%BB%E5%8D%B8%E8%BD%BD%20Cocoapods.command)

> **目的：** 卸载脚本列出的 CocoaPods 安装。

- 阅读影响范围并确认卸载。
- 按已有安装来源处理 gem 或 Homebrew 项。
- 检查 pod 命令和残留位置，后续项目需重新准备依赖工具。


### [【MacOS】🫘JobsPublishPods.command](./Cocoapods/%E3%80%90MacOS%E3%80%91%F0%9F%AB%98JobsPublishPods.command/%E3%80%90MacOS%E3%80%91%F0%9F%AB%98JobsPublishPods.command)

> **目的：** 校验 Pod 发布资料并推送 CocoaPods trunk。

- 读取 podspec、版本与发布环境，检查资料完整性。
- 运行发布前校验，按脚本分支处理账号或依赖问题。
- 执行 trunk push，处理失败并查询发布信息。


### [【MacOS】♻️双击Git（识别子Git） 提交回退.command](./Git%E7%9B%B8%E5%85%B3/%E3%80%90MacOS%E3%80%91%E2%99%BB%EF%B8%8F%E5%8F%8C%E5%87%BBGit%EF%BC%88%E8%AF%86%E5%88%AB%E5%AD%90Git%EF%BC%89%20%E6%8F%90%E4%BA%A4%E5%9B%9E%E9%80%80.command/%E3%80%90MacOS%E3%80%91%E2%99%BB%EF%B8%8F%E5%8F%8C%E5%87%BBGit%EF%BC%88%E8%AF%86%E5%88%AB%E5%AD%90Git%EF%BC%89%20%E6%8F%90%E4%BA%A4%E5%9B%9E%E9%80%80.command)

> **目的：** 为选中的 Git 仓库选择历史目标并执行回退。

- 定位当前仓库或子仓，检查可用的历史记录。
- 选择回退目标与模式，核对即将影响的提交和工作区。
- 按脚本确认后执行回退并打印状态。
  - 如果选择 hard，工作区修改可能丢失；先核对备份和确认提示。


### [【MacOS】♻️双击恢复误删本地Git已储藏的资料.command](./Git%E7%9B%B8%E5%85%B3/%E3%80%90MacOS%E3%80%91%E2%99%BB%EF%B8%8F%E5%8F%8C%E5%87%BB%E6%81%A2%E5%A4%8D%E8%AF%AF%E5%88%A0%E6%9C%AC%E5%9C%B0Git%E5%B7%B2%E5%82%A8%E8%97%8F%E7%9A%84%E8%B5%84%E6%96%99.command/%E3%80%90MacOS%E3%80%91%E2%99%BB%EF%B8%8F%E5%8F%8C%E5%87%BB%E6%81%A2%E5%A4%8D%E8%AF%AF%E5%88%A0%E6%9C%AC%E5%9C%B0Git%E5%B7%B2%E5%82%A8%E8%97%8F%E7%9A%84%E8%B5%84%E6%96%99.command)

> **目的：** 从本地 Git 悬空对象中寻找并恢复误删资料。

- 在目标仓运行对象检查，列出可恢复的提交或文件对象。
- 选择恢复分支或文件名，核对对象内容。
- 按所选方式恢复到工作区或分支，并输出后续审查提示。


### [【MacOS】🔍Git依据提交日志关键字查找.command](./Git%E7%9B%B8%E5%85%B3/%E3%80%90MacOS%E3%80%91%F0%9F%94%8DGit%E4%BE%9D%E6%8D%AE%E6%8F%90%E4%BA%A4%E6%97%A5%E5%BF%97%E5%85%B3%E9%94%AE%E5%AD%97%E6%9F%A5%E6%89%BE.command/%E3%80%90MacOS%E3%80%91%F0%9F%94%8DGit%E4%BE%9D%E6%8D%AE%E6%8F%90%E4%BA%A4%E6%97%A5%E5%BF%97%E5%85%B3%E9%94%AE%E5%AD%97%E6%9F%A5%E6%89%BE.command)

> **目的：** 按提交说明关键词定位历史记录。

- 确定目标 Git 仓库并输入搜索关键词。
- 筛选提交记录，在列表中选择要查看的提交。
- 显示提交号、作者、时间与标题，按提示继续查询。


### [【MacOS】🔍Git寻找分支最近的一次原始切点.command](./Git%E7%9B%B8%E5%85%B3/%E3%80%90MacOS%E3%80%91%F0%9F%94%8DGit%E5%AF%BB%E6%89%BE%E5%88%86%E6%94%AF%E6%9C%80%E8%BF%91%E7%9A%84%E4%B8%80%E6%AC%A1%E5%8E%9F%E5%A7%8B%E5%88%87%E7%82%B9.command/%E3%80%90MacOS%E3%80%91%F0%9F%94%8DGit%E5%AF%BB%E6%89%BE%E5%88%86%E6%94%AF%E6%9C%80%E8%BF%91%E7%9A%84%E4%B8%80%E6%AC%A1%E5%8E%9F%E5%A7%8B%E5%88%87%E7%82%B9.command)

> **目的：** 找出两条分支最近的共同历史起点。

- 确定 Git 仓库并列出可比较的分支。
- 选择两条分支，计算共同祖先或分叉起点。
- 输出提交信息，并按提示继续下一轮比较。


### [【MacOS】⌚️Xcode编译耗时菜单栏.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%E2%8C%9A%EF%B8%8FXcode%E7%BC%96%E8%AF%91%E8%80%97%E6%97%B6%E8%8F%9C%E5%8D%95%E6%A0%8F.command/%E3%80%90MacOS%E3%80%91%E2%8C%9A%EF%B8%8FXcode%E7%BC%96%E8%AF%91%E8%80%97%E6%97%B6%E8%8F%9C%E5%8D%95%E6%A0%8F.command)

> **目的：** 安装或刷新显示 Xcode 编译耗时的菜单栏工具。

- 检查 Swift 编译环境并选择工程 / 安装动作。
- 准备构建记录与 Hook，编译菜单栏 App。
- 安装或刷新工具并启动，后续从构建记录显示耗时。


### [【MacOS】⏬simios.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%E2%8F%ACsimios.command/%E3%80%90MacOS%E3%80%91%E2%8F%ACsimios.command)

> **目的：** 下载并检查 iOS 模拟器运行时。

- 检查 Xcode、许可、磁盘空间和网络条件。
- 列出当前运行时，按交互选择下载目标。
- 执行下载并汇总运行时状态与日志。


### [【MacOS】⏳提取项目中所有的podspec.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%E2%8F%B3%E6%8F%90%E5%8F%96%E9%A1%B9%E7%9B%AE%E4%B8%AD%E6%89%80%E6%9C%89%E7%9A%84podspec.command/%E3%80%90MacOS%E3%80%91%E2%8F%B3%E6%8F%90%E5%8F%96%E9%A1%B9%E7%9B%AE%E4%B8%AD%E6%89%80%E6%9C%89%E7%9A%84podspec.command)

> **目的：** 从工程中收集 podspec 文件。

- 选择工程与输出目录，扫描 podspec 来源。
- 按来源整理并复制匹配文件，保留源文件。
- 打开输出目录，按提示选择是否生成 Zip。


### [【MacOS】⚙️双击为私人账户生成 SSH 密钥（加密手段：RSA 4096 + ED25519 二选一）.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%8F%8C%E5%87%BB%E4%B8%BA%E7%A7%81%E4%BA%BA%E8%B4%A6%E6%88%B7%E7%94%9F%E6%88%90%20SSH%20%E5%AF%86%E9%92%A5%EF%BC%88%E5%8A%A0%E5%AF%86%E6%89%8B%E6%AE%B5%EF%BC%9ARSA%204096%20%2B%20ED25519%20%E4%BA%8C%E9%80%89%E4%B8%80%EF%BC%89.command/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%8F%8C%E5%87%BB%E4%B8%BA%E7%A7%81%E4%BA%BA%E8%B4%A6%E6%88%B7%E7%94%9F%E6%88%90%20SSH%20%E5%AF%86%E9%92%A5%EF%BC%88%E5%8A%A0%E5%AF%86%E6%89%8B%E6%AE%B5%EF%BC%9ARSA%204096%20%2B%20ED25519%20%E4%BA%8C%E9%80%89%E4%B8%80%EF%BC%89.command)

> **目的：** 为个人账号生成并配置 [**SSH**](https://www.openssh.com/) 登录密钥。

- 选择 RSA 4096 或 ED25519，填写邮箱和密钥保存位置。
- 检查既有密钥，按提示生成密钥并配置 SSH config 与 agent。
- 打开公钥设置页面，并按选择验证连接；私钥留在本机。


### [【MacOS】⚙️双击任何来源安装.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%8F%8C%E5%87%BB%E4%BB%BB%E4%BD%95%E6%9D%A5%E6%BA%90%E5%AE%89%E8%A3%85.command/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%8F%8C%E5%87%BB%E4%BB%BB%E4%BD%95%E6%9D%A5%E6%BA%90%E5%AE%89%E8%A3%85.command)

> **目的：** 调整 macOS 应用来源限制并打开安全设置。

- 阅读系统安全设置影响并继续。
- 检查 SIP 状态，执行脚本中的应用来源设置命令。
- 打开系统设置，人工核对“任何来源”是否可用。


### [【MacOS】⚙️双击卸载Homebrew.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%8F%8C%E5%87%BB%E5%8D%B8%E8%BD%BDHomebrew.command/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%8F%8C%E5%87%BB%E5%8D%B8%E8%BD%BDHomebrew.command)

> **目的：** 卸载 Homebrew 并处理脚本列出的残留目录。

- 查看自述与卸载范围，按脚本要求再次确认。
- 运行官方卸载入口，再处理配置的残留路径。
- 核对终端结果；依赖 Homebrew 的工具可能随之不可用。


### [【MacOS】⚙️双击显示隐藏文件.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%8F%8C%E5%87%BB%E6%98%BE%E7%A4%BA%E9%9A%90%E8%97%8F%E6%96%87%E4%BB%B6.command/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%8F%8C%E5%87%BB%E6%98%BE%E7%A4%BA%E9%9A%90%E8%97%8F%E6%96%87%E4%BB%B6.command)

> **目的：** 切换 [**Finder**](https://support.apple.com/guide/mac-help/mchlp2605/mac) 的隐藏文件显示状态。

- 读取 Finder 当前的隐藏文件设置。
- 切换 AppleShowAllFiles 配置。
- 重启 Finder，使新显示状态生效。


### [【MacOS】⚙️备份:恢复 iOS设备支持.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%A4%87%E4%BB%BD%3A%E6%81%A2%E5%A4%8D%20iOS%E8%AE%BE%E5%A4%87%E6%94%AF%E6%8C%81.command/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%A4%87%E4%BB%BD%3A%E6%81%A2%E5%A4%8D%20iOS%E8%AE%BE%E5%A4%87%E6%94%AF%E6%8C%81.command)

> **目的：** 备份或恢复 Xcode 的设备支持目录。

- 检查源码中的 Xcode 路径与备份位置。
- 选择备份或恢复并核对需要使用管理员权限的目录。
- 复制设备支持文件；恢复分支会替换目标目录，先保留原内容。


### [【MacOS】⚙️运行授权.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E8%BF%90%E8%A1%8C%E6%8E%88%E6%9D%83.command/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E8%BF%90%E8%A1%8C%E6%8E%88%E6%9D%83.command)

> **目的：** 为指定脚本或目录中的入口补执行权限。

- 阅读影响范围，输入或拖入待授权目标。
- 选择单项或递归扫描范围并执行 chmod。
  - 如果选择递归，会处理该目标下匹配的脚本；先确认目录范围。
- 输出成功与失败结果，按提示继续或退出。


### [【MacOS】✍️IPA免编译重签.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%E2%9C%8D%EF%B8%8FIPA%E5%85%8D%E7%BC%96%E8%AF%91%E9%87%8D%E7%AD%BE.command/%E3%80%90MacOS%E3%80%91%E2%9C%8D%EF%B8%8FIPA%E5%85%8D%E7%BC%96%E8%AF%91%E9%87%8D%E7%AD%BE.command)

> **目的：** 用明确签名材料重签 IPA 并按选择安装设备。

- 选择 IPA、设备、签名身份和描述文件，先检查材料。
- 解包并检查加密或不支持的嵌套代码，生成授权与签名计划。
- 按嵌套顺序签名，回读验证后重新打包；再按提示决定设备安装。


### [【MacOS】🌞颜色格式的转换.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%F0%9F%8C%9E%E9%A2%9C%E8%89%B2%E6%A0%BC%E5%BC%8F%E7%9A%84%E8%BD%AC%E6%8D%A2.command/%E3%80%90MacOS%E3%80%91%F0%9F%8C%9E%E9%A2%9C%E8%89%B2%E6%A0%BC%E5%BC%8F%E7%9A%84%E8%BD%AC%E6%8D%A2.command)

> **目的：** 在常见颜色数值表示之间转换。

- 输入颜色值或使用命令行参数。
- 识别十六进制、RGB 等受支持格式并计算对应表示。
- 输出转换结果，继续输入或按退出指令结束。


### [【MacOS】🎈切换Shell.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%F0%9F%8E%88%E5%88%87%E6%8D%A2Shell.command/%E3%80%90MacOS%E3%80%91%F0%9F%8E%88%E5%88%87%E6%8D%A2Shell.command)

> **目的：** 从系统允许的 Shell 中选择并切换登录 Shell。

- 检查菜单工具并读取可用 Shell 列表。
- 选择目标 Shell，核对路径。
- 执行切换并显示结果；新终端会使用新的登录 Shell。


### [【MacOS】🎈切换生成 iOS 的 Web Clip（桌面网页快捷方式）.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%F0%9F%8E%88%E5%88%87%E6%8D%A2%E7%94%9F%E6%88%90%20iOS%20%E7%9A%84%20Web%20Clip%EF%BC%88%E6%A1%8C%E9%9D%A2%E7%BD%91%E9%A1%B5%E5%BF%AB%E6%8D%B7%E6%96%B9%E5%BC%8F%EF%BC%89.command/%E3%80%90MacOS%E3%80%91%F0%9F%8E%88%E5%88%87%E6%8D%A2%E7%94%9F%E6%88%90%20iOS%20%E7%9A%84%20Web%20Clip%EF%BC%88%E6%A1%8C%E9%9D%A2%E7%BD%91%E9%A1%B5%E5%BF%AB%E6%8D%B7%E6%96%B9%E5%BC%8F%EF%BC%89.command)

> **目的：** 生成 iOS 桌面网页快捷方式配置。

- 输入网页地址、显示名与可选图标。
- 处理图标并生成 Web Clip 的配置文件。
- 在 Finder 定位产物，后续由设备安装配置。


### [【MacOS】🎈双击打开已实例化的iOS模拟器.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%F0%9F%8E%88%E5%8F%8C%E5%87%BB%E6%89%93%E5%BC%80%E5%B7%B2%E5%AE%9E%E4%BE%8B%E5%8C%96%E7%9A%84iOS%E6%A8%A1%E6%8B%9F%E5%99%A8.command/%E3%80%90MacOS%E3%80%91%F0%9F%8E%88%E5%8F%8C%E5%87%BB%E6%89%93%E5%BC%80%E5%B7%B2%E5%AE%9E%E4%BE%8B%E5%8C%96%E7%9A%84iOS%E6%A8%A1%E6%8B%9F%E5%99%A8.command)

> **目的：** 打开已有的 iOS 模拟器应用。

- 阅读入口自述并继续。
- 调用系统 Simulator 应用。
- 在模拟器中选择或使用已经存在的设备。


### [【MacOS】🎈生成iOS.AppIcon.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%F0%9F%8E%88%E7%94%9F%E6%88%90iOS.AppIcon.command/%E3%80%90MacOS%E3%80%91%F0%9F%8E%88%E7%94%9F%E6%88%90iOS.AppIcon.command)

> **目的：** 将输入图片生成 iOS AppIcon 资源。

- 选择源图并确定输出目录。
- 按图标尺寸缩放图片，写入资源目录与 Contents.json。
- 清理临时图并在 Finder 中定位结果。


### [【MacOS】📱双击初始化iOS模拟器.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%F0%9F%93%B1%E5%8F%8C%E5%87%BB%E5%88%9D%E5%A7%8B%E5%8C%96iOS%E6%A8%A1%E6%8B%9F%E5%99%A8.command/%E3%80%90MacOS%E3%80%91%F0%9F%93%B1%E5%8F%8C%E5%87%BB%E5%88%9D%E5%A7%8B%E5%8C%96iOS%E6%A8%A1%E6%8B%9F%E5%99%A8.command)

> **目的：** 选择系统运行时并创建可用的 iOS 模拟器。

- 检查模拟器后台状态和菜单工具。
- 选择可用运行时、设备类型与设备名称。
- 创建并启动模拟器，等待就绪后按提示继续创建或退出。


### [【MacOS】📹双击制作iOS模拟器录屏Gif.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%F0%9F%93%B9%E5%8F%8C%E5%87%BB%E5%88%B6%E4%BD%9CiOS%E6%A8%A1%E6%8B%9F%E5%99%A8%E5%BD%95%E5%B1%8FGif.command/%E3%80%90MacOS%E3%80%91%F0%9F%93%B9%E5%8F%8C%E5%87%BB%E5%88%B6%E4%BD%9CiOS%E6%A8%A1%E6%8B%9F%E5%99%A8%E5%BD%95%E5%B1%8FGif.command)

> **目的：** 录制选定 iOS 模拟器并按需生成 GIF。

- 检查录制与转换工具，选择模拟器并等待启动。
- 开始录制，按提示停止并保存视频。
- 选择是否转换 GIF，填写尺寸与帧率后转换。
  - 如果不转换，保留已生成的视频。
- 打开录制或转换产物。


### [【MacOS】🔍查询Xcode工程依赖关系.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%F0%9F%94%8D%E6%9F%A5%E8%AF%A2Xcode%E5%B7%A5%E7%A8%8B%E4%BE%9D%E8%B5%96%E5%85%B3%E7%B3%BB.command/%E3%80%90MacOS%E3%80%91%F0%9F%94%8D%E6%9F%A5%E8%AF%A2Xcode%E5%B7%A5%E7%A8%8B%E4%BE%9D%E8%B5%96%E5%85%B3%E7%B3%BB.command)

> **目的：** 分析 Xcode 工程依赖并输出报告与关系图。

- 定位工程，检查 [**Python**](https://www.python.org/) 与图形分析依赖。
- 读取工程和相关依赖配置，生成依赖关系数据。
- 导出 Markdown / 图形结果并按提示打开。


### [【MacOS】🚪双击打开SPM的下载文件夹.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%F0%9F%9A%AA%E5%8F%8C%E5%87%BB%E6%89%93%E5%BC%80SPM%E7%9A%84%E4%B8%8B%E8%BD%BD%E6%96%87%E4%BB%B6%E5%A4%B9.command/%E3%80%90MacOS%E3%80%91%F0%9F%9A%AA%E5%8F%8C%E5%87%BB%E6%89%93%E5%BC%80SPM%E7%9A%84%E4%B8%8B%E8%BD%BD%E6%96%87%E4%BB%B6%E5%A4%B9.command)

> **目的：** 定位当前工程的 SPM checkout 缓存。

- 在当前工程查找 .xcodeproj 并取得工程名。
- 匹配对应 DerivedData 目录和 SourcePackages/checkouts。
- 打开匹配目录；没有匹配缓存时按提示先解析依赖。


### [【MacOS】🚪双击打开系统的环境配置文件.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%F0%9F%9A%AA%E5%8F%8C%E5%87%BB%E6%89%93%E5%BC%80%E7%B3%BB%E7%BB%9F%E7%9A%84%E7%8E%AF%E5%A2%83%E9%85%8D%E7%BD%AE%E6%96%87%E4%BB%B6.command/%E3%80%90MacOS%E3%80%91%F0%9F%9A%AA%E5%8F%8C%E5%87%BB%E6%89%93%E5%BC%80%E7%B3%BB%E7%BB%9F%E7%9A%84%E7%8E%AF%E5%A2%83%E9%85%8D%E7%BD%AE%E6%96%87%E4%BB%B6.command)

> **目的：** 打开用户的常见 Shell 环境文件。

- 确认当前用户与脚本自述。
- 依次打开 .bash_profile、.bashrc 和 .zshrc。
- 在编辑器中自行检查或修改，脚本不会替你审核配置内容。


### [【MacOS】🧩iOS工程改名工具.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%F0%9F%A7%A9iOS%E5%B7%A5%E7%A8%8B%E6%94%B9%E5%90%8D%E5%B7%A5%E5%85%B7.command/%E3%80%90MacOS%E3%80%91%F0%9F%A7%A9iOS%E5%B7%A5%E7%A8%8B%E6%94%B9%E5%90%8D%E5%B7%A5%E5%85%B7.command)

> **目的：** 将工程按指定名称原地改名或复制开版。

- 填写工程目录、旧名、新名与运行模式。
- 按模式准备工作副本，并选择是否 Zip 备份。
- 替换工程文本与路径、重命名根目录，再按选择处理 Pods 与 workspace。


### [【MacOS】🧮双击统计MD文件的有效行数.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%F0%9F%A7%AE%E5%8F%8C%E5%87%BB%E7%BB%9F%E8%AE%A1MD%E6%96%87%E4%BB%B6%E7%9A%84%E6%9C%89%E6%95%88%E8%A1%8C%E6%95%B0.command/%E3%80%90MacOS%E3%80%91%F0%9F%A7%AE%E5%8F%8C%E5%87%BB%E7%BB%9F%E8%AE%A1MD%E6%96%87%E4%BB%B6%E7%9A%84%E6%9C%89%E6%95%88%E8%A1%8C%E6%95%B0.command)

> **目的：** 安装统计 Markdown 有效行数的提交钩子。

- 确认脚本位于目标 Git 项目，检查 .git。
- 写入 pre-commit：提交时扫描 Markdown、计算有效行数并更新统计内容。
- 给钩子补执行权限并显示安装结果；后续提交会触发该钩子。


### [【MacOS】🧮文件数统计.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%F0%9F%A7%AE%E6%96%87%E4%BB%B6%E6%95%B0%E7%BB%9F%E8%AE%A1.command/%E3%80%90MacOS%E3%80%91%F0%9F%A7%AE%E6%96%87%E4%BB%B6%E6%95%B0%E7%BB%9F%E8%AE%A1.command)

> **目的：** 统计目标目录中的文件数量。

- 选择待统计目录并检查路径。
- 递归遍历目录，计算各级文件数量。
- 输出统计结果，按提示继续或退出。


### [【MacOS】🧹双击清理iOS缓存.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%F0%9F%A7%B9%E5%8F%8C%E5%87%BB%E6%B8%85%E7%90%86iOS%E7%BC%93%E5%AD%98.command/%E3%80%90MacOS%E3%80%91%F0%9F%A7%B9%E5%8F%8C%E5%87%BB%E6%B8%85%E7%90%86iOS%E7%BC%93%E5%AD%98.command)

> **目的：** 按项目类型清理 iOS / Flutter 的依赖和构建缓存。

- 定位脚本对应工程，阅读清理范围并确认。
- 识别 Flutter 或原生 iOS 工程，执行对应缓存清理。
- 显示结果；被删除的依赖和构建产物需要后续重新生成。


### [【MacOS】🫡CodeX+UnderstandAnything.command](./%E5%85%B6%E4%BB%96/%E3%80%90MacOS%E3%80%91%F0%9F%AB%A1CodeX%2BUnderstandAnything.command/%E3%80%90MacOS%E3%80%91%F0%9F%AB%A1CodeX%2BUnderstandAnything.command)

> **目的：** 为 iOS 工程准备 [**Codex**](https://openai.com/codex) 与 [**Understand Anything**](https://github.com/Lum1104/Understand-Anything) 使用入口。

- 检查内嵌运行时并定位 Xcode 工程。
- 检查 Codex CLI，按选择安装或更新 Understand Anything。
- 验证技能入口，显示使用方法并询问是否启动 Codex。


### [【MacOS】📦Fastfile.command](./%E6%89%93%E5%8C%85%E7%9B%B8%E5%85%B3/%E3%80%90MacOS%E3%80%91%F0%9F%93%A6Fastfile.command/%E3%80%90MacOS%E3%80%91%F0%9F%93%A6Fastfile.command)

> **目的：** 为检测到的工程准备或打开 [**fastlane**](https://fastlane.tools/) 的 Fastfile。

- 识别工程类型，检查菜单工具与 fastlane。
- 查找现有 Fastfile，缺失时按脚本模板创建。
- 选择编辑器或 Finder 打开目标文件，后续打包使用其中配置。


### [【MacOS】📦双击自动生成ipa文件.command](./%E6%89%93%E5%8C%85%E7%9B%B8%E5%85%B3/%E3%80%90MacOS%E3%80%91%F0%9F%93%A6%E5%8F%8C%E5%87%BB%E8%87%AA%E5%8A%A8%E7%94%9F%E6%88%90ipa%E6%96%87%E4%BB%B6.command/%E3%80%90MacOS%E3%80%91%F0%9F%93%A6%E5%8F%8C%E5%87%BB%E8%87%AA%E5%8A%A8%E7%94%9F%E6%88%90ipa%E6%96%87%E4%BB%B6.command)

> **目的：** 把现有真机 App 打包为 IPA。

- 定位目标工程与已有 iPhoneOS App，排除模拟器或不匹配产物。
- 在独立 Payload 目录复制 App 并压缩为 IPA。
- 检查输出并打开位置；此入口以已有 App 为基础。


### [【MacOS】📦生成JobsPod二进制打包器.command](./%E6%89%93%E5%8C%85%E7%9B%B8%E5%85%B3/%E3%80%90MacOS%E3%80%91%F0%9F%93%A6%E7%94%9F%E6%88%90JobsPod%E4%BA%8C%E8%BF%9B%E5%88%B6%E6%89%93%E5%8C%85%E5%99%A8.command/%E3%80%90MacOS%E3%80%91%F0%9F%93%A6%E7%94%9F%E6%88%90JobsPod%E4%BA%8C%E8%BF%9B%E5%88%B6%E6%89%93%E5%8C%85%E5%99%A8.command)

> **目的：** 编译并安装 JobsPod 二进制打包器原生应用。

- 检查 Xcode、swiftc 和随包源码。
- 在暂存目录编译 App，完成临时签名与 Bundle 验证。
- 安装验证后的应用，清理暂存并启动 GUI。


### [【MacOS】⏬下载配置系统环境变量.command](./%E9%85%8D%E7%BD%AE%E7%9B%B8%E5%85%B3/%E3%80%90MacOS%E3%80%91%E2%8F%AC%E4%B8%8B%E8%BD%BD%E9%85%8D%E7%BD%AE%E7%B3%BB%E7%BB%9F%E7%8E%AF%E5%A2%83%E5%8F%98%E9%87%8F.command/%E3%80%90MacOS%E3%80%91%E2%8F%AC%E4%B8%8B%E8%BD%BD%E9%85%8D%E7%BD%AE%E7%B3%BB%E7%BB%9F%E7%8E%AF%E5%A2%83%E5%8F%98%E9%87%8F.command)

> **目的：** 下载脚本指定的系统环境配置仓库。

- 读取源码中的仓库地址和目标目录。
- 检查已有目标并按提示决定是否继续。
  - 如果确认替换，会删除该目标旧目录；先保留自有内容。
- 克隆配置仓库并输出后续配置位置。


### [【MacOS】⏬双击下载SourceTree效率脚本.command](./%E9%85%8D%E7%BD%AE%E7%9B%B8%E5%85%B3/%E3%80%90MacOS%E3%80%91%E2%8F%AC%E5%8F%8C%E5%87%BB%E4%B8%8B%E8%BD%BDSourceTree%E6%95%88%E7%8E%87%E8%84%9A%E6%9C%AC.command/%E3%80%90MacOS%E3%80%91%E2%8F%AC%E5%8F%8C%E5%87%BB%E4%B8%8B%E8%BD%BDSourceTree%E6%95%88%E7%8E%87%E8%84%9A%E6%9C%AC.command)

> **目的：** 取得可本地运行的 [**Sourcetree**](https://www.sourcetreeapp.com/) 脚本库。

- 检查 Git 和脚本声明的下载位置。
- 按提示处理已有目标，再从配置的远端克隆脚本库。
- 给下载入口补执行权限并打开输出目录。


### [【MacOS】⚙️双击安装JobsCodeSnippets.command](./%E9%85%8D%E7%BD%AE%E7%9B%B8%E5%85%B3/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%8F%8C%E5%87%BB%E5%AE%89%E8%A3%85JobsCodeSnippets.command/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%8F%8C%E5%87%BB%E5%AE%89%E8%A3%85JobsCodeSnippets.command)

> **目的：** 将 Jobs 代码片段安装到 Xcode 用户目录。

- 检查下载源和 Xcode CodeSnippets 目标目录。
- 下载代码片段并按提示处理目标既有内容。
- 复制或移动片段到目标位置，打开目录确认。


### [【MacOS】⚙️双击安装quicktype.command](./%E9%85%8D%E7%BD%AE%E7%9B%B8%E5%85%B3/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%8F%8C%E5%87%BB%E5%AE%89%E8%A3%85quicktype.command/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%8F%8C%E5%87%BB%E5%AE%89%E8%A3%85quicktype.command)

> **目的：** 安装命令行 quicktype 代码生成工具。

- 检查 Homebrew、[**Node.js**](https://nodejs.org/) 与 [**npm**](https://www.npmjs.com/)。
- 检测全局 quicktype，缺失时执行源码声明的 npm 安装。
- 校验命令可用并输出后续用法。


### [【MacOS】⚙️安装代码地图CodeGraph.command](./%E9%85%8D%E7%BD%AE%E7%9B%B8%E5%85%B3/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%AE%89%E8%A3%85%E4%BB%A3%E7%A0%81%E5%9C%B0%E5%9B%BECodeGraph.command/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%AE%89%E8%A3%85%E4%BB%A3%E7%A0%81%E5%9C%B0%E5%9B%BECodeGraph.command)

> **目的：** 安装或复用可验证工作的 CodeGraph。

- 逐层检查 Homebrew、Node.js、npm 和下载通道。
- 复用健康安装，按确认安装或更新官方包。
- 用隔离样例验证实际建图，再登记用户 PATH 并显示结果。


### [【MacOS】🎈双击打开系统配置文件.command](./%E9%85%8D%E7%BD%AE%E7%9B%B8%E5%85%B3/%E3%80%90MacOS%E3%80%91%F0%9F%8E%88%E5%8F%8C%E5%87%BB%E6%89%93%E5%BC%80%E7%B3%BB%E7%BB%9F%E9%85%8D%E7%BD%AE%E6%96%87%E4%BB%B6.command/%E3%80%90MacOS%E3%80%91%F0%9F%8E%88%E5%8F%8C%E5%87%BB%E6%89%93%E5%BC%80%E7%B3%BB%E7%BB%9F%E9%85%8D%E7%BD%AE%E6%96%87%E4%BB%B6.command)

> **目的：** 选择并打开用户环境配置文件。

- 检查菜单工具，列出支持的配置文件。
- 选择要查看的文件并调用默认编辑器打开。
- 按脚本逻辑 source 所选配置，让其中命令在当前进程执行。


<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
