#!/usr/bin/env ruby
# Adds / updates the PacketTunnel Network Extension target for K-Pax.
# Run on macOS (Codemagic): ruby ios/scripts/setup_packet_tunnel.rb
# Requires: gem install xcodeproj

require 'xcodeproj'
require 'fileutils'

ROOT = File.expand_path('../..', __dir__)
PROJECT_PATH = File.join(ROOT, 'ios', 'Runner.xcodeproj')
TUNNEL_DIR = File.join(ROOT, 'ios', 'PacketTunnel')
FRAMEWORKS = File.join(ROOT, 'ios', 'Frameworks', 'Libbox.xcframework')

BUNDLE_APP = 'space.kpax.app'
BUNDLE_EXT = 'space.kpax.app.extension'
APP_GROUP = 'group.space.kpax.app'

unless File.directory?(TUNNEL_DIR)
  abort "Missing #{TUNNEL_DIR}"
end

project = Xcodeproj::Project.open(PROJECT_PATH)
runner = project.targets.find { |t| t.name == 'Runner' }
abort 'Runner target not found' unless runner

tunnel = project.targets.find { |t| t.name == 'PacketTunnel' }
if tunnel.nil?
  tunnel = project.new_target(:app_extension, 'PacketTunnel', :ios, '15.0')
  tunnel.product_reference.name = 'PacketTunnel.appex'
end

# Group for sources
group = project.main_group.find_subpath('PacketTunnel', true)
group.set_source_tree('<group>')
group.set_path('PacketTunnel')

swift_files = Dir[File.join(TUNNEL_DIR, '*.swift')].map { |p| File.basename(p) }
plist = 'Info.plist'
entitlements = 'PacketTunnel.entitlements'

(swift_files + [plist, entitlements]).each do |name|
  path = File.join(TUNNEL_DIR, name)
  next unless File.exist?(path)
  ref = group.files.find { |f| f.path == name || f.path == "PacketTunnel/#{name}" }
  ref ||= group.new_file(name)
  if name.end_with?('.swift')
    unless tunnel.source_build_phase.files_references.include?(ref)
      tunnel.add_file_references([ref])
    end
  end
end

# Embed extension in Runner
embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' }
unless embed
  embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.symbol_dst_subfolder_spec = :plug_ins # 13
end
product_ref = tunnel.product_reference
unless embed.files_references.include?(product_ref)
  build_file = embed.add_file_reference(product_ref)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end

# Dependency Runner -> PacketTunnel
unless runner.dependencies.any? { |d| d.target == tunnel }
  runner.add_dependency(tunnel)
end

# Build settings
%w[Debug Release Profile].each do |cfg_name|
  tcfg = tunnel.build_configurations.find { |c| c.name == cfg_name } ||
         tunnel.build_configurations.first
  next unless tcfg
  tcfg.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_EXT
  tcfg.build_settings['INFOPLIST_FILE'] = 'PacketTunnel/Info.plist'
  tcfg.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'PacketTunnel/PacketTunnel.entitlements'
  tcfg.build_settings['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'
  tcfg.build_settings['SKIP_INSTALL'] = 'YES'
  tcfg.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  tcfg.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  tcfg.build_settings['SWIFT_VERSION'] = '5.0'
  if File.directory?(FRAMEWORKS)
    tcfg.build_settings['FRAMEWORK_SEARCH_PATHS'] = '$(inherited) $(PROJECT_DIR)/Frameworks'
    tcfg.build_settings['OTHER_LDFLAGS'] = '$(inherited) -framework Libbox'
  end

  rcfg = runner.build_configurations.find { |c| c.name == cfg_name }
  next unless rcfg
  rcfg.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_APP
  rcfg.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
  rcfg.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
end

# Link Libbox.xcframework into PacketTunnel when present
if File.directory?(FRAMEWORKS)
  fw_group = project.main_group.find_subpath('Frameworks', true)
  fw_group.set_source_tree('<group>')
  fw_group.set_path('Frameworks')
  lib_ref = fw_group.files.find { |f| f.path.to_s.include?('Libbox.xcframework') }
  lib_ref ||= fw_group.new_file('Libbox.xcframework')
  unless tunnel.frameworks_build_phase.files_references.include?(lib_ref)
    tunnel.frameworks_build_phase.add_file_reference(lib_ref)
  end
end

# Ensure Embed Foundation Extensions runs before Thin Binary
thin = runner.build_phases.find { |p| p.display_name.to_s.include?('Thin Binary') || p.respond_to?(:name) && p.name.to_s.include?('Thin Binary') }
if thin && embed
  phases = runner.build_phases
  e_idx = phases.index(embed)
  t_idx = phases.index(thin)
  if e_idx && t_idx && e_idx > t_idx
    phases.delete(embed)
    phases.insert(t_idx, embed)
  end
end

project.save
puts "PacketTunnel target ready (#{BUNDLE_EXT}), App Group #{APP_GROUP}"
