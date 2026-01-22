package org.example.dictapp.settings

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * Extension property to create a singleton DataStore instance.
 */
private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

/**
 * English variant options for pronunciation and spelling preferences.
 */
enum class EnglishVariant(val displayName: String) {
    US("American English"),
    UK("British English"),
    AU("Australian English"),
    NONE("No preference")
}

/**
 * Repository for managing app settings with DataStore persistence.
 * 
 * Provides reactive flows for settings that automatically update UI when changed.
 */
class SettingsRepository(private val context: Context) {
    
    companion object {
        private val ENGLISH_VARIANT_KEY = stringPreferencesKey("english_variant")
    }
    
    /**
     * Flow of the current English variant preference.
     */
    val englishVariant: Flow<EnglishVariant> = context.dataStore.data
        .map { preferences ->
            val variantName = preferences[ENGLISH_VARIANT_KEY] ?: EnglishVariant.NONE.name
            try {
                EnglishVariant.valueOf(variantName)
            } catch (e: IllegalArgumentException) {
                EnglishVariant.NONE
            }
        }
    
    /**
     * Update the English variant preference.
     */
    suspend fun setEnglishVariant(variant: EnglishVariant) {
        context.dataStore.edit { preferences ->
            preferences[ENGLISH_VARIANT_KEY] = variant.name
        }
    }
}
