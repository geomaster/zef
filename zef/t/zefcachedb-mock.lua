local zefcachedb_mock = { fail_on_open = false }

function zefcachedb_mock.open(proj)
    if zefcachedb_mock.fail_on_open then
        return nil, 'Requested orchestrated error on zef_cachedb.open()'
    end
    return {}
end

return zefcachedb_mock
