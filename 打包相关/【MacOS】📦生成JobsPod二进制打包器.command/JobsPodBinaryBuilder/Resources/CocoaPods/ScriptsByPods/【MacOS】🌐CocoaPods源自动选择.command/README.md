# `CocoaPods 公共源自动选择`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

本包随 Jobs Pod 二进制打包器复制到临时宿主与消费 Demo，由生成的 `Podfile` 在[网络适配](<../【MacOS】🌐CocoaPods网络适配.command/README.md>)之后同步加载。[**CocoaPods**](https://cocoapods.org/) 会按本次网络测试结果选择官方 CDN 或 [**GitHub Specs**](https://github.com/CocoaPods/Specs)，后续源码下载继续使用同一本次进程环境。

## 一、选择规则 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 场景 | 结果 |
| --- | --- |
| 真实 `pod install` / `pod update` | 测试两源中同一个锁定 podspec；Git 源额外验证仓库协议；按有效响应和耗时选择 |
| 查询命令 | 不联网，根据现有锁及可读 Git 缓存回退，否则使用官方 CDN |
| 两源不可用或模块异常 | 明确告警并回用可用缓存源或 CDN 默认值，不删除锁或 Pods、不升级依赖 |

选择只映射官方公共源，不替换私有源、依赖版本或校验值。锁来源适配仅作用于本次 CocoaPods 锁对象，正常安装成功后再由 CocoaPods 写锁文件，严格部署比较保持原样。打包器的 `--no-repo-update` 继续保留，不因探测额外执行仓库更新。

## 二、运行与日志 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

生成工程正常执行 `pod install` 无需另设命令；独立诊断从本目录运行：

```zsh
/bin/zsh './【MacOS】🌐CocoaPods源自动选择.command'
```

| 环境变量 | 默认值 | 含义 |
| --- | --- | --- |
| `JOBS_SPECS_SOURCE` | `auto` | `auto` / `cdn` / `git` |
| `JOBS_SPECS_PROBE_TIMEOUT` | `8` | 单源探测秒数，`1..30` |
| `JOBS_SPECS_CONNECT_TIMEOUT` | `2` | 连接秒数，不能大于单源预算 |

每个生成工程独立写系统临时目录中的 `jobs-cocoapods-source-<工程路径摘要>.log`；诊断不运行安装。迁移工程需同时保留生成的 `Podfile` 和两个 `ScriptsByPods` 包；选源成功不表示源码下载或工程集成已成功。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
