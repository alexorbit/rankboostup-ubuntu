var windowId = undefined;
var exchangeTabId = undefined;
var currentPayload = {};
var currentUA = "";

function syncSharedState() {
    try {
        chrome.storage.local.set({
            currentUA: currentUA || "",
            windowId: typeof windowId === "number" ? windowId : null,
            isRunning: Boolean(isRunning)
        }, function () {
            if (chrome.runtime && chrome.runtime.lastError) {
                console.warn("Rankboostup: failed to persist shared state", chrome.runtime.lastError);
            }
        });
    } catch (error) {
        console.warn("Failed to sync Rankboostup shared state", error);
    }
}
var mobileUAs = [
    "Mozilla/5.0 (iPhone; CPU iPhone OS 7_0 like Mac OS X) AppleWebKit/537.51.1 (KHTML, like Gecko) Version/7.0 Mobile/11A465 Safari/9537.53",
    "Mozilla/5.0 (iPad; CPU OS 7_0 like Mac OS X) AppleWebKit/537.51.1 (KHTML, like Gecko) Version/7.0 Mobile/11A465 Safari/9537.53",
    "Mozilla/5.0 (Linux; Android 5.1.1; Nexus 5 Build/LMY48B; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/43.0.2357.65 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 4.1.1; Galaxy Nexus Build/JRO03C) AppleWebKit/535.19 (KHTML, like Gecko) Chrome/18.0.1025.166 Mobile Safari/535.19"
];
var isRunning = false; // this keeps track of whether the browsing exchange session is running or not.
var roothost = "app.rankboostup.com";
// var roothost = "localhost:8000";
// var rootprotocol = "http://";
var rootprotocol = "https://";

syncSharedState();

chrome.action.onClicked.addListener(function (tab) { 
	/**Fired when User Clicks ICON **/
	chrome.tabs.create({
		'url': rootprotocol + roothost + "/dashboard/traffic-exchange/"
	});
});

chrome.runtime.onMessage.addListener(
  function(request, sender, sendResponse) {
      var tabid = sender.tab.id;

           if(request.doAction == "startSession") {
                        chrome.windows.getCurrent(function(window) {
                                windowId = window.id;
                                exchangeTabId = tabid;
                                syncSharedState();
                        });
           }

	   if (request.doAction == "startPayload") {
	   		var payload = request.payload;
	   		currentPayload = payload;
	   		console.log("Browsing : ");
	   		console.log(payload);

	   		var has_referrer = payload.referrer.length>0;
	   		var end_url = has_referrer ? payload.referrer : payload.url;

	   		currentUA = payload.is_mobile ? mobileUAs[Math.floor(Math.random() * mobileUAs.length)] : "";

                        chrome.tabs.create({'url': end_url, 'windowId': windowId, 'active': false}, function(tab) {
                                        currentPayload.tabid = tab.id;

                                        chrome.scripting.executeScript({
                                                target: { tabId: tab.id },
                                                files: ['/scripts/uninterrupt.js'],
                                                world: 'MAIN'
                                        });

                                        // Inject User-Agent override for mobile sessions
                                        if (currentUA && currentUA !== "") {
                                                chrome.scripting.executeScript({
                                                        target: { tabId: tab.id },
                                                        func: (userAgent) => {
                                                                Object.defineProperty(navigator, 'userAgent', {
                                                                        get: function() { return userAgent; },
                                                                        configurable: true
                                                                });
                                                        },
                                                        args: [currentUA],
                                                        world: 'MAIN'
                                                });
                                        }

					if (has_referrer) {
						function clickIt() {
							//console.log("assigning referrer script");
                                                        chrome.scripting.executeScript({
                                                                target: { tabId: tab.id },
                                                                func: (url) => {
                                                                        console.log('clicking');
                                                                        var aTag = document.createElement('a');
                                                                        aTag.setAttribute('href', url);
                                                                        aTag.innerHTML = 'link';
                                                                        document.documentElement.appendChild(aTag);
                                                                        aTag.click();
                                                                },
                                                                args: [payload.url],
                                                                world: 'MAIN'
                                                        });
                                                }
                                                setTimeout(clickIt, 3*1000);
                                }

                                        if (currentPayload.is_bounce===false) {
						// console.log("assigning non bounce script");
                                                function bounceIt() {
                                                        // console.log("clicking random link because not bounce");
                                                        chrome.scripting.executeScript({
                                                                target: { tabId: tab.id },
                                                                func: () => {
                                                                        var links = document.querySelectorAll('a[href^="/"], a[href^="'+document.location.protocol+'//'+document.location.host+'"]');
                                                                        var randomInt = Math.floor(Math.random() * links.length);
                                                                        var randomLink = links[randomInt];
                                                                        if (randomLink) randomLink.click();
                                                                },
                                                                world: 'MAIN'
                                                        });
                                                }
                                                setTimeout(bounceIt, (currentPayload.timer-2)*1000);
                                        }

                                        isRunning = true;
                                        syncSharedState();
                                }
                        );
           }

           if (request.doAction == "stopPayload") {
	   		// close all tabs in this window
		   var payloadClone = JSON.parse(JSON.stringify(currentPayload));
	   		chrome.tabs.query({'windowId': windowId}, function(tabs) {
				tabs.forEach(function(tab) {
					if (tab.id != exchangeTabId) {
                        chrome.tabs.remove(tab.id, function () {
                        	if (tab.active==false) {
                        		// console.log("tab closed", tab);
							} else {
                        		// console.log("tab didn't close ! report", tab);
                        		chrome.tabs.sendMessage(tabid, {doAction: "reportSite", payload: payloadClone});
							}
                        });
                        isRunning = false;
                    }
				});
			});

                        currentPayload = {};
                        currentUA = "";
                        syncSharedState();
           }

           if (request.doAction == "getRunning") {
                        if (sender.tab.windowId == windowId) {
                                /** only do this once we start browsing **/
                chrome.tabs.sendMessage(tabid, {doAction: "setRunning", "value": isRunning});
            }
	   }
  });

chrome.tabs.onRemoved.addListener(
        function(tabId, removeInfo) {
                if(tabId==exchangeTabId) {
                        isRunning = false;
                        currentUA = "";
                        syncSharedState();
                }
        }
);
