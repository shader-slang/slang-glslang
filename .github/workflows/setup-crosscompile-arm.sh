#!/bin/bash
sudo apt-get update
dpkg --status g++-9-aarch64-linux-gnu 2>&1 | grep -qP "not installed|not-installed"
if [ $? -eq 0 ]; then
    sudo apt-get install -y g++-9-aarch64-linux-gnu
fi