package dev.kvadou.cubby

import android.os.ParcelFileDescriptor
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.hasScrollAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Signs in as the local demo parent (api/db/seeds/demo_users.rb) against the API on the Mac's
 * localhost:3000, walks the tabs, and saves a screenshot of each where the test APK's uninstall
 * leaves it (adb pull /data/local/tmp/cubby-screenshots). Needs `docker compose up`.
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
class ParentFlowTest {
    private val email = "parent@littleoaks.test"
    private val password = "littleoaks-demo" // the public, fictional local demo value

    @get:Rule val compose = createEmptyComposeRule()

    @Test fun parentSignsInAndSeesEachTab() {
        // Start signed out so sign-in is always exercised.
        TokenStore(InstrumentationRegistry.getInstrumentation().targetContext).clear()
        ActivityScenario.launch(MainActivity::class.java).use { walkTheTabs() }
    }

    private fun walkTheTabs() {
        compose.waitUntilExactlyOneExists(hasTestTag("email"), 10_000)
        snap("1-sign-in")
        compose.onNodeWithTag("email").performTextInput(email)
        compose.onNodeWithTag("password").performTextInput(password)
        compose.onNodeWithTag("signIn").performClick()

        compose.waitUntilAtLeastOneExists(hasText("Meryl"), 15_000)
        compose.waitUntilAtLeastOneExists(hasText("Center"), 10_000)
        compose.waitForIdle()
        snap("2-today")

        compose.onNodeWithTag("tab-Messages").performClick()
        compose.waitUntilAtLeastOneExists(hasText("Welcome to Cubby"), 10_000)
        compose.waitForIdle()
        snap("3-messages")
        compose.onNodeWithText("Welcome to Cubby").performClick()
        compose.waitUntilExactlyOneExists(hasTestTag("back"), 5_000)
        snap("4-message")
        compose.onNodeWithTag("back").performClick()

        compose.onNodeWithTag("tab-Billing").performClick()
        compose.waitUntilAtLeastOneExists(hasText("Due"), 10_000)
        compose.waitForIdle()
        snap("5-billing")

        compose.onNodeWithTag("tab-Today").performClick()
        compose.waitUntilAtLeastOneExists(hasText("Meryl"), 10_000)
        compose.onNode(hasScrollAction()).performScrollToNode(hasTestTag("signOut"))
        compose.onNodeWithTag("signOut").performClick()
        compose.waitUntilExactlyOneExists(hasTestTag("email"), 10_000)
    }

    private fun snap(name: String) {
        Thread.sleep(400) // let ripples and the pull-to-refresh indicator settle
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        // Reading the output to the end waits for the command to finish.
        for (command in listOf("mkdir -p $DIR", "screencap -p $DIR/$name.png")) {
            ParcelFileDescriptor.AutoCloseInputStream(automation.executeShellCommand(command)).use { it.readBytes() }
        }
    }

    private companion object {
        const val DIR = "/data/local/tmp/cubby-screenshots"
    }
}
