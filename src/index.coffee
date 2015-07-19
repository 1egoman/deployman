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
  mkdirp appl_root, (err) ->
    return console.error(err) if err
    console.log repo.path, path.join(appl_root, ".git"), appl_name

    # copy the repo to the intial directory
    ncp repo.path, path.join(appl_root, ".git"), appl_name, (err) ->
     return console.error(err) if err
     console.log('done!')



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
