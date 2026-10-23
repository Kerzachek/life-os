import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/platform_info.dart';
import '../../../../core/widgets/responsive.dart';
import '../../../finance/domain/finance_enums.dart';
import '../../../finance/presentation/widgets/transaction_dialog.dart';
import '../../../settings/domain/app_module.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import 'quick_note_sheet.dart';
import 'routine_check_in_sheet.dart';

/// Пункт меню быстрых действий. Пункты отключённых разделов скрываются.
class QuickMenuAction {
  final String id;
  final AppModule module;
  final IconData icon;
  final String label;
  final Color color;
  final WidgetBuilder builder;

  const QuickMenuAction({
    required this.id,
    required this.module,
    required this.icon,
    required this.label,
    required this.color,
    required this.builder,
  });
}

final List<QuickMenuAction> quickMenuActions = [
  QuickMenuAction(
    id: 'expense',
    module: AppModule.finance,
    icon: Icons.remove_shopping_cart_rounded,
    label: 'Расход',
    color: const Color(0xFFFF7675),
    builder: (_) => const TransactionDialog(
      initialType: FinanceTransactionType.expense,
      quick: true,
    ),
  ),
  QuickMenuAction(
    id: 'income',
    module: AppModule.finance,
    icon: Icons.account_balance_wallet_rounded,
    label: 'Пополнение',
    color: const Color(0xFF00B894),
    builder: (_) => const TransactionDialog(
      initialType: FinanceTransactionType.income,
      quick: true,
    ),
  ),
  QuickMenuAction(
    id: 'transfer',
    module: AppModule.finance,
    icon: Icons.swap_horiz_rounded,
    label: 'Перевод',
    color: const Color(0xFF74B9FF),
    builder: (_) => const TransactionDialog(
      initialType: FinanceTransactionType.transfer,
      quick: true,
    ),
  ),
  QuickMenuAction(
    id: 'note',
    module: AppModule.notes,
    icon: Icons.edit_note_rounded,
    label: 'Заметка',
    color: const Color(0xFFFDCB6E),
    builder: (_) => const QuickNoteSheet(),
  ),
  QuickMenuAction(
    id: 'check_in',
    module: AppModule.routine,
    icon: Icons.wb_sunny_rounded,
    label: 'Чек-ин рутины',
    color: const Color(0xFFA29BFE),
    builder: (_) => const RoutineCheckInSheet(),
  ),
];

/// Плавающая полупрозрачная кнопка быстрых действий поверх всех разделов.
///
/// Перетаскивается, при отпускании примагничивается к ближайшему боковому
/// краю; положение сохраняется в настройках. По тапу (или Ctrl/Cmd+Shift+Q
/// на десктопе) раскрывает вертикальный стек действий; формы открываются
/// через [showFormSheet] — на телефоне шторкой снизу.
///
/// Кладётся в [Stack] поверх области разделов, на всю её площадь: системные
/// отступы и клавиатуру учитывает по [MediaQuery].
class QuickActionsOverlay extends ConsumerStatefulWidget {
  const QuickActionsOverlay({super.key});

  static const double buttonSize = 56;
  static const double edgeMargin = 12;

  /// Прозрачность в покое и при наведении / касании.
  static const double idleOpacity = 0.45;
  static const double activeOpacity = 1.0;

  @override
  ConsumerState<QuickActionsOverlay> createState() =>
      _QuickActionsOverlayState();
}

class _QuickActionsOverlayState extends ConsumerState<QuickActionsOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _menu = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  final FocusNode _menuFocus = FocusNode(debugLabel: 'quick_actions_menu');

  /// Левый верхний угол кнопки во время перетаскивания.
  Offset? _dragOffset;

  /// Положение после отпускания — до того, как его вернёт поток настроек.
  QuickButtonPosition? _pending;

  bool _hovered = false;
  bool _touched = false;
  Timer? _touchTimer;

  bool get _expanded =>
      _menu.status == AnimationStatus.forward ||
      _menu.status == AnimationStatus.completed;

  @override
  void initState() {
    super.initState();
    _menu.addStatusListener((_) => setState(() {}));
    if (isDesktopPlatform) HardwareKeyboard.instance.addHandler(_onHotkey);
  }

  @override
  void dispose() {
    if (isDesktopPlatform) HardwareKeyboard.instance.removeHandler(_onHotkey);
    _touchTimer?.cancel();
    _menuFocus.dispose();
    _menu.dispose();
    super.dispose();
  }

  /// Ctrl+Shift+Q (Cmd+Shift+Q на macOS) — открыть / закрыть меню. Только
  /// когда поверх раздела нет диалога или шторки.
  bool _onHotkey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.keyQ) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    final modifier =
        isMacOSPlatform ? keyboard.isMetaPressed : keyboard.isControlPressed;
    if (!modifier || !keyboard.isShiftPressed) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    if (_actions.isEmpty) return false;
    _toggleMenu();
    return true;
  }

  List<QuickMenuAction> get _actions {
    final enabled = ref.read(enabledModulesProvider);
    return quickMenuActions.where((a) => enabled.contains(a.module)).toList();
  }

  void _toggleMenu() => _expanded ? _closeMenu() : _openMenu();

  void _openMenu() {
    _menu.forward();
    // Фокус уходит с полей ввода раздела: цифры и Esc достаются меню.
    _menuFocus.requestFocus();
  }

  void _closeMenu() {
    _menu.reverse();
    _menuFocus.unfocus();
  }

  void _run(QuickMenuAction action) {
    _closeMenu();
    showFormSheet<void>(context: context, builder: action.builder);
  }

  KeyEventResult _onMenuKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _closeMenu();
      return KeyEventResult.handled;
    }
    final digit = int.tryParse(event.character ?? '');
    final actions = _actions;
    if (digit != null && digit >= 1 && digit <= actions.length) {
      _run(actions[digit - 1]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _touch() {
    _touchTimer?.cancel();
    setState(() => _touched = true);
  }

  /// На сенсорном экране кнопка остаётся яркой ещё немного после касания.
  void _release() {
    _touchTimer?.cancel();
    _touchTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _touched = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(enabledModulesProvider);
    final actions = _actions;
    if (actions.isEmpty) return const SizedBox.shrink();

    final saved = ref.watch(quickButtonPositionProvider);
    if (_pending == saved) _pending = null;
    final position = _pending ?? saved;

    return LayoutBuilder(builder: (context, constraints) {
      final bounds = _Bounds.of(context, constraints);
      final dragging = _dragOffset != null;
      final topLeft = _dragOffset ?? bounds.anchor(position);
      final active = _hovered || _touched || dragging || _expanded;

      return Stack(
        children: [
          if (_menu.status != AnimationStatus.dismissed) ...[
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('quick_actions_barrier'),
                behavior: HitTestBehavior.opaque,
                onTap: _closeMenu,
                child: FadeTransition(
                  opacity: _menu,
                  child: const ColoredBox(color: Color(0x55000000)),
                ),
              ),
            ),
            _menuStack(actions, bounds, topLeft, position.isLeft),
          ],
          AnimatedPositioned(
            duration:
                dragging ? Duration.zero : const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            left: topLeft.dx,
            top: topLeft.dy,
            child: MouseRegion(
              cursor: dragging
                  ? SystemMouseCursors.grabbing
                  : SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: Listener(
                onPointerDown: (_) => _touch(),
                onPointerUp: (_) => _release(),
                onPointerCancel: (_) => _release(),
                child: GestureDetector(
                  key: const ValueKey('quick_actions_button'),
                  onTap: _toggleMenu,
                  onPanStart: (_) {
                    if (_expanded) _closeMenu();
                    setState(() => _dragOffset = topLeft);
                  },
                  onPanUpdate: (d) => setState(() {
                    _dragOffset = bounds.clamp(_dragOffset! + d.delta);
                  }),
                  onPanEnd: (_) => _drop(bounds, constraints.maxWidth),
                  onPanCancel: () => _drop(bounds, constraints.maxWidth),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: active
                        ? QuickActionsOverlay.activeOpacity
                        : QuickActionsOverlay.idleOpacity,
                    child: Tooltip(
                      message: isDesktopPlatform
                          ? 'Быстрые действия (${isMacOSPlatform ? 'Cmd' : 'Ctrl'}+Shift+Q)'
                          : 'Быстрые действия',
                      waitDuration: const Duration(milliseconds: 600),
                      child: _GlassButton(rotation: _menu),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  /// Отпускание: примагничивание к ближайшему краю и сохранение положения.
  void _drop(_Bounds bounds, double width) {
    final offset = _dragOffset;
    if (offset == null) return;
    final center = offset.dx + QuickActionsOverlay.buttonSize / 2;
    final next = QuickButtonPosition(
      isLeft: center < width / 2,
      verticalFraction: bounds.fractionOf(offset.dy),
    );
    setState(() {
      _dragOffset = null;
      _pending = next;
    });
    _release();
    ref.read(settingsControllerProvider).setQuickButtonPosition(next);
  }

  /// Стек действий у кнопки: вниз, если кнопка в верхней половине,
  /// иначе вверх. Подписи — со стороны центра экрана.
  Widget _menuStack(
    List<QuickMenuAction> actions,
    _Bounds bounds,
    Offset button,
    bool isLeft,
  ) {
    const gap = 10.0;
    const size = QuickActionsOverlay.buttonSize;
    final below = button.dy + size / 2 < bounds.height / 2;
    final maxHeight = below
        ? bounds.bottomLimit - (button.dy + size + gap)
        : button.dy - gap - bounds.minY;
    final horizontalInset = isLeft
        ? button.dx
        : bounds.width - button.dx - size;

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          isLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < actions.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _MenuItem(
              action: actions[i],
              hotkey: isDesktopPlatform ? '${i + 1}' : null,
              labelFirst: !isLeft,
              onTap: () => _run(actions[i]),
            ),
          ),
      ],
    );

    return Positioned(
      left: isLeft ? horizontalInset : null,
      right: isLeft ? null : horizontalInset,
      top: below ? button.dy + size + gap : null,
      bottom: below ? null : bounds.height - button.dy + gap,
      child: Focus(
        focusNode: _menuFocus,
        onKeyEvent: _onMenuKey,
        child: FadeTransition(
          opacity: _menu,
          child: ScaleTransition(
            alignment: Alignment(
              isLeft ? -1 : 1,
              below ? -1 : 1,
            ),
            scale: CurvedAnimation(parent: _menu, curve: Curves.easeOutBack),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight.clamp(0, 600)),
              child: SingleChildScrollView(
                key: const ValueKey('quick_actions_menu'),
                reverse: !below,
                child: column,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Допустимая область для кнопки с учётом системных панелей, выреза,
/// нижней навигации и клавиатуры.
class _Bounds {
  final double width;
  final double height;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;

  const _Bounds({
    required this.width,
    required this.height,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  factory _Bounds.of(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    const margin = QuickActionsOverlay.edgeMargin;
    const size = QuickActionsOverlay.buttonSize;
    final padding = MediaQuery.paddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final bottom = keyboard > padding.bottom ? keyboard : padding.bottom;

    final minX = padding.left + margin;
    final minY = padding.top + margin;
    final maxX = width - padding.right - margin - size;
    final maxY = height - bottom - margin - size;
    return _Bounds(
      width: width,
      height: height,
      minX: minX,
      maxX: maxX < minX ? minX : maxX,
      minY: minY,
      maxY: maxY < minY ? minY : maxY,
    );
  }

  /// Нижняя граница для раскрытого меню.
  double get bottomLimit => maxY + QuickActionsOverlay.buttonSize;

  Offset anchor(QuickButtonPosition position) => Offset(
        position.isLeft ? minX : maxX,
        minY + position.verticalFraction * (maxY - minY),
      );

  Offset clamp(Offset offset) => Offset(
        offset.dx.clamp(minX, maxX),
        offset.dy.clamp(minY, maxY),
      );

  double fractionOf(double dy) {
    final range = maxY - minY;
    if (range <= 0) return 0;
    return ((dy - minY) / range).clamp(0.0, 1.0);
  }
}

/// Круглая кнопка «матовое стекло»: размытие фона под ней.
class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.rotation});

  final Animation<double> rotation;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const size = QuickActionsOverlay.buttonSize;
    return DecoratedBox(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.22),
                  colorScheme.primary.withValues(alpha: 0.28),
                ],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
            ),
            child: RotationTransition(
              turns: Tween(begin: 0.0, end: 0.125).animate(rotation),
              child: const Icon(Icons.add_rounded, size: 30, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.action,
    required this.hotkey,
    required this.labelFirst,
    required this.onTap,
  });

  final QuickMenuAction action;

  /// Цифра для выбора с клавиатуры (только десктоп).
  final String? hotkey;

  /// Подпись слева от иконки — когда кнопка у правого края.
  final bool labelFirst;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final label = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hotkey != null) ...[
            Text(
              hotkey!,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            action.label,
            style: theme.textTheme.labelLarge?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );

    final icon = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: action.color.withValues(alpha: 0.2),
        border: Border.all(color: action.color.withValues(alpha: 0.6)),
      ),
      child: Icon(action.icon, size: 22, color: action.color),
    );

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey('quick_action_${action.id}'),
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: labelFirst
                ? [label, const SizedBox(width: 10), icon]
                : [icon, const SizedBox(width: 10), label],
          ),
        ),
      ),
    );
  }
}
