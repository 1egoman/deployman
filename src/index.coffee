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
deploy = require "./deploy"

GitServer = require './git-server'

# load config from file
reload_config = deploy.reload_config

exports.main = ->

  # get config
  reload_config (err, data) ->
    return header "Config error: #{err}" if err

    # create new git-server 
    server = new GitServer data, header
    server.on 'post-update', deploy.on_push

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

   

    # admin page
    app.get "/admin", admin.can_we_do_admin_things, admin.admin_page(data)

    # rebuild slug
    app.get "/rebuild", admin.can_we_do_admin_things, (req, res) ->
      if req.query.slug
        deploy.build_slug req.query.slug, (log) ->

          # a status update
          # write the correct info to keep the user up to data
          res.write "#{chalk.stripColor log}\n"

        , (err) ->
          if err
            res.write "Error rebuilding slug: #{err}"
          else
            res.write "Built slug! WOOHOO!"
      else
        res.send "No slug specified. Use ?slug=..."


    # get bound ports
    app.get "/ports", admin.can_we_do_admin_things, (req, res) ->
      if req.query.slug
        appl_name = req.query.slug.split('/').reverse()[0].split('.')[...1].join ''
        deploy.get_exposed_ports appl_name, (err, ports) ->
          if err
            res.send
              name: "error.slug.ports"
              data: "Error getting ports for slug: #{err}"
          else
            res.send ports: ports
      else
        res.send "No slug specified. Use ?slug=..."


    # start a slug
    app.get "/start", admin.can_we_do_admin_things, (req, res) ->
      if req.query.slug
        appl_name = req.query.slug.split('/').reverse()[0].split('.')[...1].join ''
        deploy.start_all_app appl_name, (err, data) ->
          if err
            res.send
              name: "error.slug.start"
              data: "Error starting slug: #{err}"
          else
            res.send data: data
      else
        res.send "No slug specified. Use ?slug=..."


    # stop a slug
    app.get "/rm", admin.can_we_do_admin_things, (req, res) ->
      if req.query.slug
        appl_name = req.query.slug.split('/').reverse()[0].split('.')[...1].join ''
        deploy.rm_all_app appl_name, (err, data) ->
          if err
            res.send
              name: "error.slug.stop"
              data: "Error stopping slug: #{err}"
          else
            res.send data: data
      else
        res.send "No slug specified. Use ?slug=..."


    # delete an app
    app.get "/delete", admin.can_we_do_admin_things, (req, res) ->
      if req.query.slug
        appl_name = req.query.slug.split('/').reverse()[0].split('.')[...1].join ''
        deploy.delete_all_of_app appl_name, (err, data) ->
          if err
            res.send
              name: "error.slug.delete"
              data: "Error deleting slug: #{err}"
          else
            res.send data: data
      else
        res.send "No slug specified. Use ?slug=..."






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

    # Try One
    # See if the user is accessing with a folder-like port
    # Like "example.com/12345"
    app.get '/:port(\\d+)/', (req, res) ->
      req.url = req.url[req.params.port.length+1..]
      proxy req, res, req.params.port

    # Try Two
    # See if the user is accessing with a subdomain
    # Like "appl_name.example.com"
    app.use (req, res, next) ->
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
        # Umm, excuse me? That app doesn't exist.
        next()










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
