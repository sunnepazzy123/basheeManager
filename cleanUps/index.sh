#!/bin/bash

# Unset Environmental variables
unset $(cut -d= -f1 < .env)

echo -e "\e[0;32mClean Ups is done \e[0m"
