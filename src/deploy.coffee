chalk = require "chalk"
path = require "path"
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



reload_config = exports.reload_config = (cb) ->
  fs.readFile path.join(__dirname, "..", "config.json"), (err, data) ->
    if err
      cb err
    else
      try
        cb null, JSON.parse data
      catch e
        cb e



# stop all instances of the specified app
exports.stop_all_app = (appl_name, cb) ->
  ps (err, containers) ->
    return cb(err) if err
    async.forEach containers.filter((c) -> appl_name is c.image), (c, cb) ->
      exec "docker stop #{c.id} && docker rm #{c.id}", (err, sout, serr) ->
        log sout.toString().trim '\n'
        log serr.toString().trim '\n'
        cb err or null
    , (err) ->
      cb err or null


# get all exposed ports for a specified app
exports.get_exposed_ports = (appl_name, cb) ->
  ps (err, containers) ->
    return cb err if err
    ports = []

    containers.filter(
      (c) -> appl_name is c.image.split(':')[0] # account for appname:latest stuff
    ).forEach (i) ->
      console.log i
      ports = collect ports, i.ports

    cb null, ports


# force-rebuild slug
exports.build_slug = (name, cb) ->
  exports.on_push null, path: "/#{name}.git", cb

# user pushed their branch to us!
exports.on_push = (update, repo, done_cb=null) ->
  got_all = false

  appl_name = repo.path.split('/').reverse()[0].split('.')[...1].join ''
  appl_root = path.join(repos_root, appl_name)
  appl_port = process.env.CONTAINER_PORT or 8000

  header "Deploying #{chalk.green appl_name}@#{chalk.cyan repo.path}..."
  async.waterfall [

    # make the  appl_root
    (cb) ->
      header "Making app root..."
      try
        mkdirp appl_root, cb
        set_log_file path.join(appl_root, "deploy.log")
      catch e
        cb e

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
      exports.stop_all_app appl_name, cb

    (cb) ->
      header "Running Docker image..."
      reload_config (err, data) ->
        return cb err if err
        
        # scale based off of the config settings
        image = data.filter (d) -> d.name is appl_name
        if image.length and image[0].scale
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

          containers.filter(
            (c) -> appl_name is c.image.split(':')[0] # account for appname:latest stuff
          ).forEach (i) ->
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

    if done_cb
      done_cb err

