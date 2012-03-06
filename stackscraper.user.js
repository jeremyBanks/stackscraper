// ==UserScript==
// @name           StackScraper
// @version        0.2.7
// @namespace      http://extensions.github.com/stackscraper/
// @description    Adds download options to Stack Exchange questions.
// @include        *://*.stackexchange.com/questions/*
// @include        *://stackoverflow.com/questions/*
// @include        *://*.stackoverflow.com/questions/*
// @include        *://superuser.com/questions/*
// @include        *://*.superuser.com/questions/*
// @include        *://serverfault.com/questions/*
// @include        *://*.serverfault.com/questions/*
// @include        *://stackapps.com/questions/*
// @include        *://*.stackapps.com/questions/*
// @include        *://askubuntu.com/questions/*
// @include        *://*.askubuntu.com/questions/*
// @include        *://answers.onstartups.com/questions/*
// @include        *://*.answers.onstartups.com/questions/*
// ==/UserScript==
;

var body, e, manifest,
  __slice = Array.prototype.slice;

manifest = {
  name: 'StackScraper',
  version: '0.2.7',
  description: 'Adds download options to Stack Exchange questions.',
  homepage_url: 'http://stackapps.com/questions/3211/stackscraper-export-questions-as-json-or-html',
  permissions: ['*://*.stackexchange.com/*', '*://*.stackoverflow.com/*', '*://*.serverfault.com/*', '*://*.superuser.com/*', '*://*.askubuntu.com/*', '*://*.answers.onstartups.com/*', '*://*.stackapps.com/*'],
  content_scripts: [
    {
      matches: ['*'],
      js: ['stackscraper.user.js']
    }
  ],
  icons: {
    128: 'icon128.png'
  }
};

body = function(manifest) {
  __slice = Array.prototype.slice;

  var BlobBuilder, StackScraper, URL, encodeHTMLText, main, makeDocument, makeThrottle, renderQuestion;
  BlobBuilder = this.BlobBuilder || this.WebKitBlobBuilder || this.MozBlobBuilder || this.OBlobBuilder;
  URL = this.URL || this.webkitURL || this.mozURL || this.oURL;
  main = function() {
    var questionId, stackScraper;
    this.stackScraper = stackScraper = new StackScraper;
    questionId = $('#question').data('questionid');
    $('#question .post-menu').append('<span class="lsep">|</span>').append($('<a href="#" title="download a JSON copy of this post">json</a>').click(function() {
      var _this = this;
      $(this).addClass('ac_loading');
      stackScraper.getQuestion(questionId).then(function(question) {
        var bb;
        bb = new BlobBuilder;
        bb.append(JSON.stringify(question));
        $(_this).removeClass('ac_loading');
        return window.location = URL.createObjectURL(bb.getBlob()) + ("#question-" + questionId + ".json");
      });
      return false;
    }));
    return $('#question .post-menu').append('<span class="lsep">|</span>').append($('<a href="#" title="download an HTML copy of this post">html</a>').click(function() {
      $(this).addClass('ac_loading');
      stackScraper.getQuestion(questionId).then(function(question) {
        var bb;
        bb = new BlobBuilder;
        bb.append(renderQuestion(question));
        $(this).removeClass('ac_loading');
        return window.location = URL.createObjectURL(bb.getBlob()) + ("#question-" + questionId + ".html");
      });
      return false;
    }));
  };
  makeThrottle = function(interval) {
    var intervalId, queue, throttle;
    queue = [];
    intervalId = null;
    return throttle = function(f) {
      var throttled;
      throttled = function() {
        var argVals, resultP, thisVal;
        thisVal = this;
        argVals = arguments;
        resultP = new $.Deferred;
        if (intervalId != null) {
          queue.push([f, thisVal, argVals, resultP]);
        } else {
          $.when(f.apply(thisVal, argVals)).then(resultP.resolve, resultP.reject, resultP.notify);
          intervalId = setInterval(function() {
            var argVals_, f_, resultP_, thisVal_, _ref;
            if (queue.length) {
              _ref = queue.shift(), f_ = _ref[0], thisVal_ = _ref[1], argVals_ = _ref[2], resultP_ = _ref[3];
              return $.when(f_.apply(thisVal_, argVals_)).then(resultP_.resolve, resultP_.reject, resultP_.notify);
            } else {
              clearInterval(intervalId);
              return intervalId = null;
            }
          }, interval);
        }
        return resultP;
      };
      throttled.throttle = throttle;
      throttled.wrapped = f;
      return throttled;
    };
  };
  makeDocument = function(html, title) {
    var doc;
    if (title == null) title = '';
    doc = document.implementation.createHTMLDocument(title);
    if (html != null) doc.head.parentElement.innerHTML = html;
    return doc;
  };
  StackScraper = (function() {
    var scrapePostElement;

    StackScraper.name = 'StackScraper';

    function StackScraper() {
      this.questions = {};
      this.throttles = {};
    }

    StackScraper.prototype.getQuestion = function(questionid) {
      var _this = this;
      if (questionid in this.questions) return this.questions[questionid];
      return this.questions[questionid] = this.getShallowQuestion(questionid).pipe(function(question) {
        var post, questionP, tasks, _fn, _i, _len, _ref;
        tasks = [];
        _ref = [question].concat(question.answers);
        _fn = function(post) {
          tasks.push(_this.getPostSource(post.post_id, null).pipe(function(postSource) {
            post.title_source = postSource.title;
            post.body_source = postSource.body;
            return post;
          }, function() {
            console.warn("unable to retrieve source of post " + post.post_id);
            return (new $.Deferred).resolve();
          }));
          tasks.push(_this.getPostComments(post.post_id).pipe(function(postComments) {
            post.comments = postComments;
            return post;
          }, function() {
            console.warn("unable to retrieve comments on post " + post.post_id);
            return (new $.Deferred).resolve();
          }));
          return tasks.push(_this.getPostVoteCount(post.post_id).pipe(function(voteCount) {
            post.up_votes = voteCount.up;
            post.down_votes = voteCount.down;
            return post;
          }, function() {
            console.warn("unable to retrieve vote counts of post " + post.post_id);
            return (new $.Deferred).resolve();
          }));
        };
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          post = _ref[_i];
          _fn(post);
        }
        questionP = new $.Deferred;
        $.when.apply($, tasks).then(function() {
          return questionP.resolve(question);
        }, questionP.reject);
        return questionP.promise();
      });
    };

    StackScraper.prototype.getShallowQuestion = function(questionid) {
      return this.getQuestionDocuments(questionid).pipe(function(pages) {
        var answer, key, page$, question, row, status, tag, type, _i, _j, _k, _l, _len, _len2, _len3, _len4, _ref, _ref2, _ref3, _ref4, _ref5;
        question = scrapePostElement($('.question', pages[0]));
        question.title = $('#question-header h1 a', pages[0]).text();
        question.tags = (function() {
          var _i, _len, _ref, _results;
          _ref = $('.post-taglist .post-tag', pages[0]);
          _results = [];
          for (_i = 0, _len = _ref.length; _i < _len; _i++) {
            tag = _ref[_i];
            _results.push($(tag).text());
          }
          return _results;
        })();
        question.favorite_count = +((_ref = $('.favoritecount', pages[0]).text()) != null ? _ref : 0);
        question.answers = [];
        question.closed = false;
        question.locked = false;
        question.protected = false;
        _ref2 = pages[0].find('.question-status');
        for (_i = 0, _len = _ref2.length; _i < _len; _i++) {
          status = _ref2[_i];
          type = $('b', status).text();
          if (type === 'closed') {
            question.closed = true;
            question.title = question.title.replace(/\ \[(closed|migrated)\]$/, '');
          }
          if (type === 'locked') question.locked = true;
          if (type === 'protected') question.protected = true;
        }
        _ref3 = $('#qinfo tr', pages[0]);
        for (_j = 0, _len2 = _ref3.length; _j < _len2; _j++) {
          row = _ref3[_j];
          key = $('.label-key', row).first().text();
          if (key === 'asked') {
            question.creation_date_z = $('.label-key', row).last().attr('title');
          }
          if (key === 'viewed') {
            question.view_count = +((_ref4 = $('.label-key', row).last().text()) != null ? _ref4.split(' ')[0].replace(/,/g, '') : void 0);
          }
        }
        for (_k = 0, _len3 = pages.length; _k < _len3; _k++) {
          page$ = pages[_k];
          _ref5 = page$.find('.answer');
          for (_l = 0, _len4 = _ref5.length; _l < _len4; _l++) {
            answer = _ref5[_l];
            question.answers.push(scrapePostElement($(answer)));
          }
        }
        return question;
      });
    };

    scrapePostElement = function(post$) {
      var communityOwnage$, creationTime$, editTime$, editorSig, is_question, ownerSig, post, sigs, _ref;
      if (is_question = post$.is('.question')) {
        post = {
          post_id: +post$.data('questionid'),
          post_type: 'question'
        };
      } else {
        post = {
          post_id: +post$.data('answerid'),
          post_type: 'answer',
          is_accepted: post$.find('.vote-accepted-on').length !== 0
        };
      }
      post.body = $.trim(post$.find('.post-text').html());
      post.score = +post$.find('.vote-count-post').text();
      post.deleted = post$.is('.deleted-question, .deleted-answer');
      sigs = post$.find('.post-signature');
      if (sigs.length === 2) {
        editorSig = sigs[0], ownerSig = sigs[1];
      } else {
        editorSig = null;
        ownerSig = sigs[0];
      }
      if ((communityOwnage$ = post$.find('.community-wiki')).length) {
        post.community_owned_date_s = (_ref = communityOwnage$.attr('title')) != null ? _ref.match(/as of ([^\.]+)./)[1] : void 0;
      } else {
        if ((!communityOwnage$.length) && (ownerSig != null) && $('.user-details a', ownerSig).length) {
          post.owner = {
            user_id: +$('.user-details a', ownerSig).attr('href').split(/\//g)[2],
            display_name: $('.user-details a', ownerSig).text(),
            reputation: $('.reputation-score', ownerSig).text().replace(/,/g, ''),
            profile_image: $('.user-gravatar32 img', ownerSig).attr('src')
          };
        }
        if ((!communityOwnage$.length) && (editorSig != null) && $('.user-details a', editorSig).length) {
          post.last_editor = {
            user_id: +$('.user-details a', editorSig).attr('href').split(/\//g)[2],
            display_name: $('.user-details a', editorSig).text(),
            reputation: $('.reputation-score', editorSig).text().replace(/,/g, ''),
            profile_image: $('.user-gravatar32 img', editorSig).attr('src')
          };
        }
      }
      if ((editorSig != null) && (editTime$ = $('.relativetime', editorSig)).length) {
        post.last_edit_date_s = editTime$.text();
        post.last_edit_date_z = editTime$.attr('title');
      }
      if ((ownerSig != null) && (creationTime$ = $('.relativetime', ownerSig)).length) {
        post.creation_date_s = creationTime$.text();
        post.creation_date_z = creationTime$.attr('title');
      }
      return post;
    };

    StackScraper.prototype.getQuestionDocuments = function(questionid) {
      var _this = this;
      return this.ajax("/questions/" + questionid).pipe(function(firstSource) {
        var firstPage$, lastPageNav$, pageCount, pageNumber;
        firstPage$ = $(makeDocument(firstSource));
        if (lastPageNav$ = $('.page-numbers:not(.next)').last()) {
          pageCount = +lastPageNav$.text();
          return $.when.apply($, [firstPage$].concat(__slice.call((pageCount > 1 ? (function() {
            var _i, _results;
            _results = [];
            for (pageNumber = _i = 2; 2 <= pageCount ? _i <= pageCount : _i >= pageCount; pageNumber = 2 <= pageCount ? ++_i : --_i) {
              _results.push(this.ajax("/questions/" + questionid + "?page=" + pageNumber + "&noredirect=1&answertab=votes").pipe(function(source) {
                return $(makeDocument(source));
              }));
            }
            return _results;
          }).call(_this) : [])))).pipe(function() {
            var pages;
            pages = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
            return pages;
          });
        } else {
          return [firstPage$];
        }
      });
    };

    StackScraper.prototype.getPostSource = function(postid, revisionguid) {
      var _this = this;
      if (revisionguid == null) revisionguid = null;
      return this.ajax("/posts/" + postid + "/edit" + (revisionguid ? "/" + revisionguid : '')).pipe(function(editPageSource) {
        var postSource, sourcePage$;
        sourcePage$ = $(makeDocument(editPageSource));
        return postSource = {
          title: $('[name=title]', sourcePage$).val(),
          body: $('[name=post-text]', sourcePage$).val()
        };
      });
    };

    StackScraper.prototype.getPostComments = function(postid) {
      var _this = this;
      return this.ajax("/posts/" + postid + "/comments").pipe(function(commentsSource) {
        var commentPage$, postComments;
        commentPage$ = $(makeDocument("<body><table>" + commentsSource + "</table></body>"));
        postComments = [];
        $('.comment').each(function() {
          var _ref;
          return postComments.push({
            comment_id: $(this).attr('id').split('-')[2],
            score: +((_ref = $.trim($('.comment-score', this).text())) != null ? _ref : 0),
            body: $.trim($('.comment-copy', this).html()),
            user_id: +$('a.comment-user', this).attr('href').split(/\//g)[2],
            display_name: $($('a.comment-user', this)[0].childNodes[0]).text()
          });
        });
        return postComments;
      });
    };

    StackScraper.prototype.getPostVoteCount = function(postid) {
      var _this = this;
      return this.throttledAjax('get-vote-count', 1400, "/posts/" + postid + "/vote-counts", {
        dataType: 'json'
      }).pipe(function(voteCounts) {
        return {
          up: +voteCounts.up,
          down: +voteCounts.down
        };
      });
    };

    StackScraper.prototype.ajax = function(url, options) {
      if (options == null) options = {};
      return this.throttledAjax('default', 400, url, options);
    };

    StackScraper.prototype.throttledAjax = function(throttleName, throttleDelay, url, options) {
      var throttle, _base, _ref;
      if (options == null) options = {};
      throttle = (_ref = (_base = this.throttles)[throttleName]) != null ? _ref : _base[throttleName] = makeThrottle(throttleDelay)(function(f) {
        return f();
      });
      return throttle(function() {
        var existingBeforeSend;
        existingBeforeSend = options.beforeSend;
        if (options.cache == null) options.cache = true;
        options.beforeSend = function(request) {
          request.setRequestHeader('X-StackScraper-Version', manifest.version);
          return existingBeforeSend != null ? existingBeforeSend.apply(this, arguments) : void 0;
        };
        return $.ajax(url, options);
      });
    };

    return StackScraper;

  })();
  encodeHTMLText = function(text) {
    return String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/"/g, '&#39;');
  };
  renderQuestion = function(question, base) {
    var answer, comment, tag, _ref;
    if (base == null) {
      base = 'http://' + (typeof window !== "undefined" && window !== null ? (_ref = window.location) != null ? _ref.host : void 0 : void 0);
    }
    return ("<!doctype html><html>\n<head>\n  <meta charset=\"utf-8\" />\n  <title>\n    " + (encodeHTMLText(question.title)) + "\n  </title>\n  " + (base ? "<base href=\"" + base + "\" />" : '') + "\n  <style>\n    html {\n      background: #D8D8D8;\n    }\n    \n    body {\n      font: 14px sans-serif;\n    }\n      \n    a, a:visited {\n      color: #226;\n    }\n      \n    .wrapper {\n      width: 735px;\n      margin: 1em auto;\n      background: white;\n      padding: 1em;\n    }\n      \n    h1,h2, h3, h4 {\n      padding-bottom: .2em;\n      border-bottom: 1px solid black;\n      margin-top: 0;\n    }\n      \n    h1 {\n      font-size: 1.6em;\n    }\n    h2 {\n      font-size: 1.4em;\n    }\n    h3 {\n      font-size: 1.2em;\n    }\n      \n    h2.answers {\n      border-bottom: 1px solid black;\n    }\n      \n    .implied-by-style {\n      display: none;\n    }\n      \n    .source-header {\n      display: block;\n      background-color: #EEE;\n      padding: 1em 1em;\n      font-size: 1.3em;\n      font-weight: bold;\n      color: black;\n      text-align: left;\n      margin: 0.5em 0;\n      text-align: center;\n    }\n    \n    .comments {\n      padding: .25em .5em;\n      border: .25em solid #EEE;\n      background: #F8F8F8;\n      display: none;\n    }\n      \n      .source-header a, .source-header a:visited {\n        color: black;\n      }\n      \n    .post .score {\n      float: left;\n      text-align: center;\n      width: 58px;\n      margin: 0px 0 0;\n      padding: 5px 0;\n      border-right: 1px solid #DDD;\n    }\n      \n    .post + .post {\n        border-top: 1px solid #888;\n        padding-top: 1em;\n        margin-top: 1em;\n    }\n      \n      .post .score .value {\n        display: block;\n        font-weight: bold;\n        font-size: 1.3em;\n        margin: 3px 0 0;\n      }\n        \n      .post .score .unit {\n        display: block;\n        opacity: 0.5;\n      }\n        \n      .post .score .annotation {\n        display: block;\n        font-weight: bold;\n        font-size: 0.8em;\n        opacity: 0.75;\n        margin: 5px 0 0;\n      }\n      \n    .post .tags {\n      list-style-type: none;\n      padding: 0;\n      line-height: 1.75em;\n    }\n      \n      .post .tags li {\n        display: inline;\n        padding: .3em .5em;\n        margin: .2em;\n        border: 1px solid #888;\n        background: #F8F8F4;\n        font-size: .75em;\n      }\n        .post .tags li a {\n          color: inherit;\n          text-decoration: inherit;\n        }\n        \n      .post .body {\n        line-height: 1.3em;\n      }\n      \n      .post .body p, .post .body pre {\n        margin-top: 0;\n      }\n      \n    .post .attribution {  \n      font-size: 11px;\n      height: 4em;\n      float: right;\n      width: 160px;\n      border: 1px solid #E8E8E4;\n      margin-left: 1em;\n      padding: 4px;\n      padding-bottom: 8px;\n      background: #F8F8F4;\n      position: relative;\n      line-height: 1.6em;\n      margin-bottom: 8px;\n    }\n      \n      .post .attribution img {\n        border: 1px solid #E8E8E4;\n        border-right: 0;\n        border-bottom: 0;\n        float: right;\n        position: absolute;\n        bottom: 0px;\n        right: 0px;\n      }\n      \n    .post .col {\n      float: right;\n      width: 665px;\n    }\n\n    .post .col img {\n      max-width: 665px;\n    }\n    \n    blockquote {\n      margin: .5em .25em;\n      margin-bottom: .75em;\n      padding: 1em;\n      padding-bottom: 0.5em;\n      background: #EEE;\n    }\n      \n    pre {\n      background: #EEE;\n      padding: 8px 8px;\n      margin-bottom; 10px;\n      font: 100% Menlo, Monaco, Consolas, \"Lucida Console\", monospace;\n      line-height: 1.3em;\n      overflow-x: scroll;\n    }\n      \n    .footer {\n      font-size: 0.8em;\n      text-align: center;\n    }\n      \n    .footer a {\n      text-decoration: none;\n      color: #222;\n    }\n      \n    .footer a:hover {\n      text-decoration: underline;\n    }\n    \n    .commments {\n      display: none;\n    }\n    \n    .comments:target {\n      display: block;\n    }\n  </style>\n</head>\n<body>\n  <div class=\"wrapper\">\n    <div class=\"question post\" id=\"" + (encodeHTMLText(question.post_id)) + "\">\n      <h1>" + (encodeHTMLText(question.title)) + "</h1>\n      \n      <div class=\"score\">\n        <span class=\"value\">" + question.score + "</span>\n        <span class=\"unit\">votes</span>\n        <br>\n        <span class=\"value\">" + question.view_count + "</span>\n        <span class=\"unit\">views</span>\n          " + (question.comments.length ? "<br><a href=\"javascript:void(location.hash = '" + question.post_id + "-comments')\" style=\"text-decoration: none;\"><span class=\"value\">" + question.comments.length + "</span><span class=\"unit\" style=\"font-size: 50%;\">comments</span></a>" : '') + "\n      </div>\n      <div class=\"col\">\n        <div class=\"body\">\n          " + question.body + "\n        </div>") + (question.owner || question.creation_date_s ? "  <div class=\"attribution\">\n    asked " + (question.owner ? "by <a href=\"/u/" + (encodeHTMLText(question.owner.user_id)) + "\">" + (encodeHTMLText(question.owner.display_name)) + "<img src=\"" + (encodeHTMLText(question.owner.profile_image)) + "\" alt=\"\" /></a><br>" : '<br>') + "\n    " + question.creation_date_s + "\n</div>" : '') + (question.last_edit_date_s || question.last_editor ? "  <div class=\"attribution\">\n    edited " + (question.last_editor ? "by <a href=\"/u/" + (encodeHTMLText(question.last_editor.user_id)) + "\">" + (encodeHTMLText(question.last_editor.display_name)) + "<img src=\"" + (encodeHTMLText(question.last_editor.profile_image)) + "\" alt=\"\" /></a><br>" : '<br>') + "\n    " + (encodeHTMLText(question.last_edit_date_s)) + "\n</div>" : '') + ("  <ul class=\"tags\">\n    " + (((function() {
      var _i, _len, _ref2, _results;
      _ref2 = question.tags;
      _results = [];
      for (_i = 0, _len = _ref2.length; _i < _len; _i++) {
        tag = _ref2[_i];
        _results.push("<li><a href=\"/tags/" + (encodeHTMLText(tag)) + "\">" + (encodeHTMLText(tag)) + "</a></li>");
      }
      return _results;
    })()).join('\n')) + "\n  </ul>\n\n<div style=\"clear: both;\"></div>\n\n  ") + (question.comments.length ? "<div class=\"comments\" id=\"" + question.post_id + "-comments\">\n  " + (((function() {
      var _i, _len, _ref2, _results;
      _ref2 = question.comments;
      _results = [];
      for (_i = 0, _len = _ref2.length; _i < _len; _i++) {
        comment = _ref2[_i];
        _results.push("<p><strong>[" + comment.score + "] <a href=\"/u/" + comment.user_id + "\">" + (encodeHTMLText(comment.display_name)) + "</a>:</strong> " + comment.body + "</p>");
      }
      return _results;
    })()).join('\n')) + "\n</div>" : '') + ("        <div class=\"source-header\">\n          This was <a href=\"/q/" + question.post_id + "\">originally posted</a> on Stack Exchange" + (question.deleted ? ', but it has been deleted' : '') + ".\n        </div>\n        \n      </div>\n    </div>  \n    \n      <div style=\"clear: both;\"></div>\n\n    <h2 class=\"answers\">\n      " + (encodeHTMLText(question.answers.length)) + " Answers\n    </h2>\n    ") + ((function() {
      var _i, _len, _ref2, _results;
      _ref2 = question.answers;
      _results = [];
      for (_i = 0, _len = _ref2.length; _i < _len; _i++) {
        answer = _ref2[_i];
        _results.push(("<div class=\"answer post\" id=\"" + (encodeHTMLText(answer.post_id)) + "\">\n  <div class=\"score\">\n    <span class=\"value\">" + answer.score + "</span>\n    <span class=\"unit\">votes</span>\n    " + (answer.comments.length ? "<a href=\"javascript:void(location.hash = '" + answer.post_id + "-comments')\" + '#' + answer.post_id}-comments\" style=\"text-decoration: none;\"><span class=\"value\">" + answer.comments.length + "</span><span class=\"unit\" style=\"font-size: 50%;\">comments</span></a>" : '') + "\n  </div>\n  <div class=\"col\">\n    <div class=\"body\">\n      " + answer.body + "\n    </div>") + (answer.owner || answer.creation_date_s ? "  <div class=\"attribution\">\n    answered " + (answer.owner ? "by <a href=\"/u/" + (encodeHTMLText(answer.owner.user_id)) + "\">" + (encodeHTMLText(answer.owner.display_name)) + "<img src=\"" + (encodeHTMLText(answer.owner.profile_image)) + "\" alt=\"\" /></a><br>" : '<br>') + "\n     " + answer.creation_date_s + "\n</div>" : '') + (answer.last_edit_date_s || answer.last_editor ? "  <div class=\"attribution\">\n    edited " + (answer.last_editor ? "by <a href=\"/u/" + (encodeHTMLText(answer.last_editor.user_id)) + "\">" + (encodeHTMLText(answer.last_editor.display_name)) + "<img src=\"" + (encodeHTMLText(answer.last_editor.profile_image)) + "\" alt=\"\" /></a><br>" : '<br>') + "\n     " + (encodeHTMLText(answer.last_edit_date_s)) + "\n</div>" : '') + "</div>\n<div style=\"clear: both;\"></div>\n" + (answer.comments.length ? "<div class=\"comments\" id=\"" + (String(window.location) + '#' + answer.post_id) + "-comments\">\n  " + (((function() {
          var _j, _len2, _ref3, _results2;
          _ref3 = answer.comments;
          _results2 = [];
          for (_j = 0, _len2 = _ref3.length; _j < _len2; _j++) {
            comment = _ref3[_j];
            _results2.push("<br><p><strong>[" + comment.score + "] <a href=\"/u/" + comment.user_id + "\">" + (encodeHTMLText(comment.display_name)) + "</a>:</strong> " + comment.body + "</p>");
          }
          return _results2;
        })()).join('\n')) + "\n</div>" : '') + "</div>");
      }
      return _results;
    })()).join('\n') + ("</div>\n  <div class=\"footer\">\n    <a href=\"/\">exported using <a href=\"" + (encodeHTMLText(manifest.homepage_url)) + "\">StackScraper</a></a>\n  </div>\n</body>\n</html>");
  };
  return main();
};

if (typeof exports !== "undefined" && exports !== null) {
  exports.manifest = manifest;
  exports.body = body;
} else if ((typeof document !== "undefined" && document !== null) && (typeof location !== "undefined" && location !== null)) {
  if (location.pathname.match(/\/questions\/\d+/)) {
    e = document.createElement('script');
    e.textContent = "(" + body + ")(" + (JSON.stringify(manifest)) + ");";
    document.body.appendChild(e);
  }
}
