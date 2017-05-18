module xymodem.ymodem;

import xymodem.exception;

alias ReadCallback = ubyte[] delegate();
alias SendCallback = bool delegate(const ubyte[] data); /// Returns: true if send was successful
alias TimeOutCallback = void delegate(ubyte msecs);

class YModemSender
{
    private const ReadCallback readData;
    private const SendCallback sendData;
    private const TimeOutCallback timeOutCallback;

    private ubyte currBlockNum;
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
        in ubyte[] fileData
    )
    {
        // TODO: check filename for valid YMODEM symbols

        currBlockNum = 0;
        currByte = 0;

        Control recv = receive();

        const size_t remaining = fileData.length - currByte;
        const size_t blockSize = remaining > 1024 ? 1024 : remaining;

        if(recv == Control.ST_C)
        {
            sendBlock(fileData[currByte .. currByte + blockSize]);
        }
    }

    private bool sendBlock(in ubyte[] blockData)
    {
        import xymodem.crc: crc16;
        import std.bitmanip: nativeToLittleEndian;

        const ubyte[3] header = [
            cast(ubyte) Control.STX,
            currBlockNum,
            0xFF - currBlockNum
        ];

        ushort crc;
        crc16(crc, blockData);

        ubyte[2] orderedCRC = nativeToLittleEndian(crc);

        return
            sendData(header) &&
            sendData(blockData) &&
            sendData(orderedCRC);
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

    bool sendToLine(const ubyte[])
    {
        return true;
    }

    void doTimeout(ubyte) {}

    auto sender = new YModemSender(&readFromFile, &sendToLine, &doTimeout);

    sender.send("unittest.bin", [1, 2, 3, 4, 5]);
}
