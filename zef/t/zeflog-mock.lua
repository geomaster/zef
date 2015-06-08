zeflog_mock = { log = {}, ignore = true }

-- Levels:
--   0 - debug
--   1 - notice
--   2 - warning
--   3 - error
function zeflog_mock.set_level(level)
    -- noop
end

function zeflog_mock.message(level, msg)
    if not zeflog_mock.ignore then
        table.insert(zeflog_mock.log, { level = level, message = msg })
    end

    return msg
end

function zeflog_mock.debug(msg)
    return zeflog_mock.message(0, msg)
end

function zeflog_mock.notice(msg)
    return zeflog_mock.message(1, msg)
end

function zeflog_mock.warning(msg)
    return zeflog_mock.message(2, msg)
end

function zeflog_mock.err(msg)
    return zeflog_mock.message(3, msg)
end

function zeflog_mock.peek(as_string)
    if as_string then
        local buf = ''
        for _, v in ipairs(zeflog_mock.log) do
            buf = buf .. v .. '\n'
        end

        return buf
    else 
        return zeflog_mock.log
    end
end

function zeflog_mock.purge()
    zeflog_mock.log = {}
end

function zeflog_mock.has_item(item)
    for _, v in ipairs(zeflog_mock.peek()) do
        if string.find(v.message:gsub("^%s*(.-)%s*$", "%1"), item) then
            return true
        end
    end
    return false
end

function zeflog_mock.get(as_string)
    local buf = zeflog_mock.peek(as_string)
    zeflog_mock.purge()

    return buf
end

function zeflog_mock.enable(disable)
    zeflog_mock.ignore = disable
end

return zeflog_mock
