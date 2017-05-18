import xymodem.ymodem;
import std.getopt;
import std.file;
import std.conv: to;
import std.stdio;
import cstdio = core.stdc.stdio;
import core.thread;

int main(string[] args)
{
    string filename;
    getopt(args, "filename", &filename);

    const ubyte[] fileContent = cast(ubyte[]) read(filename);

    bool toStdout(const ubyte[] toSend)
    {
        Thread.sleep(dur!("msecs")(500));

        write(cast(string) toSend);
        stdout.flush();

        return true;
    }

    ubyte[] fromStdin()
    {
        Thread.sleep(dur!("msecs")(500));

        ubyte[] ret;

        while(true)
        {
            auto c = getchar();

            if(c != EOF)
                ret ~= c.to!ubyte;
            else
                break;
        }

        //~ ret = [ 0x06 /*ACK*/, 0x06 /*ACK*/ ];
        return ret;
    }

    auto sender = new YModemSender(
            &fromStdin,
            &toStdout
        );

    sender.send(filename, fileContent);

    return 0;
}
