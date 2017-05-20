#!/bin/bash

set -e

socat -x \
EXEC:'rb --ymodem' \
EXEC:'./xymodem_integration_test --filename=2KiB_random.bin'

diff 2KiB_random.bin integration_test/2KiB_random.bin

socat -x \
EXEC:'rb --ymodem' \
EXEC:'./xymodem_integration_test --filename=120B_random.bin'

diff 120B_random.bin integration_test/120B_random.bin

# Reference YMODEM interchange implementation:
#~ socat -x \
#~ EXEC:'rb --ymodem' \
#~ EXEC:'sb --1k --ymodem integration_test/bbcsched.txt'
