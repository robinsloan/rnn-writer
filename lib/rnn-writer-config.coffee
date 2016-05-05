module.exports = {
  numberOfSuggestionsPerRequest:
    order: 1
    type: "integer"
    title: "Number of suggestions per request"
    maximum: 10
    default: 5
  lookbackLength:
    order: 2
    type: "integer"
    title: "Lookback length"
    description: "How many characters should we send as sample text?"
    maximum: 256
    default: 48
  overrideBracketMatcher:
    order: 3
    type: "boolean"
    title: "Override automatic matching of quotation marks?"
    description: "Because it's annoying when you're writing prose..."
    default: true
  localSuggestionGenerator:
    order: 4
    type: "string"
    title: "Location of torch-rnn-server"
    description: "Including protocol and port"
    default: "http://localhost:8080"
  textBargains:
    order: 5
    type: "object"
    title: "Are you using text.bargains??"
    properties:
      usingTextBargains:
        order: 1
        type: "boolean"
        title: "Yes, I'm using text.bargains"
        default: false
      apiKey:
        order: 2
        type: "string"
        title: "API key"
        description: "If you need one, email `api@robinsloan.com`"
        default: "op3n-s3s4m3"
  }
