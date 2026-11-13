#!/usr/bin/env ruby
# Adds / updates the PacketTunnel Network Extension target.
# Run on macOS (Codemagic): BRAND=xplm ruby ios/scripts/setup_packet_tunnel.rb
# Prefer: BRAND=xplm ruby ios/scripts/apply_ios_brand.rb && ruby ios/scripts/setup_packet_tunnel.rb
# Requires: gem install xcodeproj

require 'xcodeproj'
require 'fileutils'

ROOT = File.expand_path('../..', __dir__)
PROJECT_PATH = File.join(ROOT, 'ios', 'Runner.xcodeproj')
TUNNEL_DIR = File.join(ROOT, 'ios', 'PacketTunnel')
FRAMEWORKS = File.join(ROOT, 'ios', 'Frameworks', 'Libbox.xcframework')

BRAND = (ENV['BRAND'] || 'kpax').strip.downcase
BRAND_IDS = {
  'kpax' => {
    app: 'space.kpax.app',
    ext: 'space.kpax.app.extension',
    group: 'group.space.kpax.app',
  },
  'xplm' => {
    app: 'online.xplm.app',
    ext: 'online.xplm.app.extension',
    group: 'group.online.xplm.app',
  },
}.freeze
ids = BRAND_IDS[BRAND] || BRAND_IDS['kpax']

BUNDLE_APP = ENV['BUNDLE_ID'] || ENV['BUNDLE_ID_APP'] || ids[:app]
BUNDLE_EXT = ENV['BUNDLE_ID_EXT'] || ids[:ext]
APP_GROUP = ENV['APP_GROUP'] || ids[:group]

unless File.directory?(TUNNEL_DIR)
  abort "Missing #{TUNNEL_DIR}"
end

project = Xcodeproj::Project.open(PROJECT_PATH)
runner = project.targets.find { |t| t.name == 'Runner' }
abort 'Runner target not found' unless runner

tunnel = project.targets.find { |t| t.name == 'PacketTunnel' }
if tunnel.nil?
  tunnel = project.new_target(:app_extension, 'PacketTunnel', :ios, '15.0')
end
# Empty PRODUCT_NAME yields UninstalledProducts/iphoneos/.appex and
# "Multiple commands produce" during archive.
product_ref = tunnel.product_reference
product_ref.name = 'PacketTunnel.appex'
product_ref.path = 'PacketTunnel.appex' if product_ref.respond_to?(:path=)

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

# Info.plist / entitlements must not be in Copy Bundle Resources (duplicate outputs).
if tunnel.resources_build_phase
  tunnel.resources_build_phase.files.to_a.each do |bf|
    ref = bf.file_ref
    next unless ref
    path = ref.path.to_s
    if path.end_with?('Info.plist') || path.end_with?('.entitlements')
      tunnel.resources_build_phase.remove_build_file(bf)
    end
  end
end

# Embed extension in Runner (once).
embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' }
unless embed
  embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.symbol_dst_subfolder_spec = :plug_ins # 13
end
kept_product = false
embed.files.to_a.each do |bf|
  ref = bf.file_ref
  next unless ref
  is_appex = ref == product_ref ||
             ref.path.to_s.end_with?('.appex') ||
             ref.name.to_s.end_with?('.appex')
  next unless is_appex
  if ref == product_ref && !kept_product
    kept_product = true
    next
  end
  embed.remove_build_file(bf)
end
unless kept_product
  build_file = embed.add_file_reference(product_ref)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end

# Dependency Runner -> PacketTunnel
unless runner.dependencies.any? { |d| d.target == tunnel }
  runner.add_dependency(tunnel)
end

debug_xcconfig = project.files.find { |f| f.path.to_s.end_with?('Flutter/Debug.xcconfig') || f.path.to_s == 'Debug.xcconfig' }
release_xcconfig = project.files.find { |f| f.path.to_s.end_with?('Flutter/Release.xcconfig') || f.path.to_s == 'Release.xcconfig' }
abort 'Flutter Debug/Release xcconfig references are required' unless debug_xcconfig && release_xcconfig

# Build settings
%w[Debug Release Profile].each do |cfg_name|
  tcfg = tunnel.build_configurations.find { |c| c.name == cfg_name } ||
         tunnel.build_configurations.first
  next unless tcfg
  # Pull FLUTTER_BUILD_NAME / FLUTTER_BUILD_NUMBER from Flutter xcconfig (→ Generated.xcconfig)
  # so PacketTunnel Info.plist $(FLUTTER_BUILD_*) resolves at archive time.
  xcconfig = cfg_name == 'Debug' ? debug_xcconfig : release_xcconfig
  tcfg.base_configuration_reference = xcconfig if xcconfig
  tcfg.build_settings['PRODUCT_NAME'] = 'PacketTunnel'
  tcfg.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_EXT
  tcfg.build_settings['WRAPPER_EXTENSION'] = 'appex'
  tcfg.build_settings['INFOPLIST_FILE'] = 'PacketTunnel/Info.plist'
  tcfg.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  tcfg.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'PacketTunnel/PacketTunnel.entitlements'
  tcfg.build_settings['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'
  tcfg.build_settings['SKIP_INSTALL'] = 'YES'
  tcfg.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  tcfg.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  tcfg.build_settings['SWIFT_VERSION'] = '5.0'
  tcfg.build_settings['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  tcfg.build_settings['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  tcfg.build_settings['VERSIONING_SYSTEM'] = 'apple-generic'
  if File.directory?(FRAMEWORKS)
    tcfg.build_settings['FRAMEWORK_SEARCH_PATHS'] = '$(inherited) $(PROJECT_DIR)/Frameworks'
    # Libbox (Go) references res_9_*; must link system libresolv
    tcfg.build_settings['OTHER_LDFLAGS'] = '$(inherited) -framework Libbox -lresolv'
  end

  rcfg = runner.build_configurations.find { |c| c.name == cfg_name }
  next unless rcfg
  rcfg.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_APP
  rcfg.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
  rcfg.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  runner_ld = rcfg.build_settings['OTHER_LDFLAGS'] || '$(inherited)'
  runner_ld = runner_ld.is_a?(Array) ? runner_ld.join(' ') : runner_ld.to_s
  unless runner_ld.include?('-lresolv')
    rcfg.build_settings['OTHER_LDFLAGS'] = "#{runner_ld} -lresolv".strip
  end
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
