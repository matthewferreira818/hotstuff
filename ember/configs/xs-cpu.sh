#!/bin/sh
# Ember-XS: the CPU proof-of-life run (~35 min on 4 cores). 7M params, 32px.
python train.py --out runs/xs --size 32 --base-ch 48 --batch 32 --steps 3000
