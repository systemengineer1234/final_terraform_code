#!/bin/bash
git add .
read commit
git commit -am "$commit"
git push
