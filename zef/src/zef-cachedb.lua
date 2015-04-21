local zef_cachedb = {}
local sqlite3 = require('lsqlite3')
local lyaml = require('lyaml')

local CacheDBFilename = '.Zefcache'

function zef_cachedb.open(proj)
    local db, err = sqlite3.open(CacheDBFilename)
    local cachedb = { db = db }
    if not db then 
        return nil, string.format(
            'could not read database `%s`: %s', CacheDBFilename, err)
    end

    local ret = db:exec([[
         CREATE TABLE IF NOT EXISTS param
            (name TEXT NOT NULL UNIQUE PRIMARY KEY, 
             value TEXT);

         CREATE TABLE IF NOT EXISTS file
            (id INTEGER NOT NULL UNIQUE PRIMARY KEY,
             path TEXT NOT NULL,
             timestamp INTEGER NOT NULL)

         -- type is one of 
         --   meta
         --   phony
         --   file
         CREATE TABLE IF NOT EXISTS target
            (id INTEGER NOT NULL UNIQUE PRIMARY KEY,
             name TEXT NOT NULL,
             type CHAR(8) NOT NULL,
             rules TEXT NOT NULL,
             file_id INTEGER NOT NULL REFERENCES (file.id));

         CREATE TABLE IF NOT EXISTS feature
            (id INTEGER NOT NULL UNIQUE PRIMARY KEY,
             name TEXT NOT NULL UNIQUE PRIMARY KEY);

         -- type is one of
         --   target
         --   feature
         --   option
         CREATE TABLE IF NOT EXISTS node
            (id INTEGER NOT NULL UNIQUE PRIMARY KEY,
             type CHAR(8) NOT NULL,
             timestamp INTEGER,
             ref_id INTEGER NOT NULL);

         CREATE TABLE IF NOT EXISTS edge
            (id_from INTEGER NOT NULL REFERENCES(node.id),
             id_to INTEGER NOT NULL REFERENCES(node.id),
             state INTEGER NOT NULL,
             UNIQUE PRIMARY KEY (id_from, id_to));

         CREATE TABLE IF NOT EXISTS provider
            (name TEXT NOT NULL UNIQUE PRIMARY KEY,
             feature_id INTEGER NOT NULL REFERENCES(feature.name),
             file_id INTEGER NOT NULL REFERENCES(file.id));

         CREATE TABLE IF NOT EXISTS option
            (id INTEGER NOT NULL UNIQUE PRIMARY KEY,
             name TEXT NOT NULL,
             desc_yaml TEXT NOT NULL,
             value_yaml TEXT NOT NULL,
             file_id INTEGER NOT NULL REFERENCES(file.id))
         
         CREATE INDEX IF NOT EXISTS file_by_path ON file(path)
         CREATE INDEX IF NOT EXISTS feature_by_name ON feature(name)
         CREATE INDEX IF NOT EXISTS option_by_name ON option(name)

         ]])
    if ret ~= sqlite3.OK then 
        return nil, self:db_error()
    end
  
    return cachedb
end

function zef_cachedb:db_error()
    return string.format('cache database error: %s', self.db:errmsg())
end

function zef_cachedb:get_file_timestamp(path)
    local db = self.db
    local stmt = self.db:prepare([[
        SELECT timestamp FROM file WHERE path = ?
    ]])
    local ret = stmt:bind_values(path)
    if ret ~= sqlite3.OK then
        return nil, self:db_error()
    end

    local timestamp
    for row in stmt:nrows() do
        timestamp = row.timestamp
    end

    return timestamp
end

function zef_cachedb:set_file_timestamp(path, timestamp)
    local db = self.db
    local filecount
    local stmt = db:prepare('SELECT COUNT(*) FROM file WHERE path = ?')
    local ret = stmt:bind_values(path)
    if ret ~= sqlite3.OK then
        return nil, self:db_error()
    end

    for x in db:urows(stmt) do 
        filecount = x
    end

    if not filecount then
        return nil, 'unexpected cache database error'
    end

    if filecount == 0 then
        stmt = db:prepare('INSERT INTO file (path, timestamp) VALUES (?, ?) ')
        ret = stmt:bind_values(path, timestamp)
    else 
        stmt = db:prepare('UPDATE file SET timestamp = ? WHERE path = ?')
        ret = stmt:bind_values(timestamp, path)
    end

    if ret ~= sqlite3.OK then
        return nil, self:db_error()
    end

    ret = stmt:step()
    if ret ~= sqlite3.DONE then
        return nil, self:db_error()
    end

    return timestamp
end

function zef_cachedb:get_options()
    local db = self.db
    local stmt = db:prepare([[
        SELECT file.path AS source_file,
               option.name AS name
               option.desc_yaml AS desc,
               option.value_yaml AS value,
               node.timestamp AS timestamp
        INNER JOIN file ON file.id = option.file_id
        LEFT JOIN node ON node.type = 'option' AND node.ref_id = option.id
    ]])

    
    local opts = {}
    local ret
    ret = stmt:step()
    while ret == sqlite3.ROW do
        local sqlopt = stmt:get_named_values()
        local retd, yamld = pcall(function() return lyaml.load(sqlopt.desc) end)
        local retv, yamlv = pcall(function() return lyaml.load(sqlopt.value) end)
        if not retv or not retd then
            return nil, string.format('error while parsing YAML from cachedb: `%s`',
                retd and yamld or yamlv)
        end

        local opt =
            { name = sqlopt.name, file = sqlopt.source_file,
              desc = yamld, value = yamlv, timestamp = sqlopt.timestamp }
            
        table.insert(opts, opt)
        ret = stmt:step()
    end 
end

function zef_cachedb:set_option(name, val)

end

return zef_cachedb

