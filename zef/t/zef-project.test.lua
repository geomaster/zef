local fsmock = require('filesystem-mock')
package.path = '../src/?.lua;' .. package.path

function inject_fsmock(fsmock, zefproj)
    fsmock:inject(zefproj)
end

function restore_fsmock(fsmock, zefproj)
    fsmock:restore(zefproj)
end

describe("zef-project", function()
    local proj

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
                fs.err_on_read[v] = true
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

    function with_zefyaml(proj, zefyaml, fn) 
        with_mock_fs(proj, {
            ['Zef.yaml'] = zefyaml
        }, {}, {}, fn)
    end

    function read_validate_zefyaml(proj)
        local yaml = proj.read_zefyaml()
        assert.are.same('table', type(yaml))

        return proj.validate_zefyaml(yaml)
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

    describe('Zef.yaml parser', function()
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
            with_zefyaml(proj, 
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
                ]],
            function() 
                local yaml, err = proj:read_zefyaml()
                assert.are.same({ 
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
                }, yaml)
            end)
        end)
    end)

    describe('Zef.yaml validation', function()
        it('fails when mandatory keys are not given', function()
            with_zefyaml(proj,
                [[
---
description: blah blah
                ]], 
            function()
                local ret, err = read_validate_zefyaml(proj)
                assert.falsy(ret)
                assert.are.same(err, 'required entry `project` not found')
            end)
        end)

        it('does not accept invalid key types', function()
            local table_yaml = [[

    - key1: val1
    - key2: val2]]

            local invalid_maps = {
                project = { '1', 'yes', table_yaml },
                description = { '2', 'yes', table_yaml },
                website = { '3', 'yes', table_yaml },
                version = { '4', 'yes', table_yaml },
                options = { '5', 'yes', 'not a table but a string' }
            }

            for entry, vals in pairs(invalid_maps) do
                for _, v in ipairs(vals) do
                    with_zefyaml(proj,
                        [[
---
]] 
                    .. entry .. ': ' .. v .. '\n',
                    function()
                        local ret, err = read_validate_zefyaml(proj)
                        assert.falsy(ret)
                        assert.are.same(err, 'unexpected type for entry `'.. entry .. '`')
                    end)
                end
            end
        end)


        it('accepts all allowed non-options keys', function()
            with_zefyaml(proj,
                [[
---
project: Project Name
description: Description
website: www.example.com
version: 1.2.1
                ]],
            function()
                local ret, err = read_validate_zefyaml(proj)
                assert.are.same({
                    project = 'Project Name',
                    description = 'Description',
                    website = 'www.example.com',
                    version = '1.2.1',
                    options = {}
                }, ret)
            end)
            


        end)
    end)

end)
