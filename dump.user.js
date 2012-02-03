// ==UserScript==
// @name           Stack Dump
// @version        0.0.2
// @namespace      http://stackoverflow.com/q/
// @description    Scrapes Stack Exchange posts en masse, including deleted ones if visible to you.
// @include        http://*.stackexchange.com/tools/dump
// @include        http://stackoverflow.com/tools/dump
// @include        http://*.stackoverflow.com/tools/dump
// @include        http://superuser.com/tools/dump
// @include        http://*.superuser.com/tools/dump
// @include        http://serverfault.com/tools/dump
// @include        http://*.serverfault.com/tools/dump
// @include        http://askubuntu.com/tools/dump
// @include        http://*.askubuntu.com/tools/dump
// ==/UserScript==

var load,execute,loadAndExecute;load=function(a,b,c){var d;d=document.createElement("script"),d.setAttribute("src",a),b!=null&&d.addEventListener("load",b),c!=null&&d.addEventListener("error",c),document.body.appendChild(d);return d},execute=function(a){var b,c;typeof a=="function"?b="("+a+")();":b=a,c=document.createElement("script"),c.textContent=b,document.body.appendChild(c);return c},loadAndExecute=function(a,b){return load(a,function(){return execute(b)})};
execute(function(){

var BlobBuilder = window.BlobBuilder || window.WebKitBlobBuilder || window.MozBlobBuilder || window.OBlobBuilder;
var URL = window.URL || webkitURL || mozURL || oURL;

var _getPost = function(id) {
  $.ajax("/posts/" + id + "/ajax-load", { cache: true }).then(function(e) {
    $("<div>").append(e).appendTo(content);
  });
};

var siteName = document.title.split(/\ - /)[1];
document.title = "Stack Dump - Tools - " + siteName;

_getPost(1);

var content = $("#content").empty();

$("<div class='subheader'><h1><a href='/tools/dump'>Stack Dump</a> (<a href='https://gist.github.com/raw/54559d41cc8041ebc534/dump.user.js'>update/install></a></h1></div>").appendTo(content);

 
});