local zef_project = {}
local zef_log = require('zef-log')
local zef_eye = require('zef-eye')
local zef_cachedb = require('zef-cachedb')
local lfs = require('lfs')
local lyaml = require('lyaml')
local io = require('io')

local ZefYamlFilenames = {
    'Zef.yaml',
    'zef.yaml'
}

local ZefConfigFilenames = {
    'ZefConfig.yaml',
    'zefconfig.yaml'
}


function zef_project.find_file(names)
    local foundfile

    for i, fn in ipairs(names) do
        local attr = lfs.attributes(fn, "mode")
        if attr and attr == "file" then 
            if foundfile then
                return nil,
                    'found both `'..foundfile..'` and `'..fn..'`, cannot decide which to use'
            end

            foundfile = fn 
        end
    end

    return foundfile or nil, nil
end

function zef_project.read_yaml_file(filenames)
    -- check for the existence of this file
    local foundfile, err = zef_project.find_file(filenames)

    if not foundfile then
        -- the first filename is the 'preferred' one
        return nil, (err or string.format('no `%s` file present', filenames[1]))
    end

    local f, err = io.open(foundfile, 'rb')
    if not f then 
        return nil, 'could not open `'..foundfile..'`: '..err
    end

    local fstr = f:read('*all');
    if not fstr then
        return nil, string.format('error while reading `%s`', foundfile)
    end

    -- parse yaml
    local ret, yaml = pcall(function() return lyaml.load(fstr) end)
    if not ret then
        return nil, string.format('error while parsing `%s`: %s', foundfile, yaml)
    end
    
    return yaml
end

function zef_project.read_zefyaml()
    return zef_project.read_yaml_file(ZefYamlFilenames)
end

function zef_project.validate_zefyaml(zefyaml)
    local valid_keys = {
        project = 'string',
        description = 'string',
        website = 'string',
        version = 'string',
        options = 'table'
    }
    
    local mandatory_keys = {
        project = false
    }

    if type(zefyaml) ~= 'table' then
        return nil, string.format('invalid data type for Zef.yaml data')
    end

    for k, v in pairs(zefyaml) do
        if not valid_keys[k] then
            return nil, string.format('unexpected entry: `%s`', k)
        end
        if type(v) ~= valid_keys[k] then
            return nil, string.format('unexpected type for entry `%s`', k)
        end

        if mandatory_keys[k] ~= nil then mandatory_keys[k] = true end
    end

    for k, v in pairs(mandatory_keys) do
        if not v then 
            return nil, string.format('required entry `%s` not found', k)
        end
    end

    -- check options
    local opts = {}
    if zefyaml.options then 
        for _, v in pairs(zefyaml.options) do
            local valid_types = {
                string = true,
                path = true,
                number = true,
                enum = true,
                boolean = true
            }

            local valid_keys = {
                name = "string",
                description = "string",
                default = true,
                values = "table",
                tuple = "boolean",
                ['type'] = "string"
            }

            local mandatory_keys = {
                name = false,
                ['type'] = false
            }

            -- if this is an enum, `values` should be mandatory
            if v.type == 'enum' then
                mandatory_keys.values = false
            end

            for k1, v1 in pairs(v) do
                if not valid_keys[k1] then
                    return nil, string.format('unexpected entry: `%s` in option `%s`', k1, 
                        type(v.name) == 'string' and v.name or 'unknown')
                end
                if type(valid_keys[k1]) == 'string' and type(v1) ~= valid_keys[k1] then
                    return nil, string.format(
                        'unexpected type for entry `%s` in option `%s`', k1, type(v.name) == 'string'
                            and v.name or 'unknown')
                end
                if mandatory_keys[k1] ~= nil then mandatory_keys[k1] = true end
            end

            for k1, v1 in pairs(mandatory_keys) do
                if not v1 then
                    return nil, string.format('required entry `%s` in option `%s` not found', k1, v.name or 'unknown')
                end
            end

            local typ = v['type']
            local name = v.name

            if not valid_types[typ] then
                return nil, string.format('not a valid option type: `%s` in option `%s`', typ, name)
            end

            if v.values ~= nil then
                local vallen = 0
                for i, _ in pairs(v.values) do
                    vallen = vallen + 1
                end

                if typ == 'enum' then
                    local seen_values = {}

                    for i, v in pairs(v.values) do
                        if type(i) ~= 'number' or i < 1 or i > vallen then
                            return nil, string.format('`values` should be an array of valid values, bad key '..
                                '`%s` found in option `%s`', i, name)
                        elseif type(v) ~= 'string' then
                            return nil, string.format('all enum values should be of type `string`, bad value '..
                                '`%s` found in option `%s`', v, name)
                        elseif seen_values[v] then
                            return nil, string.format('enum value `%s` repeated in option `%s`', v, name)
                        end

                        seen_values[v] = true
                    end
                    
                    if vallen == 0 then
                        return nil, string.format('empty `values` entry found in option `%s`', name)
                    end
                else
                    return nil, string.format('`values` not allowed for types that are not enum in option `%s`', 
                        name)
                end
            end

            if v.default then
                local ret, err = zef_project.validate_option(v.default, name, v)
                if not ret then
                    return nil, string.format('default value error: %s', err[1])
                end
            end

            opts[name] = {
                ['type'] = typ,
                values = v.values,
                description = v.description,
                tuple = v.tuple or false,
                default = v.default
            }
        end
    end

    return {
        project = zefyaml.project,
        description = zefyaml.description,
        website = zefyaml.website,
        version = zefyaml.version,
        options = opts
    }
end


function zef_project.validate_option_type(option, desc)
    local t = desc['type']
    if t == 'string' then
        return type(option) == 'string'
    elseif t == 'path' then
        return type(option) == 'string' and zef_project.is_valid_path(option)
    elseif t == 'number' then
        return type(option) == 'number'
    elseif t == 'boolean' then
        return type(option) == 'boolean'
    elseif t == 'enum' then
        if type(option) ~= 'string' then return false end

        local vals = desc.values
        for _, v in ipairs(vals) do
            if option == v then
                return true
            end
        end

        return false
   end

    return false
end

function zef_project.validate_option(v, name, desc)
    local errors = {}
    local pass = true

    if desc.tuple then
        if type(v) == 'table' then
            local vlen = 0
            for i, _ in pairs(v) do
                vlen = vlen + 1
            end

            for i, item in pairs(v) do
                if type(i) ~= 'number' or i < 1 or i > vlen then
                    table.insert(errors, string.format('option `%s` is not of valid type, should be '..
                        'a tuple of `%s`s, bad key `%s` found', name, desc['type'], i))

                    pass = false
                else
                    if not zef_project.validate_option_type(item, desc) then 
                        table.insert(errors, string.format('element %d of option `%s` should be of '..
                            'type `%s`', i, name, desc['type']))

                        pass = false
                    end
                end
            end

            if pass then
                return v
            else
                return nil, errors
            end
        elseif zef_project.validate_option_type(v, desc) then
            -- make it a single-valued tuple
            return { v }
        else
            return nil, { string.format('option `%s` should be a tuple of type `%s`, '..
                'single value of wrong type given', name, desc['type']) }
        end
    else
        if not zef_project.validate_option_type(v, desc) then
            return nil, { string.format('option `%s` should be of type `%s`',
                name, desc['type']) }
        end

        return v
    end
end

function zef_project.is_valid_path(path)
    return true -- TODO
end

function zef_project.validate_options(desc, options)
    local optdesc = desc.options or {}
    local pass = true
    local errors = {}

    local nonpass = function(msg) 
        table.insert(errors, msg)
        return false
    end
  
    for k, v in pairs(optdesc) do
        if options[k] == nil then
            if v.default ~= nil then
                options[k] = v.default
            end
        end
    end

   for k, v in pairs(options) do
        local desc = optdesc[k]
        if not desc then
            pass = nonpass(string.format('option `%s` not recognized', k))
        else
            local opt, err = zef_project.validate_option(v, k, desc)
            if opt then
                options[k] = opt
            else
                for _, v in ipairs(err) do
                    pass = nonpass(v)
                end
            end
        end
    end
    
    if pass then 
        return options
    else
        return nil, errors
    end
end

function zef_project.read_zefconfig()
    return zef_project.read_yaml_file(ZefConfigFilenames)
end

function zef_project.init()
    local proj = {}
    local ret, err = zef_project.read_zefyaml()
    if not ret then
        return nil, zef_log.err(err)
    end
    proj.zefyaml = ret

    local ret, err = zef_project.validate_zefyaml(proj.zefyaml)
    if not ret then
        return nil, zef_log.err(err)
    end
    proj.description = ret

    local cachedb, err = zef_cachedb.open()
    if not cachedb then
        return nil, zef_log.err(err)
    end
    proj.cachedb = cachedb
    
    local ret, err = zef_project.read_zefconfig()
    if not ret then 
        return nil, zef_log.err(err)
    end
    proj.options = ret

    local ret, err = zef_project.validate_options(proj.description, proj.options)
    if not ret then
        zef_log.err('could not validate all options:')
        for _, v in ipairs(err) do
            zef_log.err('  ' .. v)
        end
            
        return nil, 'could not validate all options'
    end
    proj.options = ret

    return proj
end

return zef_project

