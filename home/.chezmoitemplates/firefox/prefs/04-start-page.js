// Change home page
user_pref("browser.startup.homepage", "file://{{ .chezmoi.homeDir }}/.config/firefox/startpage/index.html");
// Change new tab page
user_pref("browser.newtab.url", "file://{{ .chezmoi.homeDir }}/.config/firefox/startpage/index.html");
