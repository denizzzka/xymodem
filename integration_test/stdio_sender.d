import xymodem.ymodem;
import std.getopt;
import std.file;
import std.stdio;

int main(string[] args)
{
    string filename;
    getopt(args, "filename", &filename);

    const ubyte[] fileContent = cast(ubyte[]) read(filename);

    bool toStdout(const ubyte[] toSend)
    {
        write(cast(string) toSend);

        return true;
    }

    ubyte[] fromStdin()
    {
        ubyte[] b = [ 0x06 /*ACK*/, 0x06 /*ACK*/ ];

        return b;
    }

    auto sender = new YModemSender(
            &fromStdin,
            &toStdout
        );

    sender.send(filename, fileContent);

    return 0;
}
