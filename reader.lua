--
-- Copyright (C) 2024 Masatoshi Fukunaga
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
local find = string.find
local match = string.match
local sub = string.sub
local type = type
local isfile = require('io.isfile')
local fopen = require('io.fopen')
local fileno = require('io.fileno')
local readn = require('io.readn')
local wait_readable = require('gpoll').wait_readable
-- constants
local EINVAL = require('errno').EINVAL
local EBADF = require('errno').EBADF

--- @class io.reader
--- @field private fd integer
--- @field private file? file*
--- @field private waitsec? number
--- @field private buf string
local Reader = {}

--- init
--- @param fd integer
--- @param f file*
--- @param sec number?
--- @return io.reader
function Reader:init(fd, f, sec)
    self.fd = fd
    self.file = f
    self.buf = ''
    self.waitsec = sec
    return self
end

--- getfd
--- @return integer fd
function Reader:getfd()
    return self.fd
end

--- set_timeout
--- @param sec? number
function Reader:set_timeout(sec)
    assert(sec == nil or type(sec) == 'number', 'sec must be number or nil')
    self.waitsec = sec
end

--- close
--- @return boolean ok
--- @return any err
function Reader:close()
    local f = self.file
    if f then
        self.file = nil
        self.fd = self.fd == 0 and -1 or -self.fd
        return f:close()
    end
    return true
end

--- read
--- @param fd integer
--- @param count integer
--- @param sec number?
--- @return string? data
--- @return any err
--- @return boolean? timeout
local function read(fd, count, sec)
    local data, err, again = readn(fd, count)
    if again then
        fd, err, again = wait_readable(fd, sec)
        if not fd then
            return nil, err, again
        end
        return readn(fd, count)
    end
    return data, err
end

--- read
--- @param fmt string|integer?
--- @return string? data
--- @return any err
--- @return boolean? timeout
function Reader:read(fmt)
    assert(fmt == nil or type(fmt) == 'number' or type(fmt) == 'string',
           'fmt must be integer, string or nil')

    if self.fd < 0 then
        return nil, EBADF:new('reader is closed')
    end

    local t = type(fmt)
    if t == 'number' then
        -- read n bytes from the file
        local n = fmt
        if n < 0 then
            error('invalid argument #1 (negative number)')
        elseif n == 0 then
            return nil
        end

        local buf = self.buf
        local len = #buf
        if len < n then
            local data, err, timeout = read(self.fd, n - len, self.waitsec)
            if not data then
                return nil, err, timeout
            end
            -- append data to the buffer
            buf = buf .. data
        end

        -- return the specified bytes from the buffer
        self.buf = sub(buf, n + 1)
        return sub(buf, 1, n)
    end

    -- check the format
    local spec = 'l'
    if fmt then
        spec = match(fmt, '^%*?([alL])$')
        if not spec then
            error("fmt must be string as 'a', 'l' or 'L'")
        end
    end

    if spec == 'a' then
        local buf = self.buf
        if #buf > 0 then
            -- return all data from the buffer
            self.buf = ''
            return buf
        end
        -- read all data from the file
        return read(self.fd, nil, self.waitsec)
    end

    local buf = self.buf
    local head, tail = find(buf, '\r?\n', 1)
    while not head do
        -- need to read more data
        local data, err, timeout = read(self.fd, nil, self.waitsec)
        if not data then
            return nil, err, timeout
        end
        buf = buf .. data
        self.buf = buf

        -- find the delimiter
        head, tail = find(buf, '\r?\n', 1)
    end

    if spec == 'l' then
        -- line without delimiter
        local line = sub(buf, 1, head - 1)
        self.buf = sub(buf, tail + 1)
        return line
    end

    -- line with delimiter
    local line = sub(buf, 1, tail)
    self.buf = sub(buf, tail + 1)
    return line
end

--- lines
--- @return function
function Reader:lines()
    return function()
        local line = self:read('*l')
        if not line and self.buf ~= '' then
            line = self.buf
            self.buf = ''
        end
        return line
    end
end

Reader = require('metamodule').new(Reader)

--- new
--- @param file string|integer|file*
--- @param sec number?
--- @return io.reader? rdr
--- @return any err
local function new(file, sec)
    local t = type(file)
    local f, err
    if isfile(file) then
        -- duplicate the file handle
        f, err = fopen(fileno(file), 'r')
    elseif t == 'string' or t == 'number' then
        -- open the file
        f, err = fopen(file, 'r')
    else
        return nil, EINVAL:new(
                   'FILE*, pathname or file descriptor expected, got ' .. t)
    end

    if not f then
        return nil, err
    end

    assert(sec == nil or type(sec) == 'number', 'sec must be number or nil')
    return Reader(fileno(f), f, sec)
end

return {
    new = new,
}
