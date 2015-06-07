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

    function with_zefconfig(proj, zefyaml, zefconfig, fn)
        with_mock_fs(proj, {
            ['Zef.yaml'] = zefyaml,
            ['ZefConfig.yaml'] = zefconfig
        }, {}, {}, fn)
    end

    function read_validate_zefyaml(proj)
        local yaml = proj.read_zefyaml()
        assert.are.same('table', type(yaml))

        return proj.validate_zefyaml(yaml)
    end
        
    function read_validate_zefconfig(proj)
        local desc = read_validate_zefyaml(proj)
        local yaml = proj.read_zefconfig()

        return proj.validate_options(desc, yaml or {})
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

    describe('YAML file parser', function()
        local yaml_files = { 
            { f = proj.read_zefyaml, files = {'Zef.yaml', 'zef.yaml'} }, 
            { f = proj.read_zefconfig, files = { 'ZefConfig.yaml', 'zefconfig.yaml' } }
        }

        for _, v in ipairs(yaml_files) do
            it('fails with no ' .. v.files[1], function()
                with_mock_fs(proj, {
                    -- empty dir
                }, {}, {}, function()
                    local ret, err = v.f()
                    assert.falsy(ret)
                    assert.truthy(err:find('no `' .. v.files[1] .. '` file'))
                end)
            end)

            it('gracefully handles an open error in ' .. v.files[1], function()
                with_mock_fs(proj, {
                    [v.files[1]] = 'this file will not be opened'
                }, {v.files[1]}, {}, function()
                    local ret, err = v.f()
                    assert.falsy(ret)
                    assert.truthy(err:find('could not open'))
                end)
            end)

            it('gracefully handles a read error in ' .. v.files[1], function()
                with_mock_fs(proj, {
                    [v.files[1]] = 'this file will not be read'
                }, {}, {v.files[1]}, function()
                    local ret, err = v.f()
                    assert.falsy(ret)
                    assert.truthy(err:find('error while reading'))
                end)
            end)

            it('fails with more than one ' .. v.files[1], function()
                local vfs = {}
                for i, v in ipairs(v.files) do
                    vfs[v] = 'file number ' .. i
                end

                with_mock_fs(proj, vfs, {}, {}, function()
                    local ret, err = v.f()
                    assert.falsy(ret)
                    assert.truthy(err:find('cannot decide which to use'))
                end)
            end)
        end

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
                local yaml, err = proj.read_zefyaml()
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
                assert.are.same('required entry `project` not found', err)
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
                        assert.are.same('unexpected type for entry `'.. entry .. '`', err)
                    end)
                end
            end
        end)


        it('accepts and correctly parses allowed non-options keys', function()
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

        it('rejects invalid keys', function()
            with_zefyaml(proj,
                [[
---
project: Project Name
invalid_key: Invalid key value
                ]], 
            function()
                local ret, err = read_validate_zefyaml(proj)
                assert.falsy(ret)
                assert.are.same('unexpected entry: `invalid_key`', err)
            end)
        end)

        it('accepts and correctly parses a valid project declaration', function()
            with_zefyaml(proj,
                [[
---
project: Project Name
options:
    - name: string_option
      description: StringDesc
      type: string
      default: Default String Value

    - name: path_option
      description: PathDesc
      type: path
      default: /

    - name: number_option
      description: NumberDesc
      type: number
      default: 42

    - name: enum_option
      description: EnumDesc
      type: enum
      default: opt1
      values:
        - opt1
        - opt2
        - opt3

    - name: boolean_option
      description: BoolDesc
      type: boolean
      default: yes

    - name: string_tuple_option
      description: StringTupleDesc
      type: string
      tuple: yes
      default: ['aaaa', 'bbbb', 'cccc']
                ]],
            function()
                local ret, err = read_validate_zefyaml(proj)
                assert.are.same({
                    project = 'Project Name',
                    options = {
                        string_option = {
                            ['type'] = 'string',
                            description = 'StringDesc',
                            default = 'Default String Value',
                            tuple = false
                        },

                        path_option = {
                            ['type'] = 'path',
                            description = 'PathDesc',
                            default = '/',
                            tuple = false
                        },

                        number_option = {
                            ['type'] = 'number',
                            description = 'NumberDesc',
                            default = 42, 
                            tuple = false
                        },

                        enum_option = {
                            ['type'] = 'enum',
                            description = 'EnumDesc',
                            values = { 'opt1', 'opt2', 'opt3' },
                            default = 'opt1',
                            tuple = false
                        },

                        boolean_option = {
                            ['type'] = 'boolean',
                            description = 'BoolDesc',
                            default = true, 
                            tuple = false,
                        },

                        string_tuple_option = {
                            ['type'] = 'string',
                            description = 'StringTupleDesc',
                            default = { 'aaaa', 'bbbb', 'cccc' },
                            tuple = true
                        }
                    }
                }, ret);
            end)
        end)

        it('rejects invalid keys for options', function()
            with_zefyaml(proj,
                [[
---
project: Project Name
options: 
    - name: option
      type: string
      invalid_key: invalid key value
                ]],
            function()
                local ret, err = read_validate_zefyaml(proj)
                assert.falsy(ret)
                assert.are.same('unexpected entry: `invalid_key` in option `option`', err)
            end)

            with_zefyaml(proj,
                [[
---
project: Project Name
options:
    - name: non_enum_option
      type: string
      values: [ 'a', 'b', 'c' ]
                ]],
            function()
                local ret, err = read_validate_zefyaml(proj)
                assert.falsy(ret)
                assert.are.same('`values` not allowed for types that are not enum in option `non_enum_option`', err)
            end)

        end)

        it('rejects incomplete options', function()
            local entries = { 
                name = { missing = 'type', value = 'option'},
                ['type'] = { missing = 'name', value = 'string' }
            }

            for k, v in pairs(entries) do
                with_zefyaml(proj,
                    [[
---
project: Project Name
options:
    - ]] 
                .. k .. ': ' .. v.value .. '\n',
                function()
                    local ret, err = read_validate_zefyaml(proj)
                    assert.falsy(ret)
                    assert.are.same('required entry `'.. v.missing ..'` in option `' .. (k == 'name' and v.value or 'unknown') .. '` not found', err)

                end)
            end
        end)

        it('rejects invalid option types', function()
            with_zefyaml(proj,
                [[
---
project: Project Name
options:
    - name: option1
      type: invalid_type
                ]],
            function()
                local ret, err = read_validate_zefyaml(proj)
                assert.falsy(ret)
                assert.are.same('not a valid option type: `invalid_type` in option `option1`', err)
            end)
        end)
    end)

    describe('ZefConfig.yaml option validator', function()
        local zefyaml = [[
---
project: Project Name
options:
    - name: string_option
      description: StringDesc
      type: string
      default: Default String Value

    - name: path_option
      description: PathDesc
      type: path
      default: /

    - name: number_option
      description: NumberDesc
      type: number
      default: 42

    - name: enum_option
      description: EnumDesc
      type: enum
      default: opt1
      values:
        - opt1
        - opt2
        - opt3

    - name: boolean_option
      description: BoolDesc
      type: boolean
      default: yes

    - name: string_tuple_option
      description: StringTupleDesc
      type: string
      tuple: yes
      default: ['aaaa', 'bbbb', 'cccc']
        ]]

        it('validates valid defaults', function()
            with_zefconfig(proj, zefyaml, '', function()
                local ret, err = read_validate_zefconfig(proj)
                assert.are.same({
                    string_option = 'Default String Value',
                    path_option = '/',
                    number_option = 42,
                    enum_option = 'opt1',
                    boolean_option = true,
                    string_tuple_option = { 'aaaa', 'bbbb', 'cccc' }
                }, ret)
            end)
        end)

        it('rejects bad option types', function()
            with_zefconfig(proj, zefyaml, 
                [[
---
string_option: 42
path_option: 41
number_option: not a number
enum_option: optN
boolean_option: 3
string_tuple_option: [ 2, 3, yes ]
                ]],
            function()
                local ret, err = read_validate_zefconfig(proj)
                assert.falsy(ret)
                
                local real_types = {
                    string_option = 'string',
                    path_option = 'path',
                    number_option = 'number',
                    enum_option = 'enum',
                    boolean_option = 'boolean'
                }

                local errstr = ''
                for _, v in ipairs(err) do
                    errstr = errstr .. v .. '\n'
                end

                for k, v in pairs(real_types) do
                    assert.truthy(errstr:find('option `' .. k .. '` should be of type `' .. v .. '`'))
                end

                for _, v in ipairs({1, 2, 3}) do
                    assert.truthy(errstr:find('element ' .. v .. ' of option `string_tuple_option` should be '..
                        'of type `string`'))
                end
            end)

            with_zefconfig(proj, zefyaml,
                [[
---
string_tuple_option: 40
                ]],
            function()
                local ret, err = read_validate_zefconfig(proj)
                assert.falsy(ret)
                assert.are.same(1, #err)
                assert.are.same('option `string_tuple_option` should be a tuple of type `string`, '..
                    'single value of wrong type given', err[1])
            end)
        end)

        it('assumes a single-valued tuple when appropriate', function()
            with_zefconfig(proj, zefyaml, 
                [[
---
string_tuple_option: abcd
                ]],
            function()
                local ret, err = read_validate_zefconfig(proj)
                assert.are.same({ 'abcd' }, ret['string_tuple_option'])
            end)
        end)

    end)

end)
