local T = MiniTest.new_set()
local expect = MiniTest.expect

T['map_parallel returns results in item order'] = function()
  local async = require('async')
  local system = require('ghlite.system')

  local results = async
    .run(function()
      -- Later items finish first, so completion order differs from item order.
      return system.map_parallel({ 30, 20, 10, 0 }, function(delay)
        async.sleep(delay)
        return delay
      end)
    end)
    :wait(1000)

  expect.equality(results, { 30, 20, 10, 0 })
end

return T
