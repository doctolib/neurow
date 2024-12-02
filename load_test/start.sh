#!/bin/sh -e

ulimit -n 1000000
exec /app/bin/load_test start