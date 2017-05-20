import xymodem.ymodem;
import std.getopt;
import std.file;
import std.conv: to;
import std.stdio;
import core.thread;
import std.typecons;
import core.time;

int main(string[] args)
{
    string filename;
    getopt(args, "filename", &filename);

    ubyte[] fileContent = cast(ubyte[]) read(filename);

    bool toStdout(const ubyte[] toSend)
    {
        write(cast(string) toSend);
        stdout.flush();

        return true;
    }

    Nullable!ubyte fromStdin(uint timeout)
    {
        auto startTime = MonoTime.currTime;

        Nullable!ubyte ret;

        while((MonoTime.currTime - startTime).total!"msecs" < timeout)
        {
            int c = getchar();

            if(c == EOF)
                Thread.sleep(dur!"msecs"(50));
            else
            {
                ret = c.to!ubyte;
                break;
            }
        }

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
