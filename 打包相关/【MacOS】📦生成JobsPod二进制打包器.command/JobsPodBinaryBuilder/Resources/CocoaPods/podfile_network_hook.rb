# 同步准备当前安装进程的网络链路，让选源和后续源码下载继承同一配置。
jobs_pod_network_dir = File.join(__dir__, 'ScriptsByPods', '【MacOS】🌐CocoaPods网络适配.command')
jobs_pod_network_path = File.join(jobs_pod_network_dir, 'jobs_cocoapods_network.rb')
begin
  if File.file?(jobs_pod_network_path)
    require jobs_pod_network_path
    JobsCocoaPodsNetwork.apply!(project_root: __dir__)
  else
    warn '[PodNetwork] 网络适配模块缺失，沿用当前网络；请迁移完整脚本包。'
  end
rescue LoadError, SyntaxError, StandardError => error
  warn "[PodNetwork] 网络适配不可用，沿用当前网络（#{error.class}）。"
end

# 只在真实安装入口注册已核验依赖的官方归档回退，不改变依赖声明和版本。
jobs_pod_dependency_command = File.basename($PROGRAM_NAME) == 'pod' &&
  %w[install update].include?(ARGV.find { |argument| !argument.start_with?('-') })
if jobs_pod_dependency_command
  jobs_pod_download_fallback_path = File.join(jobs_pod_network_dir, 'jobs_cocoapods_download_fallback.rb')
  begin
    if File.file?(jobs_pod_download_fallback_path)
      require jobs_pod_download_fallback_path
      JobsCocoaPodsDownloadFallback.install!
    else
      warn '[PodNetwork] 官方源码归档回退模块缺失，继续使用 CocoaPods 原下载器。'
    end
  rescue LoadError, SyntaxError, StandardError => error
    warn "[PodNetwork] 官方源码归档回退不可用，继续原下载流程（#{error.class}）。"
  end
end

# 源选择必须同步完成，才能影响本次依赖解析。
jobs_specs_source_path = File.join(
  __dir__,
  'ScriptsByPods',
  '【MacOS】🌐CocoaPods源自动选择.command',
  'jobs_cocoapods_source.rb'
)
begin
  if File.file?(jobs_specs_source_path)
    require jobs_specs_source_path
    JobsCocoaPodsSource.apply!(self, project_root: __dir__)
  else
    warn '[SpecsSource] 选源模块缺失，使用官方 CDN。请迁移完整脚本包。'
    source 'https://cdn.cocoapods.org/'
  end
rescue LoadError, SyntaxError, StandardError => error
  warn "[SpecsSource] 选源模块异常，使用官方 CDN：#{error.message}"
  source 'https://cdn.cocoapods.org/'
end
