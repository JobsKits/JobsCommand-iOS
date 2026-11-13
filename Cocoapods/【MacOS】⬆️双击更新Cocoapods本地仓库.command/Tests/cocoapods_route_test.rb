# frozen_string_literal: true

# JOBS_TERMINAL_STYLE_GUARD_V1_BEGIN
if $PROGRAM_NAME == __FILE__
  # 直接运行时由 fork 父进程保护配色；子进程继续原文件，不重放 Ruby 参数和预载模块。
  def jobs_terminal_style_bootstrap_v1
    return unless $PROGRAM_NAME == __FILE__
    plain = lambda do
      ENV.update('PLAIN_OUTPUT' => '1', 'NO_COLOR' => '1', 'FORCE_COLOR' => '0',
                 'CLICOLOR' => '0', 'ANSI_COLORS_DISABLED' => '1', 'npm_config_color' => 'false')
    end
    notify = lambda do |message|
      encoding = $stderr.external_encoding || Encoding::UTF_8
      $stderr.write((message + "\n").encode(encoding, invalid: :replace, undef: :replace))
    end
    return unless $stdin.tty? && $stdout.tty?
    return if ENV.key?('NO_COLOR') || ENV['PLAIN_OUTPUT'] == '1' ||
              ENV['IS_SOURCETREE_RUNTIME'] == '1' ||
              ENV.keys.any? { |key| key.match?(/\A(?:SOURCETREE|SOURCE_TREE)/i) }
    return if ['', 'dumb'].include?(ENV.fetch('TERM', ''))
    if File::ALT_SEPARATOR == '\\' || !Process.respond_to?(:fork) ||
       Thread.list.length > 1 || ENV['TMUX'] || ENV['STY']
      plain.call
      return
    end
    tty_name = IO.popen(['tty'], err: File::NULL, &:read).strip
    groups = IO.popen(['ps', '-o', 'pgid=', '-o', 'tpgid=', '-p', Process.pid.to_s], err: File::NULL, &:read).split
    unless tty_name.match?(%r{\A/dev/[A-Za-z0-9_./-]+\z}) && groups.length == 2 &&
           groups.all? { |group| group.match?(/\A\d+\z/) } && groups[0].to_i > 0 && groups[0] == groups[1]
      plain.call
      return
    end
    owner = ENV['JOBS_TERMINAL_STYLE_OWNER']
    if ENV['JOBS_TERMINAL_STYLE_TTY'] == tty_name && owner && owner.match?(/\A\d+\z/)
      begin
        Process.kill(0, owner.to_i)
        return
      rescue Errno::ESRCH, Errno::EPERM
      end
    end
    require 'io/console'
    require 'tmpdir'
    if Thread.list.length > 1
      plain.call
      return
    end
    tty = File.open('/dev/tty', 'r+')
    tty.binmode
    tty.sync = true
    keys = ['10', '11', '12'] + (0..15).map { |index| "4;#{index}" }
    palette = %w[000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee
                 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff]
    targets = { '10' => 'ffffff', '11' => '000000', '12' => 'ffffff' }
    palette.each_with_index { |color, index| targets["4;#{index}"] = color }
    query = lambda do |key|
      tty.write("\e]#{key};?\a")
      bytes = ''.b
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.3
      loop do
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return nil if remaining <= 0 || !IO.select([tty], nil, nil, remaining)
        piece = tty.read_nonblock(256, exception: false)
        next if piece == :wait_readable
        return nil unless piece && !piece.empty?
        bytes << piece
        return nil if bytes.bytesize > 256 || !bytes.start_with?("\e".b)
        break if bytes.end_with?("\a".b) || bytes.end_with?("\e\\".b)
      end
      match = bytes.match(/\A\e\]#{Regexp.escape(key)};rgb:([0-9a-fA-F]{1,4})\/([0-9a-fA-F]{1,4})\/([0-9a-fA-F]{1,4})(?:\a|\e\\)\z/n)
      return nil unless match
      components = match.captures.map { |hex| (hex.to_i(16) * 65535.0 / (16**hex.length - 1)).round }
      { raw: bytes, rgb: components }
    rescue IOError, SystemCallError
      nil
    end
    snapshot = lambda do
      values = {}
      tty.raw(min: 0, time: 0, intr: true) do
        keys.each do |key|
          value = query.call(key)
          return nil unless value
          values[key] = value
        end
      end
      values
    rescue IOError, SystemCallError, ArgumentError
      nil
    end
    original = snapshot.call
    unless original
      notify.call('终端不支持完整配色保存，或启动时收到其它输入；保留原配色并使用纯文本。')
      tty.close
      plain.call
      return
    end
    directory = Dir.mktmpdir('jobs-terminal-style-')
    recovery = File.join(directory, 'restore.sh')
    original_bytes = keys.map { |key| original.fetch(key).fetch(:raw) }.join
    recovery_source = "#!/bin/sh\n" \
      "[ -t 0 ] && [ \"$(tty)\" = '#{tty_name}' ] || { printf '请在原终端运行恢复入口。\\n' >&2; exit 1; }\n" \
      "printf '本操作会覆盖此终端当前配色。确认恢复脚本启动前的配色，请输入 YES：' >&2\n" \
      "IFS= read -r jobs_restore_choice\n[ \"$jobs_restore_choice\" = YES ] || exit 1\n" \
      "printf '%s\\033[0m' '#{original_bytes}' > /dev/tty\n"
    File.open(recovery, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.binmode
      file.write(recovery_source.b)
    end
    notify.call("本次终端临时使用黑底白字；强退后恢复入口：sh \"#{recovery}\"")
    changed = false
    applied = nil
    # 比较仍生效的本轮颜色，只恢复未被用户另行修改的项。
    cleanup = lambda do
      current = applied && snapshot.call
      unless current
        notify.call("终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh \"#{recovery}\"")
        return false
      end
      conflicts = []
      restore_bytes = ''.b
      keys.each do |key|
        if current.fetch(key).fetch(:rgb) == applied.fetch(key).fetch(:rgb)
          restore_bytes << original.fetch(key).fetch(:raw)
        else
          conflicts << key
        end
      end
      tty.write(restore_bytes + "\e[0m".b)
      if conflicts.empty?
        File.unlink(recovery)
        Dir.rmdir(directory)
        true
      else
        notify.call("检测到运行期间的配色变更，已保留这些项：#{conflicts.join(' ')}")
        notify.call("确认要覆盖后续改色时才使用恢复入口：sh \"#{recovery}\"")
        false
      end
    rescue IOError, SystemCallError
      notify.call("终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh \"#{recovery}\"")
      false
    end
    child_pid = nil
    guardian = false
    interrupted = nil
    previous_signals = {}
    %w[INT TERM HUP].each do |name|
      previous_signals[name] = Signal.trap(name) do
        interrupted = name
        if child_pid && name != 'INT'
          begin
            Process.kill(name, child_pid)
          rescue Errno::ESRCH
          end
        end
      end
    end
    begin
      changed = true
      tty.write(targets.map { |key, color| "\e]#{key};##{color}\a" }.join + "\e[0m")
      applied = snapshot.call
      unless applied
        notify.call('无法核实本次临时配色，已停止启动业务。')
        raise SystemExit, 1
      end
      desired = targets.all? do |key, hex|
        rgb = hex.scan(/../).map { |component| component.to_i(16) * 257 }
        applied.fetch(key).fetch(:rgb).zip(rgb).all? { |actual, expected| (actual - expected).abs <= 255 }
      end
      unless desired
        notify.call('终端未接受本次配色，恢复后使用纯文本。')
        restored = cleanup.call
        changed = false
        raise SystemExit, 1 unless restored
        plain.call
        return
      end
      if interrupted
        raise SystemExit, 128 + Signal.list.fetch(interrupted)
      end
      if Thread.list.length > 1
        restored = cleanup.call
        changed = false
        raise SystemExit, 1 unless restored
        plain.call
        return
      end
      $stdout.flush
      $stderr.flush
      begin
        child_pid = Process.fork
      rescue NotImplementedError, SystemCallError
        restored = cleanup.call
        changed = false
        raise SystemExit, 1 unless restored
        plain.call
        return
      end
      unless child_pid
        changed = false
        ENV['JOBS_TERMINAL_STYLE_TTY'] = tty_name
        ENV['JOBS_TERMINAL_STYLE_OWNER'] = Process.ppid.to_s
        raise SystemExit, 128 + Signal.list.fetch(interrupted) if interrupted
        return
      end
      guardian = true
      result = nil
      loop do
        begin
          _, result = Process.wait2(child_pid)
          break
        rescue Interrupt, Errno::EINTR
        end
      end
      status_code = result.exitstatus || 128 + result.termsig
      %w[INT TERM HUP].each { |name| Signal.trap(name, 'IGNORE') }
      restored = cleanup.call
      changed = false
      status_code = 1 if !restored && status_code.zero?
      tty.close
      Process.exit!(status_code)
    ensure
      if changed
        %w[INT TERM HUP].each { |name| Signal.trap(name, 'IGNORE') }
        cleanup.call
      end
      previous_signals.each { |name, handler| Signal.trap(name, handler) } unless guardian
      tty.close unless tty.closed?
    end
  rescue IOError, SystemCallError, LoadError => error
    if guardian
      notify.call("终端保护监督进程异常：#{error.message}")
      Process.exit!(1)
    end
    raise SystemExit, 1 if changed
    notify.call("终端保护不可用，使用纯文本：#{error.message}")
    plain.call
  end
  jobs_terminal_style_bootstrap_v1

end
# JOBS_TERMINAL_STYLE_GUARD_V1_END

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

    def test_refresh_main_preserves_existing_lock_pods_and_workspace
      [false, true].each do |flutter|
        result = run_fixture(flutter: flutter, through_main: true, preserve_existing: true)
        assert result[:status].success?, result[:output]
        assert_equal [[result[:project], ['install', '--repo-update']]], result[:calls]
        assert_empty result[:cleanup_calls]
        assert_equal result[:retained_before], result[:retained_after]
      end
      refute_match(/\b(?:clean_pod_cache|rm)\b/, extracted_function('main'))
    end

    def test_refresh_failure_also_preserves_existing_lock_pods_and_workspace
      [false, true].each do |flutter|
        result = run_fixture(flutter: flutter, through_main: true, preserve_existing: true, pod_exit: 17)
        refute result[:status].success?
        assert_empty result[:cleanup_calls]
        assert_equal result[:retained_before], result[:retained_after]
      end
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

  def run_fixture(adapted: false, pod_exit: 0, architecture: 'x86_64', confirm: true, flutter: false, through_main: false, preserve_existing: false)
    Dir.mktmpdir('jobs-pod-wrapper-') do |temporary_root|
      base = File.join(temporary_root, '工程 中文 with spaces')
      project = flutter ? File.join(base, 'ios') : base
      fake_bin = File.join(temporary_root, 'bin')
      trace = File.join(temporary_root, 'commands')
      cleanup_trace = File.join(temporary_root, 'cleanup-commands')
      module_executed = File.join(temporary_root, 'module-executed')
      FileUtils.mkdir_p([project, fake_bin])
      File.write(File.join(base, 'pubspec.yaml'), 'name: fixture') if flutter
      podfile = File.join(project, 'Podfile')
      before = adapted ? "JobsCocoaPodsNetwork.apply!\nJobsCocoaPodsSource.apply!\n" : "target 'Fixture' do\nend\n"
      File.write(podfile, before)
      retained_before = preserve_existing ? {
        'Podfile.lock' => "PODS:\n  - LockedPod (1.0.0)\n",
        'Pods/cached-source.m' => 'existing downloaded source',
        'Fixture.xcworkspace/contents.xcworkspacedata' => 'existing workspace'
      } : {}
      retained_before.each do |relative_path, bytes|
        retained_path = File.join(project, relative_path)
        FileUtils.mkdir_p(File.dirname(retained_path))
        File.write(retained_path, bytes)
      end
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
      invocation = 'main' if through_main
      runner = <<~ZSH
        info_echo() { print -r -- "$*"; }
        success_echo() { print -r -- "$*"; }
        warn_echo() { print -r -- "$*"; }
        error_echo() { print -r -- "$*"; }
        ask_run() { [[ "$JOBS_TEST_CONFIRM" == 1 ]]; }
        create_desktop_shortcut_if_needed() { return 0; }
        init_basedir() { basedir="$JOBS_TEST_BASE"; }
        print_intro() { return 0; }
        make_files_executable() { return 0; }
        clean_pod_cache() { print -r -- cleanup >> "$JOBS_TEST_CLEANUP_TRACE"; return 91; }
        rm() { print -r -- "rm $*" >> "$JOBS_TEST_CLEANUP_TRACE"; return 92; }
        lipo() { print -r -- x86_64; }
        #{extracted_function('jobs_describe_project_network')}
        #{extracted_function(BUSINESS_FUNCTION)}
        #{through_main ? extracted_function('main') : ''}
        #{invocation}
      ZSH
      environment = {
        'PATH' => "#{fake_bin}:/usr/bin:/bin",
        'JOBS_TEST_TRACE' => trace,
        'JOBS_TEST_CLEANUP_TRACE' => cleanup_trace,
        'JOBS_TEST_BASE' => base,
        'JOBS_TEST_POD_EXIT' => pod_exit.to_s,
        'JOBS_TEST_ARCH' => architecture,
        'JOBS_TEST_CONFIRM' => confirm ? '1' : '0'
      }
      stdout, stderr, status = Open3.capture3(environment, '/bin/zsh', '-c', runner, 'fixture', base)
      calls = File.exist?(trace) ? File.readlines(trace).map { |line| pieces = line.chomp.split("\t"); [pieces.shift, pieces] } : []
      retained_after = retained_before.each_with_object({}) do |(relative_path, _), result|
        retained_path = File.join(project, relative_path)
        result[relative_path] = File.file?(retained_path) ? File.read(retained_path) : nil
      end
      return { :status => status, :output => stdout + stderr, :calls => calls, :project => project,
               :before => before, :after => File.read(podfile), :module_was_executed => File.exist?(module_executed),
               :cleanup_calls => File.exist?(cleanup_trace) ? File.readlines(cleanup_trace) : [],
               :retained_before => retained_before, :retained_after => retained_after }
    end
  end
end
