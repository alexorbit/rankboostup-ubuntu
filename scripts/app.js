/**
 * Created by yussufs on 3/3/17.
 */
var currentPayload = {};
window.currentPayload = currentPayload;
var isRunning = false;
var roothost = "app.rankboostup.com";
// var roothost = "localhost:8000";
// var rootprotocol = "http://";
var rootprotocol = "https://";
const currentVersion = 'v2.13'; // Current version of the plugin

function injectScript(file, node) {
    var th = document.getElementsByTagName(node)[0];
    var s = document.createElement('script');
    s.setAttribute('type', 'text/javascript');
    s.setAttribute('src', file);
    th.appendChild(s);
}

if (location.host!=roothost) {
    // when we are not on rankboostup.com, we need to check if the session is running or not and then inject
    // the script into the window
    chrome.runtime.onMessage.addListener(
      function(request, sender, sendResponse) {
        if(request.doAction == "setRunning") {
            isRunning = request.value;

            if (isRunning) {
                injectScript( chrome.runtime.getURL('/scripts/uninterrupt.js'), 'body');
            }
	    }
    });

    chrome.runtime.sendMessage({doAction: "getRunning"});

    document.addEventListener("DOMContentLoaded", function() {
      chrome.runtime.sendMessage({doAction: "getRunning"});
    });
}

var exchange_list = "dashboard/traffic-exchange/";

if (location.href.indexOf(exchange_list) >=0) {
    var start_session_button = document.querySelector('.start-exchange-boostup');
    if (start_session_button) {
        start_session_button.addEventListener('click', function(e) {
            // console.log("start session clicked");
            e.preventDefault();
            chrome.runtime.sendMessage({doAction: "startSession"});
            var aTag = document.createElement('a');aTag.setAttribute('href',"https://"+roothost+"/dashboard/exchange-session/browser/");aTag.innerHTML = 'link';document.documentElement.appendChild(aTag);aTag.click();
        });
    }

    (function autoStartIfRequested() {
        try {
            var params = new URLSearchParams(window.location.search);
            var autostartRaw = params.get('autostart');
            var shouldAutostart = false;

            if (autostartRaw) {
                var normalized = autostartRaw.toLowerCase();
                shouldAutostart = ['1', 'true', 'yes', 'y'].indexOf(normalized) !== -1;
            }

            if (!shouldAutostart) {
                return;
            }

            var triggerClick = function () {
                var button = document.querySelector('.start-exchange-boostup');
                if (!button) {
                    setTimeout(triggerClick, 500);
                    return;
                }

                if (button.dataset.autostartTriggered === 'true') {
                    return;
                }

                button.dataset.autostartTriggered = 'true';
                button.click();
            };

            if (document.readyState === 'complete' || document.readyState === 'interactive') {
                setTimeout(triggerClick, 500);
            } else {
                document.addEventListener('DOMContentLoaded', function () {
                    setTimeout(triggerClick, 500);
                }, { once: true });
            }
        } catch (error) {
            console.warn('Failed to auto-start Rankboostup exchange session', error);
        }
    })();
}

var exchange_url = "dashboard/exchange-session/browser/";

if (location.href.indexOf(exchange_url) >=0) {
    injectScript( chrome.runtime.getURL('/scripts/autosurf.js'), 'body');

    window.addEventListener("startPayload", function(event) {
        chrome.runtime.sendMessage({doAction: "startPayload", payload: event.detail});
    }, false);

    window.addEventListener("stopPayload", function(event) {
      chrome.runtime.sendMessage({doAction: "stopPayload", payload: event.detail});
    }, false);

    chrome.runtime.onMessage.addListener(
        function (request, sender, sendResponse) {
            if (request.doAction == "reportSite") {
                var event = new CustomEvent("reportSite", {bubbles: true, detail: request.payload});
                document.documentElement.dispatchEvent(event);
            }
        }
    );
};

// Header injection for Manifest V3 compatibility
if (location.host.indexOf(roothost) !== -1) {
    // Add RankboostupPlugin header for requests to rankboostup.com
    const originalFetch = window.fetch;
    window.fetch = function(...args) {
        let [url, options = {}] = args;
        if (!options.headers) {
            options.headers = {};
        }
        options.headers['RankboostupPlugin'] = currentVersion;
        return originalFetch.apply(this, [url, options]);
    };

    // Override XMLHttpRequest for legacy requests
    const originalXHROpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url, ...args) {
        this.addEventListener('readystatechange', function() {
            if (this.readyState === 1) { // OPENED
                this.setRequestHeader('RankboostupPlugin', currentVersion);
            }
        });
        return originalXHROpen.apply(this, [method, url, ...args]);
    };
}

// Handle User-Agent modification for traffic exchange sessions
chrome.storage.local.get(['currentUA', 'windowId', 'isRunning'], function(result) {
    if (result.isRunning && result.currentUA && location.host.indexOf(roothost) === -1) {
        // Override navigator.userAgent for mobile sessions
        Object.defineProperty(navigator, 'userAgent', {
            get: function() { return result.currentUA; },
            configurable: true
        });
    }
});