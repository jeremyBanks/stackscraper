`// ==UserScript==
// @name           StackScraper
// @version        0.0.2
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
`
# jQuerys are suffixied with $, Promises (including Deferreds) suffixed with P

BlobBuilder = @BlobBuilder or @WebKitBlobBuilder or @MozBlobBuilder or @OBlobBuilder
URL = @URL or @webkitURL or @mozURL or @oURL

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
  getQuestion: (questionid) ->
    @getShallowQuestion(questionid).pipe (question) =>
      tasks = []
      
      for post in [question].concat(question.answers)
        do (post) =>
          tasks.push @getPostSource(post.post_id, null).pipe( (postSource) =>
            post.title_source = postSource.title
            post.body_source = postSource.body
            post
          )
          
          tasks.push @getPostComments(post.post_id).pipe( (postComments) =>
            post.comments = postComments
            post
          )
          
          tasks.push @getPostVoteCount(post.post_id).pipe( (voteCount) =>
            post.up_votes = voteCount.up
            post.down_votes = voteCount.down
            post
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
          question.view_count = +$('.label-key', row).last().attr('title')
      
      for page$ in pages
        for answer in page$.find('.answer')
          question.answers.push scrapePostElement $(answer)
      
      question
  
  scrapePostElement = (post$) ->
    if is_question = post$.is('.question')
      post =
        post_id: +post$.data('questionid')
        post_type: 'question'
        is_accepted: post$.find('.vote-accepted-on').length isnt 0
    else
      post =
        post_id: +post$.data('answerid')
        post_type: 'answer'
      
    post.body = $.trim post$.find('.post-text').html()
    post.score = +post$.find('.vote-count-post').text()
    post.deleted = post$.is('.deleted-question, .deleted-answer')
      
    sigs = post$.find('.post-signature')
    if sigs.length is 2
      [editorSig, ownerSig] = sigs
    else
      editorSig = null
      [ownerSig] = sigs
      
    if communityOwnage$ = post$.find('.community-wiki')
      post.community_owned_date_s = communityOwnage$.attr('title')?.match(/as of ([^\.]+)./)[1]
    else
      if ownerSig? and not communityOwnage$
        post.owner =
          user_id: +$('.user-details a', ownerSig).split(/\//g)[2]
          display_name: $('.user-details a', ownerSig).text()
          reputation: $('.reputation-score', ownerSig).text().replace(/,/g, '')
          profile_image: $('.user-gravatar32 img').attr('src')
        
      if editorSig? and not communityOwnage$
        post.last_editor =
          user_id: +$('.user-details a', editorSig).split(/\//g)[2]
          display_name: $('.user-details a', editorSig).text()
          reputation: $('.reputation-score', editorSig).text().replace(/,/g, '')
          profile_image: $('.user-gravatar32 img').attr('src')
      
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
        
        $.when(firstPage$, (for pageNumber in [2..pageCount]
          @ajax("/questions/#{questionid}?page=#{pageNumber}").pipe (source) ->
            $(makeDocument(source))
        )...).pipe (pages...) -> pages
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
  
  getPostVoteCount: (postid) ->
    @ajax("/posts/#{postid}/vote-counts", dataType: 'json').pipe (voteCounts) =>
      (up: +voteCounts.up, down: +voteCounts.down)
  
  # be nice: wrap $.ajax to add our throttle and header.
  ajax: (makeThrottle 500) (url, options = {}) ->
    existingBeforeSend = options.beforeSend;
    options.beforeSend = (request) ->
      request.setRequestHeader 'X-StackScraper-Version', '0.0.2'
      return existingBeforeSend?.apply this, arguments
    $.ajax(url, options)

@stackScraper = stackScraper = new StackScraper

$('#question .post-menu').append('<span class="lsep">|</span>').append $('<a href="#" title="download a JSON copy of this post">download</a>').click ->
  questionId = $('#question').data('questionid')
  stackScraper.getQuestion(questionId).then (question) ->
    bb = new BlobBuilder
    bb.append JSON.stringify(question, 4)
    window.location = URL.createObjectURL(bb.getBlob())
  
  false
