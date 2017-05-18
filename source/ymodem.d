module xymodem.ymodem;

import xymodem.exception;

alias ReadCallback = ubyte[] delegate();
alias SendCallback = void delegate(ubyte[] data);
alias TimeOutCallback = void delegate(ubyte msecs);

class YModemSender
{
    private const ReadCallback readCallback;
    private const SendCallback sendCallback;
    private const TimeOutCallback timeOutCallback;

    private size_t currBlockNum;
    private bool isAborting;

    this
    (
        ReadCallback readCb,
        SendCallback sendCb,
        TimeOutCallback timeoutCb
    )
    {
        readCallback = readCb;
        sendCallback = sendCb;
        timeOutCallback = timeoutCb;
    }

    void send
    (
        in string filename,
        size_t size
    )
    {
        // TODO: check filename for valid YMODEM symbols

        currBlockNum = 0;
        ubyte[] recv = readCallback();

        if(recv == [cast(ubyte) Control.ST_C])
        {
            // ready to send block
        }
    }

    private void sendBlock(in ubyte[] data)
    {
    }
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

    auto sender = new YModemSender(&readFromFile, &sendToLine, &doTimeout);

    sender.send("unittest.bin", 2000);
}
