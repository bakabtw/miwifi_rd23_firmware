#!/bin/sh

##close 2.4G and 5G
iwpriv wl1 set thermal_protect_disable=0:1:1
iwpriv wl0 set thermal_protect_disable=1:1:1

## open 2.4G
iwpriv wl1 set thermal_protect_duty_cfg=0:0:100
iwpriv wl1 set thermal_protect_duty_cfg=0:1:60
iwpriv wl1 set thermal_protect_duty_cfg=0:2:40
iwpriv wl1 set thermal_protect_duty_cfg=0:3:20
iwpriv wl1 set thermal_protect_enable=0:1:1:110:100:0005

## open 5G
iwpriv wl0 set thermal_protect_duty_cfg=1:0:100
iwpriv wl0 set thermal_protect_duty_cfg=1:1:60
iwpriv wl0 set thermal_protect_duty_cfg=1:2:40
iwpriv wl0 set thermal_protect_duty_cfg=1:3:20
iwpriv wl0 set thermal_protect_enable=1:1:1:110:100:0005
