{Range, Point, CompositeDisposable, NotificationManager} = require "atom"

request = require "request-json"
sfx = require "sfx"
# nlp = require "nlp_compromise" # skipping this for now

module.exports = RNNWriter =

  GET_MORE_SUGGESTIONS_THRESHOLD: 3

  # let's muddle through CoffeeScript together, shall we

  config: require "./rnn-writer-config"

  keySubscriptions: null # do I need to list these here?? I don't know
  cursorSubscription: null

  activate: (state) ->
    @keySubscriptions = new CompositeDisposable
    @keySubscriptions.add atom.commands.add "atom-workspace", "rnn-writer:toggle": => @toggle()

    # note: all these key command wrapper functions are down at the very bottom
    @keySubscriptions.add atom.commands.add "atom-workspace", "rnn-writer:suggest": => @keySuggest()
    @keySubscriptions.add atom.commands.add "atom-workspace", "rnn-writer:scroll-up-suggestion": => @keyScrollUpSuggestion()
    @keySubscriptions.add atom.commands.add "atom-workspace", "rnn-writer:scroll-down-suggestion": => @keyScrollDownSuggestion()
    @keySubscriptions.add atom.commands.add "atom-workspace", "rnn-writer:accept-suggestion-right": => @keyAcceptSuggestion("right")
    @keySubscriptions.add atom.commands.add "atom-workspace", "rnn-writer:accept-suggestion-enter": => @keyAcceptSuggestion("enter")
    @keySubscriptions.add atom.commands.add "atom-workspace", "rnn-writer:cancel-suggestion-left": => @keyCancelSuggestion("left")
    @keySubscriptions.add atom.commands.add "atom-workspace", "rnn-writer:cancel-suggestion-esc": => @keyCancelSuggestion("escape")

    @running = false

  toggle: ->
    if @running
      @showMessage "RNN Writer has shut down."
      @running = false
      @reset "Shutting down for now."
      return

    if atom.config.get("rnn-writer.overrideBracketMatcher")
      atom.config.set("bracket-matcher.autocompleteBrackets", false) # :)

    @LOOKBACK_LENGTH = atom.config.get("rnn-writer.lookbackLength")
    @NUM_SUGGESTIONS_PER_REQUEST = atom.config.get("rnn-writer.numberOfSuggestionsPerRequest")
    if atom.config.get("rnn-writer.textBargains.usingTextBargains")
      @GENERATOR_BASE = "https://text.bargains"
      @API_KEY = atom.config.get("rnn-writer.textBargains.apiKey")
    else if atom.config.get("rnn-writer.localSuggestionGenerator")
      @GENERATOR_BASE = atom.config.get("rnn-writer.localSuggestionGenerator")
    else
      @showError "There's no server specified in the `rnn-writer` package settings."
      return

    @client = request.createClient(@GENERATOR_BASE)
    if @API_KEY then @client.headers["x-api-key"] = @API_KEY

    @client.get "/", (error, response, body) =>
      if error
        console.log "...error."
        console.log JSON.stringify(error, null, 2)
        @showError "Tried to start RNN Writer, but couldn't reach the server. Check your developer console for more details."
        @running = false
      else
        successMessage = "RNN Writer is up and running. Press `tab` for completions."
        if @API_KEY and body["message"] then successMessage += " " + body["message"]
        @showMessage successMessage
        @running = true

    @reset "Setting all vars for the first time."

  deactivate: ->
    @reset "Deactivated!"
    if @keySubscriptions?
      @keySubscriptions.dispose()
    if @cursorSubscription?
      @cursorSubscription.dispose()

  reset: (message) ->
    @suggestions = []
    @suggestionIndex = 0
    [@currentStartText, @currentSuggestionText] = ["", ""]
    [@offeringSuggestions, @changeSuggestionInProgress] = [false, false]
    if @suggestionMarker?
      @suggestionMarker.destroy()
    if @spinner?
      @spinner.destroy()

    console.log message

  # IGNORE THIS PART
  # not currently used

  updateEntities: ->
    @editor = atom.workspace.getActiveTextEditor()
    if @editor.getBuffer().getText().split(" ").length > 4
      nlpText = nlp.text @editor.getBuffer().getText()
      @people = if nlpText.people().length > 0
        nlpText.people().map (entity) -> entity.text
      else
        ["she", "Jenny", "Jenny Nebula"]
    else
      @people = ["she", "Jenny", "Jenny Nebula"]

  randomFrom: (array) ->
    return array[Math.floor(Math.random()*array.length)]

  interpolateEntityIntoSuggestion: (suggestion) ->
    # person placeholder char is @
    if suggestion.includes("@")
      suggestion = suggestion.replace(/@/g, @randomFrom(@people))

    return suggestion

  # OK STOP IGNORING

  # interface

  showMessage: (messageText) ->
    atom.notifications.addInfo("🤖 " + messageText, dismissable: true, icon: "radio-tower")

  showError: (errorText) ->
    sfx.basso()
    atom.notifications.addError("🤖 " + errorText, dismissable: true, icon: "stop")

  showSpinner: -> # while waiting for server response
    if @spinner?
      @spinner.destroy()

    spinnerSpan = document.createElement "span"
    spinnerSpan.className = "loading loading-spinner-tiny inline-block rnn-spinner-hack"

    buffer = @editor.getBuffer()
    startCharIndex = buffer.characterIndexForPosition(@editor.getCursorBufferPosition())
    currentSuggestionEndPos = buffer.positionForCharacterIndex(startCharIndex + @currentSuggestionText.length)

    @spinner = buffer.markPosition(currentSuggestionEndPos)
    @editor.decorateMarker(@spinner, {type: "overlay", position: "head", item: spinnerSpan})

  # vaguely chronological application lifecycle begins here

  lookBackToGetStartText: (howManyChars) ->
    # this is very step-by-step to make it easier for me to follow
    buffer = @editor.getBuffer()
    endPos = @editor.getCursorBufferPosition()
    endCharIndex = buffer.characterIndexForPosition(endPos)
    startCharIndex = endCharIndex - howManyChars
    startPos = buffer.positionForCharacterIndex(startCharIndex)
    startTextRange = new Range(startPos, endPos)
    return @editor.getBuffer().getTextInRange(startTextRange)

  suggest: ->
    @offeringSuggestions = true

    # make double extra sure we have the current editor
    @editor = atom.workspace.getActiveTextEditor()
    @editor.setSoftWrapped(true) # it is perhaps a bit aggro to put this here, but it kept bothering me

    # watch the cursor in this editor
    if @cursorSubscription?
      @cursorSubscription.dispose()
    @cursorSubscription = new CompositeDisposable
    @cursorSubscription.add @editor.onDidChangeCursorPosition => @loseFocus()

    # showtime!
    @currentStartText = @lookBackToGetStartText(@LOOKBACK_LENGTH)
    @getSuggestions()

  queryForCurrentStartText: ->
    return "/generate?start_text=" + encodeURIComponent(@currentStartText) + "&n=" + @NUM_SUGGESTIONS_PER_REQUEST

  getSuggestions: ->
    if @suggestions.length == 0
      @suggestionPos = new Point(@editor.getCursorBufferPosition().row, @editor.getCursorBufferPosition().column) # ugh??

    @showSpinner()

    console.log("Fetching suggestions from server...")
    @client.get @queryForCurrentStartText(), (error, response, body) =>
      if @spinner?
        @spinner.destroy()
      if error
        console.log "...error."
        @showError "<pre>" + JSON.stringify(error, null, 2) + "</pre>"
        @reset "Network error (see notification)"
      else
        if body["message"]
          console.log "...error."
          switch body["message"]
            when "Network error communicating with endpoint" then @showError "Looks like the server is offline."
            when "Forbidden" then @showError "That API key doesn't appear to be valid."
            else @showError "The server replied with this error:<pre>" + body["message"] + "</pre>"
          @reset "Network error (see notification)"
        else
          startTextForThisRequest = decodeURIComponent(body["start_text"]).replace(/\+/g, " "); # that extra replace is annoying
          if @offeringSuggestions and startTextForThisRequest == @currentStartText # be careful! things might have changed!
            console.log "...success."
            if @suggestions.length > 0
              @suggestions = @suggestions.concat(body["completions"])
            else
              @suggestions = body["completions"]
              @suggestionIndex = 0
              @changeSuggestion()
          else
            # can get into some weird states here, but it's fine for now
            console.log "Note: received outdated server reply. Ignoring."

  changeSuggestion: ->
    @changeSuggestionInProgress = true # dear event handler: please don't respond to cursor moves while in this block

    newSuggestionText = @suggestions[@suggestionIndex] + " " # always with the extra space; this might be annoying?

    # get start point
    buffer = @editor.getBuffer()
    startCharIndex = buffer.characterIndexForPosition(@suggestionPos)

    # clear old text
    oldEndPos = buffer.positionForCharacterIndex(startCharIndex + @currentSuggestionText.length)
    @editor.setTextInBufferRange(new Range(@suggestionPos, oldEndPos), "")

    @editor.setCursorBufferPosition(@suggestionPos) # go back to the place where this all started
    @editor.insertText(newSuggestionText) # insert new text
    @editor.setCursorBufferPosition(@suggestionPos) # keep the cursor where it was

    # mark the new text's region
    newEndPos = buffer.positionForCharacterIndex(startCharIndex + newSuggestionText.length)
    if @suggestionMarker?
      @suggestionMarker.destroy()
    @suggestionMarker = @editor.markBufferRange(new Range(@suggestionPos, newEndPos), invalidate: "inside")
    @editor.decorateMarker(@suggestionMarker, type: "highlight", class: "rnn-suggestion")

    # the new text becomes the old text
    @currentSuggestionText = newSuggestionText + ""

    sfx.pop() # :)
    @changeSuggestionInProgress = false # back to normal

  cancelSuggestion: ->
    buffer = @editor.getBuffer()
    startCharIndex = buffer.characterIndexForPosition(@suggestionPos)
    endPos = buffer.positionForCharacterIndex(startCharIndex + @currentSuggestionText.length)
    @editor.setTextInBufferRange(new Range(@suggestionPos, endPos), "")
    @editor.setCursorBufferPosition(@suggestionPos)

    @reset "Suggestion canceled."

  acceptSuggestion: (moveCursorForward) ->
    if moveCursorForward
      buffer = @editor.getBuffer()
      startCharIndex = buffer.characterIndexForPosition(@suggestionPos)
      endCharIndex = startCharIndex + @currentSuggestionText.length
      endPos = buffer.positionForCharacterIndex(endCharIndex)
      @editor.setCursorBufferPosition(endPos)

    @reset "Suggestion accepted"

  loseFocus: ->
    if @offeringSuggestions
      unless @changeSuggestionInProgress
        @reset "Suggestion accepted implicitly"

  # key command wrapper functions

  keySuggest: ->
    @editor = atom.workspace.getActiveTextEditor()

    if @running
      sfx.tink()
      if @offeringSuggestions
        @acceptSuggestion(true)
      else
        @suggest()
    else
      atom.commands.dispatch(atom.views.getView(@editor), "editor:indent")

  keyScrollUpSuggestion: ->
    @editor = atom.workspace.getActiveTextEditor()

    if @running and @offeringSuggestions
      if @suggestionIndex > 0
        @suggestionIndex -= 1
        @changeSuggestion()
      else
        sfx.basso()
    else
      atom.commands.dispatch(atom.views.getView(@editor), "core:move-up")

  keyScrollDownSuggestion: ->
    @editor = atom.workspace.getActiveTextEditor()

    if @running and @offeringSuggestions
      if @suggestionIndex+1 < @suggestions.length
        @suggestionIndex += 1
        @changeSuggestion()
      else
        sfx.basso()

      if (@suggestions.length - @suggestionIndex) < @GET_MORE_SUGGESTIONS_THRESHOLD
        @getSuggestions()
    else
      atom.commands.dispatch(atom.views.getView(@editor), "core:move-down")

  keyAcceptSuggestion: (key) ->
    @editor = atom.workspace.getActiveTextEditor()

    if @running and @offeringSuggestions
      if key == "right"
        @acceptSuggestion(false)
      if key == "enter"
        @acceptSuggestion(true)
    else
      if key == "right"
        atom.commands.dispatch(atom.views.getView(@editor), "core:move-right")
      if key == "enter"
        atom.commands.dispatch(atom.views.getView(@editor), "editor:newline")

  keyCancelSuggestion: (key) ->
    console.log(key)
    @editor = atom.workspace.getActiveTextEditor()

    if @running and @offeringSuggestions
      @cancelSuggestion()
    else
      if key == "left"
        atom.commands.dispatch(atom.views.getView(@editor), "core:move-left")
      if key == "escape"
        atom.commands.dispatch(atom.views.getView(@editor), "editor:consolidate-selections")
