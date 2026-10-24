#ifndef RUNNER_QUICK_OVERLAY_H_
#define RUNNER_QUICK_OVERLAY_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <string>
#include <vector>

// Quick actions button that floats above all windows of the OS, outside the
// Flutter window: a small layered topmost tool window (no taskbar entry).
//
// It can be dragged anywhere and snaps to the nearest left/right edge of the
// monitor work area. A click opens a native popup menu with the quick
// actions; choosing one brings the main window to the front and sends
// "onAction" to Dart, which opens the form. Talks to Dart over the
// "lifeos/system_overlay" method channel (see SystemOverlayService).
class QuickOverlay {
 public:
  QuickOverlay(flutter::BinaryMessenger* messenger, HWND main_window);
  ~QuickOverlay();

  QuickOverlay(const QuickOverlay&) = delete;
  QuickOverlay& operator=(const QuickOverlay&) = delete;

 private:
  struct Item {
    std::string id;
    std::wstring label;
  };

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Creates the bubble (position is applied only on creation) or updates
  // its menu and auto-hide mode.
  void Show(const flutter::EncodableMap& args);

  // Destroys the bubble window.
  void Hide();

  // Shows or hides the bubble depending on the main window state.
  void ApplyVisibility();

  // Draws the bubble with per-pixel alpha.
  void Render();

  // Places the bubble by |is_left_| / |fraction_| on |monitor|.
  void Reposition(HMONITOR monitor);

  // Drop after dragging: snap to the nearest edge and report the position.
  void SnapToEdge();

  void ShowMenu();
  void BringMainWindowToFront();

  int SizeFor(HMONITOR monitor) const;
  RECT AreaFor(HMONITOR monitor) const;

  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam);
  LRESULT HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND main_window_;
  HWND bubble_ = nullptr;
  ULONG_PTR gdiplus_token_ = 0;

  std::vector<Item> items_;
  bool is_left_ = false;
  double fraction_ = 0.6;
  bool hide_when_app_visible_ = true;

  bool hovered_ = false;
  bool pressed_ = false;
  bool dragging_ = false;
  bool menu_open_ = false;
  POINT press_cursor_ = {};
  POINT press_origin_ = {};
};

#endif  // RUNNER_QUICK_OVERLAY_H_
