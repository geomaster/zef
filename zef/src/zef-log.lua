local zef_log = { level = 1 }

-- Levels:
--   0 - debug
--   1 - notice
--   2 - warning
--   3 - error
function zef_log.set_level(level)
    zef_log.level = level
end

function zef_log.message(level, msg)
    if zef_log.level > level then
        return
    end

    io.write(msg, '\n')
    return msg
end

function zef_log.debug(msg)
    return zef_log.message(0, msg)
end

function zef_log.notice(msg)
    return zef_log.message(1, msg)
end

function zef_log.warning(msg)
    return zef_log.message(2, msg)
end

function zef_log.err(msg)
    return zef_log.message(3, msg)
end

return zef_log
