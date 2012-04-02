`// ==UserScript==
// @name           StackScraper
// @version        0.4.3
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
`

manifest = 
  name: 'StackScraper'
  version: '0.4.3'
  description: 'Adds download options to Stack Exchange questions.'
  homepage_url: 'http://stackapps.com/questions/3211/stackscraper-export-questions-as-json-or-html'
  permissions: [
    '*://*.stackexchange.com/*'
    '*://*.stackoverflow.com/*'
    '*://*.serverfault.com/*'
    '*://*.superuser.com/*'
    '*://*.askubuntu.com/*'
    '*://*.answers.onstartups.com/*'
    '*://*.stackapps.com/*'
  ]
  content_scripts: [matches: ['*'], js: ['stackscraper.user.js']]
  icons: 128: 'icon128.png'

body = (manifest) ->
  `__slice = Array.prototype.slice` # include this manually because we break CoffeeScript's copy
  BlobBuilder = @BlobBuilder or @WebKitBlobBuilder or @MozBlobBuilder or @OBlobBuilder
  URL = @URL or @webkitURL or @mozURL or @oURL
  
  main = ->
    @stackScraper = stackScraper = new StackScraper
    questionId = $('#question').data('questionid')

    $('#question .post-menu').append('<span class="lsep">|</span>').append $('<a href="#" title="download a JSON copy of this post">json</a>').click ->
      $(@).addClass('ac_loading').text '?%'
      stackScraper.getQuestion(questionId).done (question) =>
        bb = new BlobBuilder
        bb.append JSON.stringify(question)
        $(@).removeClass('ac_loading').text 'json'
        window.location = URL.createObjectURL(bb.getBlob()) + "#/#{window.location.host}-q-#{questionId}.json"
      .progress (ratio) =>
        $(@).text "#{(ratio * 100) | 0}%"
      .fail =>
        $(@).removeClass('ac_loading').text 'error'
      
      false

    $('#question .post-menu').append('<span class="lsep">|</span>').append $('<a href="#" title="download an HTML copy of this post">html</a>').click ->
      $(@).addClass('ac_loading').text '?%'
      stackScraper.getQuestion(questionId).done (question) =>
        bb = new BlobBuilder
        bb.append stackScraper.renderQuestionPage(question)
        $(@).removeClass('ac_loading').text 'html'
        window.location = URL.createObjectURL(bb.getBlob()) + "#/#{window.location.host}-q-#{questionId}.html"
      .progress (ratio) =>
        $(@).text "#{(ratio * 100) | 0}%"
      .fail =>
        $(@).removeClass('ac_loading').text 'error'
		
    
      false
  
  makeThrottle = (interval) ->
    # Creates a throttle with a given interval. the throttle takes a function and wraps it such that it yields
    # deferred results and the wrapped function won't be called more often than once every interval miliseconds.
    queue = []
    intervalId = null
    throttle = (f) ->
      throttled = ->
        thisVal = this
        argVals = arguments
        resultP = new $.Deferred
      
        if intervalId?
          queue.push [f, thisVal, argVals, resultP]
        else
          $.when(f.apply thisVal, argVals).then(resultP.resolve, resultP.reject, resultP.notify)
          intervalId = setInterval ->
            if queue.length
              [f_, thisVal_, argVals_, resultP_] = queue.shift()
              $.when(f_.apply thisVal_, argVals_).then(resultP_.resolve, resultP_.reject, resultP_.notify)
            else
              clearInterval intervalId
              intervalId = null
          , interval
      
        resultP
      throttled.throttle = throttle
      throttled.wrapped = f
      throttled

  makeDocument = (html, title = '') ->
    doc = document.implementation.createHTMLDocument(title)
    if html? then doc.head.parentElement.innerHTML = html
    doc
  
  class StackScraper
    constructor: ->
      @questions = {}
      @throttles = {}
      
    getQuestion: (questionid) ->
      if questionid of @questions
        return @questions[questionid]
      
      @questions[questionid] = @getShallowQuestion(questionid).pipe (question) =>
        question.__generator__ = "#{manifest.name} #{manifest.version}"
        tasks = []
      
        for post in [question].concat(question.answers)
          do (post) =>
            if not post.locked
              tasks.push @getPostSource(post.post_id, null).pipe( (postSource) =>
                post.title_source = postSource.title
                post.body_source = postSource.body
                post
              , ->
                console.warn "unable to retrieve source of post #{post.post_id} (error)"
                (new $.Deferred).resolve()
              )
            else
              console.warn "unable to retrieve source of post #{post.post_id} (locked)"
            
            tasks.push @getPostComments(post.post_id).pipe( (postComments) =>
              post.comments = postComments
              post
            , ->
              console.warn "unable to retrieve comments on post #{post.post_id}"
              (new $.Deferred).resolve()
            )
            
            tasks.push @getPostVoteCount(post.post_id).pipe( (voteCount) =>
              post.up_vote_count = voteCount.up
              post.down_vote_count = voteCount.down
              post
            , ->
              console.warn "unable to retrieve vote counts of post #{post.post_id}"
              (new $.Deferred).resolve()
            )
        
        questionP = new $.Deferred
        
        completedTasks = 0
        for task in tasks
          task.then =>
            completedTasks++
            questionP.notify(completedTasks / tasks.length)
        
        $.when(tasks...).then =>
          questionP.resolve question
        , questionP.reject
      
        questionP.promise()
  
    getShallowQuestion: (questionid) ->
      @getQuestionDocuments(questionid).pipe (pages) ->
        question = scrapePostElement($('.question', pages[0]))
        question.title = $('#question-header h1 a', pages[0]).text()
        question.tags = ($(tag).text() for tag in $('.post-taglist .post-tag', pages[0]))
        question.favorite_count = +($('.favoritecount', pages[0]).text() ? 0)
        question.answers = []
        question.closed = false
        question.locked = false
        question.protected = false
        for status in pages[0].find('.question-status')
          type = $.trim($('b', status).text())
          date_z = $('.relativetime', status).attr('title')
          date = timestampFromRFCDate(date_z)
          
          if type is 'closed'
            question.title = question.title.replace(/\ \[(closed)\]$/, '')
            question.closed = true
            question.closed_date_z = date_z
            question.closed_date = date
          if type is 'migrated'
            question.title = question.title.replace(/\ \[(migrated)\]$/, '')
            question.closed ?= true
            question.closed_date_z ?= date_z
            question.closed_date ?= date
            question.migrated = true
            question.migrated_date_z = date_z
            question.migrated_date = date
          if type is 'deleted'
            question.deleted = true
            question.deleted_date_z = date_z
            question.deleted_date = date
          if type is 'locked'
            question.locked = true
            question.locked_date_z = date_z
            question.locked_date = date
          if type is 'protected'
            question.protected = true
            question.protected_date_z = date_z
            question.protected_date = date
        
        for row in $('#qinfo tr', pages[0])
          key = $('.label-key', row).first().text()
          if key is 'asked'
            question.creation_date_z = $('.label-key', row).last().attr('title')
          if key is 'viewed'
            question.view_count = +$('.label-key', row).last().text()?.split(' ')[0].replace(/,/g, '')
      
        for page$ in pages
          for answer in page$.find('.answer')
            post = scrapePostElement($(answer))
            if post.deleted and ((not question.deleted) or (post.deleted_date != question.deleted_date and post.deleted_date != question.migrated_date))
              console.log "Skipping individually-deleted answer #{post.post_id}."
              continue
            
            question.answers.push post
      
        question
    
    timestampFromRFCDate = (date_z) ->
      date = new Date(date_z)
      Math.floor(date.getTime()/1000 + date.getTimezoneOffset()*60)
    
    scrapePostElement = (post$) ->
      if is_question = post$.is('.question')
        post =
          post_id: +post$.data('questionid')
          post_type: 'question'
      else
        post =
          post_id: +post$.data('answerid')
          post_type: 'answer'
          is_accepted: post$.find('.vote-accepted-on').length isnt 0
      
      post.body = $.trim post$.find('.post-text').html()
      post.score = +post$.find('.vote-count-post').text()
      post.deleted = post$.is('.deleted-question, .deleted-answer')
      
      for statusInfo in post$.find('.deleted-answer-info')
        action = $(statusInfo).text().split(/\ /)[0]
        action_date_z = $('.relativetime', statusInfo).attr('title')
        action_date = timestampFromRFCDate(action_date_z)
        
        if action is 'deleted'
          post.deleted = true
          post.deleted_date_z = action_date_z
          post.deleted_date = action_date
        
        if action is 'locked'
          post.locked = true
          post.locked_date_z = action_date_z
          post.locked_date = action_date
      
      sigs = post$.find('.post-signature')
      if sigs.length is 2
        [editorSig, ownerSig] = sigs
      else
        editorSig = null
        [ownerSig] = sigs
      
      if post$.find('.anonymous-gravatar').length
        post.owner = display_name: post$.find('.user-details').text()
      else if (communityOwnage$ = post$.find('.community-wiki')).length
        post.community_owned_date_s = communityOwnage$.attr('title')?.match(/as of ([^\.]+)./)[1]
        
        nameDisplay = post$.find('[id^=history-]').contents()
        
        if (boldName = $('b', nameDisplay)).length and $(nameDisplay[4]).text().match(/100%/)
          post.owner = display_name: boldName.text()
        else if nameDisplay.length is 3
          if $(nameDisplay[0]).text().indexOf('%') == -1
            # can only be sure of owner if post doesn't have other contributors
            # this could still be wrong if somebody entirely rewrote a post.
            post.owner = display_name: $(nameDisplay[2]).text()
        else
          post.owner = display_name: $(nameDisplay[0]).text()
      else
        if (not communityOwnage$.length) and ownerSig? and $('.user-details a', ownerSig).length
          post.owner =
            user_id: +$('.user-details a', ownerSig).attr('href').split(/\//g)[2]
            display_name: $('.user-details a', ownerSig).text()
            reputation: $('.reputation-score', ownerSig).text().replace(/,/g, '')
            profile_image: $('.user-gravatar32 img', ownerSig).attr('src')
        
        if (not communityOwnage$.length) and editorSig? and $('.user-details a', editorSig).length
          post.last_editor =
            user_id: +$('.user-details a', editorSig).attr('href').split(/\//g)[2]
            display_name: $('.user-details a', editorSig).text()
            reputation: $('.reputation-score', editorSig).text().replace(/,/g, '')
            profile_image: $('.user-gravatar32 img', editorSig).attr('src')
      
      if editorSig? and (editTime$ = $('.relativetime', editorSig)).length
        post.last_edit_date_s = editTime$.text()
        post.last_edit_date_z = editTime$.attr('title')
        post.last_edit_date = timestampFromRFCDate(post.last_edit_date_z)
      
      if ownerSig? and (creationTime$ = $('.relativetime', ownerSig)).length
        post.creation_date_s = creationTime$.text()
        post.creation_date_z = creationTime$.attr('title')
        post.creation_date = timestampFromRFCDate(post.creation_date_z)
      
      post
    
    getPostRevisionsInfo: (postid) ->
      ###
      reads ~2 pages of /revisions/ to accurately capture
      .revisions
      .firstRevisionGuid
      .author
      .latestEditor
      .lastRevisionGuid
      ###
    
    getQuestionDocuments: (questionid) ->
      @ajax("/questions/#{questionid}?page=1&noredirect=1&answertab=votes").pipe (firstSource) =>
        firstPage$ = $(makeDocument(firstSource))
      
        # if there are multiple pages, request 'em all.
        if lastPageNav$ = $('.page-numbers:not(.next)').last()
          pageCount = +lastPageNav$.text()
        
          $.when(firstPage$, (if pageCount > 1 then (for pageNumber in [2..pageCount]
            @ajax("/questions/#{questionid}?page=#{pageNumber}&noredirect=1&answertab=votes").pipe (source) ->
              $(makeDocument(source))
          ) else [])...).pipe (pages...) -> pages
        else
          [firstPage$]
  
    getPostSource: (postid, revisionguid = null) ->
      @ajax("/posts/#{postid}/edit#{if revisionguid then "/#{revisionguid}" else ''}").pipe (editPageSource) =>
        sourcePage$ = $(makeDocument(editPageSource))
        postSource =
          title: $('[name=title]', sourcePage$).val()
          body: $('[name=post-text]', sourcePage$).val()
    
    getPostComments: (postid) ->
      @ajax("/posts/#{postid}/comments").pipe (commentsSource) =>
        commentPage$ = $(makeDocument("<body><table>#{commentsSource}</table></body>"))
        postComments = []
        $('.comment', commentPage$).each ->
          postComments.push
            comment_id: $(@).attr('id').split('-')[2]
            score: +($.trim($('.comment-score', @).text()) ? 0)
            body: $.trim($('.comment-copy', @).html())
            user_id: +$('a.comment-user', @).attr('href')?.split(/\//g)?[2]
            display_name: $($('a.comment-user', @)[0]?.childNodes?[0]).text()
        postComments
    
    getPostVoteCount: (postid) ->
      @throttledAjax('get-vote-count', 3000, "/posts/#{postid}/vote-counts", dataType: 'json').pipe (voteCounts) =>
        (up: +voteCounts.up, down: +voteCounts.down)
  
    # be nice: wrap $.ajax to add our throttle and header.
    ajax: (url, options = {}) ->
      @throttledAjax 'default', 1500, url, options
    
    throttledAjax: (throttleName, throttleDelay, url, options = {}) ->
      throttle = @throttles[throttleName] ?=  makeThrottle(throttleDelay)((f) -> f())
      throttle ->
        existingBeforeSend = options.beforeSend;
        options.cache ?= true
        options.beforeSend = (request) ->
          request.setRequestHeader 'X-StackScraper-Version', manifest.version
          return existingBeforeSend?.apply this, arguments
        $.ajax(url, options)
 
    encodeHTMLText: (text) ->
      String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/"/g, '&#39;')
  
    renderPost: (post, parent) ->
      """
      <div class="#{@encodeHTMLText(post.post_type)} post" id="#{@encodeHTMLText(post.post_id)}">
        #{if post.title?
          "<h1>#{@encodeHTMLText(post.title)}</h1>"
        else ''}
        <div class="metrics">
          #{if post.score?
            "<span class=\"value\">#{@encodeHTMLText(post.score)}</span>" +
            "<span class=\"unit\">votes</span>"
          else ''}
          #{if post.view_count?
            "<br>" +
            "<span class=\"value\">#{@encodeHTMLText(post.view_count)}</span>" +
            "<span class=\"unit\">views</span>"
          else ''}
          #{if post.comments?.length
            "<br><a href=\"javascript:void(location.hash = '#{@encodeHTMLText(post.post_id)}-comments')\" style=\"text-decoration: none;\"><span class=\"value\">#{@encodeHTMLText(post.comments.length)}</span><span class=\"unit\" style=\"font-size: 75%;\">comments</span></a>"
          else ''}
        </div>
        <div class="col">
          <div class="body">
            #{post.body}
          </div>
        
          #{@renderAttributionBox(post.creation_date_z, post.owner, if post.post_type is 'question' then 'asked' else 'answered')}
        
          #{@renderAttributionBox(post.last_edit_date_z, post.last_editor, 'edited')}
        
          #{if post.tags?
            "<ul class=\"tags\">" +
              ("<li><a href=\"/tags/#{@encodeHTMLText tag}\">#{@encodeHTMLText tag}</a></li>" for tag in post.tags
              ).join('\n') +
            "</ul>"
          else ''}
        
          <div class="clear"></div>
      
          #{@renderPostComments post}
      
          #{if post.post_type is 'question'
              "<div class=\"source-header\">" +
                "This was <a href=\"/q/#{post.post_id}\">originally posted</a> on Stack Exchange#{if post.deleted then ', but it has been deleted' else ''}." +
              "</div>"
          else ''}
        </div>
      </div>  
    
      <div class="clear"></div>
      """
    
    monthAbbrs = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
    
    renderDate: (date_z) ->
      # takes an RFC3339 UTC datetime and formats it like Stack Exchange does.
      date = new Date(date_z)
      """<span title="#{@encodeHTMLText date_z}">
        #{monthAbbrs[date.getUTCMonth()]} #{date.getUTCDay()} '#{String(date.getUTCFullYear()).substr(2)}
        at #{date.getUTCHours()}:#{date.getUTCMinutes()}Z
      </span>
      """
    
    renderAttributionBox: (date_z, shallow_user, verb) ->
        # TODO TODO timestamp
      if not (date_z? or shallow_user?.display_name?)
        return ''
      
      """
        <div class="attribution">
          #{verb}
          
          #{if shallow_user? and shallow_user.profile_image? and shallow_user.user_id? # TODO: degrade more gracefully.
            "by <a href=\"/u/#{@encodeHTMLText(shallow_user.user_id)}\">#{@encodeHTMLText(shallow_user.display_name)}<img src=\"#{@encodeHTMLText(shallow_user.profile_image)}\" alt=\"\" /></a>"
          else if shallow_user? and shallow_user.display_name?
            "by #{@encodeHTMLText shallow_user.display_name}"
          else ''}
          #{if date_z? then '<br>' + @renderDate(date_z) else ''}
        </div>
      """
  
    renderPostComments: (post) ->
      if post.comments?.length then """
        <div class="comments" id="#{@encodeHTMLText post.post_id}-comments">
          #{(for comment in post.comments
              "<div class=\"comment\">" +
                "<span class=\"score\">[#{comment.score}]</span> " +
                "<span class=\"author\"><a href=\"/u/#{comment.user_id}\">#{@encodeHTMLText comment.display_name}</a>:</span> " +
                "<span class=\"body\">#{comment.body}</span>" +
              "</div>"
          ).join('\n')}
        </div>
      """ else ''
  
    renderQuestionPage: (question, base = ('http://' + window?.location?.host)) ->
      """<!doctype html><html>
  <head>
    <meta charset="utf-8" />
    <meta name="generator" content="#{manifest.name} #{manifest.version}" /> 
    <title>
      #{@encodeHTMLText(question.title)}
    </title>
    #{if base then "<base href=\"#{@encodeHTMLText(base)}\" />" else ''}
    <style>
      html {
        background: #D8D8D8;
      }
    
      body {
        font: 14px sans-serif;
      }
      
      a, a:visited {
        color: #226;
      }
      
      .wrapper {
        width: 735px;
        margin: 1em auto;
        background: white;
        padding: 1em;
      }
      
      h1,h2, h3, h4 {
        padding-bottom: .2em;
        border-bottom: 1px solid black;
        margin-top: 0;
      }
      
      h1 {
        font-size: 1.6em;
      }
      h2 {
        font-size: 1.4em;
      }
      h3 {
        font-size: 1.2em;
      }
      
      h2.answers {
        border-bottom: 1px solid black;
      }
      
      .implied-by-style {
        display: none;
      }
      
      .source-header {
        display: block;
        background-color: #EEE;
        padding: 1em 1em;
        font-size: 1.3em;
        font-weight: bold;
        color: black;
        text-align: left;
        margin: 0.5em 0;
        text-align: center;
      }
    
      
        .source-header a, .source-header a:visited {
          color: black;
        }
      
      .post .metrics {
        float: left;
        text-align: center;
        width: 58px;
        margin: 0px 0 0;
        padding: 5px 0;
        border-right: 1px solid #DDD;
      }
      
      .post + .post {
          border-top: 1px solid #888;
          padding-top: 1em;
          margin-top: 1em;
      }
      
      .post + .clear + .post {
          border-top: 1px solid #888;
          padding-top: 1em;
          margin-top: 1em;
      }
      
        .post .metrics .value {
          display: block;
          font-weight: bold;
          font-size: 1.3em;
          margin: 3px 0 0;
        }
        
        .post .metrics .unit {
          display: block;
          opacity: 0.5;
        }
        
        .post .metrics .annotation {
          display: block;
          font-weight: bold;
          font-size: 0.8em;
          opacity: 0.75;
          margin: 5px 0 0;
        }
      
      .post .tags {
        list-style-type: none;
        padding: 0;
        line-height: 1.75em;
      }
      
        .post .tags li {
          display: inline;
          padding: .3em .5em;
          margin: .2em;
          border: 1px solid #888;
          background: #F8F8F4;
          font-size: .75em;
        }
          .post .tags li a {
            color: inherit;
            text-decoration: inherit;
          }
        
        .post .body {
          line-height: 1.3em;
        }
      
        .post .body p, .post .body pre {
          margin-top: 0;
        }
      
      .post .attribution {  
        font-size: 11px;
        height: 4em;
        float: right;
        width: 160px;
        border: 1px solid #E8E8E4;
        margin-left: 1em;
        padding: 4px;
        padding-bottom: 8px;
        background: #F8F8F4;
        position: relative;
        line-height: 1.6em;
        margin-bottom: 8px;
      }
      
        .post .attribution img {
          border: 1px solid #E8E8E4;
          border-right: 0;
          border-bottom: 0;
          float: right;
          position: absolute;
          bottom: 0px;
          right: 0px;
		  width: 32px;
		  height: 32px;
        }
      
      .post .col {
        float: right;
        width: 665px;
      }

      .post .col img {
        max-width: 665px;
      }
    
      blockquote {
        margin: .5em .25em;
        margin-bottom: .75em;
        padding: 1em;
        padding-bottom: 0.5em;
        background: #EEE;
      }
      
      pre {
        background: #EEE;
        padding: 8px 8px;
        margin-bottom; 10px;
        font: 100% Menlo, Monaco, Consolas, "Lucida Console", monospace;
        line-height: 1.3em;
        overflow-x: scroll;
      }
      
      .footer {
        font-size: 0.8em;
        text-align: center;
      }
      
      .footer a {
        text-decoration: none;
        color: #222;
      }
      
      .footer a:hover {
        text-decoration: underline;
      }
    
      .comments {
        display: none;
      }
    
      .comments:target {
        display: block;
      }
    
      .comments .comment {
        padding: .125em;
        border: .125em solid #EEE;
        background: #F8F8F8;
      }
    
      .comments .comment .score, .comments .comment .author {
        font-weight: bold;
      }
      
      .clear { clear: both; }
    </style>
  </head>
  <body>
    <div class="wrapper">
      #{@renderPost(question)}
    
      <h2 class="answers">
        #{@encodeHTMLText(question.answers.length)} Answers
      </h2>
    
      #{(@renderPost(answer, question) for answer in question.answers).join('\n')}
    </div>
    <div class="footer">
      <a href="/">exported using <a href="#{@encodeHTMLText(manifest.homepage_url)}">#{@encodeHTMLText(manifest.name)} #{@encodeHTMLText(manifest.version)}</a></a>
    </div>
  <script>
  var QUESTION =
  // BEGIN QUESTION JSON
  #{JSON.stringify question}
  // END QUESTION JSON
  ;
  </script>
    </body>
  </html>"""
  
  do main

if exports?
  exports.manifest = manifest
  exports.body = body
else if document? and location?
  if location.pathname.match /\/questions\/\d+/
    e = document.createElement 'script'
    e.textContent = "(#{body})(#{JSON.stringify manifest});"
    document.body.appendChild e
