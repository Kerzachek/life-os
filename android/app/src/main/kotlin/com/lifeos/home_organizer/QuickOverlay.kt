package com.lifeos.home_organizer

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.app.Application
import android.content.ComponentCallbacks
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Point
import android.graphics.Rect
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import android.view.Display
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowInsets
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.hypot
import kotlin.math.min

/**
 * Кнопка быстрых действий поверх всех приложений (доступ «Поверх других
 * приложений», SYSTEM_ALERT_WINDOW).
 *
 * Живёт в процессе приложения, но вне Activity: окно оверлея держит процесс
 * «заметным» для системы, и кнопка остаётся на экране, пока LifeOS свёрнут.
 * Перетаскивается и примагничивается к левому или правому краю; по тапу —
 * компактное меню. Выбор действия выводит LifeOS на передний план, форму
 * открывает Dart (событие `onAction` или `takePendingAction` при запуске).
 */
@SuppressLint("StaticFieldLeak") // Только контекст приложения / окна.
object QuickOverlay {
    const val EXTRA_ACTION = "com.lifeos.home_organizer.QUICK_ACTION"

    data class Item(val id: String, val label: String, val color: Int)

    interface Listener {
        fun onOverlayAction(id: String)
        fun onOverlayDismissed()
        fun onOverlayMoved(isLeft: Boolean, fraction: Double)
    }

    /** Активный Flutter-движок (MainActivity). `null` — Activity уничтожена. */
    var listener: Listener? = null

    private const val TAG = "QuickOverlay"
    private const val BUBBLE_DP = 52
    private const val MARGIN_DP = 8
    private const val IDLE_ALPHA = 0.55f
    private const val PRIMARY = 0xFF6366F1.toInt()
    private const val MUTED = 0xFF8B949E.toInt()

    private var app: Application? = null
    private var context: Context? = null
    private var windowManager: WindowManager? = null
    private var bubble: BubbleView? = null
    private var bubbleParams: WindowManager.LayoutParams? = null
    private var menu: View? = null

    private var items: List<Item> = emptyList()
    private var isLeft = false
    private var fraction = 0.6
    private var hideWhenAppVisible = true
    private var appVisible = false
    private var touching = false
    private var lastMenuClose = 0L
    private var callbacksRegistered = false

    private val configCallbacks = object : ComponentCallbacks {
        override fun onConfigurationChanged(newConfig: Configuration) {
            // Метрики окна обновляются после колбэка — ждём следующий кадр.
            bubble?.post { reposition() }
        }

        @Deprecated("Deprecated in Java")
        override fun onLowMemory() {}
    }

    fun canDraw(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)

    /**
     * Показывает кнопку или обновляет меню и режим скрытия. Положение
     * применяется только при создании. `false` — нет доступа.
     */
    fun show(
        application: Application,
        items: List<Item>,
        isLeft: Boolean,
        fraction: Double,
        hideWhenAppVisible: Boolean,
    ): Boolean {
        if (!canDraw(application)) return false
        this.items = items
        this.hideWhenAppVisible = hideWhenAppVisible
        closeMenu()
        if (bubble == null) {
            val ctx = windowContext(application)
            val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            app = application
            context = ctx
            windowManager = wm
            this.isLeft = isLeft
            this.fraction = fraction.coerceIn(0.0, 1.0)

            val view = BubbleView(ctx)
            val size = dp(BUBBLE_DP)
            val params = overlayParams(size, size)
            val anchor = anchor()
            params.x = anchor.x
            params.y = anchor.y
            try {
                wm.addView(view, params)
            } catch (e: Exception) {
                Log.w(TAG, "addView failed", e)
                return false
            }
            bubble = view
            bubbleParams = params
            attachTouch(view)
            if (!callbacksRegistered) {
                application.registerComponentCallbacks(configCallbacks)
                callbacksRegistered = true
            }
        }
        applyVisibility()
        return true
    }

    /** Уничтожает окна оверлея. */
    fun hide() {
        closeMenu()
        val view = bubble ?: return
        bubble = null
        bubbleParams = null
        runCatching { windowManager?.removeView(view) }
    }

    /** MainActivity видна / скрыта (onStart / onStop). */
    fun setAppVisible(visible: Boolean) {
        appVisible = visible
        applyVisibility()
    }

    private fun applyVisibility() {
        val view = bubble ?: return
        val visible = !(hideWhenAppVisible && appVisible)
        if (!visible) closeMenu()
        view.visibility = if (visible) View.VISIBLE else View.GONE
        updateAlpha()
    }

    private fun windowContext(application: Application): Context {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return application
        val display = application.getSystemService(DisplayManager::class.java)
            .getDisplay(Display.DEFAULT_DISPLAY) ?: return application
        return application.createDisplayContext(display)
            .createWindowContext(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY, null)
    }

    @Suppress("DEPRECATION")
    private fun overlayType(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            WindowManager.LayoutParams.TYPE_PHONE
        }

    private fun overlayParams(width: Int, height: Int, extraFlags: Int = 0) =
        WindowManager.LayoutParams(
            width,
            height,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                extraFlags,
            PixelFormat.TRANSLUCENT,
        ).apply { gravity = Gravity.TOP or Gravity.START }

    private fun dp(value: Int): Int =
        (value * (context ?: app)!!.resources.displayMetrics.density).toInt()

    /** Экран без системных панелей и выреза, с отступом от краёв. */
    private fun area(): Rect {
        val ctx = context!!
        val margin = dp(MARGIN_DP)
        val rect = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val metrics = windowManager!!.currentWindowMetrics
            val insets = metrics.windowInsets.getInsetsIgnoringVisibility(
                WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout(),
            )
            val bounds = metrics.bounds
            Rect(
                bounds.left + insets.left,
                bounds.top + insets.top,
                bounds.right - insets.right,
                bounds.bottom - insets.bottom,
            )
        } else {
            val res = ctx.resources
            val id = res.getIdentifier("status_bar_height", "dimen", "android")
            val top = if (id > 0) res.getDimensionPixelSize(id) else 0
            Rect(0, top, res.displayMetrics.widthPixels, res.displayMetrics.heightPixels)
        }
        rect.inset(margin, margin)
        return rect
    }

    private fun anchor(): Point {
        val a = area()
        val size = dp(BUBBLE_DP)
        val range = (a.height() - size).coerceAtLeast(0)
        return Point(
            if (isLeft) a.left else a.right - size,
            a.top + (fraction * range).toInt(),
        )
    }

    private fun reposition() {
        val view = bubble ?: return
        val params = bubbleParams ?: return
        closeMenu()
        val anchor = anchor()
        params.x = anchor.x
        params.y = anchor.y
        runCatching { windowManager?.updateViewLayout(view, params) }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun attachTouch(view: BubbleView) {
        val slop = ViewConfiguration.get(view.context).scaledTouchSlop
        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        var dragging = false
        view.setOnTouchListener { _, event ->
            val params = bubbleParams ?: return@setOnTouchListener false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    startX = params.x
                    startY = params.y
                    dragging = false
                    touching = true
                    updateAlpha()
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downX
                    val dy = event.rawY - downY
                    if (!dragging && hypot(dx, dy) > slop) {
                        dragging = true
                        closeMenu()
                    }
                    if (dragging) {
                        val a = area()
                        val size = dp(BUBBLE_DP)
                        params.x = (startX + dx).toInt()
                            .coerceIn(a.left, (a.right - size).coerceAtLeast(a.left))
                        params.y = (startY + dy).toInt()
                            .coerceIn(a.top, (a.bottom - size).coerceAtLeast(a.top))
                        runCatching { windowManager?.updateViewLayout(view, params) }
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    touching = false
                    if (dragging) {
                        drop(view, params)
                    } else if (event.actionMasked == MotionEvent.ACTION_UP) {
                        onBubbleTap()
                    }
                    updateAlpha()
                }
            }
            true
        }
    }

    /** Отпускание: примагничивание к ближайшему краю и сохранение положения. */
    private fun drop(view: View, params: WindowManager.LayoutParams) {
        val a = area()
        val size = dp(BUBBLE_DP)
        isLeft = params.x + size / 2 < a.centerX()
        val range = a.height() - size
        fraction = if (range > 0) {
            ((params.y - a.top).toDouble() / range).coerceIn(0.0, 1.0)
        } else {
            0.0
        }
        val target = if (isLeft) a.left else a.right - size
        ValueAnimator.ofInt(params.x, target).apply {
            duration = 220
            interpolator = DecelerateInterpolator()
            addUpdateListener {
                if (bubble !== view) return@addUpdateListener
                params.x = it.animatedValue as Int
                runCatching { windowManager?.updateViewLayout(view, params) }
            }
            start()
        }
        listener?.onOverlayMoved(isLeft, fraction)
    }

    private fun onBubbleTap() {
        if (menu != null) {
            closeMenu()
            return
        }
        // Тап по кнопке при открытом меню сначала закрыл его (касание
        // «снаружи») — не открываем снова.
        if (SystemClock.uptimeMillis() - lastMenuClose < 300) return
        openMenu()
    }

    private fun openMenu() {
        val ctx = context ?: return
        val params = bubbleParams ?: return
        val wm = windowManager ?: return

        val root = object : LinearLayout(ctx) {
            override fun dispatchTouchEvent(event: MotionEvent): Boolean {
                if (event.actionMasked == MotionEvent.ACTION_OUTSIDE) {
                    closeMenu()
                    return true
                }
                return super.dispatchTouchEvent(event)
            }
        }
        root.orientation = LinearLayout.VERTICAL
        root.background = GradientDrawable().apply {
            cornerRadius = dp(14).toFloat()
            setColor(0xF21C212B.toInt())
            setStroke(dp(1), 0xFF2B3245.toInt())
        }
        root.setPadding(dp(6), dp(6), dp(6), dp(6))
        for (item in items) {
            root.addView(menuRow(ctx, item.label, dot(ctx, item.color), Color.WHITE) {
                pick(item.id)
            })
        }
        root.addView(
            View(ctx).apply { setBackgroundColor(0xFF2B3245.toInt()) },
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(1)).apply {
                setMargins(dp(8), dp(4), dp(8), dp(4))
            },
        )
        root.addView(menuRow(ctx, "Открыть LifeOS", dot(ctx, PRIMARY), Color.WHITE) {
            closeMenu()
            openApp(null)
        })
        root.addView(menuRow(ctx, "Скрыть", glyph(ctx, "✕"), MUTED) { dismiss() })

        root.measure(View.MeasureSpec.UNSPECIFIED, View.MeasureSpec.UNSPECIFIED)
        val width = root.measuredWidth
        val height = root.measuredHeight
        val a = area()
        val size = dp(BUBBLE_DP)
        val gap = dp(8)
        val left = params.x + size / 2 < a.centerX()
        val below = params.y + size / 2 < a.centerY()
        val menuParams = overlayParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
        )
        menuParams.x = (if (left) params.x else params.x + size - width)
            .coerceIn(a.left, (a.right - width).coerceAtLeast(a.left))
        menuParams.y = (if (below) params.y + size + gap else params.y - gap - height)
            .coerceIn(a.top, (a.bottom - height).coerceAtLeast(a.top))
        try {
            wm.addView(root, menuParams)
        } catch (e: Exception) {
            Log.w(TAG, "menu addView failed", e)
            return
        }
        menu = root
        bubble?.animate()?.rotation(45f)?.setDuration(160)?.start()
        updateAlpha()
    }

    private fun closeMenu() {
        val view = menu ?: return
        menu = null
        lastMenuClose = SystemClock.uptimeMillis()
        runCatching { windowManager?.removeView(view) }
        bubble?.animate()?.rotation(0f)?.setDuration(160)?.start()
        updateAlpha()
    }

    private fun menuRow(
        ctx: Context,
        label: String,
        marker: View,
        textColor: Int,
        onTap: () -> Unit,
    ): View {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumWidth = dp(184)
            setPadding(dp(12), dp(11), dp(16), dp(11))
            background = RippleDrawable(
                ColorStateList.valueOf(0x33FFFFFF),
                null,
                GradientDrawable().apply {
                    cornerRadius = dp(10).toFloat()
                    setColor(Color.WHITE)
                },
            )
            isClickable = true
            setOnClickListener { onTap() }
        }
        row.addView(marker)
        row.addView(TextView(ctx).apply {
            text = label
            textSize = 15f
            setTextColor(textColor)
        })
        return row
    }

    private fun dot(ctx: Context, color: Int): View = View(ctx).apply {
        background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(color)
        }
        layoutParams = LinearLayout.LayoutParams(dp(10), dp(10)).apply {
            marginEnd = dp(12)
        }
    }

    private fun glyph(ctx: Context, text: String): View = TextView(ctx).apply {
        this.text = text
        textSize = 12f
        setTextColor(MUTED)
        gravity = Gravity.CENTER
        layoutParams = LinearLayout.LayoutParams(dp(10), LinearLayout.LayoutParams.WRAP_CONTENT)
            .apply { marginEnd = dp(12) }
    }

    private fun pick(id: String) {
        closeMenu()
        val current = listener
        // Flutter работает — форму откроет он сам; иначе Activity получит
        // действие в интенте и передаст его через takePendingAction.
        openApp(if (current == null) id else null)
        current?.onOverlayAction(id)
    }

    /** Выводит LifeOS на передний план, как значок на рабочем столе. */
    private fun openApp(action: String?) {
        val application = app ?: return
        val intent = application.packageManager.getLaunchIntentForPackage(application.packageName)
            ?: Intent(application, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (action != null) intent.putExtra(EXTRA_ACTION, action)
        try {
            application.startActivity(intent)
        } catch (e: Exception) {
            Log.w(TAG, "startActivity failed", e)
        }
    }

    private fun dismiss() {
        hide()
        listener?.onOverlayDismissed()
    }

    private fun updateAlpha() {
        bubble?.alpha = if (touching || menu != null) 1f else IDLE_ALPHA
    }

    /** Круглая кнопка с «плюсом». */
    private class BubbleView(context: Context) : View(context) {
        private val density = context.resources.displayMetrics.density
        private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = PRIMARY }
        private val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            color = 0x99FFFFFF.toInt()
            strokeWidth = 1.5f * density
        }
        private val plus = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            strokeWidth = 3f * density
            strokeCap = Paint.Cap.ROUND
        }

        override fun onDraw(canvas: Canvas) {
            val cx = width / 2f
            val cy = height / 2f
            val radius = min(width, height) / 2f - border.strokeWidth
            canvas.drawCircle(cx, cy, radius, fill)
            canvas.drawCircle(cx, cy, radius, border)
            val arm = radius * 0.42f
            canvas.drawLine(cx - arm, cy, cx + arm, cy, plus)
            canvas.drawLine(cx, cy - arm, cx, cy + arm, plus)
        }
    }
}
