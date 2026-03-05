const builtin = @import("builtin");

pub const Platform = enum {
    /// Browser environment (WASM)
    browser,
    /// Server environment
    server,

    /// Future - Android environment
    android,
    /// Future - iOS environment
    ios,
    /// Future - macOS environment
    macos,
    /// Future - Windows environment
    windows,
};

/// The platform the code is running on
/// - `browser` if running in a browser environment (WASM)
/// - `server` if running on a server environment
/// - `android` if running on an Android environment
/// - `ios` if running on an iOS environment
/// - `macos` if running on a macOS environment
/// - `windows` if running on a Windows environment
pub const platform: Platform = if (builtin.os.tag == .freestanding) .browser else .server;
