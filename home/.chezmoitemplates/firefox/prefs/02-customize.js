// === GENERAL ===
// Startup
/* Warn when quitting browser */
user_pref("browser.sessionstore.warnOnQuit", true);

// Language and Appearance
/* Set website default colorscheme to dark
 * [SETTING] General->Language and Appearance->Website Appearance */
user_pref("layout.css.prefers-color-scheme.content-override", 0);
/* Set font for languages
 * [SETTING] General->Language and Appearance->Fonts and Colors */
user_pref("font.default.x-western", "sans-serif"); // Change Latin to Sans-serif
/* Set preferred language for displaying web pages
 * [SETTING] General->Language and Appearance->Language->Choose your preferred language for displaying pages */
user_pref("intl.accept_languages", "en-US, vi");

// Files and Applications
/* Ask where to save before download
 * [SETTING] General->Files and Applications->Downloads */
user_pref("browser.download.useDownloadDir", false);

// Performance
/* Use recommended performance settings
 * [SETTING] General->Performance->Use recommended performance settings */
user_pref("browser.preferences.defaultPerformanceSettings.enabled", true);

// Browsing
/* Use autoscrolling
 * [SETTING] General->Browsing->Use autoscrolling */
user_pref("general.autoScroll", true);
/* Use smooth scrolling
 * [SETTING] General->Browsing->Use smooth scrolling */
user_pref("general.smoothScroll", true);

// Network Settings
/* Enable DNS over HTTPS
 * 0=Native DNS from network, 1=Reserved, 2=Use DoH before native, 3=Only DoH
 * [SETTING] General->Network Settings->Enable DNS over HTTPS*/
user_pref("network.trr.mode", 2);

// === HOME ===
// Set HOME+NEWWINDOW page
user_pref("browser.startup.homepage", "about:home");

// === SEARCH ===
// Set search region
user_pref("browser.search.region", "VN");

// === PRIVACY & SECURITY ===
// Password
/* Disable saving passwords */
user_pref("signon.rememberSignons", false);

// History
/* Set what items to clear on shutdown
 * [SETTING] Privacy & Security->History->Custom Settings->Clear history when Firefox closes->Settings */
user_pref("privacy.clearOnShutdown.cookies", false);
user_pref("privacy.clearOnShutdown.offlineApps", true); // Offline Website Data
/* Enable browsing and download history
 * [SETTING] Privacy & Security->History->Custom Settings->Remember browsing and download history */
user_pref("places.history.enabled", true);

// === OTHER ===
/* Default bookmark location */
user_pref("browser.bookmarks.defaultLocation", "toolbar");
/* Stop auto add bookmarks from distribution */
user_pref("distribution.gentoo.bookmarksProcessed", true);
user_pref("distribution.archlinux.bookmarksProcessed", true);
