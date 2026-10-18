# `CocoaPods 网络适配`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、实际行为与边界](#jobs-toc-heading-2)
- [二、运行与开关](#jobs-toc-heading-3)
- [三、日志与迁移](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

本包为 Jobs Pod 二进制打包器 生成的临时宿主与消费 Demo 提供 [**CocoaPods**](https://cocoapods.org/) 安装网络环境。生成器将完整运行包复制到各工程的 `ScriptsByPods`；生成的 `Podfile` 按“网络适配 → 已审核源码归档回退 → 公共 Specs 选择”同步加载，不依赖其它仓库的路径。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、实际行为与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 入口 | 实际行为 |
| --- | --- |
| `pod install` / `pod update` | 验证明确设置的已有代理、当前链路及已启用系统手工代理；候选均不可用则保留原环境并告警 |
| `pod ipc` 等查询 | 不发送网络探测，不注册归档回退 |
| `.command` 独立诊断 | 阅读内置自述并回车后只做诊断，不安装依赖 |

代理仅作用于本次安装进程及子进程，退出时恢复；不修改系统代理、全局 [**Git**](https://git-scm.com/) 配置或 shell profile，不执行 PAC、不猜端口、不安装代理软件。当前链路以 [**GitHub**](https://github.com/) 上 `andreamazz/AMPopTip` 的 `4.12.0` tag 验证；默认单轮预算 `6` 秒，显式代理、原链路和系统候选最多三轮。

官方归档回退只覆盖已审核的 `AMPopTip 4.12.0`、仓库 `andreamazz/AMPopTip` 与精确提交 `db495eea0747a3493ca8b3c737d037c0090973db`。原 Git 下载发生连接、超时或 TLS 等网络失败时才尝试官方 codeload。未知版本、其它仓库、分支、子模块、准备脚本、认证或校验错误保留原下载器行为；不改 Pod 版本、源声明、锁参数或关闭 TLS 校验。

归档验证基线为 CocoaPods `1.17.0` / downloader `2.1`；不兼容时告警并跳过。链路探测成功不代表完整安装成功，Git 与归档域名都受限仍可能失败。私有依赖保留原声明，HTTP 环境代理会被本次所有下载子进程继承。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、运行与开关 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

生成工程正常执行 `pod install` 即会挂载；打包器仍使用 `--no-repo-update`。独立诊断在本 README 所在目录运行：

```zsh
/bin/zsh './【MacOS】🌐CocoaPods网络适配.command'
```

| 环境变量 | 默认值 | 含义 |
| --- | --- | --- |
| `JOBS_POD_NETWORK_ADAPT` | 开启 | `0` 关闭代理探测与切换 |
| `JOBS_POD_NETWORK_PROBE_TIMEOUT` | `6` | 单轮秒数，`1..30` |
| `JOBS_POD_PROXY_URL` | 未设置 | 已配置代理 URL，验证通过才使用；勿提交带认证信息的地址 |
| `JOBS_POD_GITHUB_ARCHIVE_FALLBACK` | 开启 | `0` 关闭已审核归档回退 |

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、日志与迁移 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

自动挂载摘要进入打包器原有任务日志；手动执行时显示在终端。独立诊断日志为系统临时目录中的 `jobs-cocoapods-network.log`，确认后覆盖，不输出代理地址或凭据。公共 Specs 包另记同工程的源探测日志。

迁移生成的宿主或消费工程时，保留 `Podfile` 与整个 `ScriptsByPods`。仅复制 Podfile 会告警并回到原网络和官方 CDN。只迁移这个脚本包不会自动改变别的工程，需由对应 Podfile 明确挂载。

隔离生成回归位于生成器 `JobsPodBinaryBuilder/Tests/network_generation_test.rb`，不运行真实安装、GUI 或 Xcode 构建；其通过结果不替代受限设备的真实安装验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
