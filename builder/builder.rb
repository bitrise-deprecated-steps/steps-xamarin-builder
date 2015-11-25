require 'pathname'
require 'fileutils'

@mdtool = "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\""

def clean_project!(project, configuration, platform)
  params = []
  params << "xbuild"
  params << "\"#{project}\""
  params << '/t:Clean'
  params << "/p:Configuration=\"#{configuration}\""
  params << "/p:Platform=\"#{platform}\""

  puts "#{params.join(' ')}"
  system("#{params.join(' ')}")
  fail_with_message('Clean failed') unless $?.success?
end

def build_project!(project, configuration, platform)
  output_path = File.join('bin', platform, configuration)

  params = []
  params << 'xbuild'
  params << "\"#{project}\""
  params << '/t:Build'
  params << "/p:Configuration=\"#{configuration}\""
  params << "/p:Platform=\"#{platform}\""
  params << "/p:OutputPath=\"#{output_path}/\""

  puts "#{params.join(' ')}"
  system("#{params.join(' ')}")
  fail_with_message('Build failed') unless $?.success?
end

def archive_project!(api, project, configuration, platform)
  case api
  when 'Mono.Android'
    archive_android_project!(project, configuration, platform, false)
  when 'monotouch'
    archive_ios_project!('mdtool', project, configuration, platform)
  when 'Xamarin.iOS'
    archive_ios_project!('xbuild', project, configuration, platform)
  else
    fail_with_message("Invalid api: #{api}")
  end
end

def archive_ios_project!(builder, project, configuration, platform)
  output_path = File.join('bin', platform, configuration)

  params = []
  case builder
  when 'xbuild'
    params << 'xbuild'
    params << "\"#{project}\""
    params << '/t:Build'
    params << "/p:Configuration=\"#{configuration}\""
    params << "/p:Platform=\"#{platform}\""
    params << '/p:BuildIpa=true'
    params << "/p:OutputPath=\"#{output_path}/\""
  when 'mdtool'
    params << "#{@mdtool}"
    params << '-v build'
    params << "\"#{project}\""
    params << "--configuration:\"#{configuration}|#{platform}\""
    params << '--target:Build'
  else
    fail_with_message('Invalid build tool detected')
  end

  puts "#{params.join(' ')}"
  system("#{params.join(' ')}")
  fail_with_message('Build failed') unless $?.success?

  if builder.eql? 'mdtool'
    project_directory = File.dirname(project)
    app = Dir[File.join(project_directory, 'bin', platform, configuration, '/*.app')].first
    fail_with_message('No generated app file found') unless app
    app = Pathname.new(app).realpath.to_s
    app_name = File.basename(app, '.*')
    app_path = File.dirname(app)
    ipa_path = File.join(app_path, "#{app_name}.ipa")

    unless File.exist? ipa_path
      puts
      puts '==> Packaging application'
      puts "xcrun -sdk iphoneos PackageApplication -v \"#{app}\" -o \"#{ipa_path}\""
      system("xcrun -sdk iphoneos PackageApplication -v #{app} -o #{ipa_path}")
      fail_with_message('Failed to create .ipa from .app') unless $?.success?
    end
  end

  export_ipa(project, configuration, platform)
end

def archive_android_project!(project, configuration, platform, sign_apk)
  # /t:SignAndroidPackage -> generate a signed and unsigned APK
  # /t:PackageForAndroid -> generate a unsigned APK
  output_path = File.join('bin', platform, configuration)

  params = ['xbuild']
  params << "\"#{project}\""
  params << "/p:Configuration=\"#{configuration}\""
  params << "/p:Platform=\"#{platform}\""
  params << '/t:SignAndroidPackage' if sign_apk
  params << '/t:PackageForAndroid' unless sign_apk
  params << "/p:OutputPath=\"#{output_path}/\""

  puts "#{params.join(' ')}"
  system("#{params.join(' ')}")
  fail_with_message('Build failed') unless $?.success?

  export_apk(project, configuration)
end

def export_apk(project, configuration)
  project_dir = File.dirname(project)
  apk = Dir[File.join(project_dir, 'bin', '**', configuration, '**', '*.apk')].first
  fail_with_message('No generated apk file found') unless apk
  puts "(i) apk found at path: #{apk}"

  temp_path = Pathname.new(apk).realpath.to_s
  full_path = File.join(ENV['BITRISE_DEPLOY_DIR'], File.basename(temp_path))
  FileUtils.mv(temp_path, full_path)

  puts ''
  puts "(i) The apk is now available at: #{full_path}"
  system("envman add --key BITRISE_APK_PATH --value #{full_path}")
  fail_with_message('Failed to export BITRISE_APK_PATH') unless $?.success?
end

def export_ipa(project, configuration, platform)
  project_dir = File.dirname(project)
  ipa = Dir[File.join(project_dir, 'bin', platform, configuration, '/*.ipa')].first

  unless ipa
    error_with_message('No generated ipa file found')
    return
  end

  puts "(i) ipa found at path: #{ipa}"

  temp_path = Pathname.new(ipa).realpath.to_s
  temp_dir = File.dirname(temp_path)
  full_path = File.join(ENV['BITRISE_DEPLOY_DIR'], File.basename(temp_path))
  unless File.exists?(full_path)
    FileUtils.mv(temp_path, full_path)

    puts ''
    puts "(i) The IPA is now available at: #{full_path}"
    system("envman add --key BITRISE_IPA_PATH --value #{full_path}")

    dsym_file = Dir["#{temp_dir}/*.app.dSYM"].first

    dsym_name = File.basename(File.basename(dsym_file, '.*'), '.*')

    if File.exist? dsym_file
      dsym_zip = File.join(temp_dir, "#{dsym_name}.dSYM.zip")
      puts
      puts '==> Zip dSYM'
      system("/usr/bin/zip -rTy #{dsym_zip} #{dsym_file}")
      fail_with_message('Failed to zip dSYM') unless $?.success?

      temp_path = Pathname.new(dsym_zip).realpath.to_s
      full_path = File.join(ENV['BITRISE_DEPLOY_DIR'], File.basename(temp_path))
      FileUtils.mv(temp_path, full_path)

      puts ''
      puts "(i) The dSYM is now available at: #{full_path}"
      system("envman add --key BITRISE_DSYM_PATH --value #{full_path}")
      fail_with_message('Failed to export BITRISE_DSYM_PATH') unless $?.success?
    end
  end
end
