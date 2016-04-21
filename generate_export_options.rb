require 'optparse'
require 'plist'
require 'json'

require_relative 'xamarin-builder/api'

# -----------------------
# --- Functions
# -----------------------

def fail_with_message(message)
  puts "\e[31m#{message}\e[0m"
  exit(1)
end

def collect_provision_info(archive_path, target_os)
  applications_path = File.join(archive_path, '/Products/Applications')
  signing_identity_path = target_os.eql?(Api::IOS) ? '*.app/embedded.mobileprovision' : '*.app/Contents/embedded.provisionprofile'
  puts File.join(applications_path, signing_identity_path)
  provision_path = Dir[File.join(applications_path, signing_identity_path)].first

  fail_with_message('No provision_path found') if provision_path.nil?

  content = {}
  plist = Plist.parse_xml(`security cms -D -i "#{provision_path}"`)

  plist.each do |key, value|
    next if key == 'DeveloperCertificates'

    parse_value = nil
    case value
    when Hash
      parse_value = value
    when Array
      parse_value = value
    else
      parse_value = value.to_s
    end

    content[key] = parse_value
  end

  content
end

def export_method(mobileprovision_content)
  # if ProvisionedDevices: !nil & "get-task-allow": true -> development
  # if ProvisionedDevices: !nil & "get-task-allow": false -> ad-hoc
  # if ProvisionedDevices: nil & "ProvisionsAllDevices": "true" -> enterprise
  # if ProvisionedDevices: nil & ProvisionsAllDevices: nil -> app-store
  if mobileprovision_content['ProvisionedDevices'].nil?
    return 'enterprise' if !mobileprovision_content['ProvisionsAllDevices'].nil? && (mobileprovision_content['ProvisionsAllDevices'] == true || mobileprovision_content['ProvisionsAllDevices'] == 'true')
    return 'app-store'
  else
    unless mobileprovision_content['Entitlements'].nil?
      entitlements = mobileprovision_content['Entitlements']
      return 'development' if !entitlements['get-task-allow'].nil? && (entitlements['get-task-allow'] == true || entitlements['get-task-allow'] == 'true')
      return 'ad-hoc'
    end
  end
  return 'development'
end

# -----------------------
# --- Main
# -----------------------

puts

# Input validation
options = {
  export_options_path: nil,
  archive_path: nil,
  target_os: nil
}

parser = OptionParser.new do|opts|
  opts.banner = 'Usage: step.rb [options]'
  opts.on('-o', '--export_options_path path', 'Export options path') { |o| options[:export_options_path] = o unless o.to_s == '' }
  opts.on('-a', '--archive_path path', 'Archive path') { |a| options[:archive_path] = a unless a.to_s == '' }
  opts.on('-t', '--target_os string', 'Target operating system(ios or mac)') { |t| options[:target_os] = t unless t.to_s == '' }
  opts.on('-h', '--help', 'Displays Help') do
    puts opts
    exit
  end
end
parser.parse!

fail_with_message('export_options_path not specified') unless options[:export_options_path]
puts "export_options_path: #{options[:export_options_path]}"

fail_with_message('archive_path not specified') unless options[:archive_path]
puts "archive_path: #{options[:archive_path]}"

fail_with_message('target_os not specified') unless options[:target_os]
puts "target_os: #{options[:target_os]}"

puts
puts "\e[34mCollect provision info\e[0m"

mobileprovision_content = collect_provision_info(options[:archive_path], options[:target_os])
# team_id = mobileprovision_content['TeamIdentifier'].first
method = export_method(mobileprovision_content)


export_options = {}
export_options[:method] = method unless method.nil?

# explicitly set this option to false for Xamarin.Mac projects since they have no support of dSYMs
export_options[:uploadSymbols] = 'NO' if options[:target_os].eql?(Api::MAC)

puts
puts "\e[34mCreating export options for export type: #{export_options[:method]}\e[0m"

plist_content = Plist::Emit.dump(export_options)
puts "Plist saved at #{options[:export_options_path]}"
File.write(options[:export_options_path], plist_content)
