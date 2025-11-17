require('luacov')
local testcase = require('testcase')
local assert = require('assert')
local fileno = require('io.fileno')
local reader = require('io.reader')
local pipe = require('os.pipe')
local gettime = require('time.clock').gettime

local TEST_TXT = 'test.txt'

function testcase.before_all()
    local f = assert(io.open(TEST_TXT, 'w'))
    f:write('hello world')
    f:close()
end

function testcase.after_all()
    os.remove(TEST_TXT)
end

function testcase.new()
    local f = assert(io.tmpfile())
    local fd = fileno(f)

    -- test that create a new reader from file
    local r, err = reader.new(f)
    assert.is_nil(err)
    assert.match(r, '^io.reader: ', false)

    -- test that create a new reader from file with timeout seconds
    r, err = reader.new(f, 1)
    assert.is_nil(err)
    assert.match(r, '^io.reader: ', false)

    -- test that create a new reader from filename
    r, err = reader.new(TEST_TXT)
    assert.is_nil(err)
    assert.match(r, '^io.reader: ', false)

    -- test that return err if file not found
    r, err = reader.new('notfound.txt')
    assert.is_nil(r)
    assert.match(err, 'ENOENT')

    -- test that create a new reader from file descriptor
    r, err = reader.new(fd)
    assert.is_nil(err)
    assert.match(r, '^io.reader: ', false)

    -- test that create a new reader from pipe file descriptor
    local pr, _, perr = pipe(true)
    assert(perr == nil, perr)
    r, err = reader.new(pr:fd())
    assert.is_nil(err)
    assert.match(r, '^io.reader: ', false)

    -- test that return err if file descriptor is invalid
    r, err = reader.new(-1)
    assert.is_nil(r)
    assert.match(err, 'EBADF')

    -- test that return err if invalid type of argument
    r, err = reader.new(true)
    assert.is_nil(r)
    assert.match(err, 'FILE*, pathname or file descriptor expected, got boolean')

    -- test that throws an error if invalid sec argument
    err = assert.throws(reader.new, f, true)
    assert.match(err, 'sec must be number or nil')
end

function testcase.getfd()
    -- test that get file descriptor and it is duplicated from file
    local f = assert(io.tmpfile())
    local r = assert(reader.new(f))
    assert.is_uint(r:getfd())
    assert.not_equal(r:getfd(), fileno(f))

    -- test that get file descriptor and it is duplicated from file descriptor
    local pr, _, err = pipe(true)
    assert(err == nil, err)
    r = assert(reader.new(pr:fd()))
    assert.is_uint(r:getfd())
    assert.not_equal(r:getfd(), pr:fd())
end

function testcase.read_with_format_string()
    local f = assert(io.tmpfile())
    local r = assert(reader.new(f))
    f:write('foo\nbar\r\nbaz\r\nqux')
    f:seek('set')

    -- test that read a line without delimiter as default
    local s, err, again = r:read()
    assert.is_nil(err)
    assert.is_nil(again)
    assert.equal(s, 'foo')

    -- test that read a line with delimiter
    s, err, again = r:read('L')
    assert.is_nil(err)
    assert.is_nil(again)
    assert.equal(s, 'bar\r\n')

    -- test that read all remaining bytes
    s, err, again = r:read('a')
    assert.is_nil(err)
    assert.is_nil(again)
    assert.equal(s, 'baz\r\nqux')

    -- test that return nil if eof
    s, err, again = r:read()
    assert.is_nil(s)
    assert.is_nil(err)
    assert.is_nil(again)

    -- test that throws an error if invalid type of format
    err = assert.throws(r.read, r, true)
    assert.match(err, "fmt must be integer, string or nil")

    -- test that throws an error if invalid format
    err = assert.throws(r.read, r, 'x')
    assert.match(err, "fmt must be string as 'a', 'l' or 'L'")
end

function testcase.read_nbyte()
    local f = assert(io.tmpfile())
    local r = assert(reader.new(f))
    f:write('foo\nbar\r\nbaz\r\nqux')
    f:seek('set')

    -- test that read 5 bytes
    local s, err, again = r:read(5)
    assert.is_nil(err)
    assert.is_nil(again)
    assert.equal(s, 'foo\nb')

    -- test that return nil if read 0 byte
    s, err, again = r:read(0)
    assert.is_nil(s)
    assert.is_nil(err)
    assert.is_nil(again)

    -- test that throws an error if specified negative number
    err = assert.throws(r.read, r, -1)
    assert.match(err, 'negative number')
end

function testcase.read_with_timeout()
    local pr, pw, perr = pipe(true)
    assert(perr == nil, perr)

    -- test that read timeout after 0.5 second
    local r = assert(reader.new(pr:fd(), .5))
    local t = gettime()
    local s, err, again = r:read()
    t = gettime() - t
    assert.is_nil(err)
    assert.is_nil(s)
    assert.is_true(again)
    assert.is_true(t >= .5 and t < .6)

    -- test change timeout to 0.1 second
    r:set_timeout(.1)
    t = gettime()
    s, err, again = r:read()
    t = gettime() - t
    assert.is_nil(err)
    assert.is_nil(s)
    assert.is_true(again)
    assert.is_true(t >= .1 and t < .2)

    -- test that read line from pipe
    pw:write('hello\nio-reader\nworld!\n')
    s, err, again = r:read()
    assert.is_nil(err)
    assert.is_nil(again)
    assert.equal(s, 'hello')

    -- test that read line from pipe even if peer of pipe is closed
    pw:close()
    s, err, again = r:read()
    assert.is_nil(err)
    assert.is_nil(again)
    assert.equal(s, 'io-reader')

    -- test that read line from pipe even if pipe is closed
    pr:close()
    s, err, again = r:read()
    assert.is_nil(err)
    assert.is_nil(again)
    assert.equal(s, 'world!')

    -- test that return nil if eof
    s, err, again = r:read()
    assert.is_nil(s)
    assert.is_nil(err)
    assert.is_nil(again)

    -- test that throws an error if invalid sec argument
    err = assert.throws(r.set_timeout, r, true)
    assert.match(err, 'sec must be number or nil')
end

function testcase.lines()
    local f = assert(io.tmpfile())
    local r = assert(reader.new(f))
    f:write('foo\nbar\r\nbaz\r\nqux')
    f:seek('set')

    -- test that read each line
    local lines = {
        'foo',
        'bar',
        'baz',
        'qux',
    }
    for line in r:lines() do
        assert.equal(line, table.remove(lines, 1))
    end
    assert.equal(lines, {})
end

function testcase.close()
    local f = assert(io.tmpfile())
    local r = assert(reader.new(f))

    -- test that close the file associated
    local ok, err = r:close()
    assert.is_nil(err)
    assert.is_true(ok)

    -- test that close can be called multiple times
    ok, err = r:close()
    assert.is_nil(err)
    assert.is_true(ok)

    -- test that read methods return error if reader is closed
    ok, err = r:read()
    assert.match(err, 'EBADF')
    assert.is_nil(ok)

    local data
    data, err = r:readn(10)
    assert.is_nil(data)
    assert.match(err, 'EBADF')

    data, err = r:readall()
    assert.is_nil(data)
    assert.match(err, 'EBADF')

    data, err = r:readline()
    assert.is_nil(data)
    assert.match(err, 'EBADF')
end

function testcase.readn_with_remaining_buffer()
    local f = assert(io.tmpfile())
    local r = assert(reader.new(f))

    -- Write data and create a reader with data already in buffer
    f:write('hello world')
    f:seek('set')

    -- Read partial data to leave some in buffer
    local data = r:readn(5)
    assert.equal(data, 'hello')

    -- Close the file to trigger EOF path
    f:close()

    -- Try to read more than remaining - should return what's left in buffer
    local err
    data, err = r:readn(20)
    assert.equal(data, ' world')
    assert.is_nil(err)
end

function testcase.readall_with_buffer()
    local f = assert(io.tmpfile())
    local r = assert(reader.new(f))

    -- Create some buffer content
    f:write('buffered')
    f:seek('set')

    -- Read partial to leave buffer
    local partial = r:readn(3)
    assert.equal(partial, 'buf')

    -- Read all remaining
    local data, err = r:readall()
    assert.equal(data, 'fered')
    assert.is_nil(err)
end

function testcase.readline_with_remaining_buffer()
    local f = assert(io.tmpfile())
    local r = assert(reader.new(f))

    -- Write data without newline and close to test buffer-only path
    f:write('remaining data')
    f:seek('set')

    -- Read partial to leave buffer
    local partial = r:readn(5)
    assert.equal(partial, 'remai')

    -- Close file to force buffer-only reading
    f:close()

    -- readline should return remaining buffer
    local data, err = r:readline()
    assert.equal(data, 'ning data')
    assert.is_nil(err)
end

function testcase.readline_with_delimiter()
    local f = assert(io.tmpfile())
    local r = assert(reader.new(f))
    f:write('line1\r\nline2\nline3')
    f:seek('set')

    -- test readline with delimiter (with_delimiter=true)
    local line = r:readline(true)
    assert.equal(line, 'line1\r\n')

    -- test readline without delimiter (default)
    line = r:readline()
    assert.equal(line, 'line2')

    -- test readline with 'L' format (with delimiter)
    line = r:read('L')
    assert.equal(line, 'line3')
end

function testcase.readn_large_data()
    local f = assert(io.tmpfile())
    local r = assert(reader.new(f))

    -- Write large data to test multiple reads
    local large_data = string.rep('x', 10000)
    f:write(large_data)
    f:seek('set')

    -- Read all data in chunks
    local data, err = r:readn(#large_data)
    assert.equal(data, large_data)
    assert.is_nil(err)
end

function testcase.readall_empty_file()
    local f = assert(io.tmpfile())
    local r = assert(reader.new(f))

    -- Don't write anything, create empty file
    f:seek('set')
    f:close()

    -- readall on empty file should return nil, nil, nil (EOF)
    local data, err, timeout = r:readall()
    assert.is_nil(data)
    assert.is_nil(err)
    assert.is_nil(timeout)
end

function testcase.buffer_handling_unified()
    local f = assert(io.tmpfile())
    local r = assert(reader.new(f))

    -- Test readn with buffer and EOF
    f:write('test data')
    f:seek('set')
    r:readn(4) -- 'test'
    f:close()
    local data = r:readn(10)
    assert.equal(data, ' data')

    -- Test readall with buffer
    f = assert(io.tmpfile())
    r = assert(reader.new(f))
    f:write('remaining data')
    f:seek('set')
    r:readn(5) -- 'remain'
    f:close()
    data = r:readall()
    assert.equal(data, 'ning data')

    -- Test lines with buffer
    f = assert(io.tmpfile())
    r = assert(reader.new(f))
    f:write('final line')
    f:seek('set')
    r:readn(3) -- 'fin'
    f:close()
    local iter = r:lines()
    local line = iter()
    assert.equal(line, 'al line')
    assert.is_nil(iter())
end

function testcase.read_nonblocking_with_retry()
    local pr, pw, perr = pipe(true)
    assert(perr == nil, perr)

    -- Create reader with short timeout to trigger wait_readable
    local r = assert(reader.new(pr:fd(), 0.1))

    -- Start reading from empty pipe (will block and trigger wait_readable)
    local data, err, timeout = r:read(10)

    -- Should timeout since no data is available
    assert.is_nil(data)
    assert.is_nil(err)
    assert.is_true(timeout)

    pr:close()
    pw:close()
end

function testcase.readn_after_wait_success()
    local pr, pw, perr = pipe(true)
    assert(perr == nil, perr)

    -- Create reader with timeout
    local r = assert(reader.new(pr:fd(), 2))

    -- Write data to pipe
    pw:write('hello world')
    pw:close()

    -- Read data - this may trigger wait_readable then succeed
    local data, err, timeout = r:readn(11)
    assert.equal(data, 'hello world')
    assert.is_nil(err)
    assert.is_nil(timeout)

    pr:close()
end

