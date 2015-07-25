
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

