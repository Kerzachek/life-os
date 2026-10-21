import 'package:flutter/widgets.dart';

/// Ширина, ниже которой интерфейс переходит в мобильный режим:
/// нижняя навигация вместо бокового меню, карточки в одну колонку.
const double mobileBreakpoint = 600;

bool isMobileLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width < mobileBreakpoint;
