require 'optparse'
require_relative 'xamarin-builder/builder'

@nuget = '/Library/Frameworks/Mono.framework/Versions/Current/bin/nuget'

# -----------------------
# --- functions
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

# -----------------------
# --- main
# -----------------------

#
# Input validation
options = {
    project: nil,
    configuration: nil,
    platform: nil,
    clean_build: true,
}

parser = OptionParser.new do |opts|
  opts.banner = 'Usage: step.rb [options]'
  opts.on('-p', '--project path', 'Project') { |p| options[:project] = p unless p.to_s == '' }
  opts.on('-c', '--configuration config', 'Configuration') { |c| options[:configuration] = c unless c.to_s == '' }
  opts.on('-l', '--platform platform', 'Platform') { |l| options[:platform] = l unless l.to_s == '' }
  opts.on('-i', '--clean build', 'Clean build') { |i| options[:clean_build] = false if to_bool(i) == false }
  opts.on('-h', '--help', 'Displays Help') do
    exit
  end
end
parser.parse!

#
# Print configs
puts
puts '========== Configs =========='
puts " * project: #{options[:project]}"
puts " * configuration: #{options[:configuration]}"
puts " * platform: #{options[:platform]}"
puts " * clean_build: #{options[:clean_build]}"

#
# Validate inputs
fail_with_message('No project file found') unless options[:project] && File.exist?(options[:project])
fail_with_message('No configuration environment found') unless options[:configuration]
fail_with_message('No platform environment found') unless options[:platform]

#
# Main
builder = Builder.new(options[:project], options[:configuration], options[:platform])
builder.clean! if options[:clean_build]
built_projects = builder.build!

built_projects.each do |project|
  if project[:api] == MONO_ANDROID_API_NAME
    apk_path = builder.export_apk(project[:output_path])
    bitrise_apk_path = File.join(ENV['BITRISE_DEPLOY_DIR'], File.basename(apk_path))

    FileUtils.cp(apk_path, bitrise_apk_path)

    puts ''
    puts "(i) The apk is now available at: #{bitrise_apk_path}"
    system("envman add --key BITRISE_APK_PATH --value #{bitrise_apk_path}")
  end

  if project[:api] == MONOTOUCH_API_NAME || project[:api] == XAMARIN_IOS_API_NAME && project[:build_ipa]
    ipa_path = builder.export_ipa(project[:output_path])
    bitrise_ipa_path = File.join(ENV['BITRISE_DEPLOY_DIR'], File.basename(ipa_path))

    FileUtils.cp(ipa_path, bitrise_ipa_path)

    puts ''
    puts "(i) The IPA is now available at: #{bitrise_ipa_path}"
    system("envman add --key BITRISE_IPA_PATH --value #{bitrise_ipa_path}")

    dsym_path = builder.export_dsym(project[:output_path])
    dsym_zip_path = builder.zip_dsym(dsym_path)
    bitrise_dsym_zip_path = File.join(ENV['BITRISE_DEPLOY_DIR'], File.basename(dsym_zip_path))

    FileUtils.cp(dsym_zip_path, bitrise_dsym_zip_path)

    puts ''
    puts "(i) The dSYM is now available at: #{bitrise_dsym_zip_path}"
    system("envman add --key BITRISE_DSYM_PATH --value #{bitrise_dsym_zip_path}")
  end
end

