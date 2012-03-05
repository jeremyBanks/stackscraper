// ==UserScript==
// @name           StackScraper
// @version        0.0.6
// @namespace      http://extensions.github.com/stackscraper/
// @description    Allows users to export questions as JSON. (Intended for use by 10Krep+ users for now, may work for others.)
// @include        http://*.stackexchange.com/questions/*
// @include        http://stackoverflow.com/questions/*
// @include        http://*.stackoverflow.com/questions/*
// @include        http://superuser.com/questions/*
// @include        http://*.superuser.com/questions/*
// @include        http://serverfault.com/questions/*
// @include        http://*.serverfault.com/questions/*
// @include        http://stackapps.com/questions/*
// @include        http://*.stackapps.com/questions/*
// @include        http://askubuntu.com/questions/*
// @include        http://*.askubuntu.com/questions/*
// @include        http://answers.onstartups.com/questions/*
// @include        http://*.answers.onstartups.com/questions/*
// ==/UserScript==
;

var execute, load, loadAndExecute,
  __slice = Array.prototype.slice;

load = function(url, onLoad, onError) {
  var e;
  e = document.createElement("script");
  e.setAttribute("src", url);
  if (onLoad != null) e.addEventListener("load", onLoad);
  if (onError != null) e.addEventListener("error", onError);
  document.body.appendChild(e);
  return e;
};

execute = function(functionOrCode) {
  var code, e;
  if (typeof functionOrCode === "function") {
    code = "(" + functionOrCode + ")();";
  } else {
    code = functionOrCode;
  }
  e = document.createElement("script");
  e.textContent = code;
  document.body.appendChild(e);
  return e;
};

loadAndExecute = function(url, functionOrCode) {
  return load(url, function() {
    return execute(functionOrCode);
  });
};

execute(function() {
  __slice = Array.prototype.slice;

  var BlobBuilder, StackScraper, URL, makeDocument, makeThrottle, stackScraper;
  BlobBuilder = this.BlobBuilder || this.WebKitBlobBuilder || this.MozBlobBuilder || this.OBlobBuilder;
  URL = this.URL || this.webkitURL || this.mozURL || this.oURL;
  makeThrottle = function(interval) {
    var intervalId, queue, throttle;
    queue = [];
    intervalId = null;
    return throttle = function(f) {
      var throttled;
      return throttled = function() {
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

    function StackScraper() {}

    StackScraper.prototype.getQuestion = function(questionid) {
      var _this = this;
      return this.getShallowQuestion(questionid).pipe(function(question) {
        var post, questionP, tasks, _fn, _i, _len, _ref;
        tasks = [];
        _ref = [question].concat(question.answers);
        _fn = function(post) {
          tasks.push(_this.getPostSource(post.post_id, null).pipe(function(postSource) {
            post.title_source = postSource.title;
            post.body_source = postSource.body;
            return post;
          }));
          tasks.push(_this.getPostComments(post.post_id).pipe(function(postComments) {
            post.comments = postComments;
            return post;
          }));
          return tasks.push(_this.getPostVoteCount(post.post_id).pipe(function(voteCount) {
            post.up_votes = voteCount.up;
            post.down_votes = voteCount.down;
            return post;
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
        var answer, key, page$, question, row, status, tag, type, _i, _j, _k, _l, _len, _len2, _len3, _len4, _ref, _ref2, _ref3, _ref4;
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
          if (type === 'closed') question.closed = true;
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
            question.view_count = +$('.label-key', row).last().attr('title');
          }
        }
        for (_k = 0, _len3 = pages.length; _k < _len3; _k++) {
          page$ = pages[_k];
          _ref4 = page$.find('.answer');
          for (_l = 0, _len4 = _ref4.length; _l < _len4; _l++) {
            answer = _ref4[_l];
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
      if (communityOwnage$ = post$.find('.community-wiki')) {
        post.community_owned_date_s = (_ref = communityOwnage$.attr('title')) != null ? _ref.match(/as of ([^\.]+)./)[1] : void 0;
      } else {
        if ((ownerSig != null) && !communityOwnage$) {
          post.owner = {
            user_id: +$('.user-details a', ownerSig).split(/\//g)[2],
            display_name: $('.user-details a', ownerSig).text(),
            reputation: $('.reputation-score', ownerSig).text().replace(/,/g, ''),
            profile_image: $('.user-gravatar32 img').attr('src')
          };
        }
        if ((editorSig != null) && !communityOwnage$) {
          post.last_editor = {
            user_id: +$('.user-details a', editorSig).split(/\//g)[2],
            display_name: $('.user-details a', editorSig).text(),
            reputation: $('.reputation-score', editorSig).text().replace(/,/g, ''),
            profile_image: $('.user-gravatar32 img').attr('src')
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
          return $.when.apply($, [firstPage$].concat(__slice.call(((function() {
            var _i, _results;
            _results = [];
            for (pageNumber = _i = 2; 2 <= pageCount ? _i <= pageCount : _i >= pageCount; pageNumber = 2 <= pageCount ? ++_i : --_i) {
              _results.push(this.ajax("/questions/" + questionid + "?page=" + pageNumber).pipe(function(source) {
                return $(makeDocument(source));
              }));
            }
            return _results;
          }).call(_this))))).pipe(function() {
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
            body: $.trim($('.comment-copy', this).text()),
            user_id: +$('a.comment-user', this).attr('href').split(/\//g)[2],
            display_name: $('a.comment-user', this).text()
          });
        });
        return postComments;
      });
    };

    StackScraper.prototype.getPostVoteCount = function(postid) {
      var _this = this;
      return this.ajax("/posts/" + postid + "/vote-counts", {
        dataType: 'json'
      }).pipe(function(voteCounts) {
        return {
          up: +voteCounts.up,
          down: +voteCounts.down
        };
      });
    };

    StackScraper.prototype.ajax = (makeThrottle(500))(function(url, options) {
      var existingBeforeSend;
      if (options == null) options = {};
      existingBeforeSend = options.beforeSend;
      if (options.cache == null) options.cache = true;
      options.beforeSend = function(request) {
        request.setRequestHeader('X-StackScraper-Version', '0.0.6');
        return existingBeforeSend != null ? existingBeforeSend.apply(this, arguments) : void 0;
      };
      return $.ajax(url, options);
    });

    return StackScraper;

  })();
  this.stackScraper = stackScraper = new StackScraper;
  return $('#question .post-menu').append('<span class="lsep">|</span>').append($('<a href="#" title="download a JSON copy of this post">download</a>').click(function() {
    var questionId;
    questionId = $('#question').data('questionid');
    stackScraper.getQuestion(questionId).then(function(question) {
      var bb;
      bb = new BlobBuilder;
      bb.append(JSON.stringify(question, 4));
      window.location = URL.createObjectURL(bb.getBlob()) + ("#question-" + questionId + ".json");
      return $(this).text('download');
    });
    $(this).text('downloading...');
    return false;
  }));
});
