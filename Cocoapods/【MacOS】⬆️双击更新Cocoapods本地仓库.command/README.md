# `【MacOS】⬆️双击更新Cocoapods本地仓库.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

本入口在识别出的项目目录调用 [**CocoaPods**](https://cocoapods.org/)，由目标 `Podfile` 自己加载网络适配与公共 Specs 选源；包装器不再使用旧镜像缓存改写全局源。

| 原行为 | 当前调用 | 实际边界 |
| --- | --- | --- |
| 先删除 workspace / Pods / lock，再依次执行 install、setup 与无参数全仓 repo update | `pod install --repo-update`，只启动一次安装 / 更新进程 | 网络探测、Specs 选择和后续下载在同一个 pod 进程中完成；目标 Podfile 必须已接入相应脚本包 |

## 一、用途与项目路径 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

主脚本是 [【MacOS】⬆️双击更新Cocoapods本地仓库.command](<./【MacOS】⬆️双击更新Cocoapods本地仓库.command>)。沿用原来的定位方式，以脚本自身所在目录识别原生项目的 `Podfile`，或 Flutter 项目的 `ios/Podfile`；不要将启动时的终端目录当作脚本已经接受的目标参数。请在实际工程对应位置使用入口，或使用工程已有的手动安装脚本。

保留原有项目识别与当前目录文件执行权限设置，随后执行同一次安装与规格刷新。现有 `.xcworkspace`、`Pods` 和 `Podfile.lock` 保留，供 CocoaPods 复用锁定版本与安装缓存，并由正常安装流程维护；入口不主动删除或清空这些路径。安装失败返回非零，不继续宣称成功。

## 二、网络适配边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

运行前只检查目标工程是否具有以下入口与文件，不执行探测脚本、不注入代码，也不修改任何未知工程的 Podfile：

- `Podfile` 中调用 `JobsCocoaPodsNetwork.apply!` 和 `JobsCocoaPodsSource.apply!`。
- `ScriptsByPods/【MacOS】🌐CocoaPods网络适配.command/` 中的网络与归档 Ruby 模块。
- `ScriptsByPods/【MacOS】🌐CocoaPods源自动选择.command/jobs_cocoapods_source.rb`。

文件与调用标记齐备时输出已发现接入入口；实际链路仍由 Podfile 加载的实现验证。未确认接入时明确告警后继续原生 CocoaPods：本包装器不自带选路，不会假装网络已恢复。未知、第三方工程保持自己的配置。

已接入工程由同次 pod 进程执行真实网络验证、Specs 选择及下载；当前代理环境不会经由已退出的 Ruby 子进程传回父 Shell，因此不再另起 `pod setup` 或无参数 `pod repo update`。包装器不读写 `.cocoapods_mirror_config`，也不删除或重建全局 `trunk`；保留既有私有源与其它全局源配置。项目内部网络模块的开关、超时、可用代理和归档白名单以目标工程说明为准。

## 三、运行方式与交互 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

脚本保留原内置自述和回车确认；按 `Ctrl+C` 取消。确认前先核对用途和项目路径，确认后才进入原业务流程；脚本不读取或展示本 README。

```zsh
/bin/zsh './【MacOS】⬆️双击更新Cocoapods本地仓库.command'
```

需要现有可用的 zsh、CocoaPods 及其 Ruby 环境；本项目安装 / 更新路径不自动修复全局工具链。网络失败仍可能导致安装失败，不能将发现接入文件或返回某个 Specs 地址视为安装成功。

## 四、日志与迁移 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

包装器日志保存在系统临时目录中的 `【MacOS】⬆️双击更新Cocoapods本地仓库.log`，终端会输出业务日志。目标工程的网络与 Specs 摘要继续由其 Podfile 模块输出；完整 CocoaPods 输出仍以终端为准。迁移本包装器不等于迁移工程网络能力，目标 Podfile 与两个完整脚本包需要一起保留。

## 五、验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```zsh
/bin/zsh -n './【MacOS】⬆️双击更新Cocoapods本地仓库.command'
/usr/bin/ruby './Tests/cocoapods_route_test.rb'
```

隔离测试提取真实安装函数与主流程，以假 pod、arch、uname 及权限入口替身验证调用目录、一次调用、参数、未知工程提示和失败传播，并放置已有锁文件 / Pods / 工作空间，断言正常与失败路径都不调用 rm 或清理函数，文件内容保持。测试不执行真实权限变更、工具链安装或依赖下载。已进行语法与隔离验证，未对真实工程执行安装、更新或构建。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
