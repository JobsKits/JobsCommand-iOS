# 安装代码地图 [**CodeGraph**](https://github.com/colbymchenry/codegraph)

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、运行与结果速览](#jobs-toc-heading-2)
- [二、完整依赖链体检](#jobs-toc-heading-3)
- [三、交互与安装位置](#jobs-toc-heading-4)
- [四、配置、日志与边界](#jobs-toc-heading-5)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

逐层体检完整依赖链，安装或更新官方 CLI，再通过 `codemap` 给项目构建 `.codegraph`。安装器仅在系统临时目录做建图自检，不为业务仓库建图，也不调用会修改 AI 工具配置的 `codegraph install`。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与结果速览 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在本目录执行，或双击同名脚本：

```shell
/bin/zsh ./【MacOS】⚙️安装代码地图CodeGraph.command
```

| 入口 | 实际行为 |
| --- | --- |
| 此安装器 | 体检依赖链、安装或复用 CLI、临时样例验证建图 |
| 新系统配置的 CodeGraph 阶段 | 调用此安装器，保留相同体检与确认 |
| `codemap` | 构建当前终端目录的代码地图 |
| `codemap "./项目目录"` | 指定目录，支持手工输入或拖入 |
| `codemap "./项目 一" "./项目二"` | 逐个处理多个目录 |

命令注册由 [codemap 模块](../../../JobsConfigOS/🌍JobsMacEnvVarConfigs/scripts/codemap.command/README.md)负责。新系统入口见[同名目录 README](../../../JobsConfigOS/【MacOS】🆕新系统配置.command/README.md)。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、完整依赖链体检 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 层级 | 健康检查 | 缺失或损坏时 |
| --- | --- | --- |
| 系统工具 | macOS、普通用户、bash / curl / git 可执行，CLT 开发目录及 clang / make 版本 | CLT 可确认打开系统安装窗口，完成后须重跑；其它基础异常停止 |
| [**Homebrew**](https://brew.sh/) | 版本、真实前缀、shellenv、config、doctor | 按用户选择安装位置并复检；doctor 非零停止下游 |
| [**Node.js**](https://nodejs.org) | 独立检查版本，实际执行 JavaScript、加载内置模块 | 先复用 PATH 或 Brew 的健康成套环境；全不可用时安装或重装 node@24 |
| [**npm**](https://docs.npmjs.com/) | 独立检查版本、配置前缀、全局根目录、官方 registry ping | 本地损坏随 Node 定点修复；网络失败停止，不关闭 TLS 校验 |
| CodeGraph | 官方 scoped 包身份、版本、init / index 帮助，真实样例建图和数据库完整状态 | 明确确认后安装官方包，再次执行同样检查；失败停止 |

每层都验证真实可执行性，不能只判断命令存在。修复最多一次，复检失败不继续下游。

本脚本的 Node 健康基线为 20 及以上，缺失时选 Brew node@24；这是脚本策略，并非当前 CodeGraph npm 制品的版本要求。当前官方发行自带平台运行时和解析组件，不引入无实际需要的 Python / Rust 编译链。参见[官方安装说明](https://github.com/colbymchenry/codegraph#readme)。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、交互与安装位置 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

1、先显示内置自述，按回车确认后才写日志和检查；无交互终端停止，Ctrl+C 可取消。

2、健康 Homebrew 直接复用。需要安装时，精确大写 `YES` 选系统标准位置，其它输入或回车选当前用户的 `.local/homebrew`。官方系统安装器处理授权，不预先索取密码；失败不切换路线。自定义前缀限制以 [Homebrew 官方文档](https://docs.brew.sh/Installation)为准，最终仍须通过 doctor。

3、Homebrew 更新可选：回车跳过，任意字符执行 `brew update`；不全员升级、不自动清理。缺失依赖安装或损坏修复也须主动输入；回车取消必需步骤并停止。

4、健康 Node/npm 直接复用，不强制改版本；全不可用才用 Brew node@24 安装或修复。不使用 `brew link --force`。

5、健康官方 npm 安装可复用。全新安装或选择更新时，使用当前用户的 `.local/share/jobs-codegraph` 独立 npm 前缀，保留原全局安装，不运行 `sudo npm`。

实际安装命令结构如下，路径变量由脚本解析：

```shell
"$NPM_BIN" install \
  --global \
  --prefix "$CODEGRAPH_PREFIX" \
  --registry https://registry.npmjs.org/ \
  --include=optional \
  --engine-strict \
  --fetch-retries=1 \
  --fetch-timeout=60000 \
  @colbymchenry/codegraph@latest
```

平台二进制在可选依赖中，不能 `--omit=optional`；包名必须是 `@colbymchenry/codegraph`，不安装其它同名包。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、配置、日志与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 真实建图复检通过后，在当前用户 zsh 登录配置中幂等维护 `Jobs CodeGraph environment` 标记块，把已验证的 Node 和 CLI 目录加入 PATH；这会影响新终端中 Node 的优先选择。保留其它内容，修改前创建时间戳备份，保留符号链接。
- 新装 Homebrew 时另维护 `Jobs Homebrew shellenv` 标记块；当前脚本立即刷新会话，父终端新开窗口加载配置。
- 不修改业务代码、Git 提交、远端、AGENTS、MCP 或项目 Git hooks。
- 临时样例在非 Git 的系统临时目录创建；关闭遥测、自动下载与编译缓存，检查真实路径、完整索引状态、非零文件与符号数。结束或中断时清理本脚本创建的样例。
- 日志在系统临时目录，文件名 `【MacOS】⚙️安装代码地图CodeGraph.log`；终端与日志同步保存诊断和失败退出码。
- doctor 不通过时先处理诊断；npm ping 失败先查网络与代理；CLI 版本正常但样例失败时查平台可选依赖与 JSON 状态。
- 开发验证包括 zsh 静态检查、隔离假命令分支测试及现有 CLI 临时样例；未以测试名义实际安装或升级 Homebrew / npm 包。真实安装需用户运行脚本确认。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
