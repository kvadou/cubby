package dev.kvadou.cubby

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import dev.kvadou.cubby.ui.CubbyApp
import dev.kvadou.cubby.ui.CubbyTheme

class MainActivity : ComponentActivity() {
    private val session: Session by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            CubbyTheme { CubbyApp(session) }
        }
    }
}
