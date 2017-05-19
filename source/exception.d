module xymodem.exception;

import std.exception;

class YModemException : Exception
{
    this(string msg, string file, size_t line) pure @safe
    {
        super(msg, file, line);
    }
}

package:

enum RecvErrType
{
    NOT_USED_TYPE,
    NO_REPLY,
    MORE_THAN_1_OCTET,
    NOT_EXPECTED
}

class RecvException : YModemException
{
    RecvErrType type;

    this(RecvErrType t, string msg, string file, size_t line) pure @safe
    {
        type = t;
        super(msg, file, line);
    }
}
