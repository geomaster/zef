filesystem_mock = { lfs = { parent = filesystem_mock }, io = { parent = filesystem_mock } }

function filesystem_mock.new(vfs)
    local fsmock = {
        vfs = vfs,
        io = { },
        lfs = { }
    }

    fsmock.__index = filesystem_mock
    fsmock.io.__index = filesystem_mock.io
    fsmock.lfs.__index = filesystem_mock.lfs

    setmetatable(fsmock, fsmock)
    setmetatable(fsmock.io, fsmock.io)
    setmetatable(fsmock.lfs, fsmock.lfs)

    fsmock.io.parent = fsmock
    fsmock.lfs.parent = fsmock

    return fsmock
end

function filesystem_mock:inject(globals)
    globals._saved_io = globals.io
    globals._saved_lfs = globals.lfs

    globals.io = self.io
    globals.lfs = self.lfs
    
    current_fsmock = self
end

function filesystem_mock:restore(globals)
    globals.io = globals._saved_io
    globals.lfs = globals._saved_lfs

    current_fsmock = nil
end

function filesystem_mock:vfs_walk(path, root)
    root = root or self.vfs

    local slash = path:find('/')
    local dironly = false

    -- if the path ends with a slash, we are looking for a directory
    if slash == path:len() then
        dironly = true
    end

    if not slash then 
        return root[path]
    elseif dironly then
        return type(root[path]) == 'table' and root[path] or nil
    else 
        local file, pre, post;
        pre = path:sub(1, slash - 1)
        post = path:sub(slash + 1)

        for k, v in pairs(root) do
            if root[k] == pre and type(root) == 'table' then
                return self:vfs_walk(post, root[k])
            end
        end

        return nil
    end
end

function filesystem_mock.lfs.attributes(filepath, aname)
    local f = current_fsmock:vfs_walk(filepath)
    if aname == 'mode' then
        return f and (type(f) == 'table' and 'directory' or 'file') or nil, 'fsmock: No such file.'
    else
        return nil, 'fsmock: aname not implemented'
    end
end

function filesystem_mock.io.open(filepath)
    local f = current_fsmock:vfs_walk(filepath)
    if not f then
        return nil, 'fsmock: No such file.'
    end

    if type(f) == 'table' then
        return nil, 'fsmock: Requested filepath refers to a directory'
    end

    if (current_fsmock.err_on_open and current_fsmock.err_on_open[filepath]) then
        return nil, 'fsmock: Requested orchestrated error on file open'
    end

    return {
        read = function(self, what) 
            if what ~= '*all' then
                return nil, 'fsmock: io.read with partial file read not implemented'
            end

            if self.err_on_read then
                return nil, 'fsmock: Requested orchestrated error on file read'
            end

            return self.contents
        end,

        contents = f,
        err_on_read = current_fsmock.err_on_read and current_fsmock.err_on_read[filepath] or nil
    }
end

return filesystem_mock
