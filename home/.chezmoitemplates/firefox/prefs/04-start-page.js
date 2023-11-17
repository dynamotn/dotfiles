// Change home page
user_pref("browser.startup.homepage", "file://{{ .chezmoi.sourceDir }}/.chezmoitemplates/firefox/startpage/index.html");
// Change new tab page
user_pref("browser.newtab.url", "file://{{ .chezmoi.sourceDir }}/.chezmoitemplates/firefox/startpage/index.html");
