describe("zef_project", function()
    local proj;

    setup(function()
        proj = require('zef-project')
    end)

    teardown(function()
        proj = nil
    end)
end)
