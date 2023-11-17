// Change home page
user_pref("browser.startup.homepage", "{{ .chezmoi.sourceDir }}/.chezmoitemplates/firefox/startpage/index.html");
// Change new tab page
user_pref("browser.newtab.url", "{{ .chezmoi.sourceDir }}/.chezmoitemplates/firefox/startpage/index.html");
