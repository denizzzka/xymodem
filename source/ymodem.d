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

        currBlockNum = 0;
        currByte = 0;
        size_t currEndByte = 0;
        ubyte recvErrCnt;

        while(currByte < fileData.length)
        {
            // Send block
            {
                bool sendSuccess;
                ubyte sendErrCnt;

                if(currBlockNum == 0)
                {
                    sendSuccess = sendYModemHeaderBlock(filename, fileData.length);
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

                    if(remaining != blockSize)
                    {
                        // need pading
                        auto paddingBuff = new ubyte[](cast(ubyte) Control.CPMEOF);
                        paddingBuff.length = blockSize - remaining;

                        sendSuccess = sendBlock(sliceToSend ~ paddingBuff);
                    }
                    else
                    {
                        sendSuccess = sendBlock(sliceToSend);
                    }
                }

                if(!sendSuccess)
                {
                    sendErrCnt++;

                    if(sendErrCnt >= MAXERRORS)
                        throw new YModemException("Sender reached maximum error count", __FILE__, __LINE__);

                    continue; // retry sending
                }
            }

            // receive control symbol
            {
                Control ctlSymbol;

                try
                {
                    if(currBlockNum == 0)
                        ctlSymbol = waitFor([Control.ACK, Control.NAK, Control.ST_C]);
                    else
                        ctlSymbol = waitFor([Control.ACK, Control.NAK]);
                }
                catch(RecvException e)
                {
                    ctlSymbol = Control.NAK; // mark reply as erroneous
                }

                if(ctlSymbol == Control.NAK)
                {
                    recvErrCnt++;

                    if(recvErrCnt >= MAXERRORS)
                        throw new YModemException("Control symbol receiver reached maximum error count", __FILE__, __LINE__);
                }
                else
                {
                    recvErrCnt = 0;
                    currByte = currEndByte;
                    currBlockNum++;
                }
            }
        }

        // End of file transfer
        {
            const ubyte[] buff = [cast(ubyte) Control.EOT];
            Control symbol;
            ubyte errcnt;

            while(true)
            {
                sendData(buff);

                try
                    symbol = waitFor([Control.ACK, Control.NAK]);
                catch(RecvException e)
                    continue; // retry sending EOT

                if(symbol == Control.ACK)
                {
                    break;
                }
                else
                {
                    errcnt++;

                    if(errcnt >= MAXERRORS)
                        throw new YModemException("EOF control symbol receiver reached maximum error count", __FILE__, __LINE__);
                }
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

    private Control sendChunkWithConfirm(in ubyte[] data, in Control validAnswers)
    {
        // send
        { // TODO: тут надо разобраться
            ubyte errcnt = MAXERRORS;

            while(errcnt > 0)
            {
                auto r = sendData(data);

                if(r)
                    break;
                else
                    errcnt--;
            }
        }

        // receive control symbol
        {
            Control ctlSymbol;
            static ubyte recvErrCnt;

            try
            {
                if(currBlockNum == 0)
                    ctlSymbol = waitFor([Control.ACK, Control.NAK, Control.ST_C]);
                else
                    ctlSymbol = waitFor([Control.ACK, Control.NAK]);
            }
            catch(RecvException e)
            {
                ctlSymbol = Control.NAK;
            }

            if(ctlSymbol == Control.ACK || ctlSymbol == Control.ST_C)
            {
                recvErrCnt = 0;
            }
            else
            {
                recvErrCnt++;

                if(recvErrCnt >= MAXERRORS)
                    throw new YModemException("Control symbol receiver reached maximum error count", __FILE__, __LINE__);
            }

            return ctlSymbol;
        }
    }

    private Control waitFor(in Control[] ctls)
    {
        Control recv = receiveControlSymbol();

        foreach(c; ctls)
        {
            if(recv == c)
                return recv;
        }

        throw new YModemException("Received "~recv.to!string~", but expected "~ctls.to!string, __FILE__, __LINE__);
    }

    private Control receiveControlSymbol()
    {
        ubyte[] r = recvData(BLOCK_TIMEOUT);

        if(r.length == 0)
            throw new RecvException("Control symbol isn't received", __FILE__, __LINE__);

        if(r.length != 1)
            throw new RecvException("Reply with more than 1 octet received", __FILE__, __LINE__);

        return cast(Control) r[0];
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

    ubyte[] receiveFromLine(uint timeout)
    {
        ubyte[] b = [ Control.ACK ];

        return b;
    }

    void doTimeout(ubyte) {}

    auto sender = new YModemSender(
            &receiveFromLine,
            &sendToLine,
        );

    import std.digest.digest: toHexString;

    {
        sender.sendYModemHeaderBlock("bbcsched.txt", 6347);
        assert(sended.toHexString == "0200FF62626373636865642E747874203633343792F8");
        sended.length = 0;
    }

    sender.send("unittest.bin", [1, 2, 3, 4, 5]);
}
