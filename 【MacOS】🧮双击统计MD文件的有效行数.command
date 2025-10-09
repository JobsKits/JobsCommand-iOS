#!/bin/bash
# ===============================================================
#  install_precommit_markdown_counter.command
# ---------------------------------------------------------------
#  功能：
#   • 自动在当前项目中安装一个 Git pre-commit 钩子。
#   • 钩子会在每次提交前自动更新 .md 文件中的正文行数。
#   • 检测目标格式："当前总行数：xxx 行"
# ---------------------------------------------------------------
#  作者：JobsHi
# ===============================================================

set -e  # 出错即退出

# =========================== 输出函数 ===========================
info()    { echo "📘 $1"; }
success() { echo "✅ $1"; }
error()   { echo "❌ $1"; }
warn()    { echo "⚠️ $1"; }

# =========================== 自述说明 ===========================
show_intro() {
  clear
  echo -e "\033[1;31m#【初始化】请在需要铆定的 .md 文件中合适位置写入：当前总行数：0 行\033[0m"
  echo
  cat <<'EOF'
=============================================================
📘 功能说明：
  本脚本会自动为当前项目安装 Git pre-commit 钩子。

  当你执行 git commit 时，钩子会自动：
    ✅ 统计每个 Markdown (.md) 文件的正文行数
    ✅ 忽略空行、注释行 (# 开头)、代码块 (``` 开头)
    ✅ 自动更新文件中的“当前总行数：X 行”字段
    ✅ 自动重新添加到提交区

⚙️ 使用前准备：
  • 确保当前目录有 .git 文件夹
  • 每个目标 .md 文件中包含行：
      当前总行数：0 行

🚀 示例：
  当前总行数：12 行

=============================================================
EOF
  read "?👉 按回车键继续安装 ..."
}

# =========================== 切换到项目根 ===========================
enter_script_dir() {
  cd "$(dirname "$0")" || {
    error "无法进入脚本所在目录"
    exit 1
  }
  info "📂 当前工作目录: $(pwd)"
}

# =========================== 检查 Git 环境 ===========================
check_git() {
  if [[ ! -d ".git" ]]; then
    error "❌ 未检测到 .git 目录，请在项目根目录运行此脚本。"
    exit 1
  fi
}

# =========================== 创建 pre-commit 钩子 ===========================
create_precommit_hook() {
  info "📝 创建 Git pre-commit 钩子..."

  mkdir -p .git/hooks

  cat > .git/hooks/pre-commit <<'EOF'
#!/bin/zsh
echo "🔧 正在更新 Markdown 文件中的正文行数..."
for file in $(find . -type f -name "*.md"); do
    if grep -qE "^当前总行数：[0-9]+ 行" "$file"; then
        line_count=$(grep -vE '^\s*$|^\s*#|^```' "$file" | wc -l | tr -d ' ')
        echo "📄 更新文件：$file，正文行数：$line_count 行"
        sed -i "" -E "s/^当前总行数：[0-9]+ 行/当前总行数：${line_count} 行/" "$file"
        git add "$file"
    fi
done
echo "✅ 所有 Markdown 文件的行数已更新！"
EOF

  chmod +x .git/hooks/pre-commit
  success "Git pre-commit 钩子已创建"
}

# =========================== 验证钩子存在 ===========================
verify_hook() {
  if [[ -f ".git/hooks/pre-commit" ]]; then
    success "✅ pre-commit 文件已成功创建"
    ls -la .git/hooks/pre-commit
  else
    error "❌ pre-commit 文件创建失败"
    exit 1
  fi
}

# =========================== 主函数 ===========================
main() {
  show_intro
  enter_script_dir
  check_git
  create_precommit_hook
  verify_hook
  success "🎉 Git pre-commit 钩子安装完成！"
  echo
  read "?✅ 按回车退出 ..."
}

# =========================== 执行入口 ===========================
main "$@"
