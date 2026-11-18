// SharedPreferencesConstants.swift
// VieLotusCore
//
// Shared constants used by both VieLotusCore (QuickPhraseStore) and
// VieLotusMobileCore (KeyboardPreferences). Extracted to avoid a circular
// dependency between the two modules.

import Foundation

/// Shared constants for keyboard preferences, used across Core and Mobile modules.
public enum SharedPreferencesConstants {
    /// App Group suite name for UserDefaults shared between the host app and keyboard extension.
    public static let defaultSuiteName = "group.com.vietlotus.keyboard"

    /// Darwin notification name posted when preferences change.
    public static let preferencesDidChangeDarwinNotification = "org.vielotus.keyboard.preferencesChanged.v5"
}
