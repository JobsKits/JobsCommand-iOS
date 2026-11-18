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
require 'fileutils'
require 'tmpdir'
require 'open3'

class NetworkGenerationTest < Minitest::Test
  ROOT = File.expand_path('..', File.expand_path('..', __dir__))
  NETWORK_PACKAGE = '【MacOS】🌐CocoaPods网络适配.command'
  SPECS_PACKAGE = '【MacOS】🌐CocoaPods源自动选择.command'

  def self.fixtures
    return @fixtures if @fixtures

    @fixtures = Dir.mktmpdir('jobs-builder-network-')
    at_exit { FileUtils.remove_entry(@fixtures) if File.directory?(@fixtures) }
    script = %w[Models.swift ProjectGenerator.swift].map do |name|
      File.read(File.join(ROOT, 'Sources', name))
    end.join("\n") + "\n" + File.read(File.join(File.expand_path('..', __dir__), 'NetworkGenerationMain.swift'))
    script_path = File.join(@fixtures, 'Generate.swift')
    File.write(script_path, script)
    @output, status = Open3.capture2e(
      '/usr/bin/xcrun', 'swift', '-swift-version', '5', script_path,
      File.join(ROOT, 'Resources', 'CocoaPods'), @fixtures
    )
    raise @output unless status.success?

    @fixtures
  end

  def setup
    @fixtures = self.class.fixtures
  end

  def podfile(name)
    File.read(File.join(@fixtures, name, 'Podfile'))
  end

  def hook(name)
    podfile(name).split("platform :ios", 2).first
  end

  def test_each_generated_project_has_portable_runtime_packages
    %w[Packaging Consumer].each do |project|
      [[NETWORK_PACKAGE, 'jobs_cocoapods_network.rb'],
       [NETWORK_PACKAGE, 'jobs_cocoapods_download_fallback.rb'],
       [NETWORK_PACKAGE, NETWORK_PACKAGE],
       [SPECS_PACKAGE, 'jobs_cocoapods_source.rb'],
       [SPECS_PACKAGE, SPECS_PACKAGE]].each do |package, name|
        assert File.file?(File.join(@fixtures, project, 'ScriptsByPods', package, name)), "#{project}: #{name}"
      end
      refute_match(%r{/Users/jobs/}, hook(project))
      network = hook(project).index('JobsCocoaPodsNetwork.apply!')
      archive = hook(project).index('JobsCocoaPodsDownloadFallback.install!')
      specs = hook(project).index('JobsCocoaPodsSource.apply!')
      assert network < archive && archive < specs
    end
  end

  def test_existing_dependency_versions_local_paths_and_private_snapshots_are_preserved
    assert_includes podfile('Packaging'), "pod 'AMPopTip', '= 4.12.0'"
    assert_includes podfile('Packaging'), "pod 'PrivateFixture', :path => 'ImportedPods/PrivateFixture'"
    assert_includes podfile('Packaging'), "Source With Space'"
    assert_includes podfile('Consumer'), "pod 'JobsFixture', :path => '../Binary SDK'"
    original = File.join(@fixtures, 'ReadOnlyPrivateSource', 'PrivateFixture.podspec.json')
    imported = File.join(@fixtures, 'Packaging', 'ImportedPods', 'PrivateFixture', 'PrivateFixture.podspec.json')
    assert_equal File.binread(original), File.binread(imported)
    assert_includes File.read(imported), 'https://private.example.invalid/PrivateFixture.git'
    assert_equal 'private-source-original', File.read(File.join(@fixtures, 'ReadOnlyPrivateSource', 'Source.txt'))
  end

  def test_incomplete_resources_stop_and_existing_generated_packages_are_not_overwritten
    assert_includes self.class.instance_variable_get(:@output), 'MISSING_RESOURCES_BLOCKED'
    assert_includes self.class.instance_variable_get(:@output), 'EXISTING_RESOURCES_PRESERVED'
    assert_equal 'keep-user-content', File.read(File.join(@fixtures, 'Packaging', 'ScriptsByPods', NETWORK_PACKAGE, 'README.md'))
  end

  def test_installs_execute_network_then_archive_then_specs_in_one_environment
    %w[Packaging Consumer].each do |project|
      Dir.mktmpdir('jobs-builder-hook-') do |temporary|
        FileUtils.cp_r(File.join(@fixtures, project, 'ScriptsByPods'), temporary)
        network = File.join(temporary, 'ScriptsByPods', NETWORK_PACKAGE)
        specs = File.join(temporary, 'ScriptsByPods', SPECS_PACKAGE)
        File.write(File.join(network, 'jobs_cocoapods_network.rb'), <<~RUBY)
          module JobsCocoaPodsNetwork
            def self.apply!(project_root:)
              $trace << 'network'
              ENV['JOBS_TEST_ROUTE'] = 'verified-route'
            end
          end
        RUBY
        File.write(File.join(network, 'jobs_cocoapods_download_fallback.rb'), <<~RUBY)
          module JobsCocoaPodsDownloadFallback
            def self.install!
              $trace << 'archive:' + ENV.fetch('JOBS_TEST_ROUTE')
            end
          end
        RUBY
        File.write(File.join(specs, 'jobs_cocoapods_source.rb'), <<~RUBY)
          module JobsCocoaPodsSource
            def self.apply!(podfile, project_root:)
              $trace << 'specs:' + ENV.fetch('JOBS_TEST_ROUTE')
              podfile.source('https://cdn.cocoapods.org/')
            end
          end
        RUBY
        path = File.join(temporary, 'Podfile')
        File.write(path, hook(project))
        %w[install update].each do |command|
          output, status = run_hook(path, command)
          assert status.success?, output
          assert_includes output, 'network,archive:verified-route,specs:verified-route'
        end
      end
    end
  end

  def test_actual_copied_modules_parse_queries_offline_after_project_is_relocated
    %w[Packaging Consumer].each do |project|
      Dir.mktmpdir('jobs-builder-relocated-') do |temporary|
        FileUtils.cp_r(File.join(@fixtures, project, 'ScriptsByPods'), temporary)
        path = File.join(temporary, 'Podfile')
        File.write(path, hook(project))
        output, status = run_hook(path, 'ipc')
        assert status.success?, output
        assert_includes output, 'https://cdn.cocoapods.org/'
        refute_includes output, '[PodNetwork]'
      end
    end
  end

  def test_generator_copies_resources_into_app_bundle_without_a_swiftpm_dependency
    launcher = File.read(File.join(ROOT, '..', '【MacOS】📦生成JobsPod二进制打包器.command'))
    assert_includes launcher, '/bin/cp -R "${RESOURCE_DIR}/CocoaPods"'
    assert_includes launcher, 'Contents/Resources/CocoaPods'
    refute File.exist?(File.join(ROOT, 'Package.swift'))
  end

  def test_app_uses_only_bundled_resources_even_when_original_sources_still_exist
    Dir.mktmpdir('jobs-builder-app-resource-') do |temporary|
      app = File.join(temporary, 'Moved App 中文.app')
      executable = File.join(app, 'Contents', 'MacOS', 'ResourceFixture')
      FileUtils.mkdir_p(File.dirname(executable))
      File.write(File.join(app, 'Contents', 'Info.plist'), <<~PLIST)
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>CFBundleExecutable</key><string>ResourceFixture</string>
        <key>CFBundleIdentifier</key><string>com.jobs.resource-fixture</string>
        <key>CFBundlePackageType</key><string>APPL</string>
        </dict></plist>
      PLIST
      source = File.join(temporary, 'main.swift')
      File.write(source, <<~'SWIFT')
        import Foundation
        @main struct ResourceFixture {
            static func main() {
                do {
                    let target = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
                    _ = try ProjectGenerator.writeCocoaPodsSupport(at: target)
                    print("BUNDLED_RESOURCES_OK")
                } catch {
                    print(error)
                    exit(3)
                }
            }
        }
      SWIFT
      output, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', '-parse-as-library',
                                     File.join(ROOT, 'Sources', 'Models.swift'),
                                     File.join(ROOT, 'Sources', 'ProjectGenerator.swift'), source, '-o', executable)
      assert status.success?, output
      target = File.join(temporary, 'Generated')
      output, status = Open3.capture2e(executable, target, chdir: '/')
      assert_equal 3, status.exitstatus, output
      assert_includes output, 'Contents/Resources/CocoaPods'
      refute File.exist?(target)
      cli = File.join(temporary, 'ResourceFixtureCLI')
      FileUtils.cp(executable, cli)
      cli_target = File.join(temporary, 'CLIGenerated')
      output, status = Open3.capture2e(cli, cli_target, chdir: '/')
      assert_equal 3, status.exitstatus, output
      assert_includes output, '已查找：'
      assert_includes output, '/CocoaPods'
      refute File.exist?(cli_target)
      resources = File.join(app, 'Contents', 'Resources')
      FileUtils.mkdir_p(resources)
      FileUtils.cp_r(File.join(ROOT, 'Resources', 'CocoaPods'), resources)
      output, status = Open3.capture2e(executable, target, chdir: '/')
      assert status.success?, output
      assert_includes output, 'BUNDLED_RESOURCES_OK'
      assert File.file?(File.join(target, 'ScriptsByPods', NETWORK_PACKAGE, 'jobs_cocoapods_network.rb'))
    end
  end

  private

  def run_hook(path, command)
    code = <<~RUBY
      $PROGRAM_NAME = 'pod'
      ARGV.replace([ARGV.fetch(1)])
      $trace = []
      class OfflinePodfile
        def source(url)
          puts url
        end
      end
      path = #{path.inspect}
      OfflinePodfile.new.instance_eval(File.read(path), path, 1)
      puts $trace.join(',')
    RUBY
    Open3.capture2e('/usr/bin/ruby', '-e', code, path, command)
  end
end
