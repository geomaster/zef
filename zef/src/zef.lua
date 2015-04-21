local zef = {}
local zef_help = require('zef-help')
local zef_build = require('zef-build')
local zef_clean = require('zef-clean')
local zef_log = require('zef-log')

function zef.usage()
    print(zef_help.usage)
end

function zef.build(target)
    zef_build.run(target)
end

function zef.clean()
    zef_clean.run()
end

function zef.run(args)
    if #args < 1 or string.match('(--)?help|-h', args[1]) then
        zef.usage()
        return 0
    end

    local action = args[1]
    if action == 'build' then
        zef.build(args[2])
    elseif action == 'clean' then
        zef.clean()
    else
        zef_log.err('unknown command: `'..action..'`')
    end
end

zef.run(arg)
