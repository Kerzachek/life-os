import Cocoa
import FlutterMacOS
import ServiceManagement

class MainFlutterWindow: NSWindow {
  /// Кнопка быстрых действий поверх всех окон (канал lifeos/system_overlay).
  private var quickOverlay: QuickOverlay?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerLaunchAtStartupChannel(flutterViewController.engine.binaryMessenger)
    quickOverlay = QuickOverlay(
      messenger: flutterViewController.engine.binaryMessenger, mainWindow: self)

    super.awakeFromNib()
  }

  /// Канал пакета launch_at_startup: вход в систему через SMAppService (macOS 13+).
  private func registerLaunchAtStartupChannel(_ messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "launch_at_startup", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard #available(macOS 13.0, *) else {
          result(FlutterError(
            code: "UNSUPPORTED", message: "Requires macOS 13 or later", details: nil))
          return
        }
        let service = SMAppService.mainApp
        switch call.method {
        case "launchAtStartupIsEnabled":
          result(service.status == .enabled)
        case "launchAtStartupSetEnabled":
          let enabled = (call.arguments as? [String: Any])?["setEnabledValue"] as? Bool ?? false
          do {
            if enabled {
              try service.register()
            } else {
              try service.unregister()
            }
            result(nil)
          } catch {
            result(FlutterError(
              code: "FAILED", message: error.localizedDescription, details: nil))
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
  }
}

/// Кнопка быстрых действий поверх всех окон и приложений: плавающая
/// неактивирующая `NSPanel` вне окна Flutter, видна на всех рабочих столах.
///
/// Перетаскивается и примагничивается к левому или правому краю экрана;
/// по клику — меню действий. Выбор действия выводит окно LifeOS на передний
/// план и отправляет в Dart `onAction` — форму открывает главный экран.
final class QuickOverlay: NSObject {
  private struct Item {
    let id: String
    let label: String
    let color: NSColor
  }

  fileprivate static let size: CGFloat = 48
  private static let margin: CGFloat = 8
  fileprivate static let accent = NSColor(argb: 0xFF63_66F1)

  private let channel: FlutterMethodChannel
  private weak var mainWindow: NSWindow?
  private var panel: NSPanel?
  private var bubble: BubbleView?
  private var timer: Timer?
  private var screenObserver: NSObjectProtocol?

  private var items: [Item] = []
  private var isLeft = false
  private var fraction = 0.6
  private var hideWhenAppVisible = true

  init(messenger: FlutterBinaryMessenger, mainWindow: NSWindow) {
    channel = FlutterMethodChannel(name: "lifeos/system_overlay", binaryMessenger: messenger)
    self.mainWindow = mainWindow
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "canDrawOverlays":
      // На macOS отдельного разрешения нет.
      result(true)
    case "requestPermission", "takePendingAction":
      result(nil)
    case "show":
      show(call.arguments as? [String: Any] ?? [:])
      result(panel != nil)
    case "hide":
      hide()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Создаёт кнопку (положение — только при создании) или обновляет меню
  /// и режим скрытия.
  private func show(_ args: [String: Any]) {
    items = (args["items"] as? [[String: Any]] ?? []).compactMap { map in
      guard let id = map["id"] as? String, let label = map["label"] as? String else {
        return nil
      }
      let argb = (map["color"] as? NSNumber)?.uint32Value ?? 0xFF63_66F1
      return Item(id: id, label: label, color: NSColor(argb: argb))
    }
    hideWhenAppVisible = args["hideWhenAppVisible"] as? Bool ?? true
    if panel == nil {
      isLeft = args["isLeft"] as? Bool ?? false
      fraction = min(max(args["fraction"] as? Double ?? 0.6, 0), 1)
      createPanel()
    }
    applyVisibility()
  }

  private func createPanel() {
    let frame = NSRect(x: 0, y: 0, width: Self.size, height: Self.size)
    let panel = NSPanel(
      contentRect: frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false)
    panel.level = .floating
    panel.isFloatingPanel = true
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

    let bubble = BubbleView(frame: frame)
    bubble.overlay = self
    panel.contentView = bubble
    self.panel = panel
    self.bubble = bubble
    reposition(on: NSScreen.main ?? NSScreen.screens.first)
    bubble.updateAlpha()

    timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
      self?.applyVisibility()
    }
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self, let panel = self.panel else { return }
      self.reposition(on: panel.screen ?? NSScreen.main)
    }
  }

  /// Уничтожает панель.
  private func hide() {
    timer?.invalidate()
    timer = nil
    if let observer = screenObserver {
      NotificationCenter.default.removeObserver(observer)
      screenObserver = nil
    }
    panel?.orderOut(nil)
    panel = nil
    bubble = nil
  }

  private func applyVisibility() {
    guard let panel else { return }
    let window = mainWindow
    let appVisible =
      (window?.isVisible ?? false) && !(window?.isMiniaturized ?? false) && !NSApp.isHidden
    let show = !(hideWhenAppVisible && appVisible)
    if show && !panel.isVisible {
      panel.orderFrontRegardless()
    } else if !show && panel.isVisible {
      panel.orderOut(nil)
    }
  }

  private func area(of screen: NSScreen) -> NSRect {
    screen.visibleFrame.insetBy(dx: Self.margin, dy: Self.margin)
  }

  private func reposition(on screen: NSScreen?) {
    guard let panel, let screen else { return }
    let area = area(of: screen)
    let range = max(0, area.height - Self.size)
    let x = isLeft ? area.minX : area.maxX - Self.size
    // Доля считается сверху, а координаты macOS — снизу.
    let y = area.maxY - Self.size - CGFloat(fraction) * range
    panel.setFrameOrigin(NSPoint(x: x, y: y))
  }

  /// Отпускание после перетаскивания: к ближайшему краю, положение — в Dart.
  fileprivate func snapToEdge() {
    guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
    let area = area(of: screen)
    let frame = panel.frame
    isLeft = frame.midX < area.midX
    let range = area.height - Self.size
    let bottom = min(max(frame.minY, area.minY), max(area.minY, area.maxY - Self.size))
    fraction = range > 0 ? Double((area.maxY - Self.size - bottom) / range) : 0
    let x = isLeft ? area.minX : area.maxX - Self.size
    panel.setFrame(
      NSRect(x: x, y: bottom, width: Self.size, height: Self.size), display: true, animate: true)
    channel.invokeMethod("onMoved", arguments: ["isLeft": isLeft, "fraction": fraction])
  }

  fileprivate func showMenu(from view: BubbleView) {
    let menu = NSMenu()
    menu.autoenablesItems = false
    for item in items {
      let menuItem = NSMenuItem(
        title: item.label, action: #selector(runAction(_:)), keyEquivalent: "")
      menuItem.target = self
      menuItem.representedObject = item.id
      menuItem.image = Self.dot(item.color)
      menu.addItem(menuItem)
    }
    if !items.isEmpty { menu.addItem(.separator()) }
    let open = NSMenuItem(title: "Открыть LifeOS", action: #selector(openApp(_:)), keyEquivalent: "")
    open.target = self
    menu.addItem(open)
    let dismiss = NSMenuItem(title: "Скрыть", action: #selector(dismiss(_:)), keyEquivalent: "")
    dismiss.target = self
    menu.addItem(dismiss)

    view.menuOpen = true
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: view)
    view.menuOpen = false
  }

  @objc private func runAction(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    bringMainWindowToFront()
    channel.invokeMethod("onAction", arguments: ["id": id])
  }

  @objc private func openApp(_ sender: NSMenuItem) {
    bringMainWindowToFront()
  }

  @objc private func dismiss(_ sender: NSMenuItem) {
    hide()
    channel.invokeMethod("onDismissed", arguments: nil)
  }

  private func bringMainWindowToFront() {
    guard let window = mainWindow else { return }
    NSApp.unhide(nil)
    if window.isMiniaturized { window.deminiaturize(nil) }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private static func dot(_ color: NSColor) -> NSImage {
    NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
      color.setFill()
      NSBezierPath(ovalIn: rect).fill()
      return true
    }
  }
}

/// Круглая полупрозрачная кнопка с «плюсом»: перетаскивание и клик.
private final class BubbleView: NSView {
  weak var overlay: QuickOverlay?

  var menuOpen = false {
    didSet {
      needsDisplay = true
      updateAlpha()
    }
  }

  private var hovered = false
  private var dragStart: NSPoint?
  private var originStart: NSPoint?
  private var dragging = false

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
        owner: self, userInfo: nil))
  }

  func updateAlpha() {
    window?.alphaValue = hovered || dragStart != nil || menuOpen ? 1 : 0.55
  }

  override func mouseEntered(with event: NSEvent) {
    hovered = true
    updateAlpha()
  }

  override func mouseExited(with event: NSEvent) {
    hovered = false
    updateAlpha()
  }

  override func mouseDown(with event: NSEvent) {
    dragStart = NSEvent.mouseLocation
    originStart = window?.frame.origin
    dragging = false
    updateAlpha()
  }

  override func mouseDragged(with event: NSEvent) {
    guard let start = dragStart, let origin = originStart, let window else { return }
    let location = NSEvent.mouseLocation
    let dx = location.x - start.x
    let dy = location.y - start.y
    if !dragging && hypot(dx, dy) > 3 { dragging = true }
    if dragging { window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy)) }
  }

  override func mouseUp(with event: NSEvent) {
    let wasDragging = dragging
    dragStart = nil
    originStart = nil
    dragging = false
    if wasDragging {
      overlay?.snapToEdge()
    } else {
      overlay?.showMenu(from: self)
    }
    updateAlpha()
  }

  override func rightMouseDown(with event: NSEvent) {
    overlay?.showMenu(from: self)
  }

  override func draw(_ dirtyRect: NSRect) {
    let inset: CGFloat = 1.5
    let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: inset, dy: inset))
    QuickOverlay.accent.setFill()
    circle.fill()
    NSColor.white.withAlphaComponent(0.6).setStroke()
    circle.lineWidth = 1.5
    circle.stroke()

    let center = NSPoint(x: bounds.midX, y: bounds.midY)
    let arm = (bounds.width / 2 - inset) * 0.42
    let plus = NSBezierPath()
    plus.lineWidth = 3
    plus.lineCapStyle = .round
    plus.move(to: NSPoint(x: center.x - arm, y: center.y))
    plus.line(to: NSPoint(x: center.x + arm, y: center.y))
    plus.move(to: NSPoint(x: center.x, y: center.y - arm))
    plus.line(to: NSPoint(x: center.x, y: center.y + arm))
    if menuOpen {
      var rotation = AffineTransform(translationByX: center.x, byY: center.y)
      rotation.rotate(byDegrees: 45)
      rotation.translate(x: -center.x, y: -center.y)
      plus.transform(using: rotation)
    }
    NSColor.white.setStroke()
    plus.stroke()
  }
}

private extension NSColor {
  convenience init(argb: UInt32) {
    self.init(
      srgbRed: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255)
  }
}
