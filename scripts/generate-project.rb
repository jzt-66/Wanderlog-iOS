require 'xcodeproj'
require 'fileutils'

root = File.expand_path('..', __dir__)
Dir.chdir(root) do
  project = Xcodeproj::Project.new('Wanderlog.xcodeproj')
  project.build_configurations.each do |config|
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    config.build_settings['SWIFT_VERSION'] = '5.0'
  end
  target = project.new_target(:application, 'Wanderlog', :ios, '17.0')
  %w[Core App].each do |directory|
    group = project.main_group.new_group(directory, directory)
    Dir["#{directory}/*.swift"].sort.each { |file| target.source_build_phase.add_file_reference(group.new_file(File.basename(file))) }
  end
  resources = project.main_group.new_group('Resources', 'Resources')
  %w[SampleTrips.json WorldLand.json WorldLand-source.txt Assets.xcassets LaunchScreen.storyboard PrivacyInfo.xcprivacy].each do |name|
    target.resources_build_phase.add_file_reference(resources.new_file(name))
  end
  fonts = resources.new_group('Fonts', 'Fonts')
  %w[NotoSerifCJKsc-Regular.otf OFL.txt].each do |name|
    target.resources_build_phase.add_file_reference(fonts.new_file(name))
  end
  project.main_group.new_file('Info.plist')
  project.main_group.new_file('Wanderlog.entitlements')
  target.build_configurations.each do |config|
    config.build_settings.merge!({
      'PRODUCT_BUNDLE_IDENTIFIER' => 'com.wanderlog.travel',
      'DEVELOPMENT_TEAM' => 'UD4B2Y45PP',
      'CODE_SIGN_STYLE' => 'Automatic',
      'CODE_SIGN_ENTITLEMENTS' => 'Wanderlog.entitlements',
      'INFOPLIST_FILE' => 'Info.plist',
      'SWIFT_VERSION' => '5.0',
      'SWIFT_STRICT_CONCURRENCY' => 'targeted',
      'TARGETED_DEVICE_FAMILY' => '1,2',
      'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
      'MARKETING_VERSION' => '1.0.0',
      'CURRENT_PROJECT_VERSION' => '3',
      'ENABLE_USER_SCRIPT_SANDBOXING' => 'YES',
      'GENERATE_INFOPLIST_FILE' => 'NO'
    })
  end
  tests = project.new_target(:ui_test_bundle, 'WanderlogUITests', :ios, '17.0')
  tests.add_dependency(target)
  test_group = project.main_group.new_group('UITests', 'UITests')
  Dir['UITests/*.swift'].sort.each { |file| tests.source_build_phase.add_file_reference(test_group.new_file(File.basename(file))) }
  tests.build_configurations.each do |config|
    config.build_settings.merge!({
      'PRODUCT_BUNDLE_IDENTIFIER' => 'com.wanderlog.travel.uitests',
      'DEVELOPMENT_TEAM' => 'UD4B2Y45PP',
      'CODE_SIGN_STYLE' => 'Automatic',
      'GENERATE_INFOPLIST_FILE' => 'YES',
      'TEST_TARGET_NAME' => 'Wanderlog',
      'SWIFT_VERSION' => '5.0'
    })
  end
  project.save
  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(target)
  scheme.set_launch_target(target)
  scheme.add_test_target(tests)
  scheme.save_as(project.path, 'Wanderlog', true)
end
