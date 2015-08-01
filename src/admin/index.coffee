
exports.admin_page = (config) ->
  (req, res) ->
    res.send "<ul>"+config.map(
      (a) -> """<li>
        <strong>#{a.name}</strong>
        <pre>#{["scale", "path"].map((i) -> "#{i}: #{JSON.stringify a[i]}").join '\n'}</pre>
        
        <a href="/rebuild?slug=#{a.path}&token=#{req.query.token}">rebuild slug</a>
      </li>"""
    )+"</ul>"



exports.can_we_do_admin_things = (req, res, next) ->
  if req.query.token and req.query.token is process.env.ROOT_TOKEN
    next()
  else
    res.send name: "Go away, you unauthorized goober!"
