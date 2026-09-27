require "xcodeproj"

root = File.expand_path("..", __dir__)
project_path = File.join(root, "App", "FNMN.xcodeproj")
project = Xcodeproj::Project.new(project_path)
target = project.new_target(:application, "FNMN", :ios, "27.0")
target.build_configurations.each do |config|
  config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "local.fnmn.reader"
  config.build_settings["PRODUCT_NAME"] = "FNMN"
  config.build_settings["SWIFT_VERSION"] = "6.0"
  config.build_settings["GENERATE_INFOPLIST_FILE"] = "YES"
  config.build_settings["INFOPLIST_KEY_UILaunchScreen_Generation"] = "YES"
  config.build_settings["TARGETED_DEVICE_FAMILY"] = "1,2"
end

group = project.main_group.new_group("Sources")
files = Dir[File.join(root, "App", "FNMN", "*.swift")] + Dir[File.join(root, "Sources", "FNMNCore", "*.swift")]
files.sort.each do |path|
  reference = group.new_file(path)
  target.source_build_phase.add_file_reference(reference)
end
target.frameworks_build_phase.add_file_reference(project.frameworks_group.new_file("System/Library/Frameworks/WebKit.framework"))
project.save
