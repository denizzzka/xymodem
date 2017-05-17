module xymodem.ymodem;

alias ReadCallback = ubyte[] function() pure nothrow @safe;
alias SendCallback = void function(ubyte[]);
alias TimeOutCallback = void function(ubyte msec);

void yModemSend
(
	alias readCallback, // : ReadCallback,
	alias sendCallback, // = SendCallback
	alias timeOutCallback, // = TimeOutCallback
)
(
	in string filename,
	size_t size
)
{
	// TODO: check filename for valid YMODEM symbols

	size_t blockNum;

	//~ ubyte[] recv = readCallback;
}

/// Protocol characters
private enum Control: ubyte
{
    SOH = 0x01, /// Start Of Header
    STX = 0x02, /// Start Of Text (used like SOH but means 1024 block size)
    EOT = 0x04, /// End Of Transmission
    ACK = 0x06, /// ACKnowlege
    NAK = 0x15, /// Negative AcKnowlege
    CAN = 0x18, /// CANcel character
    CPMEOF = 0x1A, /// "^Z"
    ST_C = 'C' /// Start XMODEM/CRC block
}

// Some useful constants
private immutable MAXERRORS = 10;
immutable BLOCK_TIMEOUT = 1000;
immutable REQUEST_TIMEOUT = 3000;
immutable WAIT_FOR_RECEIVER_TIMEOUT = 60_000;
immutable SEND_BLOCK_TIMEOUT = 10_000;

unittest
{
	ubyte[] readFromFile()
	{
		auto b = new ubyte[1024];

		return b;
	}

	void sendToLine(ubyte[]) {}

	void doTimeout(ubyte) {}

	yModemSend!(readFromFile, sendToLine, doTimeout)("unittest.bin", 2000);
}