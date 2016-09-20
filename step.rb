require 'optparse'
require 'fileutils'
require 'tmpdir'

require_relative 'xamarin-builder/builder'
require_relative 'xamarin-builder/common_constants'

# -----------------------
# --- Constants
# -----------------------

@deploy_dir = ENV['BITRISE_DEPLOY_DIR']

# -----------------------
# --- Functions
# -----------------------

def log_info(message)
  puts
  puts "\e[34m#{message}\e[0m"
end

def log_details(message)
  puts "  #{message}"
end

def log_done(message)
  puts "  \e[32m#{message}\e[0m"
end

def log_warning(message)
  puts "\e[33m#{message}\e[0m"
end

def log_error(message)
  puts "\e[31m#{message}\e[0m"
end

def log_fail(message)
  system('envman add --key BITRISE_XAMARIN_TEST_RESULT --value failed')

  puts "\e[31m#{message}\e[0m"
  exit(1)
end

def export_dsym(archive_path)
  log_info("Exporting dSYM from archive at path #{archive_path}")

  archive_dsyms_folder = File.join(archive_path, 'dSYMs')
  app_dsym_paths = Dir[File.join(archive_dsyms_folder, '*.app.dSYM')]
  app_dsym_paths.each do |app_dsym_path|
    log_details("dSym found at path: #{app_dsym_path}")
  end

  if app_dsym_paths.count == 0
    log_warning('No dSym found')
  elsif app_dsym_paths.count > 1
    log_warning('Multiple dSyms found')
  else
    app_dsym_path = app_dsym_paths.first

    if File.directory?(app_dsym_path)
      dsym_zip_path = generate_dsym_zip(app_dsym_path)

      system("envman add --key BITRISE_DSYM_PATH --value \"#{dsym_zip_path}\"")
      log_done("Archived dSYM is now available at: #{dsym_zip_path}")
    end
  end
end

def generate_dsym_zip(dsym_path)
  log_info("Generating archived dSYM from dSym: #{dsym_path}")

  dsym_parent_folder = File.dirname(dsym_path)
  dsym_fold_name = File.basename(dsym_path)

  dsym_zip_path = File.join(@deploy_dir, "#{dsym_fold_name}.zip")
  Dir.chdir(dsym_parent_folder) do
    log_fail('Generating zip for dSym failed') unless system("/usr/bin/zip -rTy #{dsym_zip_path} #{dsym_fold_name}")
  end
  dsym_zip_path
end

def export_osx_xcarchive(archive_path, export_options, export_method)
  log_info("Exporting osx archive at path: #{archive_path}")

  export_options_path = export_options
  unless export_options_path
    log_info('Generating export options')

    # Generate export options
    #  Bundle install
    current_dir = File.expand_path(File.dirname(__FILE__))
    gemfile_path = File.join(current_dir, 'export-options', 'Gemfile')

    bundle_install_command = [
      "BUNDLE_GEMFILE=\"#{gemfile_path}\"",
      'bundle',
      'install'
    ]

    log_info(bundle_install_command.join(' ').to_s)
    success = system(bundle_install_command.join(' '))
    log_fail('Failed to create export options (required gem install failed)') unless success

    #  Bundle exec
    export_options_path = File.join(@deploy_dir, 'export_options.plist')
    export_options_generator = File.join(current_dir, 'export-options', 'generate_osx_export_options.rb')

    bundle_exec_command = [
      "BUNDLE_GEMFILE=\"#{gemfile_path}\"",
      'bundle',
      'exec',
      'ruby',
      export_options_generator,
      "-o \"#{export_options_path}\"",
      "-a \"#{archive_path}\"",
      "-e \"#{export_method}\""
    ]

    log_info(bundle_exec_command.join(' ').to_s)
    success = system(bundle_exec_command.join(' '))
    log_fail('Failed to create export options') unless success
  end

  # Export pkg/app
  export_dir = Dir.mktmpdir('_bitrise_')

  export_command = [
    'xcodebuild',
    '-exportArchive',
    "-archivePath \"#{archive_path}\""
  ]

  export_format = 'app'
  export_format = 'pkg' if export_method == 'app-store'

  tmp_app_path = ''

  # It seems -exportOptionsPlist doesn't support the 'none' method, and
  # an absense of an explicit method defaults to 'development', so we
  # have to use the older, deprecated style in that case
  if export_method.eql? 'none'
    app_name = File.basename(archive_path, '.xcarchive')
    tmp_app_path = File.join(export_dir, "#{app_name}.#{export_format}")

    export_command << "-exportPath \"#{tmp_app_path}\""
    export_command << '-exportFormat APP'
  else
    export_command << "-exportPath \"#{export_dir}\""
    export_command << "-exportOptionsPlist \"#{export_options_path}\""
  end

  log_info(export_command.join(' ').to_s)
  success = system(export_command.join(' '))
  log_fail("Failed to export #{export_format}") unless success

  if export_method.eql? 'none'
    app_name = File.basename(tmp_app_path)
    app_path = File.join(@deploy_dir, app_name)

    FileUtils.cp_r(tmp_app_path, app_path)
  else
    tmp_app_path = Dir[File.join(export_dir, "*.#{export_format}")].first
    log_fail("no generated #{export_format} found in export dir: #{export_dir}") unless tmp_app_path

    app_name = File.basename(tmp_app_path)
    app_path = File.join(@deploy_dir, app_name)

    FileUtils.cp_r(tmp_app_path, app_path)
  end

  env_key = 'BITRISE_APP_PATH'
  env_key = 'BITRISE_PKG_PATH' if export_format == 'pkg'
  system("envman add --key #{env_key} --value \"#{app_path}\"")
  log_done("#{export_format} is now available at: #{app_path}")
end

def export_ios_xcarchive(archive_path, export_options)
  log_info("Exporting ios archive at path: #{archive_path}")

  export_options_path = export_options
  unless export_options_path
    log_info('Generating export options')

    # Generate export options
    #  Bundle install
    current_dir = File.expand_path(File.dirname(__FILE__))
    gemfile_path = File.join(current_dir, 'export-options', 'Gemfile')

    bundle_install_command = [
      "BUNDLE_GEMFILE=\"#{gemfile_path}\"",
      'bundle',
      'install'
    ]

    log_info(bundle_install_command.join(' ').to_s)
    success = system(bundle_install_command.join(' '))
    log_fail('Failed to create export options (required gem install failed)') unless success

    #  Bundle exec
    export_options_path = File.join(@deploy_dir, 'export_options.plist')
    export_options_generator = File.join(current_dir, 'export-options', 'generate_ios_export_options.rb')

    bundle_exec_command = [
      "BUNDLE_GEMFILE=\"#{gemfile_path}\"",
      'bundle',
      'exec',
      'ruby',
      export_options_generator,
      "-o \"#{export_options_path}\"",
      "-a \"#{archive_path}\""
    ]

    log_info(bundle_exec_command.join(' ').to_s)
    success = system(bundle_exec_command.join(' '))
    log_fail('Failed to create export options') unless success
  end

  # Export ipa
  temp_dir = Dir.mktmpdir('_bitrise_')

  export_command = [
    'xcodebuild',
    '-exportArchive',
    "-archivePath \"#{archive_path}\"",
    "-exportPath \"#{temp_dir}\"",
    "-exportOptionsPlist \"#{export_options_path}\""
  ]

  log_info(export_command.join(' ').to_s)
  success = system(export_command.join(' '))
  log_fail('Failed to export IPA') unless success

  app_paths = Dir[File.join(archive_path, 'Products', 'Applications', '*.app')]
  ipa_name = app_paths.count.eql?(1) ? "#{File.basename(app_paths.first, '.app')}.ipa" : nil

  temp_ipa_path = Dir[File.join(temp_dir, '*.ipa')].first
  log_fail('No generated IPA found') unless temp_ipa_path

  ipa_name = File.basename(temp_ipa_path) unless ipa_name

  ipa_path = File.join(@deploy_dir, ipa_name)
  FileUtils.cp(temp_ipa_path, ipa_path)

  system("envman add --key BITRISE_IPA_PATH --value \"#{ipa_path}\"")
  log_done("IPA is now available at: #{ipa_path}")
end

def export_apk(path)
  apk_name = File.basename(path)
  apk_path = File.join(@deploy_dir, apk_name)
  FileUtils.cp(path, apk_path)

  system("envman add --key BITRISE_APK_PATH --value \"#{apk_path}\"")
  log_done("Apk is now available at: #{apk_path}")
end

# -----------------------
# --- Main
# -----------------------

#
# Parse options
options = {
  project: nil,
  configuration: nil,
  platform: nil,
  export_options: nil,
  export_method: nil,
  platform_filter: nil
}

parser = OptionParser.new do |opts|
  opts.banner = 'Usage: step.rb [options]'
  opts.on('-p', '--project path', 'Project') { |p| options[:project] = p unless p.to_s == '' }
  opts.on('-c', '--configuration config', 'Configuration') { |c| options[:configuration] = c unless c.to_s == '' }
  opts.on('-l', '--platform platform', 'Platform') { |l| options[:platform] = l unless l.to_s == '' }
  opts.on('-e', '--options export', 'Export options') { |e| options[:export_options] = e unless e.to_s == '' }
  opts.on('-m', '--method export', 'Export method') { |m| options[:export_method] = m unless m.to_s == '' }
  opts.on('-f', '--filter platform', 'Platform filter') { |f| options[:platform_filter] = f unless f.to_s == '' }
  opts.on('-h', '--help', 'Displays Help') do
    exit
  end
end
parser.parse!

unless options[:platform_filter].nil?
  options[:platform_filter] = options[:platform_filter].split(',').collect { |x| x.strip || x }
end

#
# Print options
log_info 'Configs:'
log_details("* project: #{options[:project]}")
log_details("* configuration: #{options[:configuration]}")
log_details("* platform: #{options[:platform]}")
log_details("* platform_filter: #{options[:platform_filter]}")
log_details("* export_options: #{options[:export_options]}")
log_details("* export_method: #{options[:export_method]}")

#
# Validate options
log_fail('No project file found') unless options[:project] && File.exist?(options[:project])
log_fail('No configuration environment found') unless options[:configuration]
log_fail('No platform environment found') unless options[:platform]

#
# Main
allow_retry_on_hang = true
allow_retry_on_hang = false if ENV['BITRISE_ALLOW_MDTOOL_COMMAND_RETRY'] == 'false'

begin
  builder = Builder.new(options[:project], options[:configuration], options[:platform], options[:platform_filter])
  builder.build(allow_retry_on_hang)
rescue => ex
  log_error(ex.inspect.to_s)
  log_error('--- Stack trace: ---')
  log_error(ex.backtrace.to_s)
  exit(1)
end

output = builder.generated_files

any_output_exported = false

output.each do |_, project_output|
  if project_output[:apk]
    export_apk(project_output[:apk])

    any_output_exported = true
  elsif project_output[:xcarchive] && project_output[:api] == Api::IOS
    export_ios_xcarchive(project_output[:xcarchive], options[:export_options])
    export_dsym(project_output[:xcarchive])

    any_output_exported = true
  elsif project_output[:xcarchive] && project_output[:api] == Api::MAC
    export_osx_xcarchive(project_output[:xcarchive], options[:export_options], options[:export_method])

    any_output_exported = true
  end
end

unless any_output_exported
  puts '--- Generated outputs: ---'
  puts output.to_s

  puts
  log_error 'Step is expected to generate Android .apk, iOS .ipa or MAC .app/.pkg file'
  log_error 'Ensure your `xamarin_configuration` and `xamarin_platform` is configured to generate archive:'
  log_error 'Select these configuration and platform in your IDE and try to run `Archive All` command on your solution'

  puts
  log_fail 'No expected output generated'
end
