# `cocoapods_route_test.rb`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行与布局](#jobs-toc-heading-2)
- [二、验证范围](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本包保存 `cocoapods_route_test.rb` 隔离回归入口，验证其上级工具的现有行为。测试源、夹具和参数继续按上级测试说明管理，不执行真实安装或系统清理。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与布局 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 使用 `ruby` 执行本包中的[测试脚本](<./cocoapods_route_test.rb>)，所需参数和确认方式沿用上级工具文档；若上级未提供说明，以源码参数解析和内置自述为准。
- 从脚本实际位置解析上级源码与资源，支持工程外工作目录；保持完整工具和夹具目录，不能只复制测试入口。
- 仅在原测试声明的临时目录或测试仓库中写入；Ctrl+C 取消，任一断言失败返回非零。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、验证范围 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

本轮完成语法和迁移路径检查；具体回归及平台实机结果见[统一审查报告](../../../../项目相关报告/脚本统一审查.md)。未执行的分支不记为通过。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
