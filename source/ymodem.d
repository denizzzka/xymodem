module xymodem.ymodem;

import xymodem.exception;
import std.conv: to;

alias ReadCallback = ubyte[] delegate();
alias RecvCallback = ubyte[] delegate();
alias SendCallback = bool delegate(const ubyte[] data); /// Returns: true if send was successful
alias TimeOutCallback = void delegate(ubyte msecs);

class YModemSender
{
    private const ReadCallback readData;
    private const RecvCallback recvData;
    private const SendCallback sendData;
    private const TimeOutCallback timeOutCallback;

    private ubyte currBlockNum;
    private size_t currByte;
    private bool isAborting;

    this
    (
        ReadCallback readCb,
        RecvCallback recvCb,
        SendCallback sendCb,
        TimeOutCallback timeoutCb
    )
    {
        readData = readCb;
        recvData = recvCb;
        sendData = sendCb;
        timeOutCallback = timeoutCb;
    }


    void send
    (
        in string filename,
        in ubyte[] fileData
    )
    {
        /*
         * TODO: check filename for valid YMODEM symbols:
         * ASCIIZ string without '\'.
         * Systems that do not distinguish between upper and lower case
         * letters in filenames shall send the pathname in lower case only.
         */

        currBlockNum = 0;
        currByte = 0;
        ubyte errcnt;

        while(currByte < fileData.length)
        {
            waitFor([Control.ST_C]);

            bool sendSuccess;

            if(currBlockNum == 0)
            {
                sendSuccess = sendYModemHeaderBlock(filename, fileData.length);
            }
            else
            {
                const size_t remaining = fileData.length - currByte;
                const size_t blockSize = remaining > 1024 ? 1024 : remaining;

                sendSuccess = sendBlock(fileData[currByte .. currByte + blockSize]);

                if(sendSuccess)
                    currByte += blockSize;
            }

            if(!sendSuccess)
            {
                errcnt++;

                if(errcnt >= MAXERRORS)
                    throw new YModemException("Sender reached maximum errors count", __FILE__, __LINE__);

                continue;
            }
            else
            {
                errcnt = 0;
                currBlockNum++;
            }
        }
    }

    private bool sendYModemHeaderBlock(string filename, size_t filesize)
    {
        import std.conv: to;
        import std.string: toStringz;

        string blockContent = filename ~ ' ' ~ filesize.to!string;
        immutable(char)* stringz = blockContent.toStringz;
        ubyte* bytes = cast(ubyte*) stringz;

        return sendBlock(bytes[0 .. blockContent.length]);
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

    private void waitFor(in Control[] ctls)
    {
        Control recv = receiveContrloSymbol();

        foreach(c; ctls)
        {
            if(recv == c)
                return;
        }

        throw new YModemException("Received "~recv.to!string~", but expected "~ctls.to!string, __FILE__, __LINE__);
    }

    private Control receiveContrloSymbol()
    {
        ubyte[] r;
        size_t errcnt;

        while(true)
        {
            r = recvData();

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
private immutable ubyte MAXERRORS = 10;
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

    ubyte[] sended;

    bool sendToLine(const ubyte[] toSend)
    {
        sended ~= toSend;

        return true;
    }

    ubyte[] receiveFromLine()
    {
        ubyte[] b = [ 'C', 'C' ];

        return b;
    }

    void doTimeout(ubyte) {}

    auto sender = new YModemSender(
            &readFromFile,
            &receiveFromLine,
            &sendToLine,
            &doTimeout
        );

    import std.stdio: writeln;
    import std.digest.digest: toHexString;

    {
        sender.sendYModemHeaderBlock("bbcsched.txt", 6347);
        writeln(sended.toHexString());
        sended.length = 0;
    }

    sender.send("unittest.bin", [1, 2, 3, 4, 5]);
}
