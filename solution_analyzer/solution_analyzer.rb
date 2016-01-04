require_relative '../logger/logger'

def allowed_to_sign_android_project(project_path, configuration, platform)
  # <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Debug|AnyCPU' ">
  config_regex = '<PropertyGroup Condition=" \'\$\(Configuration\)\|\$\(Platform\)\' == \'(?<config>.*)\' ">'
  config = configuration + '|' + platform
  related_config_start = false

  File.open(project_path).each do |line|
    match = line.match(config_regex)
    if match && match.captures && match.captures.count == 1
      found_config = match.captures[0]

      related_config_start = (found_config == config)
    end

    next unless related_config_start

    return true if line.include? '<AndroidKeyStore>True</AndroidKeyStore>'
  end

  return false
end

def get_xamarin_api(project_path)
  if File.file?(project_path)
    lines = File.readlines(project_path)

    return 'Mono.Android' if lines.grep(/Include="Mono.Android"/).size > 0
    return 'monotouch' if lines.grep(/Include="monotouch"/).size > 0
    return 'Xamarin.iOS' if lines.grep(/Include="Xamarin.iOS"/).size > 0
  end
  return nil
end

def analyze_solution(solution_path)
  solution = {}
  projects = {}

  base_directory = File.dirname(solution_path)

  p_regex = 'Project\("{(?<solution_id>.*)}"\) = "(?<project_name>.*)", "(?<project_path>.*)", "{(?<project_id>.*)}"'

  is_next_s_config = false
  s_configs_start = 'GlobalSection(SolutionConfigurationPlatforms) = preSolution'
  s_configs_end = 'EndGlobalSection'

  is_next_p_config = false
  p_configs_start = 'GlobalSection(ProjectConfigurationPlatforms) = postSolution'
  p_configs_end = 'EndGlobalSection'
  p_config_regex = '{(?<project_id>.*)}.(?<solution_configuration_platform>.*|.*) = (?<project_configuration_platform>.*)'

  File.open(solution_path).each do |line|
    #
    # Coellect Projects
    match = line.match(p_regex)
    if match && match.captures && match.captures.count == 4
      solution['projects'] = [] unless solution['projects']

      # solution_id =  match.captures[0]
      # project_name = match.captures[1]
      project_path = match.captures[2].strip.gsub(/\\/, '/')
      project_path = File.join(base_directory, project_path)

      project_id = match.captures[3]

      received_api = get_xamarin_api(project_path)
      unless received_api.nil?
        solution['projects'] << {
          'id' => project_id,
          'path' => project_path,
          'api' => received_api
        }

        next
      end
    end

    #
    # Collect SolutionConfigurationPlatforms
    is_next_s_config = false if line.include?(s_configs_end) && is_next_s_config == true

    if is_next_s_config
      begin
        config = line.split('=')[1].strip!

        solution['configs'] = [] unless solution['configs']
        solution['configs'] << config

        next
      rescue
        fail_with_message("Failed to parse configuration: #{line}")
      end
    end

    is_next_s_config = true if line.include?(s_configs_start)

    #
    # Collect ProjectConfigurationPlatforms
    is_next_p_config = false if line.include?(p_configs_end) && is_next_p_config == true

    if is_next_p_config
      match = line.match(p_config_regex)
      if match && match.captures && match.captures.count == 3
        project_id = match.captures[0]

        s_config = match.captures[1].strip
        if s_config.include? '.'
          s_config = s_config.split('.')[0]
        end
        p_config = match.captures[2].strip.gsub(' ', '')

        projects["#{project_id}"] = {} unless projects["#{project_id}"]
        projects["#{project_id}"][s_config] = p_config
      end

      next
    end

    is_next_p_config = true if line.include? p_configs_start
  end

  ret_projects = []
  s_projects = solution['projects']
  s_projects.each do |proj|
    id = proj['id']
    mapping = projects["#{id}"]
    path = proj['path']
    api = proj['api']

    proj['mapping'] = mapping

    ret_projects << {
      'path' => path,
      'mapping' => mapping,
      'api' => api
    }
  end

  solution['projects'] = ret_projects
  return solution
end
