#include "flutter_window.h"

#include <shellapi.h>
#include <commdlg.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kQuitMessage = WM_APP + 2;
constexpr UINT kTrayShow = 1;
constexpr UINT kTrayExit = 2;
constexpr UINT kTrayToggle = 3;
constexpr UINT kTrayToggleMessage = WM_APP + 3;

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "kpax/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "quit") {
          result->Success();
          PostMessage(GetHandle(), kQuitMessage, 0, 0);
          return;
        }
        if (call.method_name() == "setTrayState") {
          const auto* value = call.arguments() == nullptr
                                  ? nullptr
                                  : std::get_if<std::string>(call.arguments());
          if (value != nullptr) {
            tray_busy_ = *value == "busy";
            tray_connected_ = *value == "connected";
          }
          result->Success();
          return;
        }
        if (call.method_name() == "launchInstaller") {
          const auto* path = call.arguments() == nullptr
                                 ? nullptr
                                 : std::get_if<std::string>(call.arguments());
          if (path == nullptr ||
              path->find("K-Pax-Setup-update.exe") == std::string::npos) {
            result->Error("bad_path", "installer path rejected");
            return;
          }
          const int wide_size =
              MultiByteToWideChar(CP_UTF8, 0, path->c_str(), -1, nullptr, 0);
          if (wide_size <= 1) {
            result->Error("bad_path", "installer path rejected");
            return;
          }
          std::wstring exe(static_cast<size_t>(wide_size), L'\0');
          MultiByteToWideChar(CP_UTF8, 0, path->c_str(), -1, exe.data(),
                              wide_size);
          exe.assign(exe.c_str());
          std::wstring command =
              L"\"" + exe +
              L"\" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /FORCECLOSEAPPLICATIONS";
          STARTUPINFOW startup{};
          startup.cb = sizeof(startup);
          startup.dwFlags = STARTF_USESHOWWINDOW;
          startup.wShowWindow = SW_HIDE;
          PROCESS_INFORMATION process{};
          // The installer must leave the app job. Otherwise it is killed when
          // K-Pax exits, and the update stops with no window left.
          if (!CreateProcessW(exe.c_str(), command.data(), nullptr, nullptr,
                              FALSE,
                              CREATE_BREAKAWAY_FROM_JOB |
                                  CREATE_NEW_PROCESS_GROUP | DETACHED_PROCESS,
                              nullptr, nullptr, &startup, &process)) {
            result->Error("launch_failed", "could not start installer");
            return;
          }
          CloseHandle(process.hThread);
          CloseHandle(process.hProcess);
          result->Success();
          return;
        }
        if (call.method_name() == "pickExe") {
          wchar_t file[MAX_PATH] = {};
          OPENFILENAMEW dialog{};
          dialog.lStructSize = sizeof(dialog);
          dialog.hwndOwner = GetHandle();
          dialog.lpstrFilter = L"Programs\0*.exe\0";
          dialog.lpstrFile = file;
          dialog.nMaxFile = MAX_PATH;
          dialog.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST;
          if (GetOpenFileNameW(&dialog)) {
            result->Success(flutter::EncodableValue(WideToUtf8(file)));
          } else {
            result->Success();
          }
          return;
        }
        result->NotImplemented();
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
    this->AddTrayIcon();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::AddTrayIcon() {
  if (tray_added_ || GetHandle() == nullptr) {
    return;
  }
  tray_.cbSize = sizeof(tray_);
  tray_.hWnd = GetHandle();
  tray_.uID = 1;
  tray_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_.uCallbackMessage = kTrayMessage;
  tray_.hIcon = static_cast<HICON>(LoadImage(
      GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON), IMAGE_ICON,
      GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON),
      LR_DEFAULTCOLOR));
  wcscpy_s(tray_.szTip, sizeof(tray_.szTip) / sizeof(tray_.szTip[0]), L"K-Pax");
  if (Shell_NotifyIconW(NIM_ADD, &tray_)) {
    tray_added_ = true;
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_added_) {
    return;
  }
  Shell_NotifyIconW(NIM_DELETE, &tray_);
  if (tray_.hIcon != nullptr) {
    DestroyIcon(tray_.hIcon);
    tray_.hIcon = nullptr;
  }
  tray_added_ = false;
}

void FlutterWindow::ShowFromTray() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  ShowWindow(hwnd, SW_SHOW);
  ShowWindow(hwnd, SW_RESTORE);
  SetForegroundWindow(hwnd);
}

void FlutterWindow::ShowTrayMenu() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }
  AppendMenuW(menu, MF_STRING, kTrayShow, L"Открыть");
  const wchar_t* toggle_label =
      tray_connected_ ? L"Покинуть" : L"В эфир";
  AppendMenuW(menu, MF_STRING | (tray_busy_ ? MF_GRAYED : 0), kTrayToggle,
              toggle_label);
  AppendMenuW(menu, MF_STRING, kTrayExit, L"Закрыть приложение");
  POINT point;
  GetCursorPos(&point);
  SetForegroundWindow(hwnd);
  TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_NONOTIFY, point.x, point.y, 0,
                 hwnd, nullptr);
  DestroyMenu(menu);
  PostMessage(hwnd, WM_NULL, 0, 0);
}

void FlutterWindow::NotifyTrayToggle() {
  if (window_channel_ == nullptr || tray_busy_) {
    return;
  }
  window_channel_->InvokeMethod(
      "trayToggle", std::make_unique<flutter::EncodableValue>());
}

std::string FlutterWindow::WideToUtf8(const wchar_t* text) const {
  if (text == nullptr || text[0] == L'\0') {
    return {};
  }
  const int size =
      WideCharToMultiByte(CP_UTF8, 0, text, -1, nullptr, 0, nullptr, nullptr);
  if (size <= 1) {
    return {};
  }
  std::string out(static_cast<size_t>(size - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text, -1, out.data(), size, nullptr, nullptr);
  return out;
}

void FlutterWindow::RequestQuit() {
  if (quitting_) {
    return;
  }
  quitting_ = true;
  RemoveTrayIcon();
  SetQuitOnClose(true);
  Destroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // The installer asks the program to exit so it can replace its files.
  // The close button still only hides the window.
  if (message == WM_QUERYENDSESSION) {
    return TRUE;
  }
  if (message == WM_ENDSESSION && wparam != 0) {
    RequestQuit();
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_CLOSE:
      if (!quitting_) {
        ShowWindow(hwnd, SW_HIDE);
        AddTrayIcon();
        return 0;
      }
      break;
    case kQuitMessage:
      RequestQuit();
      return 0;
    case kTrayToggleMessage:
      NotifyTrayToggle();
      return 0;
    case kTrayMessage:
      if (lparam == WM_LBUTTONUP || lparam == WM_LBUTTONDBLCLK) {
        ShowFromTray();
      } else if (lparam == WM_RBUTTONUP) {
        ShowTrayMenu();
      }
      return 0;
    case WM_COMMAND:
      switch (LOWORD(wparam)) {
        case kTrayShow:
          ShowFromTray();
          return 0;
        case kTrayExit:
          RequestQuit();
          return 0;
        case kTrayToggle:
          PostMessage(hwnd, kTrayToggleMessage, 0, 0);
          return 0;
        default:
          break;
      }
      break;
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
