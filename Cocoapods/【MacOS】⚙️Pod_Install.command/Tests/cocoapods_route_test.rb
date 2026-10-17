# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'

class CocoaPodsWrapperRouteTest < Minitest::Test
  PACKAGE_ROOT = File.expand_path('..', __dir__)
  SCRIPT_PATH = Dir[File.join(PACKAGE_ROOT, '*.command')].fetch(0)
  SOURCE = File.read(SCRIPT_PATH)
  MODE = if File.basename(SCRIPT_PATH).include?('Pod_Install')
           :install
         elsif File.basename(SCRIPT_PATH).include?('Pod_Update')
           :update
         else
           :refresh
         end
  BUSINESS_FUNCTION = {
    :install => 'install_pod',
    :update => 'update_pod_in_dir',
    :refresh => 'run_pod_install'
  }.fetch(MODE)

  def test_commands_do_not_reconfigure_global_sources
    refute_match(/\.cocoapods_mirror_config/, SOURCE)
    refute_match(/^\s*pod\s+repo\s+(?:add|remove|update)\b/, SOURCE)
    refute_match(/^\s*pod\s+setup\b/, SOURCE)
  end

  def test_one_process_handles_the_requested_project_operation
    result = run_fixture
    assert result[:status].success?, result[:output]
    assert_equal [[result[:project], expected_arguments]], result[:calls]
  end

  def test_unknown_project_gets_a_clear_boundary_warning
    result = run_fixture
    assert_includes result[:output], '本包装器只执行原生 CocoaPods，不自带选路'
    assert_equal result[:before], result[:after]
  end

  def test_adapted_project_is_detected_without_running_its_modules
    result = run_fixture(adapted: true)
    assert result[:status].success?, result[:output]
    assert_includes result[:output], '已找到目标 Podfile 网络适配与选源入口'
    refute_includes result[:output], '不自带选路'
    refute result[:module_was_executed], '包装器不得自行加载目标工程 Ruby 脚本'
    assert_equal result[:before], result[:after]
  end

  def test_partial_script_package_is_not_reported_as_adapted
    result = run_fixture(adapted: :partial)
    assert_includes result[:output], '未确认目标 Podfile 已接入'
  end

  def test_dependency_failure_is_not_reported_as_success
    result = run_fixture(pod_exit: 17)
    refute result[:status].success?
    assert_includes result[:output], '失败'
    refute_match(/Pod (?:安装|更新)完成|CocoaPods 安装与更新完成/, result[:output])
    assert_equal 1, result[:calls].length
  end

  def test_arm_path_still_uses_the_same_target_podfile
    result = run_fixture(architecture: 'arm64')
    assert result[:status].success?, result[:output]
    assert_equal [[result[:project], expected_arguments]], result[:calls]
  end

  if MODE == :update
    def test_update_cancellation_does_not_start_a_separate_repo_refresh
      result = run_fixture(confirm: false)
      assert result[:status].success?, result[:output]
      assert_empty result[:calls]
      assert_includes result[:output], '已跳过 Pod 更新'
    end
  end

  if MODE == :refresh
    def test_flutter_refresh_enters_its_ios_podfile_directory
      result = run_fixture(flutter: true)
      assert result[:status].success?, result[:output]
      assert_equal [[result[:project], ['install', '--repo-update']]], result[:calls]
    end
  end

  private

  def expected_arguments
    case MODE
    when :install then ['install', '--repo-update', '--verbose']
    when :update then ['update']
    else ['install', '--repo-update']
    end
  end

  def extracted_function(name)
    SOURCE[/^  #{Regexp.escape(name)}\(\) \{\n.*?^  \}\n/m] || raise("未找到可隔离的函数：#{name}")
  end

  def run_fixture(adapted: false, pod_exit: 0, architecture: 'x86_64', confirm: true, flutter: false)
    Dir.mktmpdir('jobs-pod-wrapper-') do |temporary_root|
      base = File.join(temporary_root, '工程 中文 with spaces')
      project = flutter ? File.join(base, 'ios') : base
      fake_bin = File.join(temporary_root, 'bin')
      trace = File.join(temporary_root, 'commands')
      module_executed = File.join(temporary_root, 'module-executed')
      FileUtils.mkdir_p([project, fake_bin])
      File.write(File.join(base, 'pubspec.yaml'), 'name: fixture') if flutter
      podfile = File.join(project, 'Podfile')
      before = adapted ? "JobsCocoaPodsNetwork.apply!\nJobsCocoaPodsSource.apply!\n" : "target 'Fixture' do\nend\n"
      File.write(podfile, before)
      if adapted
        package = File.join(project, 'ScriptsByPods', '【MacOS】🌐CocoaPods网络适配.command')
        source_package = File.join(project, 'ScriptsByPods', '【MacOS】🌐CocoaPods源自动选择.command')
        FileUtils.mkdir_p([package, source_package])
        files = [File.join(package, 'jobs_cocoapods_network.rb'), File.join(source_package, 'jobs_cocoapods_source.rb')]
        files << File.join(package, 'jobs_cocoapods_download_fallback.rb') unless adapted == :partial
        files.each { |path| File.write(path, "File.write(#{module_executed.inspect}, 'executed')\n") }
      end
      File.write(File.join(fake_bin, 'pod'), <<~'ZSH')
        #!/bin/zsh
        printf '%s\t' "$PWD" "$@" >> "$JOBS_TEST_TRACE"
        printf '\n' >> "$JOBS_TEST_TRACE"
        exit "$JOBS_TEST_POD_EXIT"
      ZSH
      File.write(File.join(fake_bin, 'uname'), <<~'ZSH')
        #!/bin/zsh
        print -r -- "$JOBS_TEST_ARCH"
      ZSH
      File.write(File.join(fake_bin, 'arch'), <<~'ZSH')
        #!/bin/zsh
        [[ "$1" != -x86_64 ]] || shift
        "$@"
      ZSH
      FileUtils.chmod(0o755, Dir[File.join(fake_bin, '*')])
      invocation = MODE == :refresh ? "basedir=\"$1\"\n#{BUSINESS_FUNCTION}" : "#{BUSINESS_FUNCTION} \"$1\""
      runner = <<~ZSH
        info_echo() { print -r -- "$*"; }
        success_echo() { print -r -- "$*"; }
        warn_echo() { print -r -- "$*"; }
        error_echo() { print -r -- "$*"; }
        ask_run() { [[ "$JOBS_TEST_CONFIRM" == 1 ]]; }
        create_desktop_shortcut_if_needed() { return 0; }
        lipo() { print -r -- x86_64; }
        #{extracted_function('jobs_describe_project_network')}
        #{extracted_function(BUSINESS_FUNCTION)}
        #{invocation}
      ZSH
      environment = {
        'PATH' => "#{fake_bin}:/usr/bin:/bin",
        'JOBS_TEST_TRACE' => trace,
        'JOBS_TEST_POD_EXIT' => pod_exit.to_s,
        'JOBS_TEST_ARCH' => architecture,
        'JOBS_TEST_CONFIRM' => confirm ? '1' : '0'
      }
      stdout, stderr, status = Open3.capture3(environment, '/bin/zsh', '-c', runner, 'fixture', base)
      calls = File.exist?(trace) ? File.readlines(trace).map { |line| pieces = line.chomp.split("\t"); [pieces.shift, pieces] } : []
      return { :status => status, :output => stdout + stderr, :calls => calls, :project => project,
               :before => before, :after => File.read(podfile), :module_was_executed => File.exist?(module_executed) }
    end
  end
end
