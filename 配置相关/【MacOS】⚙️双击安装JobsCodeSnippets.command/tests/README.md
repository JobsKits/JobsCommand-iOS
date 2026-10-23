# JobsCodeSnippets 隔离回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行方式](#jobs-toc-heading-2)
- [二、验证范围](#jobs-toc-heading-3)
- [三、执行边界与现场](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[regression.zsh](./regression.zsh)用原生 [**zsh**](https://www.zsh.org/) 和 [**Git**](https://git-scm.com/) 验证上级安装 / 升级脚本。每组用例独立创建临时 HOME、本地裸仓、发布仓和 Xcode CodeSnippets 目标，不联网，不修改真实用户目录或源仓提交。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在本 README 所在目录运行，阅读自述后按回车开始；`Ctrl+C` 或输入结束取消。

```shell
zsh ./regression.zsh
```

自动回归可明确传入同一次回车确认：

```shell
printf '\n' |
  zsh ./regression.zsh
```

脚本不接受参数。依赖系统自带 `/bin/zsh`、`/usr/bin/git`、`awk`、`sed`、`diff`、`find`、`cp`、`mktemp` 等工具。它不安装开发工具或依赖。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、验证范围 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 场景 | 核对结果 |
| --- | --- |
| 首次安装 | 缺失目录、空目录均能安装到当前临时用户的 Xcode CodeSnippets 位置 |
| 已有独立仓 | 已是最新时不创建提交；无本地改动时快进；远端分支保持不变 |
| 本地内容 | 同一文件的暂存和未暂存改动保留层次，未跟踪和忽略内容保留，既有 stash 对象和顺序不变 |
| 分叉 | 非冲突分叉保留待提交合并；有本地部分暂存时也保留原层次；不自动生成 commit |
| 失败保护 | 拉取失败、恢复本地改动冲突、分叉合并冲突、远端新增文件覆盖本地忽略内容均非零退出，原目录和 Git 元数据内容、权限、符号链接保留 |
| 安全门禁 | 上游缺失、未完成合并、非 Git 非空目录停止；外部 GIT_* 变量不误导目标，发布前发现内容、权限或符号链接并发修改即停止 |
| 只读检查 | 真实 `--check` 入口在未安装 / 已安装且有本地改动时不写日志、锁、事务或索引缓存 |
| 工程门禁 | 接受当前层含 Xcode 工程、Podfile、podspec 或 Swift Package 的目录，以及有效工程包 / workspace 包；Flutter 根目录也按同层标记判断，有标记可接受；普通目录、无当前层原生标记的 Flutter 根目录、缺失路径、选中符号链接和桌面拒绝 |

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、执行边界与现场 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

真实业务入口保留交互确认。回归只对临时复制且移除末行 `main` 调用的源码执行 `source`，再由测试驱动调用初始化、环境检查、状态报告和业务函数；首次安装的远端只在驱动中改成本地裸仓。它没有为正式脚本增加免确认参数。

所有外部命令通过隔离环境运行，不读取系统 / 用户 Git 配置，传输协议限定为 `file`。Git 提交和推送只存在于系统临时目录中的夹具裸仓，不涉及源仓或任何托管远端。

每次结束显示成功 / 失败组数、断言数和 `JobsCodeSnippets-tests.*` 临时目录。该目录保留各组输出、核心日志、事务备份、失败候选和原目标快照，便于复核；需要释放空间时可在确认路径后手动删除。测试失败返回非零，成功返回零。

本回归不安装 Finder 扩展、不启动 / 重启 Xcode，也不验证真实 Finder 菜单或托管远端连通性。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
