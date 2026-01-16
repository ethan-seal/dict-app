package org.example.dictapp

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import org.example.dictapp.ui.DefinitionScreen
import org.example.dictapp.ui.DownloadScreen
import org.example.dictapp.ui.SearchScreen
import org.example.dictapp.ui.theme.DictAppTheme
import org.example.dictapp.viewmodel.DictViewModel

/**
 * Main entry point for the Dictionary App.
 *
 * This activity hosts the Compose navigation and manages the app lifecycle.
 * The app follows a single-activity architecture with Compose Navigation.
 *
 * Can be launched with an optional search word via [DefineWordActivity.EXTRA_SEARCH_WORD]
 * to immediately search for a word when coming from the text selection flow.
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        // Extract search word from intent (if launched from DefineWordActivity)
        val initialSearchWord = intent?.getStringExtra(DefineWordActivity.EXTRA_SEARCH_WORD)

        setContent {
            DictAppTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    DictApp(initialSearchWord = initialSearchWord)
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Handle new intent when activity is re-launched
        // This is needed when FLAG_ACTIVITY_CLEAR_TOP is used
        setIntent(intent)
    }
}

/**
 * Navigation routes for the app.
 */
object Routes {
    const val DOWNLOAD = "download"
    const val SEARCH = "search"
    const val DEFINITION = "definition/{wordId}"

    fun definition(wordId: Long) = "definition/$wordId"
}

/**
 * Main app composable with navigation.
 *
 * @param initialSearchWord Optional word to search for on launch (from text selection)
 * @param viewModel The ViewModel instance
 */
@Composable
fun DictApp(
    initialSearchWord: String? = null,
    viewModel: DictViewModel = viewModel()
) {
    val navController = rememberNavController()
    val isDatabaseReady by viewModel.isDatabaseReady.collectAsState()

    // Track if we've determined the start destination
    var startDestinationDetermined by remember { mutableStateOf(false) }
    var startDestination by remember { mutableStateOf(Routes.DOWNLOAD) }

    // Determine start destination based on database status
    LaunchedEffect(isDatabaseReady) {
        startDestination = if (isDatabaseReady) Routes.SEARCH else Routes.DOWNLOAD
        startDestinationDetermined = true
    }

    // Set initial search query if provided (from DefineWordActivity)
    LaunchedEffect(initialSearchWord, isDatabaseReady) {
        if (isDatabaseReady && !initialSearchWord.isNullOrBlank()) {
            viewModel.onQueryChange(initialSearchWord)
        }
    }

    // Show loading while determining start destination
    if (!startDestinationDetermined) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            CircularProgressIndicator()
        }
        return
    }

    NavHost(
        navController = navController,
        startDestination = startDestination
    ) {
        // Download screen - shown on first launch
        composable(Routes.DOWNLOAD) {
            DownloadScreen(
                viewModel = viewModel,
                onDownloadComplete = {
                    navController.navigate(Routes.SEARCH) {
                        popUpTo(Routes.DOWNLOAD) { inclusive = true }
                    }
                }
            )
        }

        // Search screen - main screen
        composable(Routes.SEARCH) {
            SearchScreen(
                viewModel = viewModel,
                onWordClick = { wordId ->
                    navController.navigate(Routes.definition(wordId))
                }
            )
        }

        // Definition detail screen
        composable(
            route = Routes.DEFINITION,
            arguments = listOf(
                navArgument("wordId") { type = NavType.LongType }
            )
        ) { backStackEntry ->
            val wordId = backStackEntry.arguments?.getLong("wordId") ?: return@composable
            DefinitionScreen(
                wordId = wordId,
                viewModel = viewModel,
                onBack = { navController.popBackStack() }
            )
        }
    }
}
