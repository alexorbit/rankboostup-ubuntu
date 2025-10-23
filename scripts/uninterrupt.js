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