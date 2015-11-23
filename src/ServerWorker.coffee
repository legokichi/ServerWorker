###
ServerWorker - simple request/response inline worker

InlineServerWorker
  - provide worker thread for heavy process
IframeServerWorker
  - provide UI thread for DOM sandbox

* usgae:
```
  worker = new (InlineServerWorker||IframeServerWorker) [], (emitter)->
    emitter.on "echo", (data, reply)->
      reply(data+"world")
  worker.load().then ->
    worker.request("echo", "hello").then (data)->
      console.log data
      worker.terminate()
  .catch (err)-> console.error err
```

###

EVENT_EMITTER_3_SOURCE = (/^function\s*[^\(]*\([^\)]*\)\s*\{([\s\S]*)\}$/gm.exec(""+EVENT_EMITTER_3)||["",""])[1]

class InlineServerWorker
  constructor: (@importScriptsURLs, @fn, @consts...)->
    @error = createErrorLogger(@fn)
    @urls = []
    @worker = null
  load: ->
    Promise.all(
      @importScriptsURLs.map (url)=>
        getArrayBuffer(url).then (buffer)=>
          URL.createObjectURL(
            new Blob([buffer], {"type": "text/javascript"}))
    ).then (urls)=>
      @urls = @urls.concat(urls)
      @urls.push url = URL.createObjectURL(new Blob(["""
        #{urls.map((url)-> "self.importScripts('#{url}');").join("\n")}
        #{EVENT_EMITTER_3_SOURCE}
        (#{@fn}(#{
          ->
            emitter = new EventEmitter()
            self.onmessage = ({data: {event, data, session}})->
              emitter.emit event, data, (data)->
                self.postMessage({data, session})
            emitter
        }(), #{@consts.map((a)->JSON.stringify(a)).join(", ")}));
      """], {type:"text/javascript"}))
      @worker = new Worker(url)
      return @
  request: (event, data)->
    new Promise (resolve, reject)=>
      msg = {event, data, session: hash()}
      @worker.addEventListener "error", _err = (ev)=>
        @worker.removeEventListener("error", _err)
        @worker.removeEventListener("message", _msg)
        @error(ev)
        reject(ev)
      @worker.addEventListener "message", _msg = (ev)=>
        if msg.session is ev.data.session
          @worker.removeEventListener("error", _err)
          @worker.removeEventListener("message", _msg)
          resolve(ev.data.data)
      @worker.postMessage(msg)
      return @
  terminate: ->
    @urls.forEach (url)-> URL.revokeObjectURL(url)
    @worker.terminate()
    @worker = null
    return

class IframeServerWorker
  constructor: (@importScriptsURLs, @fn, @consts...)->
    @error = createErrorLogger(@fn)
    @urls = []
    @iframe = document.createElement("iframe")
    @iframe.setAttribute("style", """
      position: absolute;
      top: 0px;
      left: 0px;
      width: 0px;
      height: 0px;
      border: 0px;
      margin: 0px;
      padding: 0px;
    """)
  load: ()->
    @urls = @importScriptsURLs
    document.body.appendChild(@iframe)
    @iframe.contentDocument.open()
    @iframe.contentDocument.write("""
      #{@urls.map((url)-> "<script src='#{url}'>\x3c/script>").join("\n")}
      <script>
      #{EVENT_EMITTER_3_SOURCE}
      (#{@fn}(#{
        ->
          emitter = new EventEmitter()
          window.addEventListener "message", (ev)->
            {data: {event, data, session}, source} = ev
            if event is "__echo__"
              window.parent.postMessage({data, session}, "*")
              return
            emitter.emit event, data, (data)->
              window.parent.postMessage({data, session}, "*")
          emitter
      }(), #{@consts.map((a)->JSON.stringify(a)).join(", ")}));
      \x3c/script>
    """)
    @iframe.contentDocument.close()
    @request("__echo__").then => @
  request: (event, data)->
    new Promise (resolve, reject)=>
      msg = {event, data, session: hash()}
      @iframe.contentWindow.addEventListener "error", _err = (ev)=>
        @iframe.contentWindow.removeEventListener("error", _err)
        window.removeEventListener("message", _msg)
        @error(ev)
        reject(ev)
      window.addEventListener "message", _msg = (ev)=>
        if msg.session is ev.data.session
          @iframe.contentWindow.removeEventListener("error", _err)
          window.removeEventListener("message", _msg)
          resolve(ev.data.data)
      @iframe.contentWindow.postMessage(msg, "*")
      return @
  terminate: ()->
    @urls.forEach (url)-> URL.revokeObjectURL(url)
    @iframe.removeAttribute("src")
    @iframe.removeAttribute("srcdoc")
    @iframe.contentWindow.removeEventListener()
    document.body.removeEventListener()
    document.body.removeChild(@iframe)
    iframe = null
    return


hash = ->
  Math.round(Math.random() * Math.pow(16, 8)).toString(16)

createErrorLogger = (code)-> (ev)->
  console.error(ev.message + "\n  at " + ev.filename + ":" + ev.lineno + ":" + ev.colno)
  ev.error && console.error(ev.error.stack);
  console.info("(" + code + "}());".slice(0, 300) + "\n...")

getArrayBuffer = (url)->
  new Promise (resolve, reject)->
    xhr = new XMLHttpRequest();
    xhr.addEventListener "load", ->
      if 200 <= xhr.status and xhr.status < 300
        if xhr.response.error?
        then reject(new Error(xhr.response.error.message))
        else resolve(xhr.response)
      else reject(new Error(xhr.status))
    xhr.open("GET", url)
    xhr.responseType = "arraybuffer"
    xhr.send()


if 'undefined' isnt typeof module
  module.exports.InlineServerWorker = InlineServerWorker
  module.exports.IframeServerWorker = IframeServerWorker
this.InlineServerWorker = InlineServerWorker
this.IframeServerWorker = IframeServerWorker
