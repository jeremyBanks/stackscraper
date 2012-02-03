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
  return $.ajax("/posts/" + id + "/ajax-load", { cache: true }).pipe(function(e) {
    var loadedPost = $("<div>").append(e);
    var type, url, tags, title, html;
    
    if (url = loadedPost.find(".question-hyperlink").attr("href")) {
      type = "question";
      tags = loadedPost.find(".post-taglist").find(".post-tag").map(function(e) {
        return $(e).text();
      });
    } else if (url = loadedPost.find(".answer-hyperlink").attr("href")) {
      type = "answer";
    } else {
      throw new Error('Unknown post type for post of id ' + id);
    }
    
    title = loadedPost.find("h3").first().text();
    html = loadedPost.find(".post-text").html();
    // really we should match the API format, neh?

    return {
      id: id,
      title: title,
      type: type,
      html: html,
      tags: tags,
      askTime: askTime,
      url: url,
      score: score,
      favoriteCount: favoriteCount,
      
      owner: {
        id: ownerId,
        name: ownerName,
        url: ownerUrl
      },
      
      editor: {
        id: editorId,
        name: editorName,
        url: editorUrl
      },
      
      states: {
        "locked": {
         
        }
      }
      locked: locked,
      lockers: lockers,
      
    };
  });
};

var siteName = document.title.split(/\ - /)[1];
document.title = "Stack Dump - Tools - " + siteName;

var content = $("#content").empty();

$("<div class='subheader'><h1><a href='/tools/dump'>Stack Dump</a> <span style='opacity: 0.5; font-size: 0.5em;'>(<a href='https://gist.github.com/raw/54559d41cc8041ebc534/dump.user.js'>update/install</a>)</span></h1></div>").appendTo(content);


_getPost(1).then(function(o) {
  console.log(o);
});
 
});