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
local open = io.open
local isfile = require('io.isfile')
local fopen = require('io.fopen')
local fileno = require('io.fileno')
local new_errno = require('errno').new
local EINVAL = require('errno').EINVAL
local readn = require('io.readn')
local wait_readable = require('gpoll').wait_readable

--- @class io.reader
--- @field private file file*
--- @field private fd integer
--- @field private buf string
local Reader = {}

--- init
--- @param f file*
--- @return io.reader
function Reader:init(f)
    self.file = f
    self.fd = fileno(f)
    self.buf = ''
    return self
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
--- wait_readable
--- @param fmt string|integer?
--- @param sec number?
--- @return string? data
--- @return any err
--- @return boolean? timeout
function Reader:read(fmt, sec)
    assert(fmt == nil or type(fmt) == 'number' or type(fmt) == 'string',
           'fmt must be integer, string or nil')
    assert(sec == nil or type(sec) == 'number', 'sec must be number or nil')

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
            local data, err, timeout = read(self.fd, n - len, sec)
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
        return read(self.fd, nil, sec)
    end

    local buf = self.buf
    local head, tail = find(buf, '\r?\n', 1)
    while not head do
        -- need to read more data
        local data, err, timeout = read(self.fd, nil, sec)
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

Reader = require('metamodule').new(Reader)

--- new_with_fd
--- @param fd integer
--- @return io.reader rdr
--- @return any err
local function new_with_fd(fd)
    local f, err = fopen(fd, 'r')
    if not f then
        return nil, err
    end
    return Reader(f)
end

--- new_with_file
--- @param f file*
--- @return io.reader rdr
local function new_with_file(f)
    if not isfile(f) then
        return nil, EINVAL:new('FILE* expected, got ' .. type(f))
    end
    return Reader(f)
end

--- new
--- @param pathname string
--- @return io.reader? rdr
--- @return any err
local function new(pathname)
    local f, err, errno = open(pathname, 'r')
    if err then
        return nil, new_errno(errno, err)
    end
    return Reader(f)
end

return {
    new = new,
    new_with_file = new_with_file,
    new_with_fd = new_with_fd,
}