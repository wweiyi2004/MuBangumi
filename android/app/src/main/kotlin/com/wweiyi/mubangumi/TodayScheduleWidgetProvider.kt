package com.wweiyi.mubangumi

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Medium home-screen widget: today's schedule titles + RSS unread badge.
 * Data is written from Flutter via home_widget SharedPreferences.
 */
class TodayScheduleWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    appWidgetIds.forEach { widgetId ->
      val views =
          RemoteViews(context.packageName, R.layout.today_schedule_widget).apply {
            val openIntent =
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("mubangumi://schedule"),
                )
            setOnClickPendingIntent(R.id.widget_root, openIntent)

            val title = widgetData.getString(KEY_TITLE, null) ?: "今日新番"
            val summary = widgetData.getString(KEY_SUMMARY, null) ?: "打开 App 同步课表"
            val unread = widgetData.getInt(KEY_UNREAD, 0)
            val empty = widgetData.getString(KEY_EMPTY, null) ?: "今天还没有安排"

            setTextViewText(R.id.widget_title, title)
            setTextViewText(R.id.widget_summary, summary)

            if (unread > 0) {
              setViewVisibility(R.id.widget_badge, View.VISIBLE)
              setTextViewText(
                  R.id.widget_badge,
                  if (unread > 99) "99+" else unread.toString(),
              )
            } else {
              setViewVisibility(R.id.widget_badge, View.GONE)
            }

            val lines =
                listOf(
                    widgetData.getString(KEY_LINE1, null),
                    widgetData.getString(KEY_LINE2, null),
                    widgetData.getString(KEY_LINE3, null),
                    widgetData.getString(KEY_LINE4, null),
                )
            val lineViews =
                listOf(
                    R.id.widget_line1,
                    R.id.widget_line2,
                    R.id.widget_line3,
                    R.id.widget_line4,
                )
            val hasAny = lines.any { !it.isNullOrBlank() }
            if (!hasAny) {
              setViewVisibility(R.id.widget_empty, View.VISIBLE)
              setTextViewText(R.id.widget_empty, empty)
              lineViews.forEach { setViewVisibility(it, View.GONE) }
            } else {
              setViewVisibility(R.id.widget_empty, View.GONE)
              lines.forEachIndexed { index, text ->
                val viewId = lineViews[index]
                if (text.isNullOrBlank()) {
                  setViewVisibility(viewId, View.GONE)
                } else {
                  setViewVisibility(viewId, View.VISIBLE)
                  setTextViewText(viewId, text)
                }
              }
            }
          }
      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }

  companion object {
    const val KEY_TITLE = "today_title"
    const val KEY_SUMMARY = "today_summary"
    const val KEY_UNREAD = "today_unread"
    const val KEY_EMPTY = "today_empty"
    const val KEY_LINE1 = "today_line1"
    const val KEY_LINE2 = "today_line2"
    const val KEY_LINE3 = "today_line3"
    const val KEY_LINE4 = "today_line4"
  }
}
