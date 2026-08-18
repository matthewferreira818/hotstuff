#!/bin/sh
# Ember-Small: first rented-GPU run (RTX 4090 / A10 class, a few hours).
# ~28M params at 64px. Expect clearly sharper, more varied output.
python train.py --out runs/small --size 64 --base-ch 96 --batch 128 --steps 60000 --workers 4
