# `【MacOS】⬆️Pod_Update.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

本入口在识别出的项目目录调用 [**CocoaPods**](https://cocoapods.org/)，由目标 `Podfile` 自己加载网络适配与公共 Specs 选源；包装器不再使用旧镜像缓存改写全局源。

| 原行为 | 当前调用 | 实际边界 |
| --- | --- | --- |
| 更新前应用旧镜像缓存；Intel 分支另起全仓 repo update | `pod update`，只启动一次安装 / 更新进程 | 网络探测、Specs 选择和后续下载在同一个 pod 进程中完成；目标 Podfile 必须已接入相应脚本包 |

## 一、用途与项目路径 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

主脚本是 [【MacOS】⬆️Pod_Update.command](<./【MacOS】⬆️Pod_Update.command>)。沿用原来的定位方式，以脚本自身所在目录识别原生项目的 `Podfile`，或 Flutter 项目的 `ios/Podfile`；不要将启动时的终端目录当作脚本已经接受的目标参数。请在实际工程对应位置使用入口，或使用工程已有的手动安装脚本。

保留 Apple Silicon 的 Rosetta 分支；Intel 分支仍由原更新交互决定是否执行，回车跳过、非空输入执行。更新成功后按原规则处理工作空间桌面快捷方式；更新失败返回非零，不打印更新完成。

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
/bin/zsh './【MacOS】⬆️Pod_Update.command'
```

需要现有可用的 zsh、CocoaPods 及其 Ruby 环境；本项目安装 / 更新路径不自动修复全局工具链。网络失败仍可能导致安装失败，不能将发现接入文件或返回某个 Specs 地址视为安装成功。

## 四、日志与迁移 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

包装器日志保存在系统临时目录中的 `【MacOS】⬆️Pod_Update.log`，终端会输出业务日志。目标工程的网络与 Specs 摘要继续由其 Podfile 模块输出；完整 CocoaPods 输出仍以终端为准。迁移本包装器不等于迁移工程网络能力，目标 Podfile 与两个完整脚本包需要一起保留。

## 五、验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```zsh
/bin/zsh -n './【MacOS】⬆️Pod_Update.command'
/usr/bin/ruby './Tests/cocoapods_route_test.rb'
```

隔离测试只提取真实安装 / 更新函数，以假 pod、arch 和 uname 验证调用目录、一次调用、参数、架构分支、未知工程提示、目标文件保持和失败传播，不执行全脚本的清理、权限变更或工具链安装。已进行语法与隔离验证，未对真实工程执行安装、更新或构建。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
