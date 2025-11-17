# lua-io-reader

[![test](https://github.com/mah0x211/lua-io-reader/actions/workflows/test.yml/badge.svg)](https://github.com/mah0x211/lua-io-reader/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/mah0x211/lua-io-reader/branch/master/graph/badge.svg)](https://codecov.io/gh/mah0x211/lua-io-reader)

A reader that reads data from a file or file descriptor.


## Installation

```
luarocks install io-reader
```


## Error Handling

the following functions return the `error` object created by https://github.com/mah0x211/lua-errno module.


## r, err = io.reader.new( f [, sec] )

create a new reader instance that reads data from a file or file descriptor.

**NOTE**

this function uses the `dup` system call internally to duplicate a file descriptor. thus, data can be read from a file even if the passed file is closed.

**Parameters**

- `f:file*|string|integer`: file, filename or file descriptor.
- `sec:number`: timeout seconds. if `nil` or `<0`, wait forever.

**Returns**

- `r:reader`: a reader instance.
- `err:any`: error message.


**Example**

```lua
local dump = require('dump')
local reader = require('io.reader')
local f = assert(io.tmpfile())
f:write('hello\r\nio\r\nreader\nworld!')
f:seek('set')
local r = reader.new(f)

-- it can read data from a file even if passed a file has been closed.
-- cause it duplicates the file descriptor by using `dup` system call internally.
f:close()

print(dump({
    r:read(4), -- read 4 bytes
    r:read('L'), -- read a line with delimiter
    r:read(), -- read a line without delimiter as default 'l'
    r:read('a'), -- read all data from the file
}))
-- {
--     [1] = "hell",
--     [2] = "o\13\
-- ",
--     [3] = "io",
--     [4] = "reader\
-- world!"
-- }
```


## fd = reader:getfd()

get the file descriptor of the reader. if the reader is closed, returns negative value.

**Returns**

- `fd:integer`: file descriptor.


## reader:set_timeout( [sec] )

set the timeout seconds.

**Parameters**

- `sec:number`: timeout seconds. if `nil` or `<0`, wait forever.


## ok, err = reader:close()

close the reader.

**Returns**

- `ok:boolean`: `true` if succeeded.
- `err:any`: error message.


## s, err, timeout = reader:readn( n )

read `n` bytes from the reader.

**Parameters**

- `n:integer`: number of bytes to read.  
    `n` must be greater than or equal to `0`. if `n` is `0`, returns an empty string.

**Returns**

- `s:string`: read data.
- `err:any`: error message.
- `timeout:boolean`: `true` if timed out.


## s, err, timeout = reader:readall()

read all data from the reader.

**Returns**

- `s:string`: read data.
- `err:any`: error message.
- `timeout:boolean`: `true` if timed out.


## s, err, timeout = reader:readline( [with_newline] )

read a line from the reader.

**Parameters**

- `with_newline:boolean`: if `true`, includes the newline character in the returned line. (default: `false`)

**Returns**

- `s:string`: read line.
- `err:any`: error message.
- `timeout:boolean`: `true` if timed out.


## s, err, timeout = reader:read( [fmt] )

read data from the reader.
 
The optional `fmt` parameter controls how data is read.
If omitted, the default is `*l` (read one line without the newline).

- When `fmt` is an integer, the call is equivalent to `reader:readn(fmt)`.
- When it is a string, the following formats are recognized (the `*` prefix may be omitted):
    - `*l`: equivalent to `reader:readline()` (without the newline).
    - `*L`: equivalent to `reader:readline(true)` (with the newline).
    - `*a`: equivalent to `reader:readall()`.


## iter = reader:lines()

returns an iterator that reads a line from the reader.

**Returns**

- `iter:function`: iterator function that returns a line or remaining data, or `nil` if reaches the end of the file.

**Example**

```lua
local reader = require('io.reader')
local f = assert(io.tmpfile())
f:write('hello\r\nio\r\nreader\nworld!')
f:seek('set')

local r = reader.new(f)
for line in r:lines() do
    print(line)
end
-- hello
-- io
-- reader
-- world!
```

