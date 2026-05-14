# pd 本地 Pod 编译自检工具

## 用途

`pd` 用来检查一个本地 CocoaPods Pod 是否能在自己的 podspec 环境下独立编译通过。

典型目录结构：

```text
PodsRoot/
├── JobsSuspend/
│   └── JobsSuspend.podspec
├── JobsModel/
│   └── JobsModel.podspec
└── JobsBaseConfig/
    └── JobsBaseConfig.podspec
```

当你输入目标 Pod 名 `JobsSuspend` 时，工具会：

1. 找到 `JobsSuspend.podspec`
2. 收集同级其他 `*.podspec`
3. 把其他 podspec 作为 `--include-podspecs` 传给 `pod lib lint`
4. 执行目标 Pod 的内部编译自检

## 第一次使用

双击运行：

```text
pd.command
```

脚本会自动安装/刷新终端命令：

```text
~/.local/bin/pd
```

并把下面这行写入 `~/.zprofile`：

```zsh
export PATH="$HOME/.local/bin:$PATH"
```

之后重新打开终端，即可直接输入：

```zsh
pd
```

## CocoaPods 逻辑

脚本会先检查 `pod` 命令：

- 如果没有 `pod`，执行：

```zsh
sudo gem install cocoapods
```

- 如果已有 `pod`，会询问是否升级：

```text
直接回车：跳过升级
输入任意字符后回车：执行 sudo gem install cocoapods
```

## lint 参数

默认执行：

```zsh
pod lib lint Target.podspec \
  --platforms=ios \
  --private \
  --verbose \
  --no-clean \
  --allow-warnings \
  --include-podspecs=其他本地podspec
```

## 常见失败方向

如果 lint 失败，优先看这些关键词：

```text
header not found
module not found
framework not found
file not found
Unable to find a specification
The following build commands failed
```

常见原因：

- `source_files` 没包含真实源码
- `public_header_files` 暴露不对
- 漏写 `frameworks` / `libraries`
- subspec 依赖关系缺失
- 本地 Pod 之间存在循环依赖
- 资源文件没有正确写入 `resources` / `resource_bundles`
