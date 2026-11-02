package com.tecclub.flutter_singbox.config

import android.content.Context
import android.util.Log
import com.tecclub.flutter_singbox.Application

object SimpleConfigManager {
    private const val TAG = "SimpleConfigManager"
    private const val PREF_NAME = "singbox_config"
    private const val KEY_CONFIG = "config_json"
    private const val KEY_AUTO_START = "auto_start"
    private const val KEY_STARTED_BY_USER = "started_by_user"
    private const val KEY_NOTIFICATION_TITLE = "notification_title"
    private const val KEY_NOTIFICATION_DESCRIPTION = "notification_description"
    private const val DEFAULT_CONFIG = "{}"
    private const val DEFAULT_NOTIFICATION_TITLE = "VPN Service"
    private const val DEFAULT_NOTIFICATION_DESCRIPTION = "Connected"
    
    // Initialize the config manager with context
    fun init(context: Context) {
        // Drop any leftover plaintext tunnel JSON from older builds.
        clearPersistedConfig(context)
    }
    
    // In-memory only — never write full sing-box JSON (uuid/password/Reality) to disk.
    private var cachedConfig: String = DEFAULT_CONFIG
    
    // Save config JSON string
    fun saveConfig(config: String): Boolean {
        if (config.isEmpty()) return false
        
        return try {
            cachedConfig = config
            clearPersistedConfig()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save config", e)
            false
        }
    }

    fun clearConfig() {
        cachedConfig = DEFAULT_CONFIG
        clearPersistedConfig()
    }

    private fun clearPersistedConfig(context: Context? = null) {
        try {
            val prefs = if (context != null) {
                context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            } else {
                Application.application.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            }
            if (prefs.contains(KEY_CONFIG)) {
                prefs.edit().remove(KEY_CONFIG).apply()
            }
        } catch (_: Exception) {
        }
    }
    
    // Get current config JSON string
    fun getConfig(): String {
        if (cachedConfig != DEFAULT_CONFIG) {
            return cachedConfig
        }
        // Do not reload secrets from disk — older builds may still have them; wipe.
        clearPersistedConfig()
        return DEFAULT_CONFIG
    }
    
    // Check if we have a valid config (not empty or default)
    fun hasValidConfig(): Boolean {
        val config = getConfig()
        return config.isNotEmpty() && config != DEFAULT_CONFIG
    }
    
    // Set auto-start setting
    fun setAutoStart(enabled: Boolean) {
        try {
            val prefs = Application.application.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            prefs.edit().putBoolean(KEY_AUTO_START, enabled).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save auto-start setting", e)
        }
    }
    
    // Get auto-start setting
    fun getAutoStart(): Boolean {
        return try {
            val prefs = Application.application.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            prefs.getBoolean(KEY_AUTO_START, false)
        } catch (e: UninitializedPropertyAccessException) {
            false
        }
    }
    
    // Set notification title
    fun setNotificationTitle(title: String) {
        try {
            val prefs = Application.application.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            prefs.edit().putString(KEY_NOTIFICATION_TITLE, title).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save notification title", e)
        }
    }
    
    // Get notification title
    fun getNotificationTitle(): String {
        return try {
            val prefs = Application.application.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            prefs.getString(KEY_NOTIFICATION_TITLE, DEFAULT_NOTIFICATION_TITLE) ?: DEFAULT_NOTIFICATION_TITLE
        } catch (e: Exception) {
            DEFAULT_NOTIFICATION_TITLE
        }
    }
    
    // Set notification description
    fun setNotificationDescription(description: String) {
        try {
            val prefs = Application.application.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            prefs.edit().putString(KEY_NOTIFICATION_DESCRIPTION, description).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save notification description", e)
        }
    }
    
    // Get notification description
    fun getNotificationDescription(): String {
        return try {
            val prefs = Application.application.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            prefs.getString(KEY_NOTIFICATION_DESCRIPTION, DEFAULT_NOTIFICATION_DESCRIPTION) ?: DEFAULT_NOTIFICATION_DESCRIPTION
        } catch (e: Exception) {
            DEFAULT_NOTIFICATION_DESCRIPTION
        }
    }
    
    // Get auto-start setting with context (for use before Application is initialized)
    fun getAutoStart(context: Context): Boolean {
        return try {
            val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            prefs.getBoolean(KEY_AUTO_START, false)
        } catch (e: Exception) {
            false
        }
    }
    
    // Set started by user flag
    fun setStartedByUser(started: Boolean) {
        try {
            val prefs = Application.application.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            prefs.edit().putBoolean(KEY_STARTED_BY_USER, started).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save started-by-user setting", e)
        }
    }
    
    // Get started by user flag
    fun getStartedByUser(): Boolean {
        val prefs = Application.application.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        return prefs.getBoolean(KEY_STARTED_BY_USER, false)
    }
}
