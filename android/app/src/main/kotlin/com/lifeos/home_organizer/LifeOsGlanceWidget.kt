package com.lifeos.home_organizer

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews

/// Виджет «LifeOS» на домашнем экране (4x2): «Доступно сегодня»,
/// две невыполненные задачи на сегодня, прогресс рутины и кнопка открытия
/// приложения.
///
/// Данные готовит Flutter (канал `lifeos/home_widget`, метод `update`) и
/// они хранятся в SharedPreferences: виджет перерисовывается и без запущенного
/// приложения (после перезагрузки, по `updatePeriodMillis`).
class LifeOsGlanceWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val views = buildViews(context)
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, views)
    }

    companion object {
        private const val PREFS = "lifeos_glance_widget"
        private val STRING_KEYS =
            listOf("safeLabel", "safeValue", "task1", "task2", "tasksEmpty", "routine")
        private const val KEY_SAFE_NEGATIVE = "safeIsNegative"

        private const val COLOR_TEXT = 0xFFF0F6FC.toInt()
        private const val COLOR_NEGATIVE = 0xFFFF7675.toInt()

        /// Сохраняет данные от Flutter и перерисовывает все экземпляры виджета.
        fun update(context: Context, data: Map<String, Any?>) {
            val editor = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            for (key in STRING_KEYS) editor.putString(key, data[key] as? String ?: "")
            editor.putBoolean(KEY_SAFE_NEGATIVE, data[KEY_SAFE_NEGATIVE] as? Boolean ?: false)
            editor.apply()

            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, LifeOsGlanceWidget::class.java))
            if (ids.isEmpty()) return
            val views = buildViews(context)
            for (id in ids) manager.updateAppWidget(id, views)
        }

        private fun buildViews(context: Context): RemoteViews {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            fun text(key: String) = prefs.getString(key, "") ?: ""

            val views = RemoteViews(context.packageName, R.layout.lifeos_glance_widget)

            views.setTextViewText(
                R.id.widget_safe_label,
                text("safeLabel").ifEmpty { "Доступно сегодня" },
            )
            // Пока приложение ни разу не передало данные — приглашение открыть его.
            views.setTextViewText(
                R.id.widget_safe_value,
                text("safeValue").ifEmpty { "Откройте LifeOS" },
            )
            views.setTextColor(
                R.id.widget_safe_value,
                if (prefs.getBoolean(KEY_SAFE_NEGATIVE, false)) COLOR_NEGATIVE else COLOR_TEXT,
            )

            val task1 = text("task1")
            val task2 = text("task2")
            bindTask(views, R.id.widget_task1, task1)
            bindTask(views, R.id.widget_task2, task2)
            if (task1.isEmpty() && task2.isEmpty()) {
                views.setTextViewText(R.id.widget_tasks_empty, text("tasksEmpty"))
                views.setViewVisibility(R.id.widget_tasks_empty, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.widget_tasks_empty, View.GONE)
            }

            val routine = text("routine")
            views.setTextViewText(R.id.widget_routine, routine)
            views.setViewVisibility(
                R.id.widget_routine,
                if (routine.isEmpty()) View.GONE else View.VISIBLE,
            )

            val launch = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java).addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP,
                ),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, launch)
            views.setOnClickPendingIntent(R.id.widget_open, launch)
            return views
        }

        private fun bindTask(views: RemoteViews, viewId: Int, title: String) {
            if (title.isEmpty()) {
                views.setViewVisibility(viewId, View.GONE)
            } else {
                views.setTextViewText(viewId, "•  $title")
                views.setViewVisibility(viewId, View.VISIBLE)
            }
        }
    }
}
