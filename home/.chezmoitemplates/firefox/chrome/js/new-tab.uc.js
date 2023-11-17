// Set browser.newtab.url in about:config to change new tab URL

(function(){
  try {
    const NEW_TAB_CONFIG_PATH = "browser.newtab.url";
    Cu.import("resource:///modules/AboutNewTab.jsm");
    // fetch pref if it exists
    let xpref = Cc["@mozilla.org/preferences-service;1"].getService(Ci.nsIPrefService);

    function setFocusOnPage() {
      setTimeout(function() {
        gBrowser.selectedBrowser.focus();
      }, 0);
    }

    function setNewTabURL(url) {
      AboutNewTab.newTabURL = url;
    }

    // set the new tab URL in the browser itself
    setNewTabURL(xpref.getStringPref(NEW_TAB_CONFIG_PATH, "about:blank"));
    // add a listener to update the new tab URL if it changes
    xpref.addObserver(NEW_TAB_CONFIG_PATH, (_) => {
      setNewTabURL(xpref.getStringPref(NEW_TAB_CONFIG_PATH, "about:blank"));
    });
    // don't place the caret in the location bar
    gBrowser.tabContainer.addEventListener("TabOpen", setFocusOnPage, false);
  } catch (e) {
    console.error(e);
  }
})();
