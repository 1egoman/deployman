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
cache_root = path.join(__dirname, "..", "cache")

{ncp} = require "ncp"
mkdirp = require "mkdirp"
{exec, spawn} = require "child_process"
async = require "async"
rmdirRecursive = require 'rmdir-recursive'
fs = require "fs"

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

GitServer = require('git-server')
newUser = {
    username:'demo',
    password:'demo'
}
newRepo = {
    name:'myrepo',
    anonRead:false,
    users: [
        { user:newUser, permissions:['R','W'] }
    ]
}
server = new GitServer([ newRepo ])
server.on 'post-update', (update, repo) ->
  console.log repo

# do (repo=path:"/tmp/repos/myrepo.git") ->
  appl_name = "appl"
  appl_root = path.join(repos_root, appl_name)
  appl_cache_root = path.join(cache_root, appl_name)
  appl_port = 8000

  buildpack_url = "https://github.com/heroku/heroku-buildpack-nodejs.git"
  buildpack_name = "nodejs"

  # console.log repo.path, path.join(appl_root, ".git"), appl_name
  
  header "Building #{chalk.green appl_name}@#{chalk.cyan repo.path}..."
  async.waterfall [

    # make the build cache
    (cb) ->
      header "Making build cache..."
      mkdirp appl_cache_root, cb

    # make the appl_root
    (data, cb) ->
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

    # # download the heroku buildpack
    # (cb) ->
    #   header "Fetching buildpack..."
    #   exec "git clone #{buildpack_url} /tmp/buildpacks/#{buildpack_name}", (err) ->
    #     # the buildpack has already been cloned, so ignore.
    #     if err and err.code is 128
    #       cb null
    #     else if err
    #       cb err
    #     else
    #       cb null

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
      child = spawn "docker", "run -p #{appl_port} #{appl_name}".split ' '

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



    # build the app using the heroku buildpack
    # (cb) ->
    #   console.log appl_root, appl_cache_root
    #   child = spawn "bin/compile", [appl_root, appl_cache_root], cwd: "/tmp/buildpacks/#{buildpack_name}"
    #
    #
    #   child.stdout.on 'data', (buffer) ->
    #     s = buffer.toString().trim '\n'
    #     rawLog s
    #   child.stdout.on 'data', (buffer) ->
    #     s = buffer.toString().trim '\n'
    #     rawLog s
    #   child.stdout.on 'end', -> cb null
    #   child.stderr.on 'end', (buffer) -> cb buffer
    #
    #   # enoent? check to be sure that bin/compile exists and can be run.
    #   child.on 'error', (err) -> cb err

    # and, we're done!
    # (o, e, cb) ->
    #   log "Done! #{chalk.cyan repo.path} has been deployed!"
    #   cb()

  ], (err) ->
    console.log err

    # run bin/compile

    # start a docker container

    # start the app!




  # copy the repo to the intial directory
  # ncp repo.path, path.join(appl_root, ".git"), appl_name, (err) ->
   # return console.error(err) if err
   # console.log('done!')



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
