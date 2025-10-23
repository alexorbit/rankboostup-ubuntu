var isTesting = false;
var testIndex = 3;
var testPayload = [
    {"is_bounce": true, "url": "http://www.w3schools.com/jsref/tryit.asp?filename=tryjsref_alert", "referrer": "https://www.google.com", "timer": 10,
             "country_list": ["US"], "is_mobile": false, "country_code": "US", "pk": 246949},

    {"is_bounce": true, "url": "http://www.w3schools.com/jsref/tryit.asp?filename=tryjsref_confirm",
     "referrer": "https://www.google.com", "timer": 10,
     "country_list": ["US"], "is_mobile": false, "country_code": "US", "pk": 246949},

    {"is_bounce": false, "url": "http://www.w3schools.com/js/tryit.asp?filename=tryjs_prompt",
     "referrer": "https://www.google.com", "timer": 10,
     "country_list": ["US"], "is_mobile": false, "country_code": "US", "pk": 246949},

    {"is_bounce": false, "url": "https://www.w3schools.com/jsref/tryit.asp?filename=tryjsref_onbeforeunload",
     "referrer": "https://www.google.com", "timer": 10,
     "country_list": ["US"], "is_mobile": false, "country_code": "US", "pk": 246949},

    {"is_bounce": false, "url": "http://www.4guysfromrolla.com/demos/OnBeforeUnloadDemo1.htm",
     "referrer": "https://www.google.com", "timer": 10,
     "country_list": ["US"], "is_mobile": false, "country_code": "US", "pk": 246949},


    {
        'url': 'http://fbcommentpictures.com',
        'referrer': 'http://www.google.com/search?q=Michael+Jackson',
        'timer': 10,
        'is_bounce': false,
        'is_mobile': true,
        'country_code': undefined
    },

    {
        'url': 'http://fbcommentpictures.com',
        'referrer': 'http://www.google.com/search?q=Michael+Jackson+Popcorn',
        'timer': 10,
        'is_bounce': false,
        'is_mobile': true,
        'country_code': undefined
    },

    {
        'url': 'http://fbcommentpictures.com',
        'referrer': 'http://www.google.com/search?q=Michael+Jackson+Popcorn',
        'timer': 10,
        'is_bounce': true,
        'is_mobile': false,
        'country_code': undefined
    },
];

function getCookie(key, value, options) {
    // key and at least value given, set cookie...
    if (arguments.length > 1 && (!/Object/.test(Object.prototype.toString.call(value)) || value === null || value === undefined)) {

        if (value === null || value === undefined) {
            options.expires = -1;
        }

        if (typeof options.expires === 'number') {
            var days = options.expires, t = options.expires = new Date();
            t.setDate(t.getDate() + days);
        }

        value = String(value);

        return (document.cookie = [
            encodeURIComponent(key), '=', options.raw ? value : encodeURIComponent(value),
            options.expires ? '; expires=' + options.expires.toUTCString() : '', // use expires attribute, max-age is not supported by IE
            options.path ? '; path=' + options.path : '',
            options.domain ? '; domain=' + options.domain : '',
            options.secure ? '; secure' : ''
        ].join(''));
    }

    // key and possibly options given, get cookie...
    options = value || {};
    var decode = options.raw ? function (s) {
        return s;
    } : decodeURIComponent;

    var pairs = document.cookie.split('; ');
    for (var i = 0, pair; pair = pairs[i] && pairs[i].split('='); i++) {
        if (decode(pair[0]) === key) return decode(pair[1] || ''); // IE saves cookies with empty string as "c; ", e.g. without "=" as opposed to EOMB, thus pair[1] may be undefined
    }
    return null;
};

function csrfSafeMethod(method) {
    // these HTTP methods do not require CSRF protection
    return (/^(GET|HEAD|OPTIONS|TRACE)$/.test(method));
}

var csrftoken = getCookie('csrftoken');
var countdown;
var maxseconds;
var finished = false;
var paused = false;

var tickTock = function () {
    if (!is_paused()) {
        if (countdown > 0) {
            countdown--;
            document.getElementById('countdown').innerHTML = "Currently Viewing " + currentPayload.url + " <br/> (" + countdown + "s left)";
            var percent = countdown / maxseconds * 100;
            document.getElementById('progressbar').style.width = percent + '%';
            active = setTimeout(tickTock, 1000);
        } else {
            clearTimeout(active);
        }

        if (countdown == 0) {
            finished = true;
            var event = new CustomEvent("stopPayload", { bubbles: true, detail: currentPayload });
            document.documentElement.dispatchEvent(event);
            window.location.reload();
        }
    } else {
        active = setTimeout(tickTock, 1000);
    }
};

var url = window.location.href;
var callbacksuccess = false;

setTimeout(function () {
    if (!callbacksuccess) {
        window.location.reload();
    }
}, 20000);

if (isTesting) {
    callbacksuccess = true;

    currentPayload = testPayload[testIndex];
    var paddingSeconds = !currentPayload.is_bounce ? 0 : 10;

    countdown = currentPayload['timer'] + paddingSeconds;
    maxseconds = currentPayload['timer'] + paddingSeconds;

    setTimeout(tickTock, 1000);
    var event = new CustomEvent("startPayload", { bubbles: true, detail: currentPayload });
    document.documentElement.dispatchEvent(event);

} else {
    fetch(url, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'X-CSRFToken': csrftoken
            // Add any other necessary headers
        }
    })
        .then(response => {
            if (!response.ok) {
                throw new Error('Network response was not ok ' + response.statusText);
            }
            return response.json();
        })
        .then(jsonObj => {
            // console.log("post is here");
            // console.log(jsonObj);
            callbacksuccess = true;

            var form = document.getElementById('delete_session');
            if (form) {
                form.setAttribute('action', jsonObj['delete_url']);
                form.style.display = 'block';
            }
            delete jsonObj['delete_url'];

            if (!jsonObj['sites'] || jsonObj['sites'].length <= 0) {
                callbacksuccess = false;
                return;
            }

            currentPayload = jsonObj['sites'][0];
            var paddingSeconds = !currentPayload.is_bounce ? 0 : 10;
            var has_referrer = currentPayload.referrer.length > 0;
            paddingSeconds += has_referrer ? 10 : 0;

            countdown = currentPayload['timer'] + paddingSeconds;
            maxseconds = currentPayload['timer'] + paddingSeconds;

            tickTock();
            // console.log("post came back a success");
            var event = new CustomEvent("startPayload", { bubbles: true, detail: currentPayload });
    document.documentElement.dispatchEvent(event);
        })
        .catch(error => {
            // console.error('There has been a problem with your fetch operation:', error);
            callbacksuccess = false;
        });
}

var is_paused = function () {
    return paused;
};

document.querySelectorAll('.pause-play').forEach(function (element) {
    element.addEventListener('click', function () {
        paused = !paused;
        document.getElementById('pause').style.display = document.getElementById('pause').style.display === 'none' ? 'inline' : 'none';
        document.getElementById('play').style.display = document.getElementById('play').style.display === 'none' ? 'inline' : 'none';
    });
});