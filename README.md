# Pansift Intro 

Pansift is a Mac OSX laptop network and system monitoring tool. It is for those who support others **remotely** and enables them to rapidly find and fix issues (especially WiFi related). Whether you are a family member doing Zoom calls, or a developer or gamer who can't afford to be disconnected or slowed down, Pansift makes the invisible visible.

Pansift is about helping others to stay sane and productive with optimally functioning tools. It's about saving you time, maintaining situational awareness, and getting to root causes quickly and remotely. Whether it's WiFi problems, DNS latency, IPv4, IPv6 or simple disk utilization issues, PanSift allows you to keep an eye on many machines. More info: [https://pansift.com](https://pansift.com) 
 
Pansift is under heavy development and eventually will be installed with a few clicks via the App Store (so less technical people can easily set it up). It will also have a Web/SaaS front end for individuals and teams to provide lots of add value troubleshooting, anomaly detection, and clear fixes.

## Install Instructions

### *Note:* Currently only intended for more technical people (who can use the terminal) to install on their own or other's machines.

You will need `git` for this method of install (until we have a native OSX installer). Just type `git version` in your terminal to see if it's there. If you don't have `git` installed then OSX should offer to install (or try `xcode-select --install`) to ensure you have the command line tools.

Then once you have `git`, from your CLI / command line in OSX cut and paste the below:

`cd /tmp && git clone https://git@github.com/pansift/p3.git && cd p3 && ./installer.sh`

*Note:* Everything is transparent so feel free to take a wander round the scripts and suggest improvements to any and all jankiness!

**P.S.** If you'd like access to the intermediate dashboards below (i.e. the front end final product is still being built) then email `donal@pansift.com` with your Pansift `UUID` for access to something like the below. Please understand this is still an interim Proof of Concept, it's not production ready, and there is much change happening, so your data might not be there tomorrow! Only embark if you're a willing alpha tester and are confident enough to check the install/uninstall scripts to spot errors :)

![Intermediate Dashboard](https://github.com/pansift/p3/blob/main/Images/publicity_cap_v1.png?raw=true)

