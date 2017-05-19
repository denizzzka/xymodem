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
                //~ const size_t blockSize =  remaining <= 128 ? 128 : 1024;
                const size_t blockSize =  1024;
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

        string blockContent = filename ~ ' ' ~ filesize.to!string;
        immutable(char)* stringz = blockContent.toStringz;
        ubyte* bytes = cast(ubyte*) stringz;
        //~ const size_t blockSize =  blockContent.length <= 128 ? 128 : 1024;
        const size_t blockSize =  1024;

        sendBlock(blockSize, bytes[0 .. blockContent.length], ACK);
    }

    /// Sends 128 or 1024 B block.
    /// Uses blockData without padding!
    private void sendBlock(in size_t blockSize, ubyte[] blockData, in Control[] validAnswers)
    {
        import xymodem.crc: crc16;
        import std.bitmanip: nativeToLittleEndian;

        const ubyte[3] header = [
            cast(ubyte) Control.STX,
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

        blockData = header ~ blockData;

        ushort crc;
        crc16(crc, blockData);

        ubyte[2] orderedCRC = nativeToLittleEndian(crc);

        sendChunkWithConfirm(blockData~orderedCRC, validAnswers);
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
        // CRC-16 routine check

        import std.conv: parse;
        import std.array: array;
        import std.range: chunks;
        import std.algorithm: map;
        import xymodem.crc;
        import std.bitmanip;

        immutable string validBlock = "02 06 f9 db 81 7c b2 a0 c9 01 a1 83 e8 12 97 19 8b e3 d1 52 e5 00 3e df 9d b8 14 21 67 9b f6 99 43 10 79 9d 21 6d de 64 24 fd 94 18 c2 38 b7 1c 07 18 9e 1c ae 4d c9 88 c8 1a 83 51 e9 75 6f c3 2b 3b 93 e8 0d 88 a5 39 ac bc 3d 18 82 a8 b8 b3 02 9f 52 c4 d7 12 a0 71 fc e9 6f fb 65 d3 7e 88 b1 30 16 6a f8 09 9e 5b f2 de 98 31 02 cd a0 ec 72 72 62 4f c2 11 a2 fc 4d ed 54 c0 4e 97 1f 00 a0 0f e2 73 ce d9 20 4c 34 74 ff d0 fa 36 87 67 ee c8 4e 88 05 a1 9a f7 f3 ab 67 66 d3 06 ec e3 07 3c dc 88 14 18 72 2e 70 a0 a2 01 f3 ea 96 42 29 d6 9a c3 fa 27 07 47 fd e3 17 88 9d 72 3e b9 ec 75 ba 0e e3 5c d7 8b 89 e7 44 f1 ce c5 a0 64 bf e4 ee 1f 0d 18 9f d2 a8 28 52 f7 af 18 f5 ba 10 53 48 0d 76 db f3 33 92 43 7f f4 cb 51 44 fb 95 65 75 6a f1 30 51 7a e3 fa cc 87 e1 a0 3a ed c7 4b dc 51 5c f6 48 42 01 b2 5b 89 f5 f7 5c 5b 01 14 1a 6d bb 47 0b 81 53 aa 89 e3 61 89 4b 62 d2 3f 3a b8 b7 53 b3 6c 3e 35 66 c0 9b 97 92 fe c9 24 06 f1 e6 c1 d9 14 e6 be ae ce 3b 13 a9 63 fa cc f1 d3 74 85 ad cb 0c 69 1c 9d f7 89 e9 e9 e2 3b af 23 b6 b4 0d b8 a7 bf 7e 8f 37 a6 ff 5d 6c 31 53 7e 4c cc df 24 b8 46 f5 f5 79 98 82 1a 3a 9c 5b ef 73 66 99 4c ca dd 71 d7 10 ca 8b 73 a7 a7 ce 23 a7 9d 24 f1 24 00 96 fa 84 db d3 67 52 ba 7a 0c 1b a0 53 40 dd b4 7a 21 5f 9b da a5 f5 a8 55 29 6d f5 a8 6c b5 25 7a 47 b0 7d e8 48 09 55 ed 87 a3 1f 2d df 7a b9 c7 ae 8c 8a d0 0b b2 3e b9 06 9c 5f a9 dd b0 43 cf 98 8a 63 1b c0 05 14 a8 fb a4 b5 5b 24 98 1f 98 91 c5 b6 24 4f 7f 40 65 e1 8f c6 2c f3 4b b8 00 28 c2 f6 51 20 5c 73 d7 09 61 41 de 18 9f 2e 0c 80 c3 71 28 95 88 cf 35 9f 7c f1 56 73 4e a4 bc a6 5e b5 b0 e6 90 bb 06 52 6b e8 a9 bb 7a 17 43 27 4f 91 91 e9 e7 b0 1c f6 ac 7e 72 e4 3a 36 36 5a 01 58 3c e1 9b a8 72 fb 42 7a 10 8f ad 3e dd f6 a2 e0 7d e9 e1 1c 3e b4 83 98 a0 a0 22 18 a6 2f 5b 07 da f0 e2 b1 a7 b5 87 5c 9e e2 42 ce 2b 9f 62 d1 78 a9 94 9b a7 da 85 12 c0 cb 60 13 bb b2 9e e1 1c 8b 0c a5 0b 63 4b 2d 79 87 fe 63 11 02 87 7e f8 58 80 0a 95 ac e6 6e 9b 9f 7a 3c 47 e6 92 3d 95 1e d4 eb 8e 42 d8 bc 00 c9 20 b6 19 43 f9 0a 47 c1 b0 e2 2e 94 70 a7 cc 10 ed 35 c5 a9 18 c8 62 e6 61 94 ae d8 78 83 69 53 30 53 da 5d 71 74 04 bf bc 46 8c 58 31 e3 f9 9f 8b c1 9d f5 6b d2 0b 74 45 21 e4 6b 34 da e8 aa 74 3e 5b ae 4d 27 d6 47 e3 07 28 8d 12 a2 47 15 44 61 11 8f 83 68 fa 43 ba 80 36 46 ed c0 50 e3 4c 5b d9 45 ff c9 44 d9 e9 bc fb d6 8c b5 83 e7 f9 e0 29 40 fd 83 cb e5 db fb b3 03 05 94 21 21 1a 5e 5e b6 d6 90 c4 3d 82 e5 b3 82 e5 82 77 03 bb 88 2e 85 eb 04 17 82 69 46 e6 58 6f 9b a2 94 ab c5 ec a4 86 92 59 6c b3 39 42 f2 60 b1 af 5c 1a c7 49 9d 3f 2d 06 52 09 3a 12 ca d8 91 eb 7b a0 15 01 0a d8 d4 79 8e 3a 02 4f 65 55 e0 ad 9f 8a 76 b4 d6 0d 7b f6 45 cd 72 34 dd 82 43 f9 f3 ff 26 96 25 c2 31 3a f9 b9 c9 50 c9 e2 92 a6 65 38 a6 83 10 b7 67 f9 29 55 ed 57 f9 51 c9 03 ac 0a 2e 63 d0 29 fb 1f d6 5d 61 07 52 6d e8 f1 11 0e 70 3d 1a c4 0e 36 0c 3e 19 1b dd 73 7a ea ee 00 68 8c 6f a8 88 6c 04 75 5e ee f7 c0 d0 9e be e6 62 10 d9 a4 0b 78 d0 a4 29 c3 26 66 16 bd 8c 14 80 4d c8 62 a1 d4 55 4a 38 02 df 7d bf b2 ba e1 83 d9 5f dd a4 97 95 94 ec f8 77 f8 00 20 5d 39 8a 35 b3 92 ca 64 3e 3c 55 39 bc d8";

        const ubyte[] validBlob = validBlock
            .chunks(3)
            .map!(twoDigits => twoDigits.parse!ubyte(16))
            .array();

        ushort crc;
        crc16(crc, validBlob[2 .. $-2]); // crc is stripped

        ubyte[2] validCRC = validBlob[$-2 .. $];
        ubyte[2] ownCRC = nativeToLittleEndian(crc);

        import std.stdio;
        writeln(validCRC);
        writeln(ownCRC);

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
