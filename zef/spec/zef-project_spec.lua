local fsmock = require('filesystem-mock')
local logmock = require('zeflog-mock')
local cachedbmock = require('zefcachedb-mock')
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
        _real_zeflog = require('zef-log')
        _real_cachedb = require('zef-cachedb')

        package.loaded.io = fsmock.io
        package.loaded.lfs = fsmock.lfs
        package.loaded['zef-log'] = logmock
        package.loaded['zef-cachedb'] = cachedbmock

        proj = require('zef-project')
    end)

    teardown(function()
        proj = nil
        package.loaded.io = _real_io
        package.loaded.lfs = _real_lfs
        package.loaded['zef-log'] = _real_zeflog
        package.loaded['zef-cachedb'] = _real_cachedb
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

        it('fails with malformed Yaml', function()
            with_zefyaml(proj,
                [[
---
key1: [ 'a', 'b'
                ]],
            function()
                local yaml, err = proj.read_zefyaml()
                assert.falsy(yaml)
                assert.truthy(err:find('error while parsing `Zef.yaml`'))
            end)
        end)
    end)

    describe('Zef.yaml validation', function()
        it('fails when a non-table type is given', function()
            local ret, err = proj.validate_zefyaml('this is not how any of this works')
            assert.falsy(ret)
            assert.are.same('invalid data type for Zef.yaml data', err)
        end)

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
    - type: string
      invalid_key: invalid key value
                ]],
            function()
                local ret, err = read_validate_zefyaml(proj)
                assert.falsy(ret)
                assert.are.same('unexpected entry: `invalid_key` in option `unknown`', err)
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

        it('rejects invalid key types for options', function()
            with_zefyaml(proj, 
                [[
---
project: Project Name
options:
    - name: yes
                ]],
            function()
                local ret, err = read_validate_zefyaml(proj)
                assert.falsy(ret)
                assert.are.same('unexpected type for entry `name` in option `unknown`', err)
            end)
            
            with_zefyaml(proj, 
                [[
---
project: Project Name
options:
    - name: valid_name
      type: 42
                ]],
            function()
                local ret, err = read_validate_zefyaml(proj)
                assert.falsy(ret)
                assert.are.same('unexpected type for entry `type` in option `valid_name`', err)
            end)

        end)

        it('rejects invalid default values for options', function()
            with_zefyaml(proj,
                [[
---
project: Project Name
options:
    - name: option1
      type: string
      default: 42
                ]],
            function()
                local ret, err = read_validate_zefyaml(proj)
                assert.falsy(ret)
                assert.are.same('default value error: option `option1` should be of type `string`', err)

                -- the rest of these are covered in other tests which explicitly
                -- hit all paths in validate_option
            end)
        end)

        it('does not allow enum types without `values` entry', function()
            with_zefyaml(proj,
                [[
---
project: Project Name
options:
    - name: option1
      type: enum
                ]],
            function()
                local ret, err = read_validate_zefyaml(proj)
                assert.falsy(ret)
                assert.are.same('required entry `values` in option `option1` not found', err)
            end)
        end)

        it('does not accept empty `values` entries', function()
            with_zefyaml(proj,
                [[
---
project: Project Name
options:
    - name: option1
      type: enum
      values: []
                ]],
            function()
                local ret, err = read_validate_zefyaml(proj)
                assert.falsy(ret)
                assert.are.same('empty `values` entry found in option `option1`', err)
            end)

        end)

        it('accepts valid default values for options', function()
            with_zefyaml(proj,
                [[
---
project: Project Name
options:
    - name: option1
      type: enum
      values: [ 'a', 'b', 'c', 'd' ]
      tuple: yes
      default: [ 'a', 'c', 'd' ]
                ]],
            function()
                local ret, err = read_validate_zefyaml(proj)
                assert.truthy(ret)
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

        it('rejects repeated values for enums', function()
            with_zefyaml(proj,
                [[
---
project: Project Name
options:
    - name: option1
      type: enum
      values: [ 'a', 'b', 'c', 'a' ]
                ]],
            function()
                local ret, err = read_validate_zefyaml(proj)
                assert.falsy(ret)
                assert.are.same('enum value `a` repeated in option `option1`', err)
            end)
        end)

        it('rejects non-string values for enums', function()
            with_zefyaml(proj,
                [[
---
project: Project Name
options:
    - name: option1
      type: enum
      values: [ 'a', 'b', 42 ]
                ]],
            function()
                local ret, err = read_validate_zefyaml(proj)
                assert.falsy(ret)
                assert.are.same('all enum values should be of type `string`, bad value `42` found in ' ..
                    'option `option1`', err)
            end)
        end)

        it('rejects non-array `values` field for enums', function()
            with_zefyaml(proj,
                [[
---
project: Project Name
options:
    - name: option1
      type: enum
      values: 
        associative: array
                ]],
            function()
                local ret, err = read_validate_zefyaml(proj)
                assert.falsy(ret)
                assert.are.same('`values` should be an array of valid values, bad key `associative` found in ' ..
                    'option `option1`', err)
            end)
            
            with_zefyaml(proj,
                [[
---
project: Project Name
options:
    - name: option1
      type: enum
      values: 
        2: invalid_index
                ]],
            function()
                local ret, err = read_validate_zefyaml(proj)
                assert.falsy(ret)
                assert.are.same('`values` should be an array of valid values, bad key `2` found in ' ..
                    'option `option1`', err)
            end)
        end)
    end)

    describe('option type validation function', function()
        it('correctly validates/rejects options with common atom types', function()
            local types = {
                string = 'A string',
                number = 42,
                boolean = true,
                path = '/this/is/a/path/'
            }

            -- check if correct types are accepted
            for t, v in pairs(types) do
                assert.truthy(proj.validate_option_type(v, { ['type'] = t }))
            end

            -- check if incorrect types are rejected
            for t, v in pairs(types) do
                for t2, v2 in pairs(types) do
                    if t2 ~= t and not ((t == 'path' and t2 == 'string') or 
                        (t == 'string' and t2 == 'path')) then
                        -- mismatching types
                        assert.falsy(proj.validate_option_type(v2, { ['type'] = t }))
                    end
                end
            end
        end)

        it('correctly validates enum types', function()
            assert.falsy(proj.validate_option_type(42, { ['type'] = 'enum', values = { 'a' } }))
            assert.falsy(proj.validate_option_type('not in enum', {
                ['type'] = 'enum',
                values = { 'in enum', 'also in enum' }
            }))

            local enumdesc = {
                ['type'] = 'enum',
                values = { 'aaa', 'bbb', 'ccc', 'ddd' }
            }

            for _, v in pairs(enumdesc.values) do
                assert.truthy(proj.validate_option_type(v, enumdesc))
            end
        end)

        it('fails to validate for non-existent types', function()
            assert.falsy(proj.validate_option_type('some string', 'bad_type'))
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

        it('rejects unknown options', function()
            with_zefconfig(proj, 
                [[
---
project: Project Name
options:
    - name: known_option
      type: string
      default: this is default
      description: Is not a required option
                ]], 
                [[
---
unknown_option: 300
                ]],
            function()
                local ret, err = read_validate_zefconfig(proj)
                assert.falsy(ret)
                assert.are.same(1, #err)
                assert.are.same('option `unknown_option` not recognized', err[1])
            end)
        end)

        it('rejects when a required option is not defined', function()
            with_zefconfig(proj,
                [[
---
project: Project Name
options:
    - name: required_option
      type: string
      description: Is a required option

    - name: optional_option
      type: string
      default: this is default
      description: Is not a required option
                ]],
                [[
---
optional_option: overriden default
                ]],
            function()
                local ret, err = read_validate_zefconfig(proj)
                assert.falsy(ret)
                assert.are.same(1, #err)
                assert.are.same('option `required_option` required but not supplied', err[1])
            end)
        end)

        it('rejects bad option types for atoms', function()
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
        end)

        it('rejects single values of wrong type for enums', function()
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

        it('rejects non-array values for tuples', function()
            with_zefconfig(proj, zefyaml,
                [[
---
string_tuple_option: 
    should: not be an associative array
                ]],
            function()
                local ret, err = read_validate_zefconfig(proj)
                assert.falsy(ret)
                assert.are.same(1, #err)
                assert.are.same('option `string_tuple_option` is not of valid type, should be '..
                    'a tuple of `string`s, bad key `should` found', err[1])
            end)

            with_zefconfig(proj, zefyaml,
                [[
---
string_tuple_option: 
    2: invalid_index
                ]],
            function()
                local ret, err = read_validate_zefconfig(proj)
                assert.falsy(ret)
                assert.are.same(1, #err)
                assert.are.same('option `string_tuple_option` is not of valid type, should be '..
                    'a tuple of `string`s, bad key `2` found', err[1])
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

    describe('init method', function()
        it('fails if Zef.yaml reading fails', function()
            with_mock_fs(proj, {}, {}, {}, function()
                local ret, err = proj.init()
                assert.falsy(ret)
                assert.are.same('no `Zef.yaml` file present', err)
            end)
        end)

        it('fails if Zef.yaml validation fails', function()
            with_zefyaml(proj,
                [[
---
bad_key: bad_value
                ]],
            function()
                local ret, err = proj.init()
                assert.falsy(ret)
                assert.are.same('unexpected entry: `bad_key`', err)
            end)
        end)

        it('fails if cache database opening fails', function()
            cachedbmock.fail_on_open = true

            with_zefyaml(proj,
                [[
---
project: Project Name
                ]],
            function()
                local ret, err = proj.init()
                assert.falsy(ret)
                assert.are.same('Requested orchestrated error on zef_cachedb.open()', err)
            end)

            cachedbmock.fail_on_open = false
            
        end)

        it('fails if ZefConfig.yaml reading fails', function()
            with_mock_fs(proj, {
                ['Zef.yaml'] = [[
---
project: Project Name
options:
    - name: string_option
      type: string
      default: aaa
                ]]
            }, {}, {}, function()
                local ret, err = proj.init()
                assert.falsy(ret)
                assert.are.same('no `ZefConfig.yaml` file present', err)
            end)
        end)

        it('fails if ZefConfig.yaml options cannot be validated', function()
            with_zefconfig(proj, 
                [[
---
project: Project Name
options:
    - name: string_option
      type: string
      default: aaa
                ]],
                [[
---
string_option: [ 'a', 'b', 'c' ]
                ]],
            function()
                logmock.purge()
                logmock.enable()
                local ret, err = proj.init()
                assert.falsy(ret)
                assert.truthy(logmock.has_item('could not validate all options:'))
            end)
        end)

        it('returns a project file if all conditions are met', function()
            with_zefconfig(proj,
                [[
---
project: Project Name
options:
    - name: string_option
      type: string
      default: 'aaa'
      tuple: yes
                ]],
                [[
---
string_option: [ 'a', 'b', 'c' ]
                ]],
            function()
                local ret, err = proj.init()
                assert.truthy(ret)
                assert.are.same('table', type(ret))
            end)
        end)
    end)
end)
