module xymodem.exception;

import std.exception;

class YModemException : Exception
{
    this(string msg, string file, size_t line) pure @safe
    {
        super(msg, file, line);
    }
}

package class RecvException : YModemException
{
    this(string msg, string file, size_t line) pure @safe
    {
        super(msg, file, line);
    }
}
