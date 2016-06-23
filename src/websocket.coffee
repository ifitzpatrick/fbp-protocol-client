Base = require './base'
platform = require '../helpers/platform'
uuid = require 'uuid'

class WebSocketRuntime extends Base
  constructor: (definition) ->
    @connecting = false
    @connection = null
    @protocol = 'noflo'
    @buffer = []
    @container = null
    super definition

  getElement: ->
    return @container if @container

    # DOM visualization for remote runtime output
    @container = document.createElement 'div'
    @container.classList.add 'preview-container'
    messageConsole = document.createElement 'pre'
    previewImage = document.createElement 'img'
    @container.appendChild previewImage
    @container.appendChild messageConsole

    @on 'network', (message) ->
      return unless message.command is 'output'

      p = message.payload
      if p.type? and p.type == 'previewurl'
        hasQuery = p.url.indexOf '?' != -1
        separator = if hasQuery then '&' else '?'
        previewImage.src = p.url + separator + 'timestamp=' + new Date().getTime()
      if p.message?
        encoded = p.message.replace /[\u00A0-\u99999<>\&]/gim, (i) -> "&##{i.charCodeAt(0)};"
        messageConsole.innerHTML += "#{encoded}\n"
        messageConsole.scrollTop = messageConsole.scrollHeight
    @on 'disconnected', ->
      messageConsole.innerHTML = ''

    @container

  isConnected: -> @connection isnt null

  connect: ->
    return if @connection or @connecting

    if @protocol
      @connection = new platform.WebSocket @getAddress(), @protocol
    else
      @connection = new platform.WebSocket @getAddress()
    @connection.addEventListener 'open', =>
      @connecting = false

      # Perform capability discovery
      @sendRuntime 'getruntime', {}

      @emit 'status',
        online: true
        label: 'connected'
      @emit 'connected'

      @flush()
    , false
    @connection.addEventListener 'message', @handleMessage, false
    @connection.addEventListener 'error', @handleError, false
    @connection.addEventListener 'close', () =>
      @connection = null
      @emit 'status',
        online: false
        label: 'disconnected'
      @emit 'disconnected'
    , false
    @connecting = true

  disconnect: ->
    return unless @connection
    @connecting = false
    @connection.close()

  send: (protocol, command, payload, id) ->
    id ?= uuid.v4()

    if @connecting
      @buffer.push
        protocol: protocol
        command: command
        payload: payload
        id: id
      return

    return unless @connection
    @connection.send JSON.stringify
      protocol: protocol
      command: command
      payload: payload
      id: id

  handleError: (error) =>
    if @protocol is 'noflo'
      delete @protocol
      @connecting = false
      @connection = null
      setTimeout =>
        @connect()
      , 1
      return
    @emit 'error', error
    @connection = null
    @connecting = false

  handleMessage: (message) =>
    msg = JSON.parse message.data
    switch msg.protocol
      when 'runtime' then @recvRuntime msg.command, msg.payload, msg.id
      when 'graph' then @recvGraph msg.command, msg.payload, msg.id
      when 'network' then @recvNetwork msg.command, msg.payload, msg.id
      when 'component' then @recvComponent msg.command, msg.payload, msg.id

  flush: ->
    for item in @buffer
      @send item.protocol, item.command, item.payload
    @buffer = []

module.exports = WebSocketRuntime
