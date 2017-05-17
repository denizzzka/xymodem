module xymodem.crc;

@safe:

/**
 * ZMODEM CRC (CRC-16/ACORN, CRC-16/LTE) calculation.
 *
 * Params:
 *      crc =   current CRC value
 *              Should be zero at start of calculation.
 *              Result of each calculation will be plased to it.
 *
 *      buff =  bytes for calculation
 */
void crc16(ref ushort crc, in ubyte[] buff) pure nothrow @safe @nogc
in
{
    assert(buff.length > 0);
}
body
{
    immutable ushort poly = 0x1021; // XMODEM CRC polynomic

    foreach(const ubyte b; buff)
    {
        crc ^= (cast(ushort) b) << 8;

        for(size_t i = 0; i < 8; i++)
        {
            bool bit15set = (crc & 0x8000) != 0;

            crc <<= 1;

            if(bit15set)
                crc ^= poly;
        }
    }
}

unittest
{
    ushort crc;
    crc16(crc, [1, 2, 3, 4, 5]);

    assert(crc == 0x8208);
}
