import 'package:flutter/material.dart';

/// Ширина, ниже которой интерфейс переходит в мобильный режим:
/// нижняя навигация вместо бокового меню, карточки в одну колонку.
const double mobileBreakpoint = 600;

/// Высота, ниже которой альбомный экран считается телефонным: нижняя
/// панель съела бы слишком много места, навигация уходит в узкую ленту слева.
const double compactLandscapeMaxHeight = 500;

/// Предельная ширина редакторов и форм на десктопе.
const double maxEditorWidth = 800;

/// Ширина формы, у которой поля не задают её сами.
const double formDialogWidth = 420;

bool isMobileLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width < mobileBreakpoint;

/// Телефон в любой ориентации: короткая сторона экрана уже планшетной.
bool isPhone(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide < mobileBreakpoint;

/// Телефон, повёрнутый горизонтально: широко, но очень низко.
bool isCompactLandscape(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.width > size.height && size.height < compactLandscapeMaxHeight;
}

/// Две колонки рядом: слева сводка, справа список. Используется на
/// телефоне в альбомной ориентации, где одна колонка — узкая полоска
/// с бесконечной прокруткой. Каждая колонка прокручивается сама.
class LandscapeSplit extends StatelessWidget {
  const LandscapeSplit({
    super.key,
    required this.summary,
    required this.list,
    this.summaryFlex = 2,
    this.listFlex = 3,
  });

  final Widget summary;
  final Widget list;
  final int summaryFlex;
  final int listFlex;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: summaryFlex, child: summary),
        const VerticalDivider(width: 1),
        Expanded(flex: listFlex, child: list),
      ],
    );
  }
}

/// Открывает форму создания/редактирования. На телефоне — шторкой снизу:
/// она поднимается над клавиатурой и не прячет поля ввода. На планшете и
/// десктопе — обычным диалогом. Форма строится через [AdaptiveFormDialog].
Future<T?> showFormSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  if (!isPhone(context)) {
    return showDialog<T>(context: context, builder: builder);
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => _FormSheetScope(child: builder(sheetContext)),
  );
}

/// Метка «форма открыта шторкой» для [AdaptiveFormDialog].
class _FormSheetScope extends InheritedWidget {
  const _FormSheetScope({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FormSheetScope>() != null;

  @override
  bool updateShouldNotify(_FormSheetScope oldWidget) => false;
}

/// Замена [AlertDialog] для форм с тем же набором полей. Внутри
/// [showFormSheet] на телефоне раскладывается как шторка: заголовок,
/// прокручиваемое содержимое и кнопки, приподнятые над клавиатурой.
class AdaptiveFormDialog extends StatelessWidget {
  const AdaptiveFormDialog({
    super.key,
    this.title,
    required this.content,
    this.actions = const [],
  });

  final Widget? title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    if (!_FormSheetScope.of(context)) {
      // AlertDialog подбирает ширину по IntrinsicWidth, а собственная ширина
      // поля ввода — ширина набранного текста: без потолка диалог растёт
      // при вводе, пока не упрётся в края окна.
      return AlertDialog(
        title: title,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxEditorWidth),
          child: content,
        ),
        actions: actions,
      );
    }
    final theme = Theme.of(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + keyboard),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: DefaultTextStyle(
                style: theme.textTheme.titleLarge!,
                child: title!,
              ),
            ),
          Flexible(child: SingleChildScrollView(child: content)),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                overflowSpacing: 8,
                overflowAlignment: OverflowBarAlignment.end,
                children: actions,
              ),
            ),
        ],
      ),
    );
  }
}
