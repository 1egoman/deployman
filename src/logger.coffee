fs = require 'fs'
exports.log_stream = null
exports.callback_on_log = ->

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
  exports.callback_on_log args.join ' '

  if exports.log_stream
    exports.log_stream.write "#{args.join ' '}\n"

exports.set_log_file = (file, callback=->) ->
  if file is null
    exports.log_stream = null
  else
    exports.log_stream = fs.createWriteStream file
  exports.callback_on_log = callback or ->
