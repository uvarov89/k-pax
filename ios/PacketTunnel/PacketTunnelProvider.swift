import Foundation
import NetworkExtension

/// Host Packet Tunnel entry: reuses ExtensionProvider from the vendored sing_box sources
/// that Codemagic compiles into this target (see ios/scripts/setup_packet_tunnel.rb).
final class PacketTunnelProvider: ExtensionProvider {}
