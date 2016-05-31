require 'optparse'
require 'plist'
require 'json'

# -----------------------
# --- Functions
# -----------------------

def log_fail(message)
  puts
  puts "\e[31m#{message}\e[0m"
  exit(1)
end

def log_info(message)
  puts
  puts "\e[34m#{message}\e[0m"
end

def log_details(message)
  puts "  #{message}"
end

# -----------------------
# --- Main
# -----------------------

# Input validation
options = {
  export_options_path: nil,
  archive_path: nil,
  export_method: nil
}

parser = OptionParser.new do|opts|
  opts.banner = 'Usage: step.rb [options]'
  opts.on('-o', '--export_options_path path', 'Export options path') { |o| options[:export_options_path] = o unless o.to_s == '' }
  opts.on('-a', '--archive_path path', 'Archive path') { |a| options[:archive_path] = a unless a.to_s == '' }
  opts.on('-e', '--export_method method', 'Export method') { |a| options[:export_method] = a unless a.to_s == '' }
  opts.on('-h', '--help', 'Displays Help') do
    puts opts
    exit
  end
end
parser.parse!

log_info('Configs:')
log_details("* export_options_path: #{options[:export_options_path]}")
log_details("* archive_path: #{options[:archive_path]}")
log_details("* export_method: #{options[:export_method]}")

log_fail('export_options_path not specified') if options[:export_options_path].to_s == ''
log_fail('archive_path not specified') if options[:archive_path].to_s == ''

method = options[:export_method] unless options[:export_method] == 'none'

log_info("Creating export options for export type: #{method}")

export_options = {}
export_options[:method] = method unless method.nil?
export_options[:uploadSymbols] = 'NO'

plist_content = Plist::Emit.dump(export_options)
log_details('* plist_content:')
puts plist_content.to_s

File.write(options[:export_options_path], plist_content)
