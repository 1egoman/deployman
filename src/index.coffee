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


exports.main = ->

  # connect to database
  

  # set ejs as view engine
  app.set "view engine", "ejs"

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



exports.main()
