#! /bin/sh

# 如果没有执行权限，在这个sh文件的目录下，执行chmod u+x *.sh
# 参考资料：https://juejin.cn/post/6844903951473754126

# 打印 "Jobs" logo
jobs_logo() {
    local logo="
JJJJJJJJ     oooooo    bb          SSSSSSSSSS
      JJ    oo    oo   bb          SS      SS
      JJ    oo    oo   bb          SS
      JJ    oo    oo   bbbbbbbbb   SSSSSSSSSS
J     JJ    oo    oo   bb      bb          SS
JJ    JJ    oo    oo   bb      bb  SS      SS
 JJJJJJ      oooooo     bbbbbbbb   SSSSSSSSSS
"
    _JobsPrint_Green "$logo"
}
# 通用打印方法
_JobsPrint() {
    local COLOR="$1"
    local text="$2"
    local RESET="\033[0m"
    echo "${COLOR}${text}${RESET}"
}
# 定义红色加粗输出方法
_JobsPrint_Red() {
    _JobsPrint "\033[1;31m" "$1"
}
# 定义绿色加粗输出方法
_JobsPrint_Green() {
    _JobsPrint "\033[1;32m" "$1"
}
# 自述信息
self_intro() {
    _JobsPrint_Red "【MacOS】双击卸载 Cocoapods "
    _JobsPrint_Green "注:如果出现root用户没有/user/bin权限,那是由于系统启用了SIP（System Integerity Protection）导致root用户也没有修改权限，所以我们需要屏蔽掉这个功能"
    _JobsPrint_Green "1.重启电脑"
    _JobsPrint_Green "2.command + R 进入recover模式"
    _JobsPrint_Green "3.点击最上方菜单使用工具，选择终端"
    _JobsPrint_Green "4.运行命令 csrutil disable "
    _JobsPrint_Green "5.重新启动电脑"
    _JobsPrint_Green "按回车键继续..."
    read
}
# 卸载 cocoapod
uninstall_cocoapod(){
    _JobsPrint_Green "查看本地安装过的cocopods相关东西"
    gem list --local | grep cocoapods

    _JobsPrint_Red "确认删除CocoaPods？确认请回车" # 参数-n的作用是不换行，echo默认换行
    read sure # 把键盘输入放入变量sure

    if [[ $sure = "" ]];then
    _JobsPrint_Red "开始卸载CocoaPods"
    #sudo gem uninstall cocoapods

    for element in `gem list --local | grep cocoapods`
        do
            _JobsPrint_Red $"正在卸载CocoaPods子模块："$element$"......"
            # 使用命令逐个删除
            sudo gem uninstall $element
        done
    else
        _JobsPrint_Green "取消卸载CocoaPods"
    fi

    exit 0
}

main() {
 jobs_logo # 打印 "Jobs" logo
 self_intro # 自述信息
 uninstall_cocoapod # 卸载 cocoapod

 echo "🎉 操作完成"
}

main "$@"
