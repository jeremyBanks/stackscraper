// ==UserScript==
// @name           Stack Dump
// @version        0.0.1
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

var siteName = document.title.split(/\ - /)[1];
document.title = "Stack Dump - Tools - " + siteName;

var content = $("#content").empty();

$("<div class='subheader'><h1><a href='/tools/dump'>Stack Dump</a></h1></div>").appendTo(content);

 
});