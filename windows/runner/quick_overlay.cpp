#include "quick_overlay.h"

#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <objidl.h>

#include <algorithm>
#include <cmath>
#include <cstdlib>

// GDI+ headers rely on min/max macros, which NOMINMAX disables.
namespace Gdiplus {
using std::max;
using std::min;
}  // namespace Gdiplus
#include <gdiplus.h>

namespace {

constexpr const wchar_t kWindowClassName[] = L"LIFEOS_QUICK_OVERLAY";
constexpr const char kChannelName[] = "lifeos/system_overlay";

// Logical size of the bubble and gap to the work area edges, in DIPs.
constexpr int kBubbleSize = 48;
constexpr int kEdgeMargin = 8;

// Opacity while idle and while hovered / pressed / menu open.
constexpr BYTE kIdleAlpha = 140;
constexpr BYTE kActiveAlpha = 255;

constexpr UINT_PTR kVisibilityTimer = 1;
constexpr UINT kVisibilityIntervalMs = 300;

constexpr UINT kOpenCommand = 1;
constexpr UINT kHideCommand = 2;
constexpr UINT kFirstActionCommand = 100;

// "Открыть LifeOS" / "Скрыть".
constexpr const wchar_t kOpenLabel[] =
    L"Открыть LifeOS";
constexpr const wchar_t kHideLabel[] = L"Скрыть";

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  int length = ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                     static_cast<int>(utf8.size()), nullptr, 0);
  if (length <= 0) {
    return std::wstring();
  }
  std::wstring utf16(static_cast<size_t>(length), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                        utf16.data(), length);
  return utf16;
}

const flutter::EncodableValue* Find(const flutter::EncodableMap& map,
                                    const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

template <typename T>
const T* FindAs(const flutter::EncodableMap& map, const char* key) {
  const flutter::EncodableValue* value = Find(map, key);
  return value == nullptr ? nullptr : std::get_if<T>(value);
}

}  // namespace

QuickOverlay::QuickOverlay(flutter::BinaryMessenger* messenger,
                           HWND main_window)
    : main_window_(main_window) {
  Gdiplus::GdiplusStartupInput input;
  Gdiplus::GdiplusStartup(&gdiplus_token_, &input, nullptr);

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
}

QuickOverlay::~QuickOverlay() {
  channel_->SetMethodCallHandler(nullptr);
  Hide();
  if (gdiplus_token_ != 0) {
    Gdiplus::GdiplusShutdown(gdiplus_token_);
  }
}

void QuickOverlay::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "canDrawOverlays") {
    // No special permission on Windows.
    result->Success(flutter::EncodableValue(true));
  } else if (method == "requestPermission" ||
             method == "takePendingAction") {
    result->Success();
  } else if (method == "show") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (args == nullptr) {
      result->Error("BAD_ARGS", "Expected a map");
      return;
    }
    Show(*args);
    result->Success(flutter::EncodableValue(bubble_ != nullptr));
  } else if (method == "hide") {
    Hide();
    result->Success();
  } else {
    result->NotImplemented();
  }
}

void QuickOverlay::Show(const flutter::EncodableMap& args) {
  items_.clear();
  if (const auto* list = FindAs<flutter::EncodableList>(args, "items")) {
    for (const auto& entry : *list) {
      const auto* map = std::get_if<flutter::EncodableMap>(&entry);
      if (map == nullptr) {
        continue;
      }
      const auto* id = FindAs<std::string>(*map, "id");
      const auto* label = FindAs<std::string>(*map, "label");
      if (id != nullptr && label != nullptr) {
        items_.push_back({*id, Utf16FromUtf8(*label)});
      }
    }
  }
  if (const auto* hide = FindAs<bool>(args, "hideWhenAppVisible")) {
    hide_when_app_visible_ = *hide;
  }

  if (bubble_ == nullptr) {
    if (const auto* left = FindAs<bool>(args, "isLeft")) {
      is_left_ = *left;
    }
    if (const auto* fraction = FindAs<double>(args, "fraction")) {
      fraction_ = std::clamp(*fraction, 0.0, 1.0);
    }

    static bool class_registered = false;
    HINSTANCE instance = ::GetModuleHandle(nullptr);
    if (!class_registered) {
      WNDCLASSEXW window_class = {};
      window_class.cbSize = sizeof(window_class);
      window_class.lpfnWndProc = QuickOverlay::WndProc;
      window_class.hInstance = instance;
      window_class.hCursor = ::LoadCursor(nullptr, IDC_HAND);
      window_class.lpszClassName = kWindowClassName;
      class_registered = ::RegisterClassExW(&window_class) != 0;
    }

    bubble_ = ::CreateWindowExW(
        WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE,
        kWindowClassName, L"LifeOS", WS_POPUP, 0, 0, kBubbleSize, kBubbleSize,
        nullptr, nullptr, instance, this);
    if (bubble_ == nullptr) {
      return;
    }
    Reposition(::MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY));
    ::SetTimer(bubble_, kVisibilityTimer, kVisibilityIntervalMs, nullptr);
  }
  ApplyVisibility();
}

void QuickOverlay::Hide() {
  if (bubble_ == nullptr) {
    return;
  }
  HWND bubble = bubble_;
  bubble_ = nullptr;
  pressed_ = dragging_ = hovered_ = false;
  ::KillTimer(bubble, kVisibilityTimer);
  ::DestroyWindow(bubble);
}

void QuickOverlay::ApplyVisibility() {
  if (bubble_ == nullptr) {
    return;
  }
  const bool app_visible =
      ::IsWindowVisible(main_window_) && !::IsIconic(main_window_);
  const bool show = !(hide_when_app_visible_ && app_visible);
  const bool shown = ::IsWindowVisible(bubble_) != FALSE;
  if (show != shown) {
    ::ShowWindow(bubble_, show ? SW_SHOWNOACTIVATE : SW_HIDE);
  }
  // Stay above topmost windows that appeared later.
  if (show && !pressed_ && !menu_open_) {
    ::SetWindowPos(bubble_, HWND_TOPMOST, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE |
                       SWP_NOOWNERZORDER);
  }
}

int QuickOverlay::SizeFor(HMONITOR monitor) const {
  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  return ::MulDiv(kBubbleSize, static_cast<int>(dpi), 96);
}

RECT QuickOverlay::AreaFor(HMONITOR monitor) const {
  MONITORINFO info = {};
  info.cbSize = sizeof(info);
  ::GetMonitorInfo(monitor, &info);
  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  const int margin = ::MulDiv(kEdgeMargin, static_cast<int>(dpi), 96);
  RECT area = info.rcWork;
  ::InflateRect(&area, -margin, -margin);
  return area;
}

void QuickOverlay::Reposition(HMONITOR monitor) {
  if (bubble_ == nullptr) {
    return;
  }
  const RECT area = AreaFor(monitor);
  const int size = SizeFor(monitor);
  const int range = std::max(0, static_cast<int>(area.bottom - area.top) - size);
  const int x = is_left_ ? area.left : area.right - size;
  const int y = area.top + static_cast<int>(std::lround(fraction_ * range));
  ::SetWindowPos(bubble_, nullptr, x, y, size, size,
                 SWP_NOZORDER | SWP_NOACTIVATE);
  Render();
}

void QuickOverlay::SnapToEdge() {
  RECT rect;
  ::GetWindowRect(bubble_, &rect);
  HMONITOR monitor = ::MonitorFromRect(&rect, MONITOR_DEFAULTTONEAREST);
  const RECT area = AreaFor(monitor);
  const int size = SizeFor(monitor);
  is_left_ = (rect.left + rect.right) / 2 < (area.left + area.right) / 2;
  const int range = static_cast<int>(area.bottom - area.top) - size;
  const int top = std::clamp(static_cast<int>(rect.top),
                             static_cast<int>(area.top),
                             std::max(static_cast<int>(area.top),
                                      static_cast<int>(area.bottom) - size));
  fraction_ = range > 0 ? static_cast<double>(top - area.top) / range : 0.0;
  Reposition(monitor);

  channel_->InvokeMethod(
      "onMoved",
      std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
          {flutter::EncodableValue("isLeft"), flutter::EncodableValue(is_left_)},
          {flutter::EncodableValue("fraction"),
           flutter::EncodableValue(fraction_)},
      }));
}

void QuickOverlay::Render() {
  if (bubble_ == nullptr) {
    return;
  }
  RECT rect;
  ::GetWindowRect(bubble_, &rect);
  const int size = rect.right - rect.left;
  if (size <= 0) {
    return;
  }

  HDC screen = ::GetDC(nullptr);
  HDC memory = ::CreateCompatibleDC(screen);
  BITMAPINFO info = {};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = size;
  info.bmiHeader.biHeight = -size;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* bits = nullptr;
  HBITMAP dib =
      ::CreateDIBSection(screen, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
  if (dib == nullptr) {
    ::DeleteDC(memory);
    ::ReleaseDC(nullptr, screen);
    return;
  }
  HGDIOBJ previous = ::SelectObject(memory, dib);

  {
    Gdiplus::Bitmap bitmap(size, size, size * 4, PixelFormat32bppPARGB,
                           static_cast<BYTE*>(bits));
    Gdiplus::Graphics graphics(&bitmap);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    graphics.Clear(Gdiplus::Color(0, 0, 0, 0));

    const float full = static_cast<float>(size);
    const float scale = full / kBubbleSize;
    const float inset = 1.5f * scale;
    const float diameter = full - 2 * inset;
    Gdiplus::SolidBrush fill(Gdiplus::Color(255, 0x63, 0x66, 0xF1));
    graphics.FillEllipse(&fill, inset, inset, diameter, diameter);
    Gdiplus::Pen border(Gdiplus::Color(150, 255, 255, 255), 1.5f * scale);
    graphics.DrawEllipse(&border, inset, inset, diameter, diameter);

    const float center = full / 2;
    const float arm = diameter / 2 * 0.42f;
    if (menu_open_) {
      graphics.TranslateTransform(center, center);
      graphics.RotateTransform(45);
      graphics.TranslateTransform(-center, -center);
    }
    Gdiplus::Pen plus(Gdiplus::Color(255, 255, 255, 255), 3.0f * scale);
    plus.SetStartCap(Gdiplus::LineCapRound);
    plus.SetEndCap(Gdiplus::LineCapRound);
    graphics.DrawLine(&plus, center - arm, center, center + arm, center);
    graphics.DrawLine(&plus, center, center - arm, center, center + arm);
  }

  POINT source = {0, 0};
  POINT destination = {rect.left, rect.top};
  SIZE extent = {size, size};
  const bool active = hovered_ || pressed_ || menu_open_;
  BLENDFUNCTION blend = {AC_SRC_OVER, 0, active ? kActiveAlpha : kIdleAlpha,
                         AC_SRC_ALPHA};
  ::UpdateLayeredWindow(bubble_, screen, &destination, &extent, memory, &source,
                        0, &blend, ULW_ALPHA);

  ::SelectObject(memory, previous);
  ::DeleteObject(dib);
  ::DeleteDC(memory);
  ::ReleaseDC(nullptr, screen);
}

void QuickOverlay::ShowMenu() {
  HMENU menu = ::CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }
  for (size_t i = 0; i < items_.size(); ++i) {
    ::AppendMenuW(menu, MF_STRING,
                  kFirstActionCommand + static_cast<UINT>(i),
                  items_[i].label.c_str());
  }
  if (!items_.empty()) {
    ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  }
  ::AppendMenuW(menu, MF_STRING, kOpenCommand, kOpenLabel);
  ::AppendMenuW(menu, MF_STRING, kHideCommand, kHideLabel);

  RECT rect;
  ::GetWindowRect(bubble_, &rect);
  HMONITOR monitor = ::MonitorFromRect(&rect, MONITOR_DEFAULTTONEAREST);
  const RECT area = AreaFor(monitor);
  const bool below = (rect.top + rect.bottom) / 2 < (area.top + area.bottom) / 2;
  UINT flags = TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON;
  flags |= is_left_ ? TPM_LEFTALIGN : TPM_RIGHTALIGN;
  flags |= below ? TPM_TOPALIGN : TPM_BOTTOMALIGN;
  const int x = is_left_ ? rect.left : rect.right;
  const int y = below ? rect.bottom : rect.top;

  menu_open_ = true;
  Render();
  // Required for the menu to close when clicking elsewhere.
  ::SetForegroundWindow(bubble_);
  const UINT command = static_cast<UINT>(
      ::TrackPopupMenuEx(menu, flags, x, y, bubble_, nullptr));
  ::PostMessage(bubble_, WM_NULL, 0, 0);
  ::DestroyMenu(menu);
  menu_open_ = false;
  Render();

  if (command == kOpenCommand) {
    BringMainWindowToFront();
  } else if (command == kHideCommand) {
    Hide();
    channel_->InvokeMethod("onDismissed", nullptr);
  } else if (command >= kFirstActionCommand &&
             command - kFirstActionCommand < items_.size()) {
    const std::string id = items_[command - kFirstActionCommand].id;
    BringMainWindowToFront();
    channel_->InvokeMethod(
        "onAction",
        std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
            {flutter::EncodableValue("id"), flutter::EncodableValue(id)},
        }));
  }
}

void QuickOverlay::BringMainWindowToFront() {
  ::ShowWindow(main_window_, ::IsIconic(main_window_) ? SW_RESTORE : SW_SHOW);
  ::SetForegroundWindow(main_window_);
}

// static
LRESULT CALLBACK QuickOverlay::WndProc(HWND window, UINT message,
                                       WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCT*>(lparam);
    ::SetWindowLongPtr(window, GWLP_USERDATA,
                       reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  } else if (auto* self = reinterpret_cast<QuickOverlay*>(
                 ::GetWindowLongPtr(window, GWLP_USERDATA))) {
    if (self->bubble_ == window) {
      return self->HandleMessage(message, wparam, lparam);
    }
  }
  return ::DefWindowProc(window, message, wparam, lparam);
}

LRESULT QuickOverlay::HandleMessage(UINT message, WPARAM wparam,
                                    LPARAM lparam) {
  HWND window = bubble_;
  switch (message) {
    case WM_MOUSEACTIVATE:
      // Clicking the bubble must not take focus from the current app.
      return MA_NOACTIVATE;

    case WM_LBUTTONDOWN:
      pressed_ = true;
      dragging_ = false;
      ::GetCursorPos(&press_cursor_);
      {
        RECT rect;
        ::GetWindowRect(window, &rect);
        press_origin_ = {rect.left, rect.top};
      }
      ::SetCapture(window);
      Render();
      return 0;

    case WM_MOUSEMOVE: {
      if (!hovered_) {
        hovered_ = true;
        TRACKMOUSEEVENT track = {};
        track.cbSize = sizeof(track);
        track.dwFlags = TME_LEAVE;
        track.hwndTrack = window;
        ::TrackMouseEvent(&track);
        Render();
      }
      if (!pressed_) {
        return 0;
      }
      POINT cursor;
      ::GetCursorPos(&cursor);
      const int dx = cursor.x - press_cursor_.x;
      const int dy = cursor.y - press_cursor_.y;
      if (!dragging_ && (std::abs(dx) > ::GetSystemMetrics(SM_CXDRAG) ||
                         std::abs(dy) > ::GetSystemMetrics(SM_CYDRAG))) {
        dragging_ = true;
      }
      if (dragging_) {
        ::SetWindowPos(window, nullptr, press_origin_.x + dx,
                       press_origin_.y + dy, 0, 0,
                       SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
      }
      return 0;
    }

    case WM_MOUSELEAVE:
      hovered_ = false;
      Render();
      return 0;

    case WM_LBUTTONUP: {
      if (!pressed_) {
        return 0;
      }
      const bool was_dragging = dragging_;
      pressed_ = false;
      dragging_ = false;
      ::ReleaseCapture();
      if (was_dragging) {
        SnapToEdge();
      } else {
        ShowMenu();
      }
      Render();
      return 0;
    }

    case WM_RBUTTONUP:
      ShowMenu();
      return 0;

    case WM_CAPTURECHANGED:
      // Capture lost mid-drag (e.g. Alt+Tab): drop where it is.
      if (pressed_) {
        const bool was_dragging = dragging_;
        pressed_ = false;
        dragging_ = false;
        if (was_dragging) {
          SnapToEdge();
        }
        Render();
      }
      return 0;

    case WM_TIMER:
      if (wparam == kVisibilityTimer) {
        ApplyVisibility();
      }
      return 0;

    case WM_DPICHANGED:
    case WM_DISPLAYCHANGE: {
      RECT rect;
      ::GetWindowRect(window, &rect);
      Reposition(::MonitorFromRect(&rect, MONITOR_DEFAULTTONEAREST));
      return 0;
    }
  }
  return ::DefWindowProc(window, message, wparam, lparam);
}
