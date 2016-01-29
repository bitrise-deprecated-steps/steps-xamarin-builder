require 'optparse'
require 'fileutils'
require 'tmpdir'

require_relative 'xamarin-builder/builder'

# -----------------------
# --- Constants
# -----------------------

@deploy_dir = ENV['BITRISE_DEPLOY_DIR']

# -----------------------
# --- Functions
# -----------------------

def fail_with_message(message)
  puts "\e[31m#{message}\e[0m"
  exit(1)
end

def error_with_message(message)
  puts "\e[31m#{message}\e[0m"
end

def to_bool(value)
  return true if value == true || value =~ (/^(true|t|yes|y|1)$/i)
  return false if value == false || value.nil? || value == '' || value =~ (/^(false|f|no|n|0)$/i)
  fail_with_message("Invalid value for Boolean: \"#{value}\"")
end

def export_dsym(archive_path)
  puts
  puts '=> Exporting dSYM...'

  archive_dsyms_folder = File.join(archive_path, 'dSYMs')
  app_dsym_paths = Dir[File.join(archive_dsyms_folder, '*.app.dSYM')]
  app_dsym_paths.each do |app_dsym_path|
    puts " (i) .app.dSYM found: #{app_dsym_path}"
  end

  puts " (i) Found dSYM count: #{app_dsym_paths.count}"

  if app_dsym_paths.count == 0
    puts '* (i) **No dSYM found!**'
  elsif app_dsym_paths.count > 1
    puts '* (i) *More than one dSYM found!*'
  else
    app_dsym_path = app_dsym_paths[0]
    puts "* dSYM found at: #{app_dsym_path}"
    if File.directory?(app_dsym_path)
      dsym_zip_path = generate_dsym_zip(app_dsym_path)

      puts ''
      puts "(i) The dSYM is now available at: #{dsym_zip_path}"
      system("envman add --key BITRISE_DSYM_PATH --value #{dsym_zip_path}")
    else
      puts '*(i) *Found dSYM path is not a directory!*'
    end
  end
end

def generate_dsym_zip(dsym_path)
  puts '=> Generating zip for dSym'

  dsym_parent_folder = File.dirname(dsym_path)
  dsym_fold_name = File.basename(dsym_path)
  # cd into dSYM parent to not to store full
  #  paths in the ZIP
  dsym_zip_path = File.join(@deploy_dir, "#{dsym_fold_name}.zip")
  Dir.chdir(dsym_parent_folder) do
    raise 'Generating zip for dSym failed' unless system("/usr/bin/zip -rTy #{dsym_zip_path} #{dsym_fold_name}")
  end
  dsym_zip_path
end

def export_xcarchive(export_options, archive_path)
  puts
  puts '=> Exporting IPA...'
  export_options_path = export_options
  unless export_options_path
    puts
    puts ' => Generating export options...'
    # Generate export options
    #  Bundle install
    current_dir = File.expand_path(File.dirname(__FILE__))
    gemfile_path = File.join(current_dir, 'Gemfile')

    bundle_install_command = "BUNDLE_GEMFILE=#{gemfile_path} bundle install"
    puts
    puts bundle_install_command
    success = system(bundle_install_command)
    fail_with_message('Failed to create export options (required gem install failed)') if success.nil? || !success


    #  Bundle exec
    export_options_path = File.join(@deploy_dir, 'export_options.plist')
    export_options_generator = File.join(current_dir, 'generate_export_options.rb')

    bundle_exec_command_params = ["BUNDLE_GEMFILE=#{gemfile_path} bundle exec ruby #{export_options_generator}"]
    bundle_exec_command_params << "-o \"#{export_options_path}\""
    bundle_exec_command_params << "-a \"#{archive_path}\""
    bundle_exec_command = bundle_exec_command_params.join(' ')
    puts
    puts bundle_exec_command
    success = system(bundle_exec_command)
    fail_with_message('Failed to create export options (required gem install failed)') if success.nil? || !success
  end

  # Export ipa
  temp_dir = Dir.mktmpdir('_bitrise_')

  export_command_params = ['xcodebuild -exportArchive']
  export_command_params << "-archivePath \"#{archive_path}\""
  export_command_params << "-exportPath \"#{temp_dir}\""
  export_command_params << "-exportOptionsPlist \"#{export_options_path}\""
  export_command = export_command_params.join(' ')
  puts
  puts export_command
  success = system(export_command)
  fail_with_message('Failed to export IPA') if success.nil? || !success

  temp_ipa_path = Dir[File.join(temp_dir, '*.ipa')].first
  fail_with_message('No generated ipa found') unless temp_ipa_path

  ipa_name = File.basename(temp_ipa_path)
  ipa_path = File.join(@deploy_dir, ipa_name)
  FileUtils.cp(temp_ipa_path, ipa_path)

  puts ''
  puts "(i) The IPA is now available at: #{ipa_path}"
  system("envman add --key BITRISE_IPA_PATH --value #{ipa_path}")
end

def export_apk(path)
  apk_name = File.basename(path)
  apk_path = File.join(@deploy_dir, apk_name)
  FileUtils.cp(path, apk_path)

  puts ''
  puts "(i) The apk is now available at: #{apk_path}"
  system("envman add --key BITRISE_APK_PATH --value #{apk_path}")
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
    platform_filter: nil
}

parser = OptionParser.new do |opts|
  opts.banner = 'Usage: step.rb [options]'
  opts.on('-p', '--project path', 'Project') { |p| options[:project] = p unless p.to_s == '' }
  opts.on('-c', '--configuration config', 'Configuration') { |c| options[:configuration] = c unless c.to_s == '' }
  opts.on('-l', '--platform platform', 'Platform') { |l| options[:platform] = l unless l.to_s == '' }
  opts.on('-e', '--options export', 'Export options') { |e| options[:export_options] = e unless e.to_s == '' }
  opts.on('-f', '--filter platform', 'Platform filter') { |f| options[:platform_filter] = f unless f.to_s == '' }
  opts.on('-h', '--help', 'Displays Help') do
    exit
  end
end
parser.parse!

if options[:platform_filter] != nil
  options[:platform_filter] = options[:platform_filter].split(',').collect { |x| x.strip || x }
end

#
# Print options
puts
puts '========== Configs =========='
puts " * project: #{options[:project]}"
puts " * configuration: #{options[:configuration]}"
puts " * platform: #{options[:platform]}"
puts " * export_options: #{options[:export_options]}"
puts " * platform_filter: #{options[:platform_filter]}"

#
# Validate options
fail_with_message('No project file found') unless options[:project] && File.exist?(options[:project])
fail_with_message('No configuration environment found') unless options[:configuration]
fail_with_message('No platform environment found') unless options[:platform]

#
# Main
builder = Builder.new(options[:project], options[:configuration], options[:platform], options[:platform_filter])
begin
  builder.build
rescue => ex
  fail_with_message("Build failed: #{ex}")
end


output = builder.generated_files

output.each do |_, project_output|
  if project_output[:apk]
    export_apk(project_output[:apk])
  elsif project_output[:xcarchive]
    export_xcarchive(options[:export_options], project_output[:xcarchive])
    export_dsym(project_output[:xcarchive])
  end
end
