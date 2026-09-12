package com.example.mobile_app

import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.content.Intent
import android.media.MediaPlayer
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.animation.LinearInterpolator
import androidx.appcompat.app.AppCompatActivity

class SplashActivity : AppCompatActivity() {

    private var mediaPlayer: MediaPlayer? = null
    private val indicatorAnimators = mutableListOf<ObjectAnimator>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_splash)


        

        Handler(Looper.getMainLooper()).postDelayed({
            val intent = Intent(this, MainActivity::class.java)
            startActivity(intent)
            finish()
        }, 5800)
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
