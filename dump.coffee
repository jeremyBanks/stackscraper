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
      result = new $.Deferred
      
      if intervalId?
        queue.push [f, thisVal, argVals, result]
      else
        $.when(f.apply thisVal, argVals).then(result.resolve, result.reject, result.notify)
        intervalId = setInterval ->
          if queue.length
            [f_, thisVal_, argVals_, result_] = queue.shift()
            $.when(f_.apply thisVal_, argVals_).then(result_.resolve, result_.reject, result_.notify)
          else
            clearInterval intervalId
            intervalId = null
        , interval
      
      result

# creates a new object using the specified object as a prototype
spawn = (parent) -> (con = ->):: = parent; new con

class StackScraper
  constructor: ->
    @posts = {} # an individual post, just what's visible on the page
    @questions = {} # a complete question
  
  throttle = makeThrottle(2000)
  
  loadQuestionPage: throttle (postid, fromPage = 1) ->
    # Loads the question page that a specified post is visible on.
    # The page argument is only relevant if postid is a question id.
    $.ajax("/questions/#{postid}#{if fromPage != 1 then "?page=#{fromPage}" else ''}", beforeSend: (request) ->
      # AJAX can't set a User-Agent, so at least give them *something* to block
      request.setRequestHeader 'X-Stack-Scraper', '0.0.0'
    ).pipe (source) =>
      # Load source into a new document so it doesn't mess up this one.
      page = $(document.implementation.createHTMLDocument("").body.parentElement)
      page[0].innerHTML = source
      
      unless (reps = page.find('#hlinks-user .reputation-score').text())? and +reps.replace(/,/g, '') > 10000
        return new $.Deferred -> @reject '10k reputation required'
      
      console.log 'yo'
      
      for postElement in page.find('.question, .answer')
        $post = $(postElement)
        
        if is_question = $post.is('.question')
          postid = +$post.data('questionid')
        else
          postid = +$post.data('questionid')
        
        post = @posts[postid] ?= post_id: postid
        post.body = $.trim $post.find('.post-text').html()
        post.score = +$post.find('.vote-count-post').text()
        post.deleted = $post.is('.deleted-question, .deleted-answer')
        
        if is_question
          post.post_type = 'question'
          post.title = page.find('#question-header h1 a').text()
          post.link = page.find('#question-header h1 a').attr('href')
          post.tags = $(tag).text() for tag in $post.find(".post-taglist .post-tag")
          post.favorite_count = +($post.find(".favoritecount").text() ? 0)
        else
          post.post_type = 'answer'
      
        # actually, just fetch everything as soon as it's known-of.
      
      page
  
  reqPost: (postid) ->
    if postid of @posts
      return $.when @posts[postid]
    
    @loadQuestionPage(postid).pipe => @posts[postid]
  
  reqQuestion: (questionid) ->
    result = new $.Deferred
    
    if questionid of @questions
      return $.when @posts[questionid]
    
    @loadQuestionPage(postid).pipe =>
      
    
    result
  
scraper = new StackScraper
scraper.reqPost(12907).then (x) -> console.log x

@posts = scraper.posts
# Okay, how about: each post has a normal Post result as well as a PostWithReplies object which uses the original as a prototype?

