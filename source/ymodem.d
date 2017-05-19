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
        in ubyte[] fileData
    )
    {
        /*
         * TODO: check filename for valid YMODEM symbols:
         * ASCIIZ string without '\'.
         * Systems that do not distinguish between upper and lower case
         * letters in filenames shall send the pathname in lower case only.
         */

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

                size_t blockSize;

                if(remaining <= 128)
                    blockSize = 128;
                else
                    blockSize = 1024;

                currEndByte = currByte + (remaining > blockSize ? blockSize : remaining);
                const sliceToSend = fileData[currByte .. currEndByte];

                if(remaining == blockSize)
                {
                    sendBlock(sliceToSend, ACK);
                }
                else
                {
                    // need pading
                    auto paddingBuff = new ubyte[](cast(ubyte) Control.CPMEOF);
                    paddingBuff.length = blockSize - remaining;

                    sendBlock(sliceToSend ~ paddingBuff, ACK);
                }

                currByte = currEndByte;
            }

            currBlockNum++;
        }

        // End of file transfer
        sendBlock([cast(ubyte) Control.EOT], ACK);
    }

    private void sendYModemHeaderBlock(string filename, size_t filesize)
    {
        import std.conv: to;
        import std.string: toStringz;

        string blockContent = filename ~ ' ' ~ filesize.to!string;
        immutable(char)* stringz = blockContent.toStringz;
        ubyte* bytes = cast(ubyte*) stringz;

        sendBlock(bytes[0 .. blockContent.length], ACK);
    }

    private void sendBlock(in ubyte[] blockData, in Control[] validAnswers)
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

    {
        sender.currBlockNum = 0;
        sender.sendYModemHeaderBlock("bbcsched.txt", 6347);
        assert(sended.toHexString == "0200FF62626373636865642E747874203633343792F8");
        sended.length = 0;
    }
}
