// SharedPreferencesConstants.swift
// VieLotusCore
//
// Shared constants for keyboard preferences and quick phrases.

import Foundation

/// Shared constants for keyboard preferences.
public enum SharedPreferencesConstants {
    /// Suite name for UserDefaults shared across VieLotusIM components.
    public static let defaultSuiteName = "group.com.vietlotus.keyboard"

    /// Darwin notification name posted when preferences change.
    public static let preferencesDidChangeDarwinNotification = "org.vielotus.keyboard.preferencesChanged.v5"
}
