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

    const ubyte[] fileContent = cast(ubyte[]) read(filename);

    bool toStdout(const ubyte[] toSend)
    {
        //~ Thread.sleep(dur!("msecs")(500));

        write(cast(string) toSend);
        stdout.flush();

        return true;
    }

    ubyte[] fromStdin(uint timeout)
    {
        Thread.sleep(dur!("msecs")(1000)); // not using timeout for faster testing results

        ubyte[] ret;

        while(true)
        {
            int c = getchar();

            if(c == EOF)
                break;
            else
                ret ~= c.to!ubyte;
        }

        return ret;
    }

    // Set stdio into non-blocking mode
    {
        import core.sys.posix.fcntl;

        int x = fcntl(stdin.fileno, F_GETFL, 0);

        if (x == -1) {
            writeln("fcntl error");
            return 1;
        }

        x |= O_NONBLOCK;

        int r = fcntl(stdin.fileno, F_SETFL, x);

        if (r == -1)
            writeln("fcntl set error");
    }

    auto sender = new YModemSender(
            &fromStdin,
            &toStdout
        );

    sender.send(filename, fileContent);

    return 0;
}
