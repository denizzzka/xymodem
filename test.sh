#!/bin/bash

set -ev

socat -x \
EXEC:'rb --ymodem' \
EXEC:'./xymodem_integration_test --filename=integration_test/2KiB_random.bin'

# Reference YMODEM interchange implementation:
#~ socat -x \
#~ EXEC:'rb --ymodem' \
#~ EXEC:'sb --1k --ymodem integration_test/bbcsched.txt'
