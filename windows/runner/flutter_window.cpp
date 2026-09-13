#include "flutter_window.h"

#include <optional>
#include <powersetting.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr UINT kAppearanceChanged = WM_APP + 51;
int64_t EncodeColor(int index) {
  const COLORREF value = GetSysColor(index);
  return static_cast<int64_t>(0xFF000000u | (GetRValue(value) << 16) |
                             (GetGValue(value) << 8) | GetBValue(value));
}
}

flutter::EncodableMap FlutterWindow::ReadAppearance() {
  HIGHCONTRASTW contrast{};
  contrast.cbSize = sizeof(contrast);
  const bool high = SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(contrast),
                                         &contrast, 0) &&
                    (contrast.dwFlags & HCF_HIGHCONTRASTON);
  SYSTEM_POWER_STATUS power{};
  const bool saver = GetSystemPowerStatus(&power) && power.SystemStatusFlag == 1;
  bool transparency = false;
  try {
    if (ui_settings_) transparency = ui_settings_.AdvancedEffectsEnabled();
  } catch (const winrt::hresult_error&) { transparency = false; }
  return {
    {flutter::EncodableValue("highContrast"), flutter::EncodableValue(high)},
    {flutter::EncodableValue("transparency"), flutter::EncodableValue(transparency)},
    {flutter::EncodableValue("batterySaver"), flutter::EncodableValue(saver)},
    {flutter::EncodableValue("background"), flutter::EncodableValue(EncodeColor(COLOR_WINDOW))},
    {flutter::EncodableValue("foreground"), flutter::EncodableValue(EncodeColor(COLOR_WINDOWTEXT))},
    {flutter::EncodableValue("highlight"), flutter::EncodableValue(EncodeColor(COLOR_HIGHLIGHT))},
    {flutter::EncodableValue("onHighlight"), flutter::EncodableValue(EncodeColor(COLOR_HIGHLIGHTTEXT))},
  };
}

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
  appearance_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "mubangumi/system_appearance",
      &flutter::StandardMethodCodec::GetInstance());
  appearance_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "read") result->Success(flutter::EncodableValue(ReadAppearance()));
    else result->NotImplemented();
  });
  try {
    ui_settings_ = winrt::Windows::UI::ViewManagement::UISettings();
    const HWND window = GetHandle();
    effects_token_ = ui_settings_.AdvancedEffectsEnabledChanged(
        [window](const auto&, const auto&) { PostMessage(window, kAppearanceChanged, 0, 0); });
  } catch (const winrt::hresult_error&) { ui_settings_ = nullptr; }
  power_notification_ = RegisterPowerSettingNotification(
      GetHandle(), &GUID_POWER_SAVING_STATUS, DEVICE_NOTIFY_WINDOW_HANDLE);
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (ui_settings_) {
    try { ui_settings_.AdvancedEffectsEnabledChanged(effects_token_); }
    catch (const winrt::hresult_error&) {}
    ui_settings_ = nullptr;
  }
  if (power_notification_) {
    UnregisterPowerSettingNotification(power_notification_);
    power_notification_ = nullptr;
  }
  appearance_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (appearance_channel_ && (message == kAppearanceChanged ||
      message == WM_SETTINGCHANGE || message == WM_SYSCOLORCHANGE ||
      message == WM_POWERBROADCAST)) {
    appearance_channel_->InvokeMethod("changed", nullptr);
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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
