// skip 1st line
let {
  classes: Cc,
  interfaces: Ci,
  utils: Cu
} = Components;

Services.obs.addObserver(function (aSubject, aTopic, aData) {
  var chromeWindow = aSubject;
  chromeWindow.setTimeout(function () {
    try {
      if (chromeWindow.userChromeJsMod) return;
      chromeWindow.userChromeJsMod = true;
      const ios = Cc["@mozilla.org/network/io-service;1"].getService(Ci.nsIIOService);
      const fph = ios.getProtocolHandler("file").QueryInterface(Ci.nsIFileProtocolHandler);
      const ds = Cc["@mozilla.org/file/directory_service;1"].getService(Ci.nsIProperties);

      let workDir = ds.get("UChrm", Ci.nsIFile);
      workDir.append('js');
      var files = workDir.directoryEntries.QueryInterface(Ci.nsISimpleEnumerator);
      while (files.hasMoreElements()) {
        var file = files.getNext().QueryInterface(Ci.nsIFile);
        if(/\.uc\.js$/i.test(file.leafName)) {
          let fileURL = fph
            .getURLSpecFromActualFile(file) + "?" + file.lastModifiedTime;
          Cc["@mozilla.org/moz/jssubscript-loader;1"].getService(Ci.mozIJSSubScriptLoader)
            .loadSubScriptWithOptions(fileURL, {
              target: chromeWindow,
              charset: "UTF-8",
              ignoreCache: true,
            });
        }
      }
    } catch (e) {
      Cu.reportError(e);
    }
  }, 10);
}, "browser-delayed-startup-finished", false);
