
exports.admin_page = (config) ->
  (req, res) ->
    res.send "<ul>"+config.map(
      (a) -> """<li>
        <strong>#{a.name}</strong>
        <pre>#{["scale", "path"].map((i) -> "#{i}: #{JSON.stringify a[i]}").join '\n'}</pre>
        
        <a href="/rebuild?slug=#{a.path}&token=#{req.query.token}">rebuild slug</a>
        <a href="/ports?slug=#{a.path}&token=#{req.query.token}">get ports</a>
        <a href="/start?slug=#{a.path}&token=#{req.query.token}">start</a>
        <a href="/rm?slug=#{a.path}&token=#{req.query.token}">delete containers</a>


        <a href="#delete" onclick="document.getElementsByClassName('deleter')[0].style.display = 'inline'" style="color: red;">delete the whole thing</a>
        <a class="deleter" href="/delete?slug=#{a.path}&token=#{req.query.token}" style="display: none;">Are you sure? Click me if so...</a>
      </li>"""
    )+"</ul>"



exports.can_we_do_admin_things = (req, res, next) ->
  if req.query.token and req.query.token is process.env.ROOT_TOKEN
    next()
  else
    res.send name: "Go away, you unauthorized goober!"

