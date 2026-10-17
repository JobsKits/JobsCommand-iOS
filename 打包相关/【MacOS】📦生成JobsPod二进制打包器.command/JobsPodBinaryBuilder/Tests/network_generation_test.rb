# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require 'open3'

class NetworkGenerationTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  NETWORK_PACKAGE = '【MacOS】🌐CocoaPods网络适配.command'
  SPECS_PACKAGE = '【MacOS】🌐CocoaPods源自动选择.command'

  def self.fixtures
    return @fixtures if @fixtures

    @fixtures = Dir.mktmpdir('jobs-builder-network-')
    at_exit { FileUtils.remove_entry(@fixtures) if File.directory?(@fixtures) }
    script = %w[Models.swift ProjectGenerator.swift].map do |name|
      File.read(File.join(ROOT, 'Sources', name))
    end.join("\n") + "\n" + File.read(File.join(__dir__, 'NetworkGenerationMain.swift'))
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
