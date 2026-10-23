# Homebrew 安全卸载入口

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

暂无章节。

</details>
<!-- jobs-toc:end -->

本入口一次处理一套 Homebrew 安装，默认选择当前 `brew --prefix`。实际卸载必须在交互终端精确输入 `YES`；回车、其它输入或输入结束均不卸载。

```sh
./【MacOS】⚙️双击卸载Homebrew.command --dry-run
./【MacOS】⚙️双击卸载Homebrew.command --prefix /opt/homebrew
```

`--dry-run` / `DRY_RUN=1` 仅检查本地安装并显示目标，不联网、不删除。自定义安装位置可用 `--prefix` 指定；脚本要求该位置的 `bin/brew` 返回相同 prefix，并拒绝系统或用户根目录。多套安装请分别预览并运行。

确认后从 [Homebrew 官方仓库](https://github.com/Homebrew/install/blob/HEAD/uninstall.sh) 下载卸载器，设置 HTTPS 限制、连接和总时限；下载失败、空文件或语法错误立即停止。只有完整下载并通过 `bash -n` 的安装器才执行。官方卸载器失败时保留非零退出码，停止后续处理。

卸载范围由官方卸载器管理；共享的 `bin`、`lib`、`etc`、`share` 等目录不额外整目录递归删除。残留内容按官方日志人工核对，不能把共享目录整体当作 Homebrew 资产。

每次运行创建权限为 600 的随机日志，终端显示实际位置；私有下载临时文件在退出时清理。不会主动安装、升级或清理 Homebrew，也不会改写 shell 配置。卸载本身仍会删除这套 Homebrew 管理的软件和文件；重要数据库和配置请先自行备份。

验证：两份入口使用相同实现，已用临时安装目录和替身下载器测试取消、预览、下载失败、空响应、卸载失败、参数传递和日志权限；没有执行真实卸载。
