package com.ismart.messenger

import android.animation.ObjectAnimator
import android.content.Intent
import android.media.MediaPlayer
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import androidx.appcompat.app.AppCompatActivity

class SplashActivity : AppCompatActivity() {

    private var mediaPlayer: MediaPlayer? = null
    private val indicatorAnimators = mutableListOf<ObjectAnimator>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // If the app is already in progress, or this launch was triggered by a notification,
        // bypass the splash delay immediately and forward all intent extras directly to MainActivity.
        val isFromNotification = isNotificationIntent(intent)
        if (!isTaskRoot || isFromNotification) {
            val forwardIntent = Intent(intent).apply {
                setClass(this@SplashActivity, MainActivity::class.java)
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            startActivity(forwardIntent)
            finish()
            return
        }

        setContentView(R.layout.activity_splash)

        Handler(Looper.getMainLooper()).postDelayed({
            if (!isFinishing) {
                val intent = Intent(this, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                startActivity(intent)
                finish()
            }
        }, 5800)
    }

    private fun isNotificationIntent(intent: Intent?): Boolean {
        if (intent == null) return false
        if (intent.action == "SELECT_NOTIFICATION" ||
            intent.action?.startsWith("com.dexterous.flutterlocalnotifications") == true
        ) {
            return true
        }
        val extras = intent.extras ?: return false
        for (key in extras.keySet()) {
            val lower = key.lowercase()
            if (lower.contains("notification") ||
                lower.contains("payload") ||
                lower.contains("conversationid") ||
                lower.contains("google.message_id") ||
                lower.contains("fcm") ||
                lower.contains("click_action")
            ) {
                return true
            }
        }
        return false
    }

    private fun prepareAnimatedView(view: View) {
        view.setLayerType(View.LAYER_TYPE_HARDWARE, null)
    }

    override fun onDestroy() {
        indicatorAnimators.forEach { it.cancel() }
        indicatorAnimators.clear()
        mediaPlayer?.release()
        mediaPlayer = null
        super.onDestroy()
    }
}
