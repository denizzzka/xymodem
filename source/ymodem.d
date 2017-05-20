module xymodem.ymodem;

import xymodem.exception;
import std.conv: to;

alias RecvCallback = ubyte[] delegate(uint timeoutMsecs);
alias SendCallback = bool delegate(const ubyte[] data); /// Returns: true if send was successful

class YModemSender
{
    private const RecvCallback recvData;
    private const SendCallback sendData;

    private ubyte currBlockNum;
    private size_t currByte;
    private bool isAborting;

    private immutable Control[] ACK = [Control.ACK];

    /// Returns: bytes count for the current/latest file transfer
    size_t bytesSent() const
    {
        return currByte;
    }

    /// Abort current transfer
    void abort()
    {
        isAborting = true;
    }

    this
    (
        RecvCallback recvCb,
        SendCallback sendCb,
    )
    {
        recvData = recvCb;
        sendData = sendCb;
    }


    void send
    (
        in string filename,
        ubyte[] fileData
    )
    {
        /*
         * TODO: check filename for valid YMODEM symbols:
         * ASCIIZ string without '\'.
         * Systems that do not distinguish between upper and lower case
         * letters in filenames shall send the pathname in lower case only.
         */

        // TODO: abort transfer support

        // Waiting for initial C symbol
        while(true)
        {
            try
                receiveTheseControlSymbols([Control.ST_C], WAIT_FOR_RECEIVER_TIMEOUT);
            catch(RecvException e)
            {
                if(e.type == RecvErrType.NO_REPLY)
                    throw new YModemException("Receiver initial reply timeout", __FILE__, __LINE__);
                else
                    continue;
            }

            break;
        }

        currBlockNum = 0;
        currByte = 0;
        size_t currEndByte = 0;
        ubyte recvErrCnt;

        while(currByte < fileData.length)
        {
            if(currBlockNum == 0)
            {
                sendYModemHeaderBlock(filename, fileData.length);
            }
            else
            {
                const size_t remaining = fileData.length - currByte;
                const size_t blockSize =  remaining <= 128 ? 128 : 1024;
                currEndByte = currByte + (remaining > blockSize ? blockSize : remaining);

                ubyte[] sliceToSend = fileData[currByte .. currEndByte];

                sendBlock(blockSize, sliceToSend, ACK);

                currByte = currEndByte;
            }

            currBlockNum++;
        }

        // End of file transfer
        sendChunkWithConfirm([cast(ubyte) Control.EOT], ACK);
    }

    private void sendYModemHeaderBlock(string filename, size_t filesize)
    {
        import std.conv: to;
        import std.string: toStringz;

        string blockContent = filename ~ '\x00' ~ filesize.to!string;
        immutable(char)* stringz = blockContent.toStringz;
        ubyte* bytes = cast(ubyte*) stringz;

        const size_t blockSize =  blockContent.length <= 128 ? 128 : 1024;

        sendBlock(blockSize, bytes[0 .. blockContent.length], ACK);
    }

    /// Sends 128 or 1024 B block.
    /// blockData without padding!
    private void sendBlock(in size_t blockSize, ubyte[] blockData, in Control[] validAnswers)
    {
        import xymodem.crc: crc16;
        import std.bitmanip: nativeToBigEndian;

        const ubyte[3] header = [
            blockSize == 1024 ? cast(ubyte) Control.STX : cast(ubyte) Control.SOH,
            currBlockNum,
            0xFF - currBlockNum
        ];

        if(blockData.length != blockSize)
        {
            // need pading
            auto paddingBuff = new ubyte[](cast(ubyte) Control.CPMEOF);
            paddingBuff.length = blockSize - blockData.length;

            blockData ~= paddingBuff;
        }

        ushort crc;
        crc16(crc, blockData);
        ubyte[2] orderedCRC = nativeToBigEndian(crc);

        sendChunkWithConfirm(header~blockData~orderedCRC, validAnswers);
    }

    private void sendChunkWithConfirm(in ubyte[] data, in Control[] validAnswers) const
    {
        ubyte recvErrCnt;

        while(true)
        {
            sendChunk(data);

            if(recvConfirm(validAnswers, SEND_BLOCK_TIMEOUT))
            {
                break;
            }
            else
            {
                recvErrCnt++;

                if(recvErrCnt >= MAXERRORS)
                    throw new YModemException("Control symbol receiver reached maximum error count", __FILE__, __LINE__);
            }
        }
    }

    private void sendChunk(in ubyte[] data) const
    {
        ubyte errcnt = 0;

        while(true)
        {
            auto r = sendData(data);

            if(r)
            {
                break;
            }
            else
            {
                errcnt++;

                if(errcnt >= MAXERRORS)
                    throw new YModemException("Sender reached maximum error count", __FILE__, __LINE__);
            }
        }
    }

    private bool recvConfirm(in Control[] validAnswers, uint timeout) const
    {
        try
            receiveTheseControlSymbols(validAnswers, timeout);
        catch(RecvException e)
            return false;

        return true;
    }

    private Control receiveTheseControlSymbols(in Control[] ctls, uint timeout) const
    {
        const ubyte[] r = recvData(timeout);

        if(r.length == 0)
            throw new RecvException(RecvErrType.NO_REPLY, "Control symbol isn't received", __FILE__, __LINE__);

        if(r.length != 1)
            throw new RecvException(RecvErrType.MORE_THAN_1_OCTET, "Reply with more than 1 octet received", __FILE__, __LINE__);

        import std.algorithm.searching: canFind;

        Control b = cast(Control) r[0];

        if(canFind(ctls, b))
            return b;

        throw new RecvException(RecvErrType.NOT_EXPECTED, "Received "~r.to!string~", but expected "~ctls.to!string, __FILE__, __LINE__);
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
    CPMEOF = 0x1A, /// '^Z'
    ST_C = 'C' /// Start XMODEM/CRC block
}

// Some useful constants
private immutable ubyte MAXERRORS = 10;
private immutable WAIT_FOR_RECEIVER_TIMEOUT = 60_000;
private immutable SEND_BLOCK_TIMEOUT = 10_000;

unittest
{
    {
        // Block CRC-16 creation check

        import std.conv: parse;
        import std.array: array;
        import std.range: chunks;
        import std.algorithm: map;
        import xymodem.crc;
        import std.bitmanip;

        immutable string textBlock = "01 08 f7 d7 85 78 59 20 01 d3 0d 19 96 57 55 71 2d e5 7d 52 16 b2 51 fe d3 72 7d 6c 3f 31 0f e1 ea 40 18 11 40 74 40 41 b4 22 c2 98 82 d8 70 34 45 8f a8 c7 ab 28 5d 05 24 89 ff f1 1b 27 62 41 4f 62 99 c1 64 bb b8 d1 df 65 d1 43 c1 f8 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 1a 42 47";

        const ubyte[] block = textBlock
            .chunks(3)
            .map!(twoDigits => twoDigits.parse!ubyte(16))
            .array();

        ushort crc;
        crc16(crc, block[3 .. $-2]); // header and crc is stripped

        ubyte[2] validCRC = block[$-2 .. $];
        ubyte[2] ownCRC = nativeToBigEndian(crc);

        assert(ownCRC == validCRC);
    }

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

    ubyte[] receiveFromLine(uint timeout)
    {
        static isFirstBlock = true;

        ubyte[] b;

        if(isFirstBlock)
        {
            b = [ Control.ST_C ];
            isFirstBlock = false;
        }
        else
            b = [ Control.ACK ];

        return b;
    }

    auto sender = new YModemSender(
            &receiveFromLine,
            &sendToLine,
        );

    import std.digest.digest: toHexString;

    {
        sender.send("unittest.bin", [1, 2, 3, 4, 5]);
        sended.length = 0;
    }
}
