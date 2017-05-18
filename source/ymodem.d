module xymodem.ymodem;

import xymodem.exception;

alias ReadCallback = ubyte[] delegate();
alias SendCallback = void delegate(ubyte[] data);
alias TimeOutCallback = void delegate(ubyte msecs);

class YModemSender
{
    private const ReadCallback readData;
    private const SendCallback sendData;
    private const TimeOutCallback timeOutCallback;

    private size_t currBlockNum;
    private size_t currByte;
    private bool isAborting;

    this
    (
        ReadCallback readCb,
        SendCallback sendCb,
        TimeOutCallback timeoutCb
    )
    {
        readData = readCb;
        sendData = sendCb;
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
        currByte = 0;

        ubyte[] recv = readData();

        if(recv == [cast(ubyte) Control.ST_C])
        {
            // ready to send block
        }
    }

    private void sendBlock(in ubyte[] data)
    {
    }

    private Control receive()
    {
        ubyte[] r;
        size_t errcnt;

        while(true)
        {
            r = readData();

            if(r.length != 0)
            {
                break;
            }
            else
            {
                errcnt++;

                if(errcnt >= MAXERRORS)
                    throw new YModemException("Too many errors on receive", __FILE__, __LINE__);
            }
        }

        return cast(Control) r[$-1];
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
