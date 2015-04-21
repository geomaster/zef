local zef_build = {}
local zef_log = require('zef-log')
local zef_project = require('zef-project')

local ZefYamlFilenames = {
    'Zef.yaml',
    'zef.yaml'
}

function zef_build.run(target)
    local proj, err = zef_project.init()
    if not proj then 
        return nil, zef_log.err('could not initialize project')
    end
end

return zef_build
