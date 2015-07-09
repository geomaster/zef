local zef_cachedb = {}
local sqlite3 = require('lsqlite3')
local lyaml = require('lyaml')

local CacheDBFilename = '.Zefcache'

function zef_cachedb.open(proj, filename)
    local db, err = sqlite3.open(CacheDBFilename)
    filename = filename or CacheDBFilename
    local cachedb = { db = db }
    if not db then 
        return nil, string.format(
            'could not read/create database `%s`: %s', CacheDBFilename, err)
    end

    local ret = db:exec([[
          -- Denotes a file Zef knows about. last_visit 
          -- stores the timestamp telling the time this
          -- file was last visited by the build system
          -- i.e. it was checked for changes and all
          -- dependent nodes were marked as dirty.
          CREATE TABLE IF NOT EXISTS file
            (id INTEGER NOT NULL UNIQUE PRIMARY KEY,
             path TEXT NOT NULL,
             last_visited INTEGER)

          -- Denotes a possible build target Zef knows about.
          -- parent_id records the name of the target which
          -- emitted the rule for this one, or NULL if the
          -- target was explicit in the rules file. If the
          -- target refers to a file, its file_id field 
          -- records an index into the file table, and its
          -- name field is NULL. If not, file_id is NULL and
          -- the name column denotes the name of this `phony`
          -- target. is_meta denotes if the target is a meta
          -- target or an ordinary one. Meta targets can add
          -- new targets to the build system but can not have
          -- side effects; they are evaluated first to get
          -- a complete list of all buildable nodes in the 
          -- system.
          CREATE TABLE IF NOT EXISTS target
            (id INTEGER NOT NULL UNIQUE PRIMARY KEY,
             name TEXT,
             parent_id INTEGER REFERENCES (target.id),
             rule BLOB,
             is_meta INTEGER CHECK(is_meta in (0, 1)) NOT NULL,
             file_id INTEGER REFERENCES (file.id));

         -- Denotes features Zef knows about.
         CREATE TABLE IF NOT EXISTS feature
            (id INTEGER NOT NULL UNIQUE PRIMARY KEY,
             name TEXT NOT NULL UNIQUE PRIMARY KEY);
         
         -- Denotes a single node in the DAG that Zef
         -- operates on. The node itself can be either a 
         -- feature, an option, or a target. This is 
         -- denoted as the value of the type column, 
         -- where:
         --    1 means the node is a feature,
         --    2 means the node is an option and
         --    3 means the node is a target.
         --
         -- ref_id is either a target.id, feature.id or
         -- option.id, depending on the value of the 
         -- type field. is_dirty tells us whether or 
         -- not the node is marked as dirty (meaning 
         -- that one of its dependencies was marked as
         -- dirty) and needs rebuilding.
         CREATE TABLE IF NOT EXISTS node
            (id INTEGER NOT NULL UNIQUE PRIMARY KEY,
             type INTEGER CHECK(type in (1, 2, 3)) NOT NULL,
             is_dirty INTEGER CHECK(is_dirty in (0, 1)) NOT NULL,
             ref_id INTEGER NOT NULL);

         -- Denotes an edge from one node to another 
         -- in the DAG that Zef operates on. 
         CREATE TABLE IF NOT EXISTS edge
            (id_from INTEGER NOT NULL REFERENCES(node.id),
             id_to INTEGER NOT NULL REFERENCES(node.id),
             UNIQUE PRIMARY KEY (id_from, id_to));

         -- Denotes a feature provider that Zef operates
         -- on. feature_id and file_id are what you 
         -- think they are.
         CREATE TABLE IF NOT EXISTS provider
            (name TEXT NOT NULL UNIQUE PRIMARY KEY,
             feature_id INTEGER NOT NULL REFERENCES(feature.name),
             file_id INTEGER NOT NULL REFERENCES(file.id));

         -- Denotes an option in the build system that
         -- Zef knows about. name is the option name
         -- as denoted in the Zef.yaml file, while 
         -- desc_yaml is the YAML representation of the
         -- option description and value_yaml is the
         -- YAML representation of the option value, as
         -- read from the Zefconfig file. 
         --
         -- type is one of
         --     1 - string
         --     2 - path
         --     3 - number
         --     4 - enum
         --     5 - boolean
         --
         -- is_tuple is 0 if the option isn't a tuple, 1
         -- otherwise. 
         -- 
         -- default denotes the default value to assume 
         -- when no value is given. When no value is 
         -- given and there is not a default value set,
         -- this option will trigger an error if the build
         -- rules attempt to access its value. value 
         -- denotes the current value the option has. Both
         -- default and value fields are in YAML notation.
         -- If the type is an enum (4), values will be a 
         -- YAML string of an array of possible values.
         --
         -- Sorry, the design is not completely following
         -- the principles, but should work fine.
         CREATE TABLE IF NOT EXISTS option
            (id INTEGER NOT NULL UNIQUE PRIMARY KEY,
             name TEXT UNIQUE NOT NULL,
             description TEXT,
             type INTEGER CHECK(type in (1, 2, 3, 4, 5)) NOT NULL,
             is_tuple INTEGER CHECK(is_tuple in (0, 1)) NOT NULL,
             values TEXT,
             default TEXT,
             value TEXT)
         
         CREATE INDEX IF NOT EXISTS file_by_path ON file(path)
         CREATE INDEX IF NOT EXISTS feature_by_name ON feature(name)
         CREATE INDEX IF NOT EXISTS option_by_name ON option(name)
         CREATE INDEX IF NOT EXISTS edge_by_from ON edge(id_from)
         CREATE INDEX IF NOT EXISTS edge_by_to ON edge(id_to)
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
        SELECT last_visit FROM file WHERE path = ?
    ]])
    local ret = stmt:bind_values(path)
    if ret ~= sqlite3.OK then
        return nil, self:db_error()
    end

    local timestamp
    for row in stmt:nrows() do
        timestamp = row.last_visit
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
        stmt = db:prepare('INSERT INTO file (path, last_visit) VALUES (?, ?) ')
        ret = stmt:bind_values(path, timestamp)
    else 
        stmt = db:prepare('UPDATE file SET last_visit = ? WHERE path = ?')
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
        SELECT name AS name
               desc_yaml AS desc,
               value_yaml AS value,
        FROM option
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
            { name = sqlopt.name, desc = yamld, value = yamlv }
            
        table.insert(opts, opt)
        ret = stmt:step()
    end 
end

function zef_cachedb:set_option(name, val)

end

return zef_cachedb

