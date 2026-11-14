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
  tcfg.build_settings['LD_RUNPATH_SEARCH_PATHS'] =
    '$(inherited) @executable_path/Frameworks @loader_path/Frameworks @executable_path/../../Frameworks'
  tcfg.build_settings['SKIP_INSTALL'] = 'YES'
  tcfg.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  tcfg.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  tcfg.build_settings['SWIFT_VERSION'] = '5.0'
  tcfg.build_settings['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  tcfg.build_settings['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  tcfg.build_settings['VERSIONING_SYSTEM'] = 'apple-generic'
  tcfg.build_settings['FRAMEWORK_SEARCH_PATHS'] = '$(inherited) $(PROJECT_DIR)/Frameworks'
  # Libbox (Go) references res_9_*; must link system libresolv
  tcfg.build_settings['OTHER_LDFLAGS'] = '$(inherited) -framework Libbox -lresolv'

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

# App Store rejects Frameworks inside .appex (ASC 90205/90206). PacketTunnel only
# *links* Libbox; the host Runner.app embeds the framework. Extension loads it via
# @executable_path/../../Frameworks (set above in LD_RUNPATH_SEARCH_PATHS).
abort "Missing #{FRAMEWORKS} — run ios/scripts/build_libbox.sh before setup_packet_tunnel.rb" unless File.directory?(FRAMEWORKS)

fw_group = project.main_group.find_subpath('Frameworks', true)
fw_group.set_source_tree('<group>')
fw_group.set_path('Frameworks')
lib_ref = fw_group.files.find { |f| f.path.to_s.include?('Libbox.xcframework') }
lib_ref ||= fw_group.new_file('Libbox.xcframework')

# Never embed Libbox into the appex (Copy Files / old shell phase).
tunnel.copy_files_build_phases.select { |p| p.name == 'Embed Frameworks' }.each do |phase|
  phase.files.to_a.each do |bf|
    ref = bf.file_ref
    next unless ref && ref.path.to_s.include?('Libbox')
    phase.remove_build_file(bf)
  end
end
[
  'Embed Libbox into PacketTunnel',
  'Strip Frameworks from PacketTunnel',
].each do |old_name|
  tunnel.shell_script_build_phases.select { |p| p.name == old_name }.each do |p|
    tunnel.build_phases.delete(p)
  end
end

existing = tunnel.frameworks_build_phase.files.find { |bf| bf.file_ref == lib_ref }
if existing
  existing.settings = {} # Do Not Embed — link only
else
  tunnel.frameworks_build_phase.add_file_reference(lib_ref)
end

# Last resort: delete Frameworks/ if anything still copied into the appex.
strip_name = 'Strip Frameworks from PacketTunnel'
strip = tunnel.new_shell_script_build_phase(strip_name)
strip.shell_path = '/bin/sh'
strip.show_env_vars_in_log = '0'
strip.shell_script = <<~'SCRIPT'
  set -euo pipefail
  APPEX="${TARGET_BUILD_DIR}/${FULL_PRODUCT_NAME}"
  if [ ! -d "$APPEX" ]; then
    APPEX="${BUILT_PRODUCTS_DIR}/${FULL_PRODUCT_NAME}"
  fi
  if [ -d "$APPEX/Frameworks" ]; then
    echo "warning: removing disallowed Frameworks from PacketTunnel.appex (ASC 90206)"
    rm -rf "$APPEX/Frameworks"
  fi
SCRIPT
tunnel_phases = tunnel.build_phases
tunnel_phases.delete(strip)
tunnel_phases << strip

# Embed + normalize Libbox into the *host* app (Runner), not the extension.
runner_embed_name = 'Embed Libbox into Runner'
runner.shell_script_build_phases.select { |p| p.name == runner_embed_name }.each do |p|
  runner.build_phases.delete(p)
end
runner_phase = runner.new_shell_script_build_phase(runner_embed_name)
runner_phase.shell_path = '/bin/sh'
runner_phase.show_env_vars_in_log = '0'
runner_phase.shell_script = <<~'SCRIPT'
  set -euo pipefail
  # Re-normalize + replace whatever CocoaPods copied (must be shallow dylib framework).
  XCFRAMEWORK="${PROJECT_DIR}/Frameworks/Libbox.xcframework"
  NORM="${PROJECT_DIR}/scripts/normalize_libbox_framework.sh"
  if [ ! -d "$XCFRAMEWORK" ]; then
    echo "error: missing $XCFRAMEWORK" >&2
    exit 1
  fi
  if [ -f "$NORM" ]; then
    # shellcheck disable=SC1090
    . "$NORM"
    normalize_xcframework "$XCFRAMEWORK"
  fi

  SLICE=""
  if [ "${PLATFORM_NAME:-}" = "iphonesimulator" ]; then
    for d in "$XCFRAMEWORK"/ios-*-simulator "$XCFRAMEWORK"/ios-arm64_x86_64-simulator; do
      if [ -d "$d/Libbox.framework" ]; then SLICE="$d"; break; fi
    done
  else
    if [ -d "$XCFRAMEWORK/ios-arm64/Libbox.framework" ]; then
      SLICE="$XCFRAMEWORK/ios-arm64"
    else
      for d in "$XCFRAMEWORK"/ios-arm64*; do
        case "$d" in *simulator*) continue ;; esac
        if [ -d "$d/Libbox.framework" ]; then SLICE="$d"; break; fi
      done
    fi
  fi
  SRC="${SLICE}/Libbox.framework"
  if [ -z "$SLICE" ] || [ ! -d "$SRC" ]; then
    echo "error: Libbox.framework slice not found (platform=${PLATFORM_NAME:-unset})" >&2
    exit 1
  fi
  if [ -d "$SRC/Versions" ]; then
    echo "error: $SRC still has Versions/ — run normalize_libbox_framework.sh" >&2
    exit 1
  fi

  FFP="${FRAMEWORKS_FOLDER_PATH:-Frameworks}"
  DEST_DIR="${TARGET_BUILD_DIR}/${FFP}"
  DEST="${DEST_DIR}/Libbox.framework"
  echo "Embedding Libbox into Runner: $SRC -> $DEST"
  mkdir -p "$DEST_DIR"
  rm -rf "$DEST"
  /usr/bin/ditto "$SRC" "$DEST"

  BINARY="$DEST/Libbox"
  if [ ! -f "$BINARY" ]; then
    echo "error: Libbox binary missing in $DEST" >&2
    ls -laR "$DEST" >&2 || true
    exit 1
  fi
  BIN_SIZE=$(/usr/bin/stat -f%z "$BINARY" 2>/dev/null || /usr/bin/stat -c%s "$BINARY")
  if [ "${BIN_SIZE:-0}" -lt 1000000 ]; then
    echo "error: Libbox binary too small (${BIN_SIZE} bytes) at $BINARY" >&2
    exit 1
  fi
  DESC=$(/usr/bin/file -b "$BINARY" || true)
  case "$DESC" in
    *dynamically\ linked*|*shared\ library*|*Mach-O*dylib*) ;;
    *)
      echo "error: Libbox is not a dylib ($DESC) — ASC 90171" >&2
      exit 1
      ;;
  esac
  for req in Info.plist Resources/Info.plist; do
    if [ ! -f "$DEST/$req" ]; then
      echo "error: missing $DEST/$req" >&2
      exit 1
    fi
  done
  EXEC=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$DEST/Info.plist" 2>/dev/null || true)
  if [ "$EXEC" != "Libbox" ]; then
    echo "error: CFBundleExecutable='$EXEC' (want Libbox)" >&2
    exit 1
  fi
  # ASC 90535: Resources/Info.plist must be BNDL without CFBundleExecutable.
  RES_EXEC=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$DEST/Resources/Info.plist" 2>/dev/null || true)
  if [ -n "$RES_EXEC" ]; then
    echo "error: Resources/Info.plist has CFBundleExecutable='$RES_EXEC' (ASC 90535)" >&2
    exit 1
  fi
  RES_TYPE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$DEST/Resources/Info.plist" 2>/dev/null || true)
  if [ "$RES_TYPE" != "BNDL" ]; then
    echo "error: Resources/Info.plist CFBundlePackageType='$RES_TYPE' (want BNDL)" >&2
    exit 1
  fi
  /usr/bin/install_name_tool -id "@rpath/Libbox.framework/Libbox" "$BINARY" 2>/dev/null || true

  IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
  if [ -z "$IDENTITY" ] || [ "$IDENTITY" = "-" ]; then
    IDENTITY="${CODE_SIGN_IDENTITY:-}"
  fi
  if [ -z "$IDENTITY" ] || [ "$IDENTITY" = "-" ]; then
    echo "error: no code signing identity to sign embedded Libbox" >&2
    exit 1
  fi
  /usr/bin/codesign --force --sign "$IDENTITY" --timestamp=none "$BINARY"
  if ! /usr/bin/codesign --force --sign "$IDENTITY" --timestamp=none --generate-entitlement-der "$DEST"; then
    /usr/bin/codesign --force --deep --sign "$IDENTITY" --timestamp=none "$DEST"
  fi
  /usr/bin/codesign --verify "$DEST"
  echo "OK Libbox in Runner ($(du -sh "$DEST" | awk '{print $1}'), dylib ${BIN_SIZE} bytes)"
SCRIPT

# After CocoaPods embed (replace stub/bad copy), before Thin Binary / codesign.
thin = runner.build_phases.find { |p| p.display_name.to_s.include?('Thin Binary') || p.respond_to?(:name) && p.name.to_s.include?('Thin Binary') }
pods_embed = runner.build_phases.find do |p|
  name = p.respond_to?(:name) ? p.name.to_s : p.display_name.to_s
  name.include?('Embed Pods Frameworks')
end
runner_phases = runner.build_phases
runner_phases.delete(runner_phase)
insert_at = nil
insert_at = runner_phases.index(pods_embed) + 1 if pods_embed && runner_phases.index(pods_embed)
insert_at = runner_phases.index(thin) if insert_at.nil? && thin && runner_phases.index(thin)
if insert_at
  runner_phases.insert(insert_at, runner_phase)
else
  runner_phases << runner_phase
end
if thin && embed
  e_idx = runner_phases.index(embed)
  t_idx = runner_phases.index(thin)
  if e_idx && t_idx && e_idx > t_idx
    runner_phases.delete(embed)
    runner_phases.insert(t_idx, embed)
  end
end

project.save
puts "PacketTunnel target ready (#{BUNDLE_EXT}), App Group #{APP_GROUP}; Libbox embeds into Runner only"

