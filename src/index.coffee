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

# initialize pushover for git events
# pushover = require "pushover"
# git = pushover path.join(__dirname, "repos")
#
#
# git.on 'push', (push) ->
#     console.log('push ' + push.repo + '/' + push.commit
#         + ' (' + push.branch + ')'
#     )
#     push.accept()
#
# git.on 'fetch', (fetch) ->
#     console.log('fetch ' + fetch.commit)
#     fetch.accept()


repos_root = path.join(__dirname, "..", "repos")

{ncp} = require "ncp"
mkdirp = require "mkdirp"
{exec, spawn} = require "child_process"
async = require "async"
rmdirRecursive = require 'rmdir-recursive'
fs = require "fs"
ps = require 'docker-ps'

# indent logs
header = ->
  args = Array.prototype.slice.call arguments
  args.unshift "------>"
  rawLog.apply this, args
log = ->
  args = Array.prototype.slice.call arguments
  args.unshift "       "
  rawLog.apply this, args
rawLog = ->
  args = Array.prototype.slice.call arguments
  console.log args.join ' '

GitServer = require './git-server'
newUser = {
    username:'demo',
    password:'demo'
}

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

reload_config (err, data) ->
  return header "Config error: #{err}" if err

  # craete gitserver
  server = new GitServer data, header

  # highjack our server and display stats
  server.server_callback = (req, res, next)->
    # home page to reload config
    if req.method is 'GET' and req.url is '/'
      res.writeHead(200, {'Content-Type': 'text/html'})
      res.end """
      Hey, you've run into deployman!
      <form method="POST" action="/reload_config">
        <input type="submit" value="Update config" />
      </form>
      """

    # reload config
    # /reload_config - reload the config
    else if req.method is 'POST' and req.url is '/reload_config'
      reload_config (err, data) ->
        if err
          header "Config error: #{err}"
          res.end err
        else
          server.repos = data
          header "Reloaded Config!"
          res.end "Reloaded Config: #{JSON.stringify data, null, 2}"

    # get running processes
    # /ps - all processes
    # /ps/:name - all processes that were build with the specified image
    else if req.method is 'GET' and req.url.indexOf('/ps') is 0
      cont_name = req.url[4..] or null
      ps (err, containers) ->
        res.end JSON.stringify containers.filter((a) ->
          if cont_name
            a.image is cont_name
          else
            true
        ), null, 2


    else
      next()
    # app.on 'request', (req, res) ->
    #   if req.url is '/'
    #     res.send "WOW!"
      # console.log req, res
      #

  # user pushed their branch to us!
  server.on 'post-update', (update, repo) ->
    # console.log update, repo
    got_all = false

    appl_name = repo.path.split('/').reverse()[0].split('.')[...1].join ''
    appl_root = path.join(repos_root, appl_name)
    appl_port = process.env.CONTAINER_PORT or 8000

    header "Deploying #{chalk.green appl_name}@#{chalk.cyan repo.path}..."
    async.waterfall [

      # make the appl_root
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

      # delete any previously deployed instance configs
      # FIXME should this be neccisary to successfully build?
      (data, cb) ->
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

        child.stdout.on 'data', (buffer) ->
          s = buffer.toString().trim '\n'
          rawLog s
        child.stdout.on 'data', (buffer) ->
          s = buffer.toString().trim '\n'
          rawLog s
        child.stdout.on 'end', -> cb null
        child.stderr.on 'end', (buffer) -> cb buffer

        # enoent? check to be sure that the executable exists and can be run.
        child.on 'error', (err) -> cb err

      (cb) ->
        header "Running Docker image..."
        child = spawn "docker", "run -d -p #{appl_port} #{appl_name}".split ' '

        child.stdout.on 'data', (buffer) ->
          s = buffer.toString().trim '\n'
          rawLog s
        child.stdout.on 'data', (buffer) ->
          s = buffer.toString().trim '\n'
          rawLog s
        child.stdout.on 'end', -> cb null
        child.stderr.on 'end', (buffer) -> cb buffer

        # enoent? check to be sure that the executable exists and can be run.
        child.on 'error', (err) -> cb err


      (cb) ->

        # get its exposed port...
        ps (err, containers) ->
          if not got_all
            got_all = true
            header "Exposed ports:"

            containers.filter((c) -> appl_name is c.image).forEach (i) ->
              log "#{chalk.cyan i.command} (#{chalk.green i.id[...4]}) exposes port(s) #{chalk.yellow JSON.stringify(i.ports)}"

            # and, we're done!
            header "Done! #{chalk.cyan repo.path} has been deployed!"
            cb()

    ], (err) ->
      console.log err if err



exports.main = ->

  # set ejs as view engine
  app.set "view engine", "ejs"

  # before middleware, intercept git events
  app.use (req, res, next) ->
    git.handle(req, res)

  # include all the required middleware
  exports.middleware app

  # some sample routes
  app.get "/", (req, res) ->
    res.send "'Allo, World!"


  

  # listen for requests
  PORT = process.argv.port or 8000
  app.listen PORT, ->
    console.log chalk.blue "-> :#{PORT}"

exports.middleware = (app) ->

  # serve static assets
  app.use require("express-static") path.join(__dirname, '../public')

# exports.main()
