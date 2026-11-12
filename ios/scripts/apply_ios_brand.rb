#!/usr/bin/env ruby
# Apply K-Pax or X-Plm identifiers/names to the iOS project (pre-publish / Codemagic).
# Usage: BRAND=xplm ruby ios/scripts/apply_ios_brand.rb
# Then:  BRAND=xplm ruby ios/scripts/setup_packet_tunnel.rb

require 'fileutils'

ROOT = File.expand_path('../..', __dir__)
BRAND = (ENV['BRAND'] || 'kpax').strip.downcase

BRANDS = {
  'kpax' => {
    bundle_app: 'space.kpax.app',
    bundle_ext: 'space.kpax.app.extension',
    app_group: 'group.space.kpax.app',
    display_name: 'K-Pax',
    tunnel_name: 'K-Pax Tunnel',
    url_scheme: 'kpax',
    app_icon: 'AppIcon',
    local_network:
      'K-Pax uses the local network while the VPN tunnel is active.',
  },
  'xplm' => {
    bundle_app: 'online.xplm.app',
    bundle_ext: 'online.xplm.app.extension',
    app_group: 'group.online.xplm.app',
    display_name: 'X-Plm',
    tunnel_name: 'X-Plm Tunnel',
    url_scheme: 'xplm',
    app_icon: 'AppIcon-Xplm',
    local_network:
      'X-Plm uses the local network while the VPN tunnel is active.',
  },
}.freeze

cfg = BRANDS[BRAND]
abort "Unknown BRAND=#{BRAND.inspect} (expected: #{BRANDS.keys.join(', ')})" unless cfg

def write_entitlements(path, app_group)
  File.write(path, <<~XML)
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    \t<key>com.apple.developer.networking.networkextension</key>
    \t<array>
    \t\t<string>packet-tunnel-provider</string>
    \t</array>
    \t<key>com.apple.security.application-groups</key>
    \t<array>
    \t\t<string>#{app_group}</string>
    \t</array>
    </dict>
    </plist>
  XML
end

def replace_plist_string(path, key, value)
  text = File.read(path)
  pattern = %r{(<key>#{Regexp.escape(key)}</key>\s*<string>)[^<]*(</string>)}
  raise "key #{key} not found in #{path}" unless text.match?(pattern)

  File.write(path, text.sub(pattern, "\\1#{value}\\2"))
end

def ensure_plist_false(path, key)
  text = File.read(path)
  return if text.include?("<key>#{key}</key>")

  updated = text.sub(
    %r{</dict>\s*</plist>\s*\z},
    "\t<key>#{key}</key>\n\t<false/>\n</dict>\n</plist>\n"
  )
  raise "could not insert #{key} into #{path}" if updated == text

  File.write(path, updated)
end

def replace_url_types(path, bundle_app, scheme)
  text = File.read(path)
  # Replace CFBundleURLName + CFBundleURLSchemes block under CFBundleURLTypes.
  updated = text.sub(
    %r{(<key>CFBundleURLName</key>\s*<string>)[^<]*(</string>)},
    "\\1#{bundle_app}\\2"
  )
  updated = updated.sub(
    %r{(<key>CFBundleURLSchemes</key>\s*<array>\s*<string>)[^<]*(</string>)},
    "\\1#{scheme}\\2"
  )
  File.write(path, updated)
end

def patch_pbxproj(path, bundle_app, app_icon)
  text = File.read(path)
  # Runner / tests bundle ids
  text.gsub!(/PRODUCT_BUNDLE_IDENTIFIER = space\.kpax\.app;/, "PRODUCT_BUNDLE_IDENTIFIER = #{bundle_app};")
  text.gsub!(/PRODUCT_BUNDLE_IDENTIFIER = online\.xplm\.app;/, "PRODUCT_BUNDLE_IDENTIFIER = #{bundle_app};")
  text.gsub!(/PRODUCT_BUNDLE_IDENTIFIER = space\.kpax\.app\.RunnerTests;/, "PRODUCT_BUNDLE_IDENTIFIER = #{bundle_app}.RunnerTests;")
  text.gsub!(/PRODUCT_BUNDLE_IDENTIFIER = online\.xplm\.app\.RunnerTests;/, "PRODUCT_BUNDLE_IDENTIFIER = #{bundle_app}.RunnerTests;")
  text.gsub!(/ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon(?:-Xplm)?;/, "ASSETCATALOG_COMPILER_APPICON_NAME = #{app_icon};")
  File.write(path, text)
end

runner_plist = File.join(ROOT, 'ios', 'Runner', 'Info.plist')
tunnel_plist = File.join(ROOT, 'ios', 'PacketTunnel', 'Info.plist')
pbxproj = File.join(ROOT, 'ios', 'Runner.xcodeproj', 'project.pbxproj')

write_entitlements(File.join(ROOT, 'ios', 'Runner', 'Runner.entitlements'), cfg[:app_group])
write_entitlements(File.join(ROOT, 'ios', 'PacketTunnel', 'PacketTunnel.entitlements'), cfg[:app_group])

replace_plist_string(runner_plist, 'CFBundleDisplayName', cfg[:display_name])
replace_plist_string(runner_plist, 'CFBundleName', cfg[:display_name])
replace_plist_string(runner_plist, 'NSLocalNetworkUsageDescription', cfg[:local_network])
replace_url_types(runner_plist, cfg[:bundle_app], cfg[:url_scheme])
ensure_plist_false(runner_plist, 'ITSAppUsesNonExemptEncryption')
replace_plist_string(tunnel_plist, 'CFBundleDisplayName', cfg[:tunnel_name])

patch_pbxproj(pbxproj, cfg[:bundle_app], cfg[:app_icon])

# Expose for setup_packet_tunnel.rb / shell
ENV['BUNDLE_ID'] = cfg[:bundle_app]
ENV['BUNDLE_ID_EXT'] = cfg[:bundle_ext]
ENV['APP_GROUP'] = cfg[:app_group]

puts "Applied iOS brand=#{BRAND}"
puts "  app=#{cfg[:bundle_app]}"
puts "  ext=#{cfg[:bundle_ext]}"
puts "  group=#{cfg[:app_group]}"
puts "  name=#{cfg[:display_name]} icon=#{cfg[:app_icon]} scheme=#{cfg[:url_scheme]}"
