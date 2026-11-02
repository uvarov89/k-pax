#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {
constexpr wchar_t kSingleInstanceMutex[] = L"Local\\KPax.SingleInstance.Mutex";
constexpr wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kWindowTitle[] = L"K-Pax";

bool ActivateExistingInstance() {
  HWND existing = ::FindWindowW(kWindowClassName, kWindowTitle);
  if (existing == nullptr) {
    return false;
  }
  if (::IsIconic(existing)) {
    ::ShowWindow(existing, SW_RESTORE);
  } else {
    ::ShowWindow(existing, SW_SHOW);
  }
  // Bring the running window forward (also when opened via kpax://).
  DWORD foreground_tid = ::GetWindowThreadProcessId(::GetForegroundWindow(), nullptr);
  DWORD target_tid = ::GetWindowThreadProcessId(existing, nullptr);
  if (foreground_tid != 0 && target_tid != 0 && foreground_tid != target_tid) {
    ::AttachThreadInput(foreground_tid, target_tid, TRUE);
    ::BringWindowToTop(existing);
    ::SetForegroundWindow(existing);
    ::AttachThreadInput(foreground_tid, target_tid, FALSE);
  } else {
    ::BringWindowToTop(existing);
    ::SetForegroundWindow(existing);
  }
  ::FlashWindow(existing, TRUE);
  return true;
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  HANDLE single_instance = ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutex);
  if (single_instance != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    ActivateExistingInstance();
    ::CloseHandle(single_instance);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(80, 40);
  Win32Window::Size size(440, 760);
  if (!window.Create(L"K-Pax", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(false);

  HANDLE job = CreateJobObjectW(nullptr, nullptr);
  if (job != nullptr) {
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION info{};
    info.BasicLimitInformation.LimitFlags =
        JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_BREAKAWAY_OK;
    if (SetInformationJobObject(job, JobObjectExtendedLimitInformation, &info,
                                sizeof(info))) {
      AssignProcessToJobObject(job, GetCurrentProcess());
    }
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
