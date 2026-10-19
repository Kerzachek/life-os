# PLAN.md: Home Organizer (Personal ERP / Life OS) - Desktop Launcher Edition

## 1. Концепция и стиль (Desktop Launcher UX)
Перевод приложения с мобильного шаблона на полноценный **Десктопный Дашборд-Лаунчер** (стилистика LoL Client, Discord, Invade):
- **Сетка и адаптивность**: Плотная трех- и четырехколоночная сетка под десктопные разрешения (Windows/macOS/Linux).
- **Фиксированный боковой Sidebar**: Закрепленная слева навигационная панель с логотипом, вкладками (Дашборд, Задачи, Привычки, Финансы, Настройки) и профилем оператора.
- **Dark Launcher Theme**: Глубокие темные оттенки подложек (`#0F1218`, `#181C26`), контрастные акценты (`#6C5CE7`, `#00CEC9`), тонкие графитовые рамки (`#2A3040`).

---

## 2. Архитектурный подход (Feature-first)

```
lib/
├── main.dart                       # Точка входа, каркас с AppSidebar и IndexedStack
├── core/                           # Общие базовые модули
│   ├── database/                   # Drift SQLite БД (Categories, Tasks, Habits, Logs, Challenges)
│   ├── theme/                      # AppTheme (Dark Gaming/Launcher Material 3 Theme)
│   └── widgets/                    # AppSidebar (Левое навигационное меню лаунчера)
│
├── features/                       # Модули приложения
│   ├── overview/                   # Модуль "Дашборд / Главная"
│   │   └── presentation/
│   │       ├── screens/            # overview_screen.dart (Сетка виджетов)
│   │       └── widgets/            # overview_header, today_tasks_card, habit_streaks_card, weekly_progress_card
│   │
│   ├── tasks/                      # Модуль "Задачи и Домашние дела"
│   │   ├── domain/                 # TaskPriority, TaskStatus
│   │   ├── data/                   # TasksRepository (Drift CRUD + Stream)
│   │   └── presentation/           # TasksScreen, TaskItemWidget, AddTaskDialog
│   │
│   ├── habits/                     # Модуль "Привычки и Челленджи"
│   │   ├── domain/                 # HabitFrequency, HabitWithStatus
│   │   ├── data/                   # HabitsRepository (Drift CRUD, Check-in, Streaks)
│   │   └── presentation/           # HabitsScreen, HabitCard, ChallengeCard, AddHabitDialog
│   │
│   └── finance/                    # Модуль "Финансовый борд"
│       ├── domain/                 # enum-ы, пресеты категорий, расчёты (сводка, фильтры, диаграмма)
│       ├── data/                   # FinanceRepository (Drift CRUD, пересчёт балансов)
│       └── presentation/           # FinanceScreen (Обзор / Продукты / Операции / Настройки)
```

---

## 3. Схема Локальной Базы Данных (Drift / SQLite + LWW Sync)

Каждая таблица содержит универсальные служебные поля синхронизации:
- `id`: `TEXT PRIMARY KEY` (UUID v4)
- `created_at`: `DATETIME` (UTC)
- `updated_at`: `DATETIME` (UTC)
- `deleted_at`: `DATETIME` (nullable, tombstone)

Таблицы:
1. `categories` (Категории задач и трат)
2. `tasks` (Задачи и бытовые дела: заголовок, описание, срок, приоритет, статус, is_chore)
3. `habits` (Привычки: название, цель, единица измерения, регулярность, архив)
4. `habit_logs` (Логи отметок привычек: дата, значение, заметка)
5. `challenges` (Челленджи: название, дата старта/финиша, статус)
6. `challenge_habits` (Связь челленджей и привычек)
7. `finance_accounts` (Счета, кредиты, депозиты — различаются колонкой `kind`)
8. `finance_categories` (Категории доходов/расходов: предустановленные и пользовательские)
9. `finance_transactions` (Расход / доход / перевод; платёж по кредиту = расход с `target_account_id` кредита)
10. `obligations` (Обязательные ежемесячные платежи; статус оплаты за месяц выводится из транзакций)

---

## 4. Этапы реализации

1. ✅ Проектирование и создание `PLAN.md`.
2. ✅ Модуль Задач (`TasksRepository`, `tasks_provider`, `TasksScreen`, `AddTaskDialog`).
3. ✅ Модуль Привычек и Челленджей (`HabitsRepository`, `habits_provider`, `HabitsScreen`, `AddHabitDialog`).
4. 🔄 Редизайн интерфейса Life OS под Десктопный Лаунчер:
   - Создание темной темы `AppTheme` (Dark Launcher Palette).
   - Создание закрепленного бокового меню `AppSidebar`.
   - Создание дашборда `OverviewScreen` с карточками производительности, задач, привычек и быстрыми действиями.
   - Интеграция в `main.dart` и валидация через `flutter analyze` и `flutter test`.

