require './util.coffee'
Config = require './config.coffee'
MSG = require './msg.coffee'
LISTEN = require './listen.coffee'
Storage = require './storage.coffee'
FileSystem = require './filesystem.coffee'
Notification = require './notification.coffee'
Server = require './server.coffee'


class Application extends Config
  LISTEN: null
  MSG: null
  Storage: null
  FS: null
  Server: null
  Notify: null
  platform:null
  currentTabId:null

  constructor: (deps) ->
    super

    @MSG ?= MSG.get()
    @LISTEN ?= LISTEN.get()
    
    for prop of deps
      if typeof deps[prop] is "object" 
        @[prop] = @wrapObjInbound deps[prop]
      if typeof deps[prop] is "function" 
        @[prop] = @wrapObjOutbound new deps[prop]

    @Notify ?= (new Notification).show 
    # @Storage ?= @wrapObjOutbound new Storage @data
    # @FS = new FileSystem 
    # @Server ?= @wrapObjOutbound new Server
    @data = @Storage.data
    
    @wrap = if @SELF_TYPE is 'APP' then @wrapInbound else @wrapOutbound

    @openApp = @wrap @, 'Application.openApp', @openApp
    @launchApp = @wrap @, 'Application.launchApp', @launchApp
    @startServer = @wrap @, 'Application.startServer', @startServer
    @restartServer = @wrap @, 'Application.restartServer', @restartServer
    @stopServer = @wrap @, 'Application.stopServer', @stopServer
    

    @wrap = if @SELF_TYPE is 'EXTENSION' then @wrapInbound else @wrapOutbound

    @getResources = @wrap @, 'Application.getResources', @getResources
    @getCurrentTab = @wrap @, 'Application.getCurrentTab', @getCurrentTab

    chrome.runtime.getPlatformInfo (info) =>
      @platform = info

    @init()

  init: () ->
    @data.server =
      host:"127.0.0.1"
      port:8089
      isOn:false

  getCurrentTab: (cb) ->
    # tried to keep only activeTab permission, but oh well..
    chrome.tabs.query
      active:true
      currentWindow:true
    ,(tabs) =>
      @currentTabId = tabs[0].id
      cb? @currentTabId

  launchApp: (cb, error) ->
      chrome.management.launchApp @APP_ID, (extInfo) =>
        if chrome.runtime.lastError
          error chrome.runtime.lastError
        else
          cb? extInfo

  openApp: () =>
      chrome.app.window.create('index.html',
        id: "mainwin"
        bounds:
          width:770
          height:800,
      (win) =>
        @appWindow = win) 

  getCurrentTab: (cb) ->
    # tried to keep only activeTab permission, but oh well..
    chrome.tabs.query
      active:true
      currentWindow:true
    ,(tabs) =>
      @currentTabId = tabs[0].id
      cb? @currentTabId

  getResources: (cb) ->
    @getCurrentTab (tabId) =>
      chrome.tabs.executeScript tabId, 
        file:'scripts/content.js', (results) =>
          @data.currentResources = []
          for r in results
            for res in r
              @data.currentResources.push res
          cb?()

  # updateResourcesListener: (resources) =>
  #     show resources
  #     _resources = []

  #     for frame in resources 
  #       do (frame) =>
  #         for item in frame 
  #           do (item) =>
  #             _resources.push item
  #     @Storage.save 'currentResources', resources
  getLocalFile: (info, cb, err) =>
    url = info.uri
    filePath = @getLocalFilePath url
    fileEntryId = @data.currentFileMatches[filePath].fileEntry
    if fileEntryId?
      chrome.fileSystem.restoreEntry fileEntryId, (fileEntry) =>
        fileEntry.file (file) =>
          cb?(fileEntry,file)
        ,err
    # dirName = info.uri

    # dirName = dirName.match(/(\/.*?\/)|(\\.*?\\)/)?[0] || ''
    # dirName = dirName.substring 0, dirName.length - 1
    # show 'looking for ' + dirName
    # _maps = {}
    # _maps[item.directory] = item.isOn for item in @data.maps

    # for k, dir of @data.directories when _maps[k]
    #   show 'in loop' + dir.relPath
    #   if dir.relPath is dirName then foundDir = dir

    # if foundDir?
    #   show 'found! ' + foundDir
    #   @FS.getLocalFile foundDir, filePath, cb, err
    # else
    #   show 'dunno, not found'
    #   err()

  startServer: (cb, err) ->
      if @Server.stopped is true
          @Server.start @data.server.host,@data.server.port,null, (socketInfo) =>
              @data.server.url = 'http://' + @data.server.host + ':' + @data.server.port + '/'
              @data.server.isOn = true
              @Notify "Server Started", "Started Server http://#{ @data.server.host }:#{@data.server.port}"
              cb?()
          ,(error) =>
              @Notify "Server Error","Error Starting Server: #{ error }"
              @data.server.url = 'http://' + @data.server.host + ':' + @data.server.port + '/'
              @data.server.isOn = true
              err?()

  stopServer: (cb, err) ->
      @Server.stop (success) =>
          @Notify 'Server Stopped', "Server Stopped"
          @data.server.url = ''
          @data.server.isOn = false
          cb?()
      ,(error) =>
          err?()
          @Notify "Server Error","Server could not be stopped: #{ error }"

  restartServer: ->
    @stopServer () =>
      @startServer()

  changePort: =>

  getLocalFilePath: (url) ->
    filePathRegex = /^((http[s]?|ftp|chrome-extension|file):\/\/)?\/?([^\/\.]+\.)*?([^\/\.]+\.[^:\/\s\.]{2,3}(\.[^:\/\s\.]‌​{2,3})?)(:\d+)?($|\/)([^#?\s]+)?(.*?)?(#[\w\-]+)?$/

    @data.currentFileMatches ?= {}
    
    return {} unless @data.maps? and @data.directories?

    resPath = url.match(filePathRegex)?[8]

    return {} unless resPath?
    
    for map in @data.maps
      resPath = url.match(new RegExp(map.url))? and map.url?

      if resPath
        if referer?
          # TODO: this
        else
          filePath = url.replace new RegExp(map.url), map.regexRepl
        break
    return filePath

  findLocalFilePathForURL: (url, cb) ->
    filePath = @getLocalFilePath url
    return unless filePath?
    @findFileInDirectories @data.directories, filePath, (fileEntry, directory) =>
    # return redirectUrl: @prefix + filePath
      delete fileEntry.entry
      @data.currentFileMatches[filePath] = 
        fileEntry: chrome.fileSystem.retainEntry fileEntry
        filePath: filePath
        directory: directory
      cb?(@data.currentFileMatches[filePath], directory)
    ,(err) =>
      show 'no files found for ' + filePath


  findFileInDirectories: (directories, path, cb, err) ->
    allDirs = directories.slice() unless allDirs?
    err() if directories is undefined or path is undefined
    _dirs = allDirs.slice()
    _path = path
    dir = _dirs.shift()
    _path.replace(/.*?\//, '') if dir is undefined
    if _path.match(/.*?\//)? #still directory
      # dir = _dirs.shift()
      if dir is undefined
        _dirs = allDirs.slice() 
        dir = _dirs.shift() 

      @FS.getLocalFileEntry dir, _path, 
        (fileEntry) =>
          cb? fileEntry, dir
        ,(error) =>
          @findFileInDirectories _dirs, _path, cb, err  
    else
      @FS.getLocalFileEntry dir, _path, 
        (fileEntry) =>
          cb? fileEntry, dir
        ,err
  
  mapAllResources: (cb) ->
    @getResources =>
      for item in @data.currentResources
        @findLocalFilePathForURL item.url, =>
          cb?()


module.exports = Application


