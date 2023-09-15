// 0102: Startup with previous pages
user_pref("browser.startup.page", 3);

// 0801: Enable search in location bar
user_pref("keyword.enabled", true);

// 2022: Enable DRM contents: videos, music, ...
user_pref("media.eme.enabled", true);

// 4501: Enable RFP
user_pref("privacy.resistFingerprinting", false);
// 4501: Enable RFP letterboxing
user_pref("privacy.resistFingerprinting.letterboxing", false);
// 4520: Enable WebGL
user_pref("webgl.disabled", false);

// 2811: Disable clear session and history on shutdown
user_pref("privacy.clearOnShutdown.history", false); // Browsing & Download History
user_pref("privacy.clearOnShutdown.sessions", false); // Active Logins
