###
 * deployman
 * https://github.com/1egoman/deployman
 *
 * Copyright (c) 2015 Ryan Gaus
 * Licensed under the MIT license.
###

'use strict';

app = require("express")()
chalk = require "chalk"
path = require "path"
bodyParser = require "body-parser"
request = require 'request'

repos_root = path.join(__dirname, "..", "repos")

{ncp} = require "ncp"
mkdirp = require "mkdirp"
{exec, spawn} = require "child_process"
async = require "async"
rmdirRecursive = require 'rmdir-recursive'
fs = require "fs"
ps = require 'docker-ps'
{header, log, rawLog, set_log_file} = require './logger'
admin = require "./admin"

GitServer = require './git-server'

# object concatination
collect = ->
  ret = {}
  len = arguments.length
  i = 0
  while i < len
    for p of arguments[i]
      `p = p`
      if arguments[i].hasOwnProperty(p)
        ret[p] = arguments[i][p]
    i++
  ret


# load config from file
reload_config = (cb) ->
  fs.readFile path.join(__dirname, "..", "config.json"), (err, data) ->
    if err
      cb err
    else
      try
        cb null, JSON.parse data
      catch e
        cb e


# user pushed their branch to us!
exports.on_push = (update, repo) ->
  got_all = false

  appl_name = repo.path.split('/').reverse()[0].split('.')[...1].join ''
  appl_root = path.join(repos_root, appl_name)
  appl_port = process.env.CONTAINER_PORT or 8000

  set_log_file path.join(appl_root, "deploy.log")
  header "Deploying #{chalk.green appl_name}@#{chalk.cyan repo.path}..."
  async.waterfall [

    # make the  appl_root
    (cb) ->
      header "Making app root..."
      mkdirp appl_root, cb

    # checkout the repo into the appl_root
    (data, cb) ->
      header "Checking out app repo..."
      exec "cd #{repo.path}; GIT_WORK_TREE=#{appl_root} git checkout -f", cb

    # make the buildpacks folder if it doesn't exist
    (out, err, cb) ->
      mkdirp "/tmp/buildpacks", cb

    # inject PORT=8000
    # this is so stuff will run correctly within docker and be able to bind
    # correctly.
    (data, cb) ->
      header "Injecting PORT=#{appl_port} into Procfile..."
      fs.readFile path.join(appl_root, "Procfile"), (err, data) ->
        return cb err if err

        procfile = data.toString().split('\n').map (ln) ->
          [start, end] = ln.split ':'
          if start and end
            end = "PORT=#{appl_port} #{end.trim ' '}"
            "#{start}: #{end}"
          else
            ''

        fs.writeFile path.join(appl_root, "Procfile"), procfile.join('\n'), (err) ->
          cb err


    # delete any previously deployed instance configs
    # FIXME should this be neccisary to successfully build?
    (cb) ->
      rmdirRecursive path.join(appl_root, ".heroku"), cb

    # create Dockerfile
    (cb) ->
      header "Creating Dockerfile..."
      fs.writeFile path.join(appl_root, "Dockerfile"), """
      FROM tutum/buildstep
      EXPOSE #{appl_port}
      CMD ["/start", "web"]
      """, cb

    (cb) ->
      header "Building Docker image..."
      child = spawn "docker", "build -t #{appl_name} #{appl_root}".split ' '
      called_back = false

      child.stdout.on 'data', (buffer) ->
        s = buffer.toString().trim '\n'
        rawLog s
      child.stdout.on 'data', (buffer) ->
        s = buffer.toString().trim '\n'
        rawLog s
      child.stdout.on 'end', ->
        if not called_back
          called_back = true
          cb null
      child.stderr.on 'end', (buffer) ->
        if not called_back
          called_back = true
          cb buffer

      # enoent? check to be sure that the executable exists and can be run.
      child.on 'error', (err) -> cb err

    (cb) ->
      header "Stopping old Docker containers..."
      ps (err, containers) ->
        return cb(err) if err
        async.forEach containers.filter((c) -> appl_name is c.image), (c, cb) ->
          exec "docker stop #{c.id} && docker rm #{c.id}", (err, sout, serr) ->
            log sout.toString().trim '\n'
            log serr.toString().trim '\n'
            cb err or null
        , (err) ->
          cb err or null

    (cb) ->
      header "Running Docker image..."
      reload_config (err, data) ->
        return cb err if err
        
        # scale based off of the config settings
        image = data.filter (d) -> d.name is appl_name
        if image.length
          scale = image[0].scale
        else
          # nothing in the file, so just spawn one of the default containers
          log chalk.red "No scaling settings were specified, so we will create 1 web container."
          scale = web: 1
        
        # iterate and spawn the specified number of containers
        for k,v of scale
          header "Scaling #{k}@#{v}..."

          # for iter in [0..v]
          async.forEach [1..v], (iter, cb) ->
            header "Spawning container #{k}@#{iter}..."

            child = spawn "docker", "run -d -p #{appl_port} #{appl_name}".split ' '

            child.stdout.on 'data', (buffer) ->
              s = buffer.toString().trim '\n'
              log s
            child.stdout.on 'data', (buffer) ->
              s = buffer.toString().trim '\n'
              log s
            child.stdout.on 'end', -> cb null

          , (err) ->
            cb err or null
            # enoent? check to be sure that the executable exists and can be run.

    (cb) ->
      # get its exposed port...
      ps (err, containers) ->
        if not got_all
          got_all = true
          ports = []
          header "Exposed ports:"

          containers.filter((c) -> appl_name is c.image).forEach (i) ->
            log "#{chalk.cyan i.command} (#{chalk.green i.id[...4]}) exposes port(s) #{chalk.yellow JSON.stringify(i.ports)}"
            ports = collect ports, i.ports

          # write config to file
          fs.writeFile path.join(appl_root, "ports.json"), JSON.stringify(ports, null, 2), (err) ->
            if err
              cb err
            else
              cb null

    (cb) ->
      # and, we're done!
      header "Done! #{chalk.cyan repo.path} has been deployed!"
      cb null

  ], (err) ->
    set_log_file null
    console.log err if err



exports.main = ->

  # get config
  reload_config (err, data) ->
    return header "Config error: #{err}" if err

    # create new git-server 
    server = new GitServer data, header
    server.on 'post-update', exports.on_push

    # set ejs as view engine
    app.set "view engine", "ejs"

    # before middleware, intercept git events
    # and send them to git-server
    app.use (req, res, next) ->
      # if the path starts with a git repo, we send to git-server.
      if req.url.match /(\/[a-zA-Z0-9_-]+\.git\/)/
        server.git.handle.apply(server.git, [req, res])
      else
        next()

    # include all the required middleware
    exports.middleware app



    # proxy to the specified port
    # this method is called by all the handlers below to quickly proxy
    # through a request to the correct handler
    proxy = (req, res, port, proxy_url="127.0.0.1") ->
      host = req.headers.host
      log "#{chalk.cyan req.method} #{host}#{req.url} => #{proxy_url}:#{chalk.yellow port}"
      method = req.method.toLowerCase()
      data =
        uri: "http://#{proxy_url}:#{port}#{req.url}"
        json: req.body
      switch method
        when "get" then r = request.get data
        when "put" then r = request.put data
        when "post" then r = request.post data
        when "delete" then r = request.del data
        else return res.send("invalid method")
      r.on 'error', (e) ->
        res.send "Error contacting host: #{e}"
      req.pipe(r).pipe(res)

    # admin page
    app.use "/admin", admin.admin_page(data)


    # Try One
    # See if the user is accessing with a folder-like port
    # Like "example.com/12345"
    app.get '/:port(\\d+)/', (req, res) ->
      req.url = req.url[req.params.port.length+1..]
      proxy req, res, req.params.port

    # Try Two
    # See if the user is accessing with a subdomain
    # Like "appl_name.example.com"
    app.use (req, res) ->
      host = req.headers.host

      appl_name = host.split('.')[0]
      if appl_name and appl_name.length and not host.match /^(?:[0-9]{1,3}\.){3}[0-9]{1,3}/

        # read a list of all the ports the app is running upon
        appl_root = path.join(repos_root, appl_name)
        fs.readFile path.join(appl_root, "ports.json"), (err, data) ->
          if err
            res.send "Couldn't read from ports.json: #{err}"
          else

            # pick one at random
            # TODO There needs to be some better logic here, but
            # this will work for now. Real Load Balancing?
            ports = JSON.parse data
            port = do (obj=ports) ->
              keys = Object.keys obj
              keys[keys.length * Math.random() << 0]

            # do the proxy
            proxy req, res, port

      else
        res.send "Umm, excuse me? That app doesn't exist."










  # listen for requests
  PORT = process.env.PORT or 7000
  app.listen PORT, ->
    console.log chalk.blue "-> :#{PORT}"





exports.middleware = (app) ->

  # serve static assets
  app.use require("express-static") path.join(__dirname, '../public')

  # logging of requests
  app.use (req, res, next) ->
    header chalk.cyan(req.method), req.url, JSON.stringify(req.params), JSON.stringify(req.body or {})
    next()






exports.main()
