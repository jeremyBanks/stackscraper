// ==UserScript==
// @name           Stack Dump
// @version        0.0.4
// @namespace      http://gist.github.com/54559d41cc8041ebc534
// @description    Scrapes Stack Exchange posts en masse, including deleted ones if visible to you.
// @include        http://*.stackexchange.com/tools/dump
// @include        http://stackoverflow.com/tools/dump
// @include        http://*.stackoverflow.com/tools/dump
// @include        http://superuser.com/tools/dump
// @include        http://*.superuser.com/tools/dump
// @include        http://serverfault.com/tools/dump
// @include        http://*.serverfault.com/tools/dump
// @include        http://stackapps.com/tools/dump
// @include        http://*.stackapps.com/tools/dump
// @include        http://askubuntu.com/tools/dump
// @include        http://*.askubuntu.com/tools/dump
// ==/UserScript==
var load,execute,loadAndExecute;load=function(a,b,c){var d;d=document.
createElement("script"),d.setAttribute("src",a),b!=null&&d.
addEventListener("load",b),c!=null&&d.addEventListener("error",c),
document.body.appendChild(d);return d},execute=function(a){var b,c;
typeof a=="function"?b="("+a+")();":b=a,c=document.createElement(
"script"),c.textContent=b,document.body.appendChild(c);return c},
loadAndExecute=function(a,b){return load(a,function(){
return execute(b)})}; execute(function(){ // in normal DOM context

var BlobBuilder = window.BlobBuilder || window.WebKitBlobBuilder || window.MozBlobBuilder || window.OBlobBuilder;
var URL = window.URL || webkitURL || mozURL || oURL;

var API_URL = "https://api.stackexchange.com/2.0/";
var API_KEY = "CtBYNg0K2ALoGmQ2MalrMw((";
var DOMAIN = location.host;

var blobify = function(o) {
	var s = JSON.stringify(o, null, "  ");
	var bb = new BlobBuilder;
	bb.append(s);
	return bb.getBlob("application/json");
};

var main = function() {
	var siteName = document.title.split(/\ - /)[1];
	document.title = "Stack Dump - Tools - " + siteName;
	var content = $("#content").empty();
	$("<div class='subheader'><h1><a href='/tools/dump'>Stack Dump</a> <span style='opacity: 0.5; font-size: 0.5em;'>(<a href='https://gist.github.com/raw/54559d41cc8041ebc534/dump.user.js'>update/install</a>)</span></h1></div>").appendTo(content);
	
	var initialId = 12900, postCount = 10;
	
	// created $.Deferred values to hold each requested posted
	var requested = [];
	for (var i = 0; i < postCount; i++) {
		requested[i] = new $.Deferred;
	}
	
	// request a new post every 2000 ms
	var j = 0, j_i = setInterval(function() {
		if (j >= postCount) { return clearInterval(j_i); }
		
		getPostByAjaxLoad(j + initialId).then(requested[j].resolve, requested[j].reject);
		
		j++;
	}, 1500);
	
	// when they're done, display them
	$.when.apply($, requested).done(function() {
		var url =  URL.createObjectURL(blobify(Array.prototype.slice.call(arguments)));
		$("<a>JSON Result</a>").attr("href", url).appendTo($("<h4>").appendTo(content));
		$("<iframe></iframe>").attr("src", url).css({
			width: "100%",
			height: "25em",
			border: "1px solid #444"
		}).appendTo(content);
	});

};

var getPostByAjaxLoad = function(id) {
  return $.ajax("/posts/" + id + "/ajax-load", { cache: true }).pipe(function(e) {
    var type, body, ownerSig, editorSig, editor, owner, isDeleted;
	
    var loadedPost = $("<div>").append(e);
    
    if (url = loadedPost.find(".question-hyperlink").attr("href")) {
      type = "question";
      tags = loadedPost.find(".post-taglist .post-tag").map(function() {
        return $(this).text();
      }).toArray();
	  favoriteCount = +(loadedPost.find(".favoritecount").text() || 0);
	  body = $.trim(loadedPost.find(".post-text").html())
    } else if (url = loadedPost.find(".answer-hyperlink").attr("href")) {
      type = "answer";
	  body = $.trim(loadedPost.find(".answer .post-text").html())
    } else {
      throw new Error('Unknown post type for post of id ' + id);
    }
    
	var sigs = loadedPost.find(".post-signature");
	if (sigs.length == 2) {
		editorSig = $(sigs[0]);
		ownerSig = $(sigs[1]);
	} else {
		ownerSig = $(sigs[0]);
	}
	
	if (loadedPost.find(".community-wiki").length > 0) {
		owner = {
			user_id: -1,
			display_name: (ownerSig.find("a").text() || "") .split(/\n/)[1] || "Stack Exchange Community"
		}
	} else {
		owner = {
			user_id: +((ownerSig.find(".user-details a").attr("href") || "").split(/\//g)[2] || -1),
			display_name: ownerSig.find(".user-details a").text() || "Stack Exchange Community"
		};
	}
	
	if (sigs.length == 2) {
		editor = {
			display_name: editorSig.find(".user-details a").text()  || owner.display_name,
			user_id: +((editorSig.find(".user-details a").attr("href") || "").split(/\//g)[2] || -1) || owner.user_id // heh
		};
	}
	
    return {
      post_id: id,
      post_type: type,
      body: body,
	  comment_count: +(loadedPost.find(".comments-link b").text() || 0),
	  owner: owner,
	  
	  editor: editor,
	  
	  is_deleted: loadedPost.find(".deleted-answer").length > 0,
	  
      title: loadedPost.find("h3").first().text(),
      tags: tags,
	  favorite_count: favoriteCount,
    };
  });
};


main();

});
