require 'optparse'
require_relative 'builder/builder'
require_relative 'logger/logger'
require_relative 'solution_analyzer/solution_analyzer'

@nuget = '/Library/Frameworks/Mono.framework/Versions/Current/bin/nuget'

# -----------------------
# --- functions
# -----------------------

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
  command: nil
}

parser = OptionParser.new do|opts|
  opts.banner = 'Usage: step.rb [options]'
  opts.on('-p', '--project path', 'Project') { |p| options[:project] = p unless p.to_s == '' }
  opts.on('-c', '--configuration config', 'Configuration') { |c| options[:configuration] = c unless c.to_s == '' }
  opts.on('-l', '--platform platform', 'Platform') { |l| options[:platform] = l unless l.to_s == '' }
  opts.on('-i', '--clean build', 'Clean build') { |i| options[:clean_build] = false if to_bool(i) == false }
  opts.on('-x', '--command command', 'Command command') { |x| options[:command] = x unless x.to_s == '' }
  opts.on('-h', '--help', 'Displays Help') do
    exit
  end
end
parser.parse!

fail_with_message('No project file found') unless options[:project] && File.exist?(options[:project])
fail_with_message('No configuration environment found') unless options[:configuration]
fail_with_message('No platform environment found') unless options[:platform]
fail_with_message('No command environment found') unless options[:command]

#
# Print configs
puts
puts '========== Configs =========='
puts " * project: #{options[:project]}"
puts " * configuration: #{options[:configuration]}"
puts " * platform: #{options[:platform]}"
puts " * clean_build: #{options[:clean_build]}"
puts " * command: #{options[:command]}"

def run(command, project, configuration, platform, clean)
  if clean
    puts
    puts "==> Cleaning project: #{project}"
    clean_project!(project, configuration, platform)
  end

  case command
  when 'build'
    puts
    puts "==> Building: #{project}"
    build_project!(project, configuration, platform)
  when 'archive'
    puts
    puts "==> Archive project: #{project}"
    api = get_xamarin_api(project)
    archive_project!(api, project, configuration, platform)
  end
end

case options[:command]
when 'build'
  run(options[:command], options[:project], options[:configuration], options[:platform], options[:clean_build])
when 'archive'
  case File.extname(options[:project])
  when '.csproj'
    run(options[:command], options[:project], options[:configuration], options[:platform], options[:clean_build])
  when '.sln'
    puts
    puts "==> Archive solution: #{options[:project]}"
    solution = analyze_solution(options[:project])
    solution['projects'].each do |project|
      mapping = project['mapping']
      configuration, platform = mapping["#{options[:configuration]}|#{options[:platform]}"].split("|")

      run(options[:command], project['path'], configuration, platform, options[:clean_build]) if configuration && platform
    end
  else
    fail_with_message("Invalid project: #{options[:project]}")
  end
else
  fail_with_message("Invalid command: #{options[:command]}")
end
