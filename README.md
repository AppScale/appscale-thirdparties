# AppScale Thirdparties

> AppScale is an easy-to-manage 
serverless platform for building and running scalable web
and mobile applications on any infrastructure.
It is open source and modeled on Google App Engine APIs.

[The main AppScale repository](https://github.com/AppScale/appscale)
contains API's implementation, services orchestration functionality, etc.
In particular it currently has a lot of provisioning scripts for
third-party backends.

Recently it was decided to move third-parties provisioning logic
outside AppScale core. As there is no unified recipe for configuring
complex services like FoundationDB, Postgres or Solr it appears
unfair to claim that AppScale core can perfectly configure it
for any particular deployment.

This repo contains basic initialization scripts for 
AppScale third-parties. The scripts suppose to be invoked either
manually on machines dedicated for corresponding backends or by
appscale-tools when it's starting deployment (appscale-tools uses
utils like EC2 User Data or Azure Custom Script Extension to
tell clouds to provision third-parties).

## Contribution

If you're willing to move another third-party backend provisioning
from AppScale to this repo you'd need to take in account few notes:

 - In order to be able to initialize backend services offline it's highly
   recommended to have `install.sh` script in your backend directory
   (like it's done for `foundationdb`).
   
   AppScale's [bootstrap](http://bootstrap.appscale.com) script prepares
   appscale images. It runs `install_all.sh` which
   calls all `install.sh` scripts found in the repo.
  
 - Use or even extend `common.sh` functions.
 
 - Make sure your initialization script is idempotent.
 
 - Make sure you `install.sh` disable installed service (it shouldn't be 
   running).
