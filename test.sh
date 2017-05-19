#!/bin/bash


socat -v \
EXEC:'rb --ymodem' \
EXEC:'./xymodem_integration_test --filename=integration_test/2KiB_random.bin'

#~ EXEC:'sb --ymodem integration_test/2KiB_random.bin'
