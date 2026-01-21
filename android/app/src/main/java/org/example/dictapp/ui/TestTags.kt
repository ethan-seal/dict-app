package org.example.dictapp.ui

/**
 * Test tags for Compose UI testing.
 * 
 * These tags are used by androidTest to find and interact with UI elements.
 */
object TestTags {
    // Search screen
    const val SEARCH_INPUT = "search_input"
    const val SEARCH_RESULTS_LIST = "search_results_list"
    const val SEARCH_RESULT_CARD = "search_result_card"
    const val SEARCH_LOADING = "search_loading"
    const val SEARCH_EMPTY_PROMPT = "search_empty_prompt"
    const val NO_RESULTS_MESSAGE = "no_results_message"
    
    // Definition screen
    const val DEFINITION_SCREEN = "definition_screen"
    const val DEFINITION_HEADER = "definition_header"
    const val DEFINITION_WORD = "definition_word"
    const val DEFINITION_POS = "definition_pos"
    const val DEFINITION_CONTENT = "definition_content"
    const val BACK_BUTTON = "back_button"
    
    // General
    const val LOADING_INDICATOR = "loading_indicator"
}
