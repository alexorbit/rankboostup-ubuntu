console.log('Disabling JS alerts...');
window.alert = null;
window.confirm = null;
window.prompt = null;

var js_alerts = setInterval("window.alert = null;", 300);
var js_confirms = setInterval("window.confirm = null;", 300);
var js_prompts = setInterval("window.prompt = null;", 300);

// Only run for the first 10 seconds of loading.
// setTimeout(function () {
//     clear_js_alerts();
// }, 10000);
// function clear_js_alerts() {
//     clearInterval(js_alerts);
// 	clearInterval(js_confirms);
// 	clearInterval(js_prompts);
// }
// console.log('Disabling JS exit pops...');

window.onbeforeunload = null;
window.onunload = null;

var js_onbeforeunload = setInterval("window.onbeforeunload = null;", 300);
var js_onunload = setInterval("window.onunload = null;", 300);

// console.log('Executing on all iframes...');

var removeAllUnloadsIframes = function () {
    var list = document.getElementsByTagName("iframe");
    for (var i = 0; i < list.length; i++) {
        var v = list[i];
        v.contentWindow.onbeforeunload = null;
        v.contentWindow.onunload = null;
    }
};

removeAllUnloadsIframes();
var js_onunloadiframe = setInterval(removeAllUnloadsIframes, 300);

(function disablePushMessaging() {
    var createNotAllowedError = function () {
        try {
            return new DOMException('Push messaging has been disabled by the Rankboostup extension.', 'NotAllowedError');
        } catch (domExceptionError) {
            var fallback = new Error('Push messaging has been disabled by the Rankboostup extension.');
            fallback.name = 'NotAllowedError';
            return fallback;
        }
    };

    var denyPromise = function () {
        return Promise.reject(createNotAllowedError());
    };

    try {
        if (typeof Notification !== 'undefined' && typeof Notification.requestPermission === 'function') {
            var deniedPromise = Promise.resolve('denied');

            Notification.requestPermission = function (callback) {
                if (typeof callback === 'function') {
                    deniedPromise.then(callback).catch(function () {});
                }
                return deniedPromise;
            };

            try {
                var permissionDescriptor = Object.getOwnPropertyDescriptor(Notification, 'permission');
                if (permissionDescriptor && permissionDescriptor.configurable) {
                    Object.defineProperty(Notification, 'permission', {
                        configurable: true,
                        enumerable: true,
                        get: function () {
                            return 'denied';
                        }
                    });
                }
            } catch (permissionError) {
                // Ignore if the property is not configurable.
            }
        }

        var patchPushManager = function (pushManager) {
            if (!pushManager) {
                return;
            }

            if (typeof pushManager.subscribe === 'function') {
                try {
                    Object.defineProperty(pushManager, 'subscribe', {
                        configurable: true,
                        writable: true,
                        value: function () {
                            return denyPromise();
                        }
                    });
                } catch (subscribeError) {
                    try {
                        pushManager.subscribe = function () {
                            return denyPromise();
                        };
                    } catch (innerSubscribeError) {
                        console.warn('Rankboostup: unable to override PushManager.subscribe', innerSubscribeError);
                    }
                }
            }

            if (typeof pushManager.getSubscription === 'function') {
                try {
                    Object.defineProperty(pushManager, 'getSubscription', {
                        configurable: true,
                        writable: true,
                        value: function () {
                            return Promise.resolve(null);
                        }
                    });
                } catch (getSubscriptionError) {
                    try {
                        pushManager.getSubscription = function () {
                            return Promise.resolve(null);
                        };
                    } catch (innerGetSubscriptionError) {
                        console.warn('Rankboostup: unable to override PushManager.getSubscription', innerGetSubscriptionError);
                    }
                }
            }
        };

        if (typeof PushManager !== 'undefined' && PushManager.prototype) {
            patchPushManager(PushManager.prototype);
        }

        if (typeof navigator !== 'undefined' && navigator.serviceWorker) {
            var originalRegister = navigator.serviceWorker.register;
            if (typeof originalRegister === 'function') {
                navigator.serviceWorker.register = function () {
                    return originalRegister.apply(this, arguments).then(function (registration) {
                        try {
                            patchPushManager(registration && registration.pushManager);
                        } catch (innerError) {
                            console.warn('Rankboostup: failed to patch push manager after registration', innerError);
                        }
                        return registration;
                    });
                };
            }

            if (navigator.serviceWorker.ready && typeof navigator.serviceWorker.ready.then === 'function') {
                navigator.serviceWorker.ready.then(function (registration) {
                    patchPushManager(registration && registration.pushManager);
                }).catch(function () {});
            }

            if (typeof navigator.serviceWorker.getRegistrations === 'function') {
                var originalGetRegistrations = navigator.serviceWorker.getRegistrations.bind(navigator.serviceWorker);
                navigator.serviceWorker.getRegistrations = function () {
                    return originalGetRegistrations().then(function (registrations) {
                        registrations.forEach(function (registration) {
                            patchPushManager(registration && registration.pushManager);
                        });
                        return registrations;
                    });
                };
            }

            if (typeof navigator.serviceWorker.getRegistration === 'function') {
                var originalGetRegistration = navigator.serviceWorker.getRegistration.bind(navigator.serviceWorker);
                navigator.serviceWorker.getRegistration = function () {
                    return originalGetRegistration.apply(this, arguments).then(function (registration) {
                        patchPushManager(registration && registration.pushManager);
                        return registration;
                    });
                };
            }
        }
    } catch (error) {
        console.warn('Rankboostup: failed to disable push messaging cleanly', error);
    }
})();
