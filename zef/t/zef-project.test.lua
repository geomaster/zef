local fsmock = require('filesystem-mock')
package.path = '../src/?.lua;' .. package.path

function inject_fsmock(fsmock, zefproj)
    fsmock:inject(zefproj)
end

function restore_fsmock(fsmock, zefproj)
    fsmock:restore(zefproj)
end

describe("zef_project", function()
    local proj;

    function with_new_project(fn)
        local proj = proj.init()
        fn(proj)
    end

    function with_mock_fs(proj, vfs, openerr, readerr, fn)
        local fs = fsmock.new(vfs)
        fs.err_on_read = {}
        fs.err_on_open = {}

        if readerr then
            for i, v in ipairs(readerr) do
                fs.err_on_read[v] = true;
            end
        end

        if openerr then
            for i, v in ipairs(openerr) do
                fs.err_on_open[v] = true
            end
        end

        inject_fsmock(fs, proj)

        fn(fs)

        restore_fsmock(fs, proj)
    end

    setup(function()
        _real_io = require('io')
        _real_lfs = require('lfs')

        package.loaded.io = fsmock.io
        package.loaded.lfs = fsmock.lfs

        proj = require('zef-project')
    end)

    teardown(function()
        proj = nil
        package.loaded.io = _real_io
        package.loaded.lfs = _real_lfs
    end)

    it('fails with no Zef.yaml', function()
        with_mock_fs(proj, {
            -- empty dir
        }, {}, {}, function()
            local ret, err = proj:read_zefyaml()
            assert.falsy(ret)
            assert.truthy(err:find('no Zef.yaml file'))
        end)
    end)

    it('gracefully handles an open error', function()
        with_mock_fs(proj, {
            ['Zef.yaml'] = 'this file will not be opened'
        }, {'Zef.yaml'}, {}, function()
            local ret, err = proj:read_zefyaml()
            assert.falsy(ret)
            assert.truthy(err:find('could not open'))
        end)
    end)

    it('gracefully handles a read error', function()
        with_mock_fs(proj, {
            ['Zef.yaml'] = 'this file will not be read'
        }, {}, {'Zef.yaml'}, function()
            local ret, err = proj:read_zefyaml()
            assert.falsy(ret)
            assert.truthy(err:find('error while reading'))
        end)
    end)

    it('fails with more than one Zef.yaml', function()
        with_mock_fs(proj, {
            ['Zef.yaml'] = 'one zef.yaml',
            ['zef.yaml'] = 'one zef.yaml'
        }, {}, {}, function()

            local ret, err = proj:read_zefyaml()
            assert.falsy(ret)
            assert.truthy(err:find('cannot decide which to use'))
        end)
    end)

    it('can read a rudimentary Yaml file', function()
        with_mock_fs(proj, {
            ['Zef.yaml'] =
                [[
---
key1: string_val
key2: 12
key3:
    - item1: item1val
    - item2: item2val
    - item3:
        - 12
        - 13
        - 14

key4: yes
]]
        }, {}, {}, function() 
            local yaml, err = proj:read_zefyaml()
            assert.are.same(yaml,
            { 
                key1 = 'string_val',
                key2 = 12,
                key3 = {
                    { 
                        item1 = 'item1val' 
                    },
                    { 
                        item2 = 'item2val' 
                    },
                    { 
                        item3 = {
                            12,
                            13,
                            14
                        }
                    }
                },

                key4 = true
            });
        end)
    end)

end)
