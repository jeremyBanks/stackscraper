`// ==UserScript==
// @name           StackScraper
// @version        0.2.4
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
  version: '0.2.4'
  description: 'Adds download options to Stack Exchange questions.'
  homepage_url: 'https://github.com/extensions/stackscraper/'
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

    $('#question .post-menu').append('<span class="lsep">|</span>').append $('<a href="#" title="download a JSON copy of this post">JSON</a>').click ->
      $(@).addClass('ac_loading')
      stackScraper.getQuestion(questionId).then (question) =>
        bb = new BlobBuilder
        bb.append JSON.stringify(question)
        $(@).removeClass('ac_loading')
        window.location = URL.createObjectURL(bb.getBlob()) + "#question-#{questionId}.json"
    
      false

    $('#question .post-menu').append('<span class="lsep">|</span>').append $('<a href="#" title="download an HTML copy of this post">HTML</a>').click ->
      $(this).addClass('ac_loading')
      stackScraper.getQuestion(questionId).then (question) ->
        bb = new BlobBuilder
        bb.append renderQuestion(question)
        $(@).removeClass('ac_loading')
        window.location = URL.createObjectURL(bb.getBlob()) + "#question-#{questionId}.html"
    
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

  makeDocument = (html, title = '') ->
    doc = document.implementation.createHTMLDocument(title)
    if html? then doc.head.parentElement.innerHTML = html
    doc
  
  class StackScraper
    constructor: ->
      @questions = {}
      
    getQuestion: (questionid) ->
      if questionid of @questions
        return @questions[questionid]
      
      @questions[questionid] = @getShallowQuestion(questionid).pipe (question) =>
        tasks = []
      
        for post in [question].concat(question.answers)
          do (post) =>
            tasks.push @getPostSource(post.post_id, null).pipe( (postSource) =>
              post.title_source = postSource.title
              post.body_source = postSource.body
              post
            , ->
              console.warn "unable to retrieve source of post #{post.post_id}"
              (new $.Deferred).resolve()
            )
            
            tasks.push @getPostComments(post.post_id).pipe( (postComments) =>
              post.comments = postComments
              post
            , ->
              console.warn "unable to retrieve comments on post #{post.post_id}"
              (new $.Deferred).resolve()
            )
            
            tasks.push @getPostVoteCount(post.post_id).pipe( (voteCount) =>
              post.up_votes = voteCount.up
              post.down_votes = voteCount.down
              post
            , ->
              console.warn "unable to retrieve vote counts of post #{post.post_id}"
              (new $.Deferred).resolve()
            )
      
        questionP = new $.Deferred
      
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
          type = $('b', status).text()
          if type is 'closed' then question.closed = true
          if type is 'locked' then question.locked = true
          if type is 'protected' then question.protected = true
      
        for row in $('#qinfo tr', pages[0])
          key = $('.label-key', row).first().text()
          if key is 'asked'
            question.creation_date_z = $('.label-key', row).last().attr('title')
          if key is 'viewed'
            question.view_count = +$('.label-key', row).last().text()?.split(' ')[0]
      
        for page$ in pages
          for answer in page$.find('.answer')
            question.answers.push scrapePostElement $(answer)
      
        question
  
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
      
      sigs = post$.find('.post-signature')
      if sigs.length is 2
        [editorSig, ownerSig] = sigs
      else
        editorSig = null
        [ownerSig] = sigs
      
      if (communityOwnage$ = post$.find('.community-wiki')).length
        post.community_owned_date_s = communityOwnage$.attr('title')?.match(/as of ([^\.]+)./)[1]
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
      
      if ownerSig? and (creationTime$ = $('.relativetime', ownerSig)).length
        post.creation_date_s = creationTime$.text()
        post.creation_date_z = creationTime$.attr('title')
    
      post
  
    getQuestionDocuments: (questionid) ->
      @ajax("/questions/#{questionid}").pipe (firstSource) =>
        firstPage$ = $(makeDocument(firstSource))
      
        # if there are multiple pages, request 'em all.
        if lastPageNav$ = $('.page-numbers:not(.next)').last()
          pageCount = +lastPageNav$.text()
        
          $.when(firstPage$, (if pageCount > 1 then (for pageNumber in [2..pageCount]
            @ajax("/questions/#{questionid}?page=#{pageNumber}").pipe (source) ->
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
        $('.comment').each ->
          postComments.push
            comment_id: $(@).attr('id').split('-')[2]
            score: +($.trim($('.comment-score', @).text()) ? 0)
            body: $.trim($('.comment-copy', @).html())
            user_id: +$('a.comment-user', @).attr('href').split(/\//g)[2]
            display_name: $($('a.comment-user', @)[0].childNodes[0]).text()
        postComments
    
    getPostVoteCount: (postid) ->
      @ajax("/posts/#{postid}/vote-counts", dataType: 'json').pipe (voteCounts) =>
        (up: +voteCounts.up, down: +voteCounts.down)
  
    # be nice: wrap $.ajax to add our throttle and header.
    ajax: (makeThrottle 1000) (url, options = {}) ->
      existingBeforeSend = options.beforeSend;
      options.cache ?= true
      options.beforeSend = (request) ->
        request.setRequestHeader 'X-StackScraper-Version', manifest.version
        return existingBeforeSend?.apply this, arguments
      $.ajax(url, options)
  
  encodeHTMLText = (text) ->
    String(text).replace(/&/, '&amp;').replace(/</, '&lt;').replace(/>/, '&gt;').replace(/>/, '&gt;').replace(/"/, '&quot;').replace(/"/, '&#39;')
  
  renderQuestion = (question, base = ('http://' + window?.location?.host)) ->
    """<!doctype html><html>
<head>
  <meta charset="utf-8" />
  <title>
    #{encodeHTMLText question.title}
  </title>
  #{if base then "<base href=\"#{base}\" />" else ''}
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
      
    .post .score {
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
      
      .post .score .value {
        display: block;
        font-weight: bold;
        font-size: 1.3em;
        margin: 3px 0 0;
      }
        
      .post .score .unit {
        display: block;
        opacity: 0.5;
      }
        
      .post .score .annotation {
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
      }
      
    .post .col {
      float: right;
      width: 665px;
    }

    .post .col img {
      max-width: 665px;
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
  </style>
</head>
<body>
  <div class="wrapper">
    <div class="question post" id="#{encodeHTMLText question.post_id}">
      <h1>#{encodeHTMLText question.title}</h1>
      
      <div class="score">
        <span class="value">#{question.score}</span>
        <span class="unit">votes</span>
        <br>
        <span class="value">#{question.view_count}</span>
        <span class="unit">views</span>
      </div>
      <div class="col">
        <div class="body">
          #{question.body}
        </div>
        """ + (if question.owner or question.creation_date_s then """
          <div class="attribution">
            asked #{if question.owner
              "by <a href=\"/u/#{encodeHTMLText question.owner.user_id}\">#{encodeHTMLText question.owner.display_name}<img src=\"#{encodeHTMLText question.owner.profile_image}\" alt=\"\" /></a><br>"
            else '<br>'}
            #{question.creation_date_s}
        </div>
        """ else '') + 
        (if question.last_edit_date_s or question.last_editor then """
          <div class="attribution">
            edited #{if question.last_editor
              "by <a href=\"/u/#{encodeHTMLText question.last_editor.user_id}\">#{encodeHTMLText question.last_editor.display_name}<img src=\"#{encodeHTMLText question.last_editor.profile_image}\" alt=\"\" /></a><br>"
            else '<br>'}
            #{encodeHTMLText question.last_edit_date_s}
        </div>
        """ else '') + """
        <ul class="tags">
          #{(for tag in question.tags
            "<li><a href=\"/tags/#{encodeHTMLText tag}\">#{encodeHTMLText tag}</a></li>"
          ).join('\n')}
        </ul>
      
      <div style="clear: both;"></div>
      
        <div class="source-header">
          This was <a href="/q/#{question.post_id}">originally posted</a> on Stack Exchange#{if question.deleted then ', but it has been deleted' else ''}.
        </div>
      </div>
    </div>  
    
      <div style="clear: both;"></div>
	  
    <h2 class="answers">
      #{encodeHTMLText question.answers.length} Answers
    </h2>
    
    """ + (for answer in question.answers
      """
      <div class="answer post" id="#{encodeHTMLText answer.post_id}">
        <div class="score">
          <span class="value">#{answer.score}</span>
          <span class="unit">votes</span>
        </div>
        <div class="col">
          <div class="body">
            #{answer.body}
          </div>
        """ +
        (if answer.owner or answer.creation_date_s then """
          <div class="attribution">
            answered #{if answer.owner
              "by <a href=\"/u/#{encodeHTMLText answer.owner.user_id}\">#{encodeHTMLText answer.owner.display_name}<img src=\"#{encodeHTMLText answer.owner.profile_image}\" alt=\"\" /></a><br>"
            else '<br>'}
             #{answer.creation_date_s}
        </div>
        """ else '') + 
        (if answer.last_edit_date_s or answer.last_editor then """
          <div class="attribution">
            edited #{if answer.last_editor
              "by <a href=\"/u/#{encodeHTMLText answer.last_editor.user_id}\">#{encodeHTMLText answer.last_editor.display_name}<img src=\"#{encodeHTMLText answer.last_editor.profile_image}\" alt=\"\" /></a><br>"
            else '<br>'}
             #{encodeHTMLText answer.last_edit_date_s}
        </div>
        """ else '') +
        """</div>
      <div style="clear: both;"></div>
      </div>
      """
    ).join('\n') + """</div>
    <div class="footer">
      <a href="/">exported using <a href="#{encodeHTMLText manifest.homepage_url}">StackScraper</a></a>
    </div>
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
