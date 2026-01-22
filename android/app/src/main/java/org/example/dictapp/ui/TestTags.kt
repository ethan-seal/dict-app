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
    
    // Definition screen sections
    const val ETYMOLOGY_SECTION = "etymology_section"
    const val DEFINITIONS_SECTION = "definitions_section"
    const val DEFINITION_CARD = "definition_card"
    const val TRANSLATIONS_SECTION = "translations_section"
    
    // General
    const val LOADING_INDICATOR = "loading_indicator"
    
    // Settings screen
    const val SETTINGS_BUTTON = "settings_button"
    const val SETTINGS_SCREEN = "settings_screen"
    const val SETTINGS_BACK_BUTTON = "settings_back_button"
    const val SETTINGS_ENGLISH_VARIANT_SELECTOR = "settings_english_variant_selector"
    const val SETTINGS_DESIGN_SYSTEM_ITEM = "settings_design_system_item"
}
