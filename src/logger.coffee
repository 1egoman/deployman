fs = require 'fs'
exports.log_stream = null

# indent logs
exports.header = ->
  args = Array.prototype.slice.call arguments
  args.unshift "------>"
  exports.rawLog.apply this, args

exports.log = ->
  args = Array.prototype.slice.call arguments
  args.unshift "       "
  exports.rawLog.apply this, args

exports.rawLog = ->
  args = Array.prototype.slice.call arguments
  console.log args.join ' '

  if exports.log_stream
    exports.log_stream.write "#{args.join ' '}\n"

exports.set_log_file = (file) ->
  if file is null
    exports.log_stream = null
  else
    exports.log_stream = fs.createWriteStream file
