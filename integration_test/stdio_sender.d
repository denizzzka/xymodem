import xymodem.ymodem;
import std.getopt;
import std.file;
import std.conv: to;
import std.stdio;
import cstdio = core.stdc.stdio;
import core.thread;
import std.socket;

int main(string[] args)
{
    string filename;
    getopt(args, "filename", &filename);

    ubyte[] fileContent = cast(ubyte[]) read(filename);

    bool toStdout(const ubyte[] toSend)
    {
        //~ Thread.sleep(dur!("msecs")(500));

        write(cast(string) toSend);
        stdout.flush();

        return true;
    }

    ubyte[] fromStdin(uint timeout)
    {
        ubyte[] ret;

        while(true)
        {
            int c = getchar();

            if(c == EOF)
            {
                Thread.sleep(dur!("msecs")(500)); // not using timeout for faster testing results

                if(ret.length > 0)
                    break;
            }
            else
                ret ~= c.to!ubyte;
        }

        //~ import std.stdio;
        //~ writeln("Received by sender: ", ret);

        return ret;
    }

    // Set stdio into non-blocking mode
    {
        import core.sys.posix.fcntl;
        import std.exception;

        int x = fcntl(stdin.fileno, F_GETFL, 0);
        enforce(x != -1, "fcntl get error");

        x |= O_NONBLOCK;

        int r = fcntl(stdin.fileno, F_SETFL, x);
        enforce(r != -1, "fcntl set error");
    }

    auto sender = new YModemSender(
            &fromStdin,
            &toStdout
        );

    sender.send("test_result_file.bin", fileContent);

    return 0;
}
