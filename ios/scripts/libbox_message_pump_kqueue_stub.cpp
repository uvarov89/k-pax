// Stub for Cronet/base when force-loading Libbox c-archive into an iOS dylib.
// MessagePumpKqueue is macOS-only; some Cronet objects still reference Init.
namespace base {
class MessagePumpKqueue {
 public:
  static void InitializeFeatures();
};

void MessagePumpKqueue::InitializeFeatures() {}
}  // namespace base
